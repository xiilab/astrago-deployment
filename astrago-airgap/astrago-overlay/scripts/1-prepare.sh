#!/bin/bash
# Astrago Airgap - 1단계: 준비 작업

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$OVERLAY_DIR")"

# 설정 파일 로드
source "$OVERLAY_DIR/configs/astrago.conf"

KUBESPRAY_PATH="$ROOT_DIR/$KUBESPRAY_OFFLINE_PATH"

echo "🔧 Astrago Airgap 준비 작업 시작..."
echo "Kubespray-offline: $KUBESPRAY_PATH"
echo "Helmfile: $HELMFILE_PATH"

# kubespray-offline 존재 확인
if [ ! -d "$KUBESPRAY_PATH" ]; then
    echo "❌ kubespray-offline 디렉토리가 없습니다: $KUBESPRAY_PATH"
    echo "다음 명령으로 초기화하세요:"
    echo "  git submodule update --init --recursive"
    exit 1
fi

# Helmfile 존재 확인
if [ ! -d "$HELMFILE_PATH" ]; then
    echo "❌ Helmfile 디렉토리가 없습니다: $HELMFILE_PATH"
    exit 1
fi

# 출력 디렉토리 생성
mkdir -p "$PACKAGE_OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

# kubespray-offline config.sh 확인 및 설정
KUBESPRAY_CONFIG="$KUBESPRAY_PATH/config.sh"
if [ -f "$KUBESPRAY_CONFIG" ]; then
    echo "✅ kubespray-offline config.sh 존재"
else
    echo "❌ kubespray-offline config.sh 없음"
    exit 1
fi

# Astrago 이미지 목록 디렉토리 생성
mkdir -p "$OVERLAY_DIR/images/imagelists"

echo "✅ 준비 작업 완료!"
echo "다음 단계: ./2-download.sh"