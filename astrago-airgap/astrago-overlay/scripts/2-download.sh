#!/bin/bash
# Astrago Airgap - 2단계: 이미지 및 패키지 다운로드

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$OVERLAY_DIR")"

# 설정 파일 로드
source "$OVERLAY_DIR/configs/astrago.conf"

KUBESPRAY_PATH="$ROOT_DIR/$KUBESPRAY_OFFLINE_PATH"

echo "🔽 Astrago 이미지 및 패키지 다운로드 시작..."

# 1. 기존 이미지 목록 사용 또는 Helmfile에서 새로 추출
echo "📋 Astrago 이미지 목록 준비 중..."

# 기존 이미지 목록이 있는지 확인
EXISTING_IMAGES="$OVERLAY_DIR/images/imagelists/images.txt"
if [ -f "$EXISTING_IMAGES" ]; then
    echo "✅ 기존 이미지 목록 사용: $EXISTING_IMAGES"
    cp "$EXISTING_IMAGES" "$OVERLAY_DIR/images/imagelists/all-images.txt"
else
    echo "📋 Helmfile에서 이미지 목록 새로 추출 중..."
    cd "$ROOT_DIR/$HELMFILE_PATH"
    
    # helmfile template으로 모든 이미지 추출
    timeout 300 helmfile template --environment default 2>/dev/null | \
        grep -oE 'image: [^"]+|repository: [^"]+' | \
        sed -E 's/(image|repository): //' | \
        grep -E '\.(io|com|org|net)/' | \
        sort -u > "$OVERLAY_DIR/images/imagelists/all-images.txt"
fi

TOTAL_IMAGES=$(wc -l < "$OVERLAY_DIR/images/imagelists/all-images.txt")
echo "✅ 사용할 이미지 수: $TOTAL_IMAGES"

# 2. kubespray-offline 다운로드 실행
echo "🔽 kubespray-offline 패키지 다운로드..."
cd "$KUBESPRAY_PATH"
./download-all.sh

# 3. Astrago 이미지 다운로드
echo "🔽 Astrago 이미지 다운로드..."
CONTAINER_CMD="podman"
if command -v nerdctl >/dev/null 2>&1; then
    CONTAINER_CMD="nerdctl"
elif command -v docker >/dev/null 2>&1; then
    CONTAINER_CMD="docker"
fi

echo "사용할 컨테이너 런타임: $CONTAINER_CMD"

# 이미지 다운로드 및 저장
mkdir -p "$ROOT_DIR/$PACKAGE_OUTPUT_DIR/astrago-images"
cd "$ROOT_DIR/$PACKAGE_OUTPUT_DIR/astrago-images"

DOWNLOADED=0
FAILED=0

while IFS= read -r image; do
    echo "📥 $image"
    if $CONTAINER_CMD pull "$image"; then
        DOWNLOADED=$((DOWNLOADED + 1))
    else
        echo "⚠️ 실패: $image" >> failed-images.txt
        FAILED=$((FAILED + 1))
    fi
done < "$OVERLAY_DIR/images/imagelists/all-images.txt"

# 이미지들을 tar로 저장
echo "📦 이미지 패키징 중..."
$CONTAINER_CMD save $(cat "$OVERLAY_DIR/images/imagelists/all-images.txt") > astrago-images.tar

echo ""
echo "✅ 다운로드 완료!"
echo "- 성공: $DOWNLOADED 개"
echo "- 실패: $FAILED 개"
if [ $FAILED -gt 0 ]; then
    echo "- 실패 목록: $ROOT_DIR/$PACKAGE_OUTPUT_DIR/astrago-images/failed-images.txt"
fi
echo ""
echo "다음 단계: ./3-package.sh"