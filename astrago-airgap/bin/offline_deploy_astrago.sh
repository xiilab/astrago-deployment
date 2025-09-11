#!/bin/bash
# Astrago Airgap - offline_deploy_astrago.sh wrapper
# 이 스크립트는 이전 버전과의 호환성을 위한 래퍼입니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
source "$ROOT_DIR/airgap.conf"

echo "🚀 Deploying Astrago in offline mode..."

# 작업 디렉토리를 루트로 변경
cd "$ROOT_DIR"

# Run Astrago offline deployment script
"$ASTRAGO_SCRIPTS_PATH/offline_deploy_astrago.sh" "$@"

echo "✅ Astrago deployment completed"