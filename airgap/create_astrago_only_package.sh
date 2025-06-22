#!/bin/bash

# AstraGo 전용 컨테이너 이미지 전달 패키지 생성 스크립트
# Kubernetes는 이미 설치된 환경용
# 작성일: $(date '+%Y-%m-%d')

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/kubespray-offline/outputs"
IMAGES_DIR="${OUTPUT_DIR}/images"
DELIVERY_DIR="${OUTPUT_DIR}/astrago-delivery"

echo "=== AstraGo 전용 컨테이너 이미지 패키지 생성 ==="
echo "Kubernetes 설치 이미지는 제외하고 AstraGo 관련 이미지만 포함합니다."

# 전달 디렉토리 생성
mkdir -p "${DELIVERY_DIR}/images"

# 필요한 이미지 목록 정의
declare -a ASTRAGO_IMAGES=(
    # AstraGo 핵심 이미지
    "docker.io\$xiilab\$astrago\$core-stag-*.tar.gz"
    "docker.io\$xiilab\$astrago\$batch-stag-*.tar.gz" 
    "docker.io\$xiilab\$astrago\$monitor-stag-*.tar.gz"
    "docker.io\$xiilab\$astrago\$frontend-stag-*.tar.gz"
    "docker.io\$xiilab\$astrago\$time-prediction-*.tar.gz"
    "docker.io\$xiilab\$astrago-dataset-nginx\$*.tar.gz"
    "docker.io\$xiilab\$git-sync\$*.tar.gz"
    
    # NVIDIA GPU Operator 관련
    "nvcr.io\$nvidia\$*.tar.gz"
    
    # Harbor 관련
    "docker.io\$goharbor\$*.tar.gz"
    
    # Keycloak
    "docker.io\$bitnami\$keycloak\$*.tar.gz"
    
    # MariaDB
    "docker.io\$bitnami\$mariadb\$*.tar.gz"
    
    # Prometheus/Grafana 모니터링
    "quay.io\$prometheus\$*.tar.gz"
    "quay.io\$prometheus-operator\$*.tar.gz"
    "docker.io\$grafana\$*.tar.gz"
    "quay.io\$kiwigrid\$k8s-sidecar\$*.tar.gz"
    
    # Flux GitOps
    "ghcr.io\$fluxcd\$*.tar.gz"
    
    # MPI Operator
    "docker.io\$mpioperator\$*.tar.gz"
    
    # NFS CSI Driver
    "registry.k8s.io\$sig-storage\$nfsplugin\$*.tar.gz"
    "registry.k8s.io\$sig-storage\$livenessprobe\$*.tar.gz"
    "registry.k8s.io\$sig-storage\$csi-node-driver-registrar\$*.tar.gz"
    
    # 기타 필수 유틸리티
    "docker.io\$library\$nginx\$*.tar.gz"
    "docker.io\$library\$busybox\$*.tar.gz"
    "docker.io\$curlimages\$curl\$*.tar.gz"
)

echo "1. 필요한 이미지 파일 복사 중..."
total_size=0
copied_count=0

for pattern in "${ASTRAGO_IMAGES[@]}"; do
    for file in ${IMAGES_DIR}/${pattern}; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            cp "$file" "${DELIVERY_DIR}/images/"
            size=$(stat -c%s "$file")
            total_size=$((total_size + size))
            copied_count=$((copied_count + 1))
            echo "   복사됨: $filename ($(numfmt --to=iec $size))"
        fi
    done
done

echo "   총 ${copied_count}개 이미지 파일 복사 완료"
echo "   총 크기: $(numfmt --to=iec $total_size)"

# 2. AstraGo 전용 이미지 목록 생성
echo "2. AstraGo 이미지 목록 생성 중..."
cat > "${DELIVERY_DIR}/images/astrago-images.list" << 'EOF'
# AstraGo 핵심 이미지
docker.io/xiilab/astrago/core:stag-52d6
docker.io/xiilab/astrago/batch:stag-52d6  
docker.io/xiilab/astrago/monitor:stag-52d6
docker.io/xiilab/astrago/frontend:stag-4897
docker.io/xiilab/astrago/time-prediction:v0.2
docker.io/xiilab/astrago-dataset-nginx:latest
docker.io/xiilab/git-sync:v3.6.0

