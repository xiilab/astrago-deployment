#!/bin/bash
# compare-with-pods.sh - 추출된 이미지 목록과 실제 실행 중인 Pod 이미지를 비교합니다

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_LIST="${1:-../kubespray-offline/imagelists/astrago.txt}"
OUTPUT_DIR="${2:-../kubespray-offline/validation}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 결과 파일 경로
mkdir -p "$OUTPUT_DIR"
POD_IMAGES_FILE="$OUTPUT_DIR/pod-images.txt"
MISSING_FILE="$OUTPUT_DIR/missing-from-extraction.txt"
EXTRA_FILE="$OUTPUT_DIR/extra-in-extraction.txt"
COMPARISON_REPORT="$OUTPUT_DIR/comparison-report.txt"

# 기존 결과 파일 초기화
> "$POD_IMAGES_FILE"
> "$MISSING_FILE"
> "$EXTRA_FILE"
> "$COMPARISON_REPORT"

echo -e "${BLUE}=== Pod 이미지와 추출 목록 비교 시작 ===${NC}"
echo ""

# kubectl 명령어 사용 가능 여부 확인
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}오류: kubectl 명령어를 찾을 수 없습니다.${NC}"
    echo "kubectl이 설치되어 있고 PATH에 포함되어 있는지 확인하세요."
    exit 1
fi

# Kubernetes 클러스터 접근 가능 여부 확인
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}오류: Kubernetes 클러스터에 접근할 수 없습니다.${NC}"
    echo "kubeconfig가 올바르게 설정되어 있는지 확인하세요."
    exit 1
fi

# 이미지 목록 파일 존재 확인
if [ ! -f "$IMAGE_LIST" ]; then
    echo -e "${RED}오류: 이미지 목록 파일을 찾을 수 없습니다: $IMAGE_LIST${NC}"
    exit 1
fi

echo -e "${BLUE}1. 실행 중인 Pod 이미지 수집 중...${NC}"
echo ""

# 제외할 네임스페이스 (Kubernetes 시스템 Pod)
EXCLUDED_NAMESPACES=(
    "kube-system"
    "kube-public"
    "kube-node-lease"
)

# 제외 네임스페이스 조건 생성
EXCLUDE_CONDITION=""
for ns in "${EXCLUDED_NAMESPACES[@]}"; do
    if [ -z "$EXCLUDE_CONDITION" ]; then
        EXCLUDE_CONDITION="select(.metadata.namespace != \"$ns\")"
    else
        EXCLUDE_CONDITION="$EXCLUDE_CONDITION and select(.metadata.namespace != \"$ns\")"
    fi
done

# Pod 이미지 추출 (init containers와 containers 모두 포함)
echo "제외 네임스페이스: ${EXCLUDED_NAMESPACES[*]}"
echo ""

