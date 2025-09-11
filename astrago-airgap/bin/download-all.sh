#!/bin/bash
# Astrago Airgap - download-all.sh wrapper
# 이 스크립트는 이전 버전과의 호환성을 위한 래퍼입니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
source "$ROOT_DIR/airgap.conf"

echo "🔽 Downloading all images and packages..."
echo "Using kubespray-offline: $KUBESPRAY_PATH"

# Run original kubespray-offline download-all.sh
"$ROOT_DIR/$KUBESPRAY_PATH/download-all.sh" "$@"

# Extract Astrago-specific images
echo "Extracting Astrago images..."
"$ROOT_DIR/$ASTRAGO_SCRIPTS_PATH/extract_astrago_images.sh"

echo "✅ Download completed"