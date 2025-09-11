#!/bin/bash
# Astrago Airgap - create_astrago_only_package.sh wrapper
# 이 스크립트는 이전 버전과의 호환성을 위한 래퍼입니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration  
source "$ROOT_DIR/airgap.conf"

echo "📦 Creating Astrago-only deployment package..."

# 작업 디렉토리를 루트로 변경
cd "$ROOT_DIR"

# Run Astrago package creation script
"$ASTRAGO_SCRIPTS_PATH/create_astrago_only_package.sh" "$@"

echo "✅ Astrago package created in $PACKAGE_OUTPUT_DIR"