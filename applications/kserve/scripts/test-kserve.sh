#!/bin/bash

# KServe 테스트 스크립트
# 사용법: ./test-kserve.sh [online|offline]

set -e

ENVIRONMENT=${1:-"online"}
CURRENT_DIR=$(dirname "$(realpath "$0")")
EXAMPLES_DIR="$CURRENT_DIR/../examples"

echo "=== KServe 테스트 시작 ==="
echo "환경: $ENVIRONMENT"

# 1. KServe 컴포넌트 상태 확인
echo "1. KServe 컴포넌트 상태 확인 중..."

echo "--- cert-manager 상태 ---"
kubectl get pods -n cert-manager

echo "--- Istio 상태 ---"
kubectl get pods -n istio-system

echo "--- KServe 상태 ---"
kubectl get pods -n kserve

echo "--- Knative Serving 상태 ---"
kubectl get pods -n knative-serving

# 2. CRD 확인
echo "2. CRD 확인 중..."
kubectl get crd | grep -E "(kserve|knative|istio)"

# 3. InferenceService 배포 테스트
echo "3. InferenceService 배포 테스트 중..."

if [ "$ENVIRONMENT" = "offline" ]; then
    echo "오프라인 환경: 로컬 모델 사용"
    kubectl apply -f "$EXAMPLES_DIR/test-inferenceservice-local.yaml"
else
    echo "온라인 환경: 원격 모델 사용"
    kubectl apply -f "$EXAMPLES_DIR/test-inferenceservice-sklearn.yaml"
fi

# 4. InferenceService 상태 확인
echo "4. InferenceService 상태 확인 중..."
kubectl get inferenceservice

# 5. Knative Service 확인
echo "5. Knative Service 확인 중..."
kubectl get ksvc

# 6. Route 확인
echo "6. Route 확인 중..."
kubectl get route

# 7. 서비스 URL 출력
echo "7. 서비스 URL:"
if [ "$ENVIRONMENT" = "offline" ]; then
    kubectl get inferenceservice sklearn-iris-local -o jsonpath='{.status.url}'
    echo
else
    kubectl get inferenceservice sklearn-iris -o jsonpath='{.status.url}'
    echo
fi

# 8. 예측 테스트 (온라인 환경에서만)
if [ "$ENVIRONMENT" = "online" ]; then
    echo "8. 예측 테스트 중..."
    SERVICE_URL=$(kubectl get inferenceservice sklearn-iris -o jsonpath='{.status.url}')
    
    if [ -n "$SERVICE_URL" ]; then
        echo "서비스 URL: $SERVICE_URL"
        
        # 예측 요청
        curl -X POST \
          "$SERVICE_URL/v1/models/sklearn-iris:predict" \
          -H 'Content-Type: application/json' \
          -d '{
            "instances": [[6.8, 2.8, 4.8, 1.4]]
          }' || echo "예측 요청 실패 (서비스가 아직 준비되지 않았을 수 있음)"
    else
        echo "서비스 URL을 가져올 수 없습니다."
    fi
else
    echo "8. 오프라인 환경: 예측 테스트 건너뜀"
fi

echo "=== KServe 테스트 완료 ==="

# 9. 유용한 명령어 출력
echo ""
echo "=== 유용한 명령어 ==="
echo "# InferenceService 상태 확인"
echo "kubectl get inferenceservice"
echo "kubectl describe inferenceservice <name>"
echo ""
echo "# Knative Service 확인"
echo "kubectl get ksvc"
echo "kubectl describe ksvc <name>"
echo ""
echo "# Route 확인"
echo "kubectl get route"
echo "kubectl describe route <name>"
echo ""
echo "# Pod 로그 확인"
echo "kubectl logs -n kserve -l app=kserve-controller-manager"
echo "kubectl logs -n knative-serving -l app=controller"
echo ""
echo "# 서비스 제거"
if [ "$ENVIRONMENT" = "offline" ]; then
    echo "kubectl delete -f $EXAMPLES_DIR/test-inferenceservice-local.yaml"
else
    echo "kubectl delete -f $EXAMPLES_DIR/test-inferenceservice-sklearn.yaml"
fi 