kubectl get pods --all-namespaces -o json | \
    jq -r ".items[] | $EXCLUDE_CONDITION |
        (.spec.initContainers[]?.image // empty),
        (.spec.containers[]?.image // empty)" | \
    sort -u > "$POD_IMAGES_FILE"

POD_IMAGE_COUNT=$(wc -l < "$POD_IMAGES_FILE" | tr -d ' ')

echo -e "${GREEN}수집된 Pod 이미지 수: $POD_IMAGE_COUNT${NC}"
echo ""

# 이미지 정규화 함수
normalize_image() {
    local image="$1"

    # docker.io 프리픽스 추가/제거 통일
    if [[ ! "$image" =~ ^[a-z0-9\.-]+\.[a-z]{2,}/ ]] && [[ ! "$image" =~ ^[a-z0-9\.-]+:[0-9]+/ ]]; then
        # registry가 명시되지 않은 경우 docker.io 가정
        if [[ "$image" != docker.io/* ]]; then
            image="docker.io/$image"
        fi
    fi

    # 태그가 없으면 latest 추가
    if [[ ! "$image" =~ : ]]; then
        image="${image}:latest"
    fi

    echo "$image"
}

# 추출된 이미지 목록 정규화 (유효한 이미지만)
echo -e "${BLUE}2. 추출된 이미지 목록 정규화 중...${NC}"
echo ""

declare -A EXTRACTED_IMAGES
while IFS= read -r image || [ -n "$image" ]; do
    # 빈 줄이나 무효한 항목 제외
    if [ -z "$image" ] || [[ "$image" =~ ^[[:space:]]*# ]] || [[ "$image" == "description:"* ]]; then
        continue
    fi

    # 레이블/어노테이션 형식 제외
    if [[ "$image" =~ ^[a-z0-9\.-]+/[a-z0-9\.-]+$ ]] && [[ ! "$image" =~ : ]]; then
        if [[ ! "$image" =~ \. ]]; then
            continue
        fi
    fi

    # 불완전한 이미지 이름 제외
    if [[ "$image" == *":" && ! "$image" =~ :.+ ]]; then
        continue
    fi

    normalized=$(normalize_image "$image")
    EXTRACTED_IMAGES["$normalized"]=1
done < "$IMAGE_LIST"

EXTRACTED_COUNT=${#EXTRACTED_IMAGES[@]}
echo -e "${GREEN}정규화된 추출 이미지 수: $EXTRACTED_COUNT${NC}"
echo ""

# Pod 이미지 목록 정규화
echo -e "${BLUE}3. Pod 이미지 정규화 중...${NC}"
echo ""

declare -A POD_IMAGES_NORMALIZED
while IFS= read -r image; do
    if [ -n "$image" ]; then
        normalized=$(normalize_image "$image")
        POD_IMAGES_NORMALIZED["$normalized"]="$image"
    fi
done < "$POD_IMAGES_FILE"

# 비교 수행
echo -e "${BLUE}4. 이미지 비교 중...${NC}"
echo ""

MISSING_COUNT=0
EXTRA_COUNT=0
MATCHED_COUNT=0

# Pod에는 있지만 추출 목록에 없는 이미지 찾기
for normalized_pod_image in "${!POD_IMAGES_NORMALIZED[@]}"; do
    original_pod_image="${POD_IMAGES_NORMALIZED[$normalized_pod_image]}"

    if [ -z "${EXTRACTED_IMAGES[$normalized_pod_image]:-}" ]; then
        echo "$original_pod_image" >> "$MISSING_FILE"
        ((MISSING_COUNT++))
        echo -e "${RED}✗ MISSING${NC}: $original_pod_image"
    else
        ((MATCHED_COUNT++))
    fi
done

# 추출 목록에는 있지만 Pod에는 없는 이미지 (이것은 정상일 수 있음 - 미사용 이미지)
for normalized_extracted_image in "${!EXTRACTED_IMAGES[@]}"; do
    if [ -z "${POD_IMAGES_NORMALIZED[$normalized_extracted_image]:-}" ]; then
        echo "$normalized_extracted_image" >> "$EXTRA_FILE"
        ((EXTRA_COUNT++))
    fi
done

# 결과 리포트 생성
echo ""
echo -e "${BLUE}=== 비교 완료 ===${NC}"
echo ""

{
    echo "======================================"
    echo "Pod 이미지 vs 추출 이미지 비교 리포트"
    echo "======================================"
    echo ""
    echo "비교 시각: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "이미지 목록: $IMAGE_LIST"
    echo ""
    echo "실행 중인 Pod 이미지 수: $POD_IMAGE_COUNT (시스템 Pod 제외)"
    echo "추출된 이미지 수: $EXTRACTED_COUNT (유효한 이미지만)"
    echo ""
    echo "매칭된 이미지: $MATCHED_COUNT"
    echo "누락된 이미지: $MISSING_COUNT (Pod에는 있지만 추출 목록에 없음)"
    echo "추가 이미지: $EXTRA_COUNT (추출 목록에는 있지만 Pod에 없음)"
    echo ""

    if [ $MISSING_COUNT -gt 0 ]; then
        echo "======================================"
        echo "⚠️  누락된 이미지 (Pod에 있지만 추출 안됨):"
        echo "======================================"
        cat "$MISSING_FILE"
        echo ""
        echo "⚠️  이 이미지들은 추출 로직에 추가해야 합니다!"
        echo ""
    fi

    if [ $EXTRA_COUNT -gt 0 ]; then
        echo "======================================"
        echo "ℹ️  추가 이미지 (추출했지만 현재 미사용):"
        echo "======================================"
        echo "첫 20개 이미지:"
        head -20 "$EXTRA_FILE"
        if [ $EXTRA_COUNT -gt 20 ]; then
            echo "... (총 $EXTRA_COUNT 개, 전체 목록: $EXTRA_FILE)"
        fi
        echo ""
        echo "ℹ️  이것은 정상일 수 있습니다. Helm 차트에 정의되었지만"
        echo "   현재 환경에서 활성화되지 않은 이미지일 수 있습니다."
        echo ""
    fi

    echo "======================================"
    echo "결론:"
    echo "======================================"
    if [ $MISSING_COUNT -eq 0 ]; then
        echo "✅ 모든 Pod 이미지가 추출 목록에 포함되어 있습니다!"
        echo "   추출 로직이 정상적으로 작동하고 있습니다."
    else
        echo "❌ $MISSING_COUNT 개의 이미지가 누락되었습니다."
        echo "   추출 로직을 보완해야 합니다."
        echo ""
        echo "   커버리지: $(awk "BEGIN {printf \"%.1f\", ($MATCHED_COUNT / $POD_IMAGE_COUNT) * 100}")%"
    fi
    echo ""
    echo "상세 결과:"
    echo "  - Pod 이미지 목록: $POD_IMAGES_FILE"
    echo "  - 누락된 이미지: $MISSING_FILE"
    echo "  - 추가 이미지: $EXTRA_FILE"
    echo ""
} | tee "$COMPARISON_REPORT"

# 통계 출력
echo -e "${GREEN}실행 중인 Pod 이미지: $POD_IMAGE_COUNT${NC}"
echo -e "${GREEN}추출된 이미지: $EXTRACTED_COUNT${NC}"
echo -e "${GREEN}✓ 매칭: $MATCHED_COUNT${NC}"
echo -e "${RED}✗ 누락: $MISSING_COUNT${NC}"
echo -e "${YELLOW}ℹ 추가: $EXTRA_COUNT${NC}"
echo ""
echo -e "${BLUE}리포트 저장됨: $COMPARISON_REPORT${NC}"

# 누락된 이미지가 있으면 종료 코드 1 반환
if [ $MISSING_COUNT -gt 0 ]; then
    exit 1
fi

exit 0
