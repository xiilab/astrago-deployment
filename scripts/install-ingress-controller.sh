#!/bin/bash

# NGINX 인그레스 컨트롤러 및 cert-manager 설치 스크립트
# AstraGo HTTPS 도메인 접근을 위한 사전 설치

set -e

echo "🚀 AstraGo HTTPS 설정을 위한 인그레스 컨트롤러 설치 시작"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 함수: 진행 상황 출력
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# kubectl 확인
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl이 설치되지 않았습니다."
    exit 1
fi

# 클러스터 연결 확인
if ! kubectl cluster-info &> /dev/null; then
    print_error "Kubernetes 클러스터에 연결할 수 없습니다."
    exit 1
fi

print_status "Kubernetes 클러스터 연결 확인됨"

# 1. NGINX 인그레스 컨트롤러 설치
print_status "NGINX 인그레스 컨트롤러 설치 중..."

# 이미 설치되어 있는지 확인
if kubectl get namespace ingress-nginx &> /dev/null; then
    print_warning "NGINX 인그레스 컨트롤러가 이미 설치되어 있습니다."
else
    # 베어메탈 환경용 NGINX 인그레스 컨트롤러 설치
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
    
    print_status "NGINX 인그레스 컨트롤러 설치 완료"
fi

# 인그레스 컨트롤러 시작 대기
print_status "인그레스 컨트롤러 시작 대기 중..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# 인그레스 컨트롤러 NodePort 확인
INGRESS_HTTP_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
INGRESS_HTTPS_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

print_status "인그레스 컨트롤러 포트 정보:"
echo "  - HTTP: ${INGRESS_HTTP_PORT}"
echo "  - HTTPS: ${INGRESS_HTTPS_PORT}"

# 2. cert-manager 설치
print_status "cert-manager 설치 중..."

# 이미 설치되어 있는지 확인
if kubectl get namespace cert-manager &> /dev/null; then
    print_warning "cert-manager가 이미 설치되어 있습니다."
else
    # cert-manager 설치
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    
    print_status "cert-manager 설치 완료"
fi

# cert-manager 시작 대기
print_status "cert-manager 시작 대기 중..."
kubectl wait --namespace cert-manager \
  --for=condition=available deployment \
  --all \
  --timeout=300s

# 3. Let's Encrypt ClusterIssuer 생성
print_status "Let's Encrypt ClusterIssuer 생성 중..."

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@company.com  # 실제 이메일로 변경 필요
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

print_status "Let's Encrypt ClusterIssuer 생성 완료"

# 4. 스테이징 환경용 ClusterIssuer 생성 (테스트용)
print_status "Let's Encrypt 스테이징 ClusterIssuer 생성 중..."

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@company.com  # 실제 이메일로 변경 필요
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

print_status "Let's Encrypt 스테이징 ClusterIssuer 생성 완료"

echo ""
print_status "🎉 인그레스 컨트롤러 및 cert-manager 설치 완료!"
echo ""
echo "📋 다음 단계:"
echo "1. DNS 설정: 도메인을 클러스터 노드 IP로 연결"
echo "2. AstraGo 환경 설정에서 ingress.enabled=true 설정"
echo "3. ./deploy_astrago.sh sync 실행"
echo ""
echo "🔗 접속 정보:"
echo "  - HTTP: http://your-domain.com:${INGRESS_HTTP_PORT}"
echo "  - HTTPS: https://your-domain.com:${INGRESS_HTTPS_PORT}"
echo ""
print_warning "Let's Encrypt 이메일 주소를 실제 이메일로 변경하세요!"