# NVIDIA GPU Operator
nvcr.io/nvidia/driver:550.144.03-ubuntu20.04
nvcr.io/nvidia/k8s-device-plugin:v0.17.0
nvcr.io/nvidia/kubevirt-gpu-device-plugin:v1.2.10
nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.2
nvcr.io/nvidia/cloud-native/dcgm:3.3.9-1-ubuntu22.04
nvcr.io/nvidia/cloud-native/k8s-driver-manager:v0.7.0
nvcr.io/nvidia/cloud-native/k8s-cc-manager:v0.1.1
nvcr.io/nvidia/cloud-native/k8s-kata-manager:v0.2.2
nvcr.io/nvidia/cloud-native/k8s-mig-manager:v0.10.0-ubuntu20.04
nvcr.io/nvidia/cloud-native/vgpu-device-manager:v0.2.8
nvcr.io/nvidia/k8s/container-toolkit:v1.17.4-ubuntu20.04
nvcr.io/nvidia/k8s/dcgm-exporter:3.3.9-3.6.1-ubuntu22.04
nvcr.io/nvidia/cuda:12.4.1-base-ubi8
nvcr.io/nvidia/cuda:12.6.3-base-ubi9

# Harbor 이미지 레지스트리
docker.io/goharbor/harbor-core:v2.11.1
docker.io/goharbor/harbor-db:v2.11.1
docker.io/goharbor/harbor-exporter:v2.11.1
docker.io/goharbor/harbor-jobservice:v2.11.1
docker.io/goharbor/harbor-portal:v2.11.1
docker.io/goharbor/harbor-registryctl:v2.11.1
docker.io/goharbor/nginx-photon:v2.11.1
docker.io/goharbor/redis-photon:v2.11.1
docker.io/goharbor/registry-photon:v2.11.1
docker.io/goharbor/trivy-adapter-photon:v2.11.1

# 인증 및 보안
docker.io/bitnami/keycloak:22.0.5-debian-11-r2

# 데이터베이스
docker.io/bitnami/mariadb:10.11.4-debian-11-r46

# 모니터링 스택
quay.io/prometheus/prometheus:v2.48.1
quay.io/prometheus-operator/prometheus-operator:v0.70.0
quay.io/prometheus-operator/prometheus-config-reloader:v0.70.0
quay.io/prometheus/node-exporter:v1.7.0
quay.io/prometheus/alertmanager:v0.26.0
docker.io/grafana/grafana:10.2.2
docker.io/grafana/loki:2.9.6
docker.io/grafana/promtail:2.9.6
quay.io/kiwigrid/k8s-sidecar:1.25.2

# GitOps (Flux)
ghcr.io/fluxcd/source-controller:v1.3.0
ghcr.io/fluxcd/notification-controller:v1.3.0
ghcr.io/fluxcd/kustomize-controller:v1.3.0
ghcr.io/fluxcd/image-reflector-controller:v0.32.0
ghcr.io/fluxcd/image-automation-controller:v0.38.0
ghcr.io/fluxcd/helm-controller:v1.0.1
ghcr.io/fluxcd/flux-cli:v2.3.0

# MPI Operator (분산 학습)
docker.io/mpioperator/mpi-operator:0.5.0

# NFS Storage
registry.k8s.io/sig-storage/nfsplugin:v4.7.0
registry.k8s.io/sig-storage/livenessprobe:v2.12.0
registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.10.0

# 기타 유틸리티
docker.io/library/nginx:1.26.0-alpine3.19
docker.io/library/busybox:latest
docker.io/curlimages/curl:7.85.0
EOF

# 3. Harbor 푸시 스크립트 생성 (AstraGo 전용)
echo "3. AstraGo 전용 Harbor 푸시 스크립트 생성 중..."
cat > "${DELIVERY_DIR}/push_astrago_to_harbor.sh" << 'EOF'
#!/bin/bash

# AstraGo 컨테이너 이미지 Harbor 푸시 스크립트
# 사용법: ./push_astrago_to_harbor.sh <HARBOR_URL> <HARBOR_PROJECT> [USERNAME] [PASSWORD]

set -e

