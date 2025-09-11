#!/bin/bash
# Astrago Airgap - get-kubespray.sh wrapper
# kubespray-offline 원본 스크립트 래퍼

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
source "$ROOT_DIR/airgap.conf"

echo "📥 Getting Kubespray components..."

# 작업 디렉토리를 루트로 변경하고 kubespray-offline 스크립트 실행
cd "$ROOT_DIR"
"$KUBESPRAY_PATH/get-kubespray.sh" "$@"