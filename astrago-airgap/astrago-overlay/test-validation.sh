#!/bin/bash
# 이미지 추출 검증 스크립트
# 추출된 이미지 목록과 클러스터에 실제 배포된 이미지를 비교

set -e

EXTRACTED_IMAGES="/Users/xiilab/Develop/astrago/astrago-deployment/astrago-airgap/kubespray-offline/imagelists/astrago.txt"
CLUSTER_IMAGES="/tmp/cluster-images.txt"
MISSING_IMAGES="/tmp/missing-images.txt"
EXTRA_IMAGES="/tmp/extra-images.txt"

echo "=========================================="
echo "  이미지 추출 검증 테스트"
echo "=========================================="
echo ""

# 1. 클러스터에서 실제 사용 중인 이미지 수집
echo "📦 [1/4] 클러스터에서 실제 이미지 수집 중..."
kubectl get pods -A -o jsonpath='{range .items[*]}{"\n"}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' | \
    grep -v '^$' | \
    sort -u > "$CLUSTER_IMAGES"

CLUSTER_COUNT=$(wc -l < "$CLUSTER_IMAGES" | tr -d ' ')
echo "   ✅ 클러스터 이미지: $CLUSTER_COUNT개"
echo ""

# 2. 추출된 이미지 확인
echo "📋 [2/4] 추출된 이미지 확인 중..."
if [ ! -f "$EXTRACTED_IMAGES" ]; then
    echo "   ❌ 추출된 이미지 파일이 없습니다: $EXTRACTED_IMAGES"
    exit 1
fi

EXTRACTED_COUNT=$(wc -l < "$EXTRACTED_IMAGES" | tr -d ' ')
echo "   ✅ 추출된 이미지: $EXTRACTED_COUNT개"
echo ""

# 3. 누락된 이미지 확인 (클러스터에는 있지만 추출 목록에는 없는 이미지)
echo "🔍 [3/4] 누락된 이미지 확인 중..."
> "$MISSING_IMAGES"

while IFS= read -r cluster_image; do
    # 추출 목록에서 찾기
    if ! grep -Fxq "$cluster_image" "$EXTRACTED_IMAGES"; then
        echo "$cluster_image" >> "$MISSING_IMAGES"
    fi
done < "$CLUSTER_IMAGES"

MISSING_COUNT=$(wc -l < "$MISSING_IMAGES" | tr -d ' ')
if [ "$MISSING_COUNT" -eq 0 ]; then
    echo "   ✅ 누락된 이미지 없음!"
else
    echo "   ⚠️  누락된 이미지: $MISSING_COUNT개"
    echo ""
    echo "   누락된 이미지 목록:"
    cat "$MISSING_IMAGES" | while read -r img; do
        echo "      - $img"
    done
fi
echo ""

# 4. 추가 이미지 확인 (추출 목록에는 있지만 클러스터에는 없는 이미지)
echo "📊 [4/4] 추가 이미지 확인 중..."
> "$EXTRA_IMAGES"

while IFS= read -r extracted_image; do
    # 클러스터에서 찾기
    if ! grep -Fxq "$extracted_image" "$CLUSTER_IMAGES"; then
        echo "$extracted_image" >> "$EXTRA_IMAGES"
    fi
done < "$EXTRACTED_IMAGES"

EXTRA_COUNT=$(wc -l < "$EXTRA_IMAGES" | tr -d ' ')
if [ "$EXTRA_COUNT" -eq 0 ]; then
    echo "   ✅ 추가 이미지 없음"
else
    echo "   ℹ️  추가 이미지: $EXTRA_COUNT개 (미래 사용 또는 옵션)"
fi
echo ""

# 5. 결과 요약
echo "=========================================="
echo "  검증 결과 요약"
echo "=========================================="
echo ""
echo "📊 통계:"
echo "   - 클러스터 이미지:     $CLUSTER_COUNT개"
echo "   - 추출된 이미지:       $EXTRACTED_COUNT개"
echo "   - 누락된 이미지:       $MISSING_COUNT개"
echo "   - 추가 이미지:         $EXTRA_COUNT개"
echo ""

# 커버리지 계산
if [ "$CLUSTER_COUNT" -gt 0 ]; then
    COVERED=$((CLUSTER_COUNT - MISSING_COUNT))
    COVERAGE=$((COVERED * 100 / CLUSTER_COUNT))
    echo "📈 커버리지: $COVERAGE% ($COVERED/$CLUSTER_COUNT)"
    echo ""
fi

# 6. 최종 판정
if [ "$MISSING_COUNT" -eq 0 ]; then
    echo "✅ 검증 성공! 모든 클러스터 이미지가 추출 목록에 포함되어 있습니다."
    exit 0
else
    echo "⚠️  검증 실패! $MISSING_COUNT개의 이미지가 누락되었습니다."
    echo ""
    echo "누락된 이미지 상세:"
    cat "$MISSING_IMAGES"
    exit 1
fi