if [ $# -lt 2 ]; then
    echo "사용법: $0 <HARBOR_URL> <HARBOR_PROJECT> [USERNAME] [PASSWORD]"
    echo "예시: $0 harbor.company.com astrago admin Harbor12345"
    echo ""
    echo "주요 컴포넌트별 프로젝트 구성 권장:"
    echo "  - astrago: AstraGo 핵심 이미지"
    echo "  - nvidia: GPU Operator 이미지"  
    echo "  - monitoring: Prometheus/Grafana 이미지"
    echo "  - infrastructure: Harbor, Keycloak 등"
    exit 1
fi

HARBOR_URL="$1"
HARBOR_PROJECT="$2"
HARBOR_USERNAME="${3:-admin}"
HARBOR_PASSWORD="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"

echo "=== AstraGo 컨테이너 이미지 Harbor 푸시 시작 ==="
echo "Harbor URL: ${HARBOR_URL}"
echo "Harbor Project: ${HARBOR_PROJECT}"
echo "Harbor Username: ${HARBOR_USERNAME}"
echo ""

# Harbor 로그인
if [ -n "$HARBOR_PASSWORD" ]; then
    echo "Harbor 로그인 중..."
    echo "$HARBOR_PASSWORD" | docker login "$HARBOR_URL" -u "$HARBOR_USERNAME" --password-stdin
else
    echo "Harbor 로그인 중... (패스워드를 입력하세요)"
    docker login "$HARBOR_URL" -u "$HARBOR_USERNAME"
fi

# 이미지 로드 및 푸시 함수
load_and_push_image() {
    local tar_file="$1"
    local original_name="$2"
    
    echo "처리 중: $original_name"
    
    # 이미지 로드
    docker load -i "$tar_file"
    
    # Harbor 태그 생성 (원본 이미지 구조 유지)
    local new_tag="${HARBOR_URL}/${HARBOR_PROJECT}/${original_name}"
    
    # 태그 변경
    docker tag "$original_name" "$new_tag"
    
    # Harbor에 푸시
    docker push "$new_tag"
    
    # 로컬 이미지 정리 (선택사항)
    docker rmi "$original_name" "$new_tag" 2>/dev/null || true
    
    echo "완료: $new_tag"
    echo ""
}

# 이미지 목록 파일 읽기 및 처리
if [ -f "${IMAGES_DIR}/astrago-images.list" ]; then
    echo "AstraGo 이미지 목록 처리 중..."
    while IFS= read -r image_name; do
        if [ -n "$image_name" ] && [[ ! "$image_name" =~ ^# ]]; then
            # 파일명 변환 (슬래시와 콜론을 달러로 변환)
            tar_filename=$(echo "$image_name" | sed 's|/|\$|g' | sed 's|:|\$|g')
            tar_file="${IMAGES_DIR}/${tar_filename}.tar.gz"
            
            if [ -f "$tar_file" ]; then
                load_and_push_image "$tar_file" "$image_name"
            else
                echo "경고: $tar_file 파일을 찾을 수 없습니다."
            fi
        fi
    done < "${IMAGES_DIR}/astrago-images.list"
fi

echo "=== 모든 AstraGo 이미지 푸시 완료 ==="
echo "Harbor 프로젝트 확인: https://${HARBOR_URL}/harbor/projects/${HARBOR_PROJECT}/repositories"
echo ""
echo "🎯 다음 단계:"
echo "1. Harbor에서 이미지 푸시 확인"
echo "2. AstraGo 배포 시 Harbor URL을 private registry로 설정"
echo "3. 각 컴포넌트별 values.yaml에서 이미지 경로 업데이트"
EOF

chmod +x "${DELIVERY_DIR}/push_astrago_to_harbor.sh"

# 4. 압축 파일 생성
echo "4. AstraGo 패키지 압축 중..."
cd "${DELIVERY_DIR}"
tar -czf "../astrago-images-only.tar.gz" .
echo "   압축 완료: astrago-images-only.tar.gz"

# 5. 사용 가이드 생성
echo "5. AstraGo 전용 사용 가이드 생성 중..."
cat > "${DELIVERY_DIR}/README-AstraGo.md" << 'EOF'
# AstraGo 전용 컨테이너 이미지 패키지

## 📋 패키지 내용 (Kubernetes 설치 이미지 제외)

이 패키지는 **이미 Kubernetes가 설치된 환경**에서 AstraGo와 관련 컴포넌트만 설치하기 위한 경량화된 패키지입니다.

### 포함된 컴포넌트:
- **AstraGo 핵심**: Core, Batch, Monitor, Frontend, Time Prediction
- **NVIDIA GPU Operator**: GPU 관련 모든 이미지
- **Harbor**: 프라이빗 이미지 레지스트리
- **Keycloak**: 인증 및 권한 관리
- **MariaDB**: 데이터베이스
- **Prometheus/Grafana**: 모니터링 스택
- **Flux**: GitOps 도구
- **MPI Operator**: 분산 학습
- **NFS CSI Driver**: 스토리지

### 제외된 컴포넌트:
- Kubernetes 기본 이미지 (kube-apiserver, kube-controller-manager 등)
- etcd, CoreDNS 등 클러스터 기본 컴포넌트
- CNI 플러그인 (Calico, Flannel 등)

## 🚀 사용 방법

### 1단계: 패키지 해제
```bash
tar -xzf astrago-images-only.tar.gz
cd astrago-delivery
```

### 2단계: Harbor에 이미지 푸시
```bash
# 실행 권한 부여
chmod +x push_astrago_to_harbor.sh

# Harbor에 푸시
./push_astrago_to_harbor.sh harbor.company.com astrago admin Harbor12345
```

### 3단계: AstraGo 배포 설정 업데이트
Harbor 푸시 완료 후, AstraGo 배포 시 다음과 같이 설정:

```yaml
# values.yaml 예시
offline:
  registry: "harbor.company.com/astrago"

astrago:
  core:
    registry: "harbor.company.com/astrago"
    repository: "docker.io/xiilab/astrago/core"
  batch:
    registry: "harbor.company.com/astrago"
    repository: "docker.io/xiilab/astrago/batch"
  # ... 기타 컴포넌트
```

## 📊 패키지 크기 비교

- **전체 패키지**: ~14GB (Kubernetes 포함)
- **AstraGo 전용**: ~8-10GB (Kubernetes 제외)

## 🎯 Harbor 프로젝트 구성 권장사항

효율적인 관리를 위해 컴포넌트별로 Harbor 프로젝트를 분리하는 것을 권장합니다:

```bash
# 컴포넌트별 푸시 예시
./push_astrago_to_harbor.sh harbor.company.com astrago-core admin password
./push_astrago_to_harbor.sh harbor.company.com nvidia-gpu admin password  
./push_astrago_to_harbor.sh harbor.company.com monitoring admin password
./push_astrago_to_harbor.sh harbor.company.com infrastructure admin password
```

## ⚠️ 주의사항

1. **Kubernetes 버전**: 클러스터가 v1.28+ 인지 확인
2. **GPU 노드**: NVIDIA GPU가 있는 노드에 적절한 라벨 설정 필요
3. **스토리지**: NFS 서버가 준비되어 있어야 함
4. **네트워크**: Harbor 접근 가능한 네트워크 환경 필요

## 🔧 문제 해결

### GPU Operator 설치 실패 시:
```bash
# GPU 노드 라벨 확인
kubectl get nodes --show-labels | grep gpu

# GPU 노드에 라벨 추가
kubectl label nodes <node-name> nvidia.com/gpu=true
```

### Harbor 연결 문제 시:
```bash
# Harbor 연결 테스트
curl -k https://harbor.company.com/api/v2.0/health

# Docker 로그인 테스트
docker login harbor.company.com
```

## 📞 지원

AstraGo 기술 지원팀에 문의하세요.
EOF

# 6. 체크섬 생성
echo "6. 체크섬 파일 생성 중..."
cd "${OUTPUT_DIR}"
sha256sum astrago-images-only.tar.gz > astrago-images-only.tar.gz.sha256

# 7. 최종 결과 출력
echo ""
echo "=== AstraGo 전용 패키지 생성 완료 ==="
echo "패키지 위치: ${OUTPUT_DIR}/astrago-images-only.tar.gz"
echo "체크섬: ${OUTPUT_DIR}/astrago-images-only.tar.gz.sha256"
echo ""
echo "📊 패키지 정보:"
ls -lh "${OUTPUT_DIR}/astrago-images-only.tar.gz"
echo ""
echo "✅ 고객 전달 파일:"
echo "   1. astrago-images-only.tar.gz (AstraGo 전용 이미지 패키지)"
echo "   2. astrago-images-only.tar.gz.sha256 (체크섬 파일)"
echo ""
echo "🚀 고객 사용법:"
echo "   1. tar -xzf astrago-images-only.tar.gz"
echo "   2. cd astrago-delivery"  
echo "   3. ./push_astrago_to_harbor.sh <HARBOR_URL> <PROJECT> <USER> <PASS>"
echo ""
echo "💡 패키지 크기가 대폭 줄어들었습니다! (Kubernetes 이미지 제외)"
echo ""
EOF 