#!/bin/bash
# Astrago Airgap - 4단계: 오프라인 환경 배포 (타겟 환경에서 실행)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 설정 파일 로드
if [ -f "./astrago-configs/astrago.conf" ]; then
    source "./astrago-configs/astrago.conf"
else
    echo "❌ astrago-configs/astrago.conf 파일이 없습니다."
    exit 1
fi

echo "🚀 Astrago 오프라인 배포 시작..."
echo "대상 IP: ${EXTERNAL_IP:-'미설정'}"
echo "NFS 서버: ${NFS_SERVER:-'미설정'}"

# 필수 설정 확인
if [ -z "$EXTERNAL_IP" ]; then
    echo "❌ EXTERNAL_IP가 설정되지 않았습니다."
    echo "astrago-configs/astrago.conf에서 EXTERNAL_IP를 설정하세요."
    exit 1
fi

# 1. 오프라인 레포지토리 설정
echo "🔧 오프라인 환경 설정 중..."
cd target-scripts
./setup-all.sh

# 2. Astrago 이미지 로드
echo "📥 Astrago 이미지 로드 중..."
if [ -f "../astrago-images.tar" ]; then
    CONTAINER_CMD="nerdctl"
    if command -v docker >/dev/null 2>&1; then
        CONTAINER_CMD="docker"
    fi
    
    echo "컨테이너 런타임: $CONTAINER_CMD"
    $CONTAINER_CMD load < ../astrago-images.tar
    echo "✅ 이미지 로드 완료"
else
    echo "⚠️ astrago-images.tar 파일이 없습니다."
fi

# 3. 로컬 레지스트리에 이미지 푸시 (선택사항)
if [ -n "$REGISTRY_HOST" ] && [ "$REGISTRY_HOST" != "harbor.astrago.io" ]; then
    echo "📤 로컬 레지스트리에 이미지 푸시 중..."
    while IFS= read -r image; do
        echo "푸시: $image -> $REGISTRY_HOST/${image##*/}"
        $CONTAINER_CMD tag "$image" "$REGISTRY_HOST/${image##*/}"
        $CONTAINER_CMD push "$REGISTRY_HOST/${image##*/}" || echo "⚠️ 푸시 실패: $image"
    done < ../astrago-images.list
fi

# 4. Kubernetes 클러스터 설정 (kubespray)
echo "☸️ Kubernetes 클러스터 확인 중..."
if command -v kubectl >/dev/null 2>&1; then
    if kubectl cluster-info >/dev/null 2>&1; then
        echo "✅ Kubernetes 클러스터가 이미 실행 중입니다."
    else
        echo "⚠️ Kubernetes 클러스터에 접근할 수 없습니다."
        echo "kubespray로 클러스터를 설정하려면 다음을 실행하세요:"
        echo "1. kubespray-offline-outputs의 kubespray 디렉토리로 이동"
        echo "2. inventory 설정 후 ansible-playbook 실행"
    fi
else
    echo "⚠️ kubectl이 설치되어 있지 않습니다."
fi

# 5. Helmfile로 Astrago 배포
echo "📊 Helmfile로 Astrago 배포 중..."
cd ../helmfile

# 환경 변수 설정
export EXTERNAL_IP="$EXTERNAL_IP"
export NFS_SERVER="$NFS_SERVER"
export NFS_BASE_PATH="$NFS_BASE_PATH"

# 배포 실행
if command -v helmfile >/dev/null 2>&1; then
    echo "helmfile 배포 시작..."
    helmfile -e default apply
    echo "✅ Astrago 배포 완료!"
else
    echo "⚠️ helmfile이 설치되어 있지 않습니다."
    echo "다음 명령으로 수동 배포하세요:"
    echo "1. helm 차트들을 개별적으로 설치"
    echo "2. 또는 helmfile 설치 후 재실행"
fi

# 6. 배포 상태 확인
echo "📋 배포 상태 확인 중..."
if command -v kubectl >/dev/null 2>&1; then
    echo ""
    echo "=== Namespace 목록 ==="
    kubectl get ns
    echo ""
    echo "=== Pod 상태 ==="
    kubectl get pods -A | grep -E "(astrago|prometheus|keycloak|harbor)"
    echo ""
    echo "=== Service 상태 ==="
    kubectl get svc -A | grep -E "(astrago|prometheus|keycloak|harbor)"
fi

echo ""
echo "🎉 Astrago 오프라인 배포가 완료되었습니다!"
echo ""
echo "다음 URL로 접속 가능합니다:"
echo "- Astrago Frontend: http://$EXTERNAL_IP"
echo "- Prometheus: http://$EXTERNAL_IP:9090"
echo "- Keycloak: http://$EXTERNAL_IP:8080"

if [ -n "$REGISTRY_HOST" ]; then
    echo "- Harbor Registry: https://$REGISTRY_HOST"
fi