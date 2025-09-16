#!/bin/bash
# Astrago Airgap - 3단계: 오프라인 배포 패키지 생성

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$OVERLAY_DIR")"

# 설정 파일 로드
source "$OVERLAY_DIR/configs/astrago.conf"

KUBESPRAY_PATH="$ROOT_DIR/$KUBESPRAY_OFFLINE_PATH"
PACKAGE_NAME="astrago-airgap-$(date +%Y%m%d-%H%M%S)"
PACKAGE_DIR="$ROOT_DIR/$PACKAGE_OUTPUT_DIR/$PACKAGE_NAME"

echo "📦 Astrago 오프라인 패키지 생성 시작..."
echo "패키지명: $PACKAGE_NAME"

# 패키지 디렉토리 생성
mkdir -p "$PACKAGE_DIR"

# 1. kubespray-offline outputs 복사
echo "📁 kubespray-offline 파일들 복사 중..."
if [ -d "$KUBESPRAY_PATH/outputs" ]; then
    cp -r "$KUBESPRAY_PATH/outputs" "$PACKAGE_DIR/kubespray-offline-outputs"
else
    echo "⚠️ kubespray-offline outputs 디렉토리가 없습니다. 먼저 2-download.sh를 실행하세요."
    exit 1
fi

# 2. kubespray-offline target-scripts 복사
cp -r "$KUBESPRAY_PATH/target-scripts" "$PACKAGE_DIR/"

# 3. Astrago 이미지 복사
echo "📁 Astrago 이미지 파일들 복사 중..."
if [ -f "$ROOT_DIR/$PACKAGE_OUTPUT_DIR/astrago-images/astrago-images.tar" ]; then
    cp "$ROOT_DIR/$PACKAGE_OUTPUT_DIR/astrago-images/astrago-images.tar" "$PACKAGE_DIR/"
    cp "$OVERLAY_DIR/images/imagelists/all-images.txt" "$PACKAGE_DIR/astrago-images.list"
else
    echo "⚠️ Astrago 이미지 tar 파일이 없습니다. 먼저 2-download.sh를 실행하세요."
    exit 1
fi

# 4. Helmfile 복사
echo "📁 Helmfile 복사 중..."
cp -r "$ROOT_DIR/$HELMFILE_PATH" "$PACKAGE_DIR/"

# 5. Astrago inventory 및 설정 복사
echo "📁 Astrago 설정 복사 중..."
cp -r "$OVERLAY_DIR/configs" "$PACKAGE_DIR/astrago-configs"

# 오프라인 inventory가 있다면 복사
if [ -d "$ROOT_DIR/astrago-airgap/astrago/inventory" ]; then
    cp -r "$ROOT_DIR/astrago-airgap/astrago/inventory" "$PACKAGE_DIR/astrago-inventory"
fi

# 6. 배포 스크립트 복사
echo "📁 배포 스크립트 복사 중..."
cp "$SCRIPT_DIR/4-deploy.sh" "$PACKAGE_DIR/"
chmod +x "$PACKAGE_DIR/4-deploy.sh"

# 7. README 및 설치 가이드 생성
cat > "$PACKAGE_DIR/README.md" << 'EOF'
# Astrago 오프라인 배포 패키지

이 패키지는 완전 오프라인 환경에서 Astrago를 배포하기 위한 모든 파일을 포함합니다.

## 구성 요소

- `kubespray-offline-outputs/`: Kubernetes 클러스터 구축용 패키지
- `target-scripts/`: 오프라인 환경 설정 스크립트
- `astrago-images.tar`: Astrago 컨테이너 이미지들
- `helmfile/`: Astrago Helm 차트들
- `astrago-configs/`: Astrago 설정 파일들
- `4-deploy.sh`: 자동 배포 스크립트

## 사용 방법

1. 이 패키지를 오프라인 환경으로 전송
2. 압축 해제 후 다음 명령 실행:

```bash
# 설정 파일 편집 (IP, NFS 등)
vi astrago-configs/astrago.conf

# 자동 배포 실행
./4-deploy.sh
```

## 요구사항

- Ubuntu 20.04/22.04 또는 RHEL 8/9
- containerd 또는 docker
- 최소 8GB 메모리, 50GB 디스크
EOF

# 8. 패키지 압축
echo "🗜️ 패키지 압축 중..."
cd "$ROOT_DIR/$PACKAGE_OUTPUT_DIR"
tar czf "$PACKAGE_NAME.tar.gz" "$PACKAGE_NAME"

# 크기 확인
PACKAGE_SIZE=$(du -h "$PACKAGE_NAME.tar.gz" | cut -f1)

echo ""
echo "✅ 패키지 생성 완료!"
echo "📦 패키지: $ROOT_DIR/$PACKAGE_OUTPUT_DIR/$PACKAGE_NAME.tar.gz"
echo "📏 크기: $PACKAGE_SIZE"
echo ""
echo "오프라인 환경에서 다음과 같이 사용하세요:"
echo "1. tar xzf $PACKAGE_NAME.tar.gz"
echo "2. cd $PACKAGE_NAME"
echo "3. vi astrago-configs/astrago.conf  # 설정 편집"
echo "4. ./4-deploy.sh"