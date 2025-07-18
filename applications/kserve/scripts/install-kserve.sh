#!/bin/bash

# KServe 설치 스크립트
# 사용법: ./install-kserve.sh [environment]

set -e

ENVIRONMENT=${1:-"astrago"}
CURRENT_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT="$CURRENT_DIR/../../.."

echo "=== KServe 설치 시작 ==="
echo "환경: $ENVIRONMENT"

# 1. 필수 도구 확인
echo "1. 필수 도구 확인 중..."
for cmd in helm helmfile kubectl; do
    if ! command -v $cmd &> /dev/null; then
        echo "오류: $cmd가 설치되지 않았습니다."
        exit 1
    fi
done

# 2. Kubernetes 클러스터 연결 확인
echo "2. Kubernetes 클러스터 연결 확인 중..."
if ! kubectl cluster-info &> /dev/null; then
    echo "오류: Kubernetes 클러스터에 연결할 수 없습니다."
    exit 1
fi

# 3. 환경 설정 확인
echo "3. 환경 설정 확인 중..."
if [ ! -f "$PROJECT_ROOT/environments/$ENVIRONMENT/values.yaml" ]; then
    echo "오류: 환경 설정 파일을 찾을 수 없습니다: environments/$ENVIRONMENT/values.yaml"
    exit 1
fi

# 4. Helmfile 실행
echo "4. KServe 설치 중..."
cd "$PROJECT_ROOT"

# cert-manager 설치
echo "--- cert-manager 설치 ---"
helmfile -e "$ENVIRONMENT" sync -l app=kserve,component=cert-manager

# 잠시 대기
echo "cert-manager 초기화 대기 중..."
sleep 30

# Istio 설치
echo "--- Istio 설치 ---"
helmfile -e "$ENVIRONMENT" sync -l app=kserve,component=istio

# 잠시 대기
echo "Istio 초기화 대기 중..."
sleep 60

# KServe 설치
echo "--- KServe 설치 ---"
helmfile -e "$ENVIRONMENT" sync -l app=kserve,component=kserve

# 5. 설치 확인
echo "5. 설치 확인 중..."
sleep 30

echo "--- cert-manager 상태 ---"
kubectl get pods -n cert-manager

echo "--- Istio 상태 ---"
kubectl get pods -n istio-system

echo "--- KServe 상태 ---"
kubectl get pods -n kserve

echo "--- Knative Serving 상태 ---"
kubectl get pods -n knative-serving

# 6. CRD 확인
echo "6. CRD 확인 중..."
kubectl get crd | grep -E "(kserve|knative|istio)" || echo "일부 CRD가 아직 생성되지 않았을 수 있습니다."

# 7. 서비스 확인
echo "7. 서비스 확인 중..."
kubectl get svc -n istio-system | grep ingressgateway

echo "=== KServe 설치 완료 ==="

# 8. 다음 단계 안내
echo ""
echo "=== 다음 단계 ==="
echo "1. 모든 Pod가 Running 상태가 될 때까지 대기하세요."
echo "2. 테스트를 실행하세요:"
echo "   cd $CURRENT_DIR"
if [ "$ENVIRONMENT" = "astrago" ]; then
    echo "   ./test-kserve.sh offline"
else
    echo "   ./test-kserve.sh online"
fi
echo ""
echo "3. 유용한 명령어:"
echo "   # 전체 상태 확인"
echo "   kubectl get pods -A | grep -E '(cert-manager|istio|kserve|knative)'"
echo ""
echo "   # 로그 확인"
echo "   kubectl logs -n kserve -l app=kserve-controller-manager"
echo "   kubectl logs -n knative-serving -l app=controller"
echo ""
echo "   # 서비스 제거"
echo "   helmfile -e $ENVIRONMENT destroy -l app=kserve" 