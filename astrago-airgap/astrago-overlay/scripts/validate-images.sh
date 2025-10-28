#!/bin/bash
# validate-images.sh - 추출된 이미지의 pull 가능 여부를 검증합니다

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
PULLABLE_FILE="$OUTPUT_DIR/pullable.txt"
UNPULLABLE_FILE="$OUTPUT_DIR/unpullable.txt"
INVALID_FILE="$OUTPUT_DIR/invalid.txt"
REPORT_FILE="$OUTPUT_DIR/validation-report.txt"

# 기존 결과 파일 초기화
> "$PULLABLE_FILE"
> "$UNPULLABLE_FILE"
> "$INVALID_FILE"
> "$REPORT_FILE"

# 통계 변수
TOTAL=0
PULLABLE=0
UNPULLABLE=0
INVALID=0

echo -e "${BLUE}=== 이미지 Pull 가능 여부 검증 시작 ===${NC}"
echo ""
echo "이미지 목록 파일: $IMAGE_LIST"
echo "결과 저장 디렉토리: $OUTPUT_DIR"
echo ""

# 이미지 목록 파일 존재 확인
if [ ! -f "$IMAGE_LIST" ]; then
    echo -e "${RED}오류: 이미지 목록 파일을 찾을 수 없습니다: $IMAGE_LIST${NC}"
    exit 1
fi

# 유효한 이미지 필터링 함수
is_valid_image() {
    local image="$1"

    # 빈 줄
    if [ -z "$image" ]; then
        return 1
    fi

    # 주석 라인
    if [[ "$image" =~ ^[[:space:]]*# ]]; then
        return 1
    fi

    # description: 같은 메타데이터
    if [[ "$image" == "description:"* ]]; then
        return 1
    fi

    # Kubernetes 레이블/어노테이션 (키만 있는 경우)
    if [[ "$image" =~ ^[a-z0-9\.-]+/[a-z0-9\.-]+$ ]] && [[ ! "$image" =~ : ]]; then
        # 슬래시가 하나만 있고 콜론이 없으면 레이블일 가능성
        if [[ ! "$image" =~ \. ]]; then
            return 1
        fi
    fi

    # 이미지 이름이나 경로만 있는 경우 (태그 없음)
    if [[ "$image" == *":" ]] || [[ "$image" == *"/" && ! "$image" =~ : ]]; then
        return 1
    fi

    return 0
}

# 이미지 정규화 함수
normalize_image() {
    local image="$1"

    # docker.io 프리픽스 제거 (docker pull은 자동으로 추가함)
    image="${image#docker.io/}"

    # 태그가 없으면 latest 추가
    if [[ ! "$image" =~ : ]]; then
        image="${image}:latest"
    fi

    echo "$image"
}

# 이미지 Pull 테스트 함수
test_pull() {
    local original_image="$1"
    local normalized_image

    # 유효성 검사
    if ! is_valid_image "$original_image"; then
        echo -e "${YELLOW}⊘ INVALID${NC}: $original_image"
        echo "$original_image" >> "$INVALID_FILE"
        ((INVALID++))
        return
    fi

    normalized_image=$(normalize_image "$original_image")

    # docker manifest inspect로 이미지 존재 확인 (실제 pull 없이)
    # 더 빠르고 디스크 공간을 절약
    if timeout 30 docker manifest inspect "$normalized_image" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PULLABLE${NC}: $normalized_image"
        echo "$original_image" >> "$PULLABLE_FILE"
        ((PULLABLE++))
    else
        echo -e "${RED}✗ UNPULLABLE${NC}: $normalized_image"
        echo "$original_image (normalized: $normalized_image)" >> "$UNPULLABLE_FILE"
        ((UNPULLABLE++))
    fi
}

# 이미지 목록 처리
echo -e "${BLUE}이미지 검증 중...${NC}"
echo ""

while IFS= read -r image || [ -n "$image" ]; do
    ((TOTAL++))
    test_pull "$image"
done < "$IMAGE_LIST"

# 결과 리포트 생성
echo ""
echo -e "${BLUE}=== 검증 완료 ===${NC}"
echo ""

# 리포트 작성
{
    echo "======================================"
    echo "이미지 Pull 가능 여부 검증 리포트"
    echo "======================================"
    echo ""
    echo "검증 시각: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "이미지 목록: $IMAGE_LIST"
    echo ""
    echo "전체 항목: $TOTAL"
    echo "유효한 이미지: $((PULLABLE + UNPULLABLE))"
    echo "무효한 항목: $INVALID"
    echo ""
    echo "Pull 가능: $PULLABLE ($(awk "BEGIN {printf \"%.1f\", ($PULLABLE / ($PULLABLE + $UNPULLABLE)) * 100}")%)"
    echo "Pull 불가능: $UNPULLABLE ($(awk "BEGIN {printf \"%.1f\", ($UNPULLABLE / ($PULLABLE + $UNPULLABLE)) * 100}")%)"
    echo ""
    echo "상세 결과:"
    echo "  - Pull 가능 목록: $PULLABLE_FILE"
    echo "  - Pull 불가능 목록: $UNPULLABLE_FILE"
    echo "  - 무효한 항목 목록: $INVALID_FILE"
    echo ""

    if [ $UNPULLABLE -gt 0 ]; then
        echo "======================================"
        echo "Pull 불가능한 이미지 목록:"
        echo "======================================"
        cat "$UNPULLABLE_FILE"
        echo ""
    fi

    if [ $INVALID -gt 0 ]; then
        echo "======================================"
        echo "무효한 항목 목록:"
        echo "======================================"
        cat "$INVALID_FILE"
        echo ""
    fi
} | tee "$REPORT_FILE"

# 통계 출력
echo -e "${GREEN}전체 항목: $TOTAL${NC}"
echo -e "${GREEN}유효한 이미지: $((PULLABLE + UNPULLABLE))${NC}"
echo -e "${YELLOW}무효한 항목: $INVALID${NC}"
echo ""
echo -e "${GREEN}✓ Pull 가능: $PULLABLE${NC}"
echo -e "${RED}✗ Pull 불가능: $UNPULLABLE${NC}"
echo ""
echo -e "${BLUE}리포트 저장됨: $REPORT_FILE${NC}"

# 불가능한 이미지가 있으면 종료 코드 1 반환
if [ $UNPULLABLE -gt 0 ]; then
    exit 1
fi

exit 0
