#!/bin/bash

# KServe 제거 스크립트
# 사용법: ./uninstall-kserve.sh [environment]

set -e

ENVIRONMENT=${1:-"astrago"}
CURRENT_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT="$CURRENT_DIR/../../.."

echo "=== KServe 제거 시작 ==="
echo "환경: $ENVIRONMENT"

# 1. 확인 메시지
read -p "정말로 KServe를 제거하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "제거가 취소되었습니다."
    exit 0
fi

# 2. 실행 중인 InferenceService 확인
echo "2. 실행 중인 InferenceService 확인 중..."
INFERENCE_SERVICES=$(kubectl get inferenceservice --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$INFERENCE_SERVICES" ]; then
    echo "경고: 다음 InferenceService가 실행 중입니다:"
    kubectl get inferenceservice --all-namespaces
    read -p "이들을 먼저 제거하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "InferenceService 제거 중..."
        kubectl delete inferenceservice --all --all-namespaces
        echo "InferenceService 제거 완료"
    else
        echo "InferenceService 제거를 건너뜁니다."
    fi
fi

# 3. Knative Service 확인
echo "3. Knative Service 확인 중..."
KNATIVE_SERVICES=$(kubectl get ksvc --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$KNATIVE_SERVICES" ]; then
    echo "경고: 다음 Knative Service가 실행 중입니다:"
    kubectl get ksvc --all-namespaces
    read -p "이들을 먼저 제거하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Knative Service 제거 중..."
        kubectl delete ksvc --all --all-namespaces
        echo "Knative Service 제거 완료"
    else
        echo "Knative Service 제거를 건너뜁니다."
    fi
fi

# 4. Helmfile을 통한 제거
echo "4. KServe 컴포넌트 제거 중..."
cd "$PROJECT_ROOT"

# KServe 제거
echo "--- KServe 제거 ---"
helmfile -e "$ENVIRONMENT" destroy -l app=kserve,component=kserve

# Istio 제거
echo "--- Istio 제거 ---"
helmfile -e "$ENVIRONMENT" destroy -l app=kserve,component=istio

# cert-manager 제거
echo "--- cert-manager 제거 ---"
helmfile -e "$ENVIRONMENT" destroy -l app=kserve,component=cert-manager

# 5. 네임스페이스 정리
echo "5. 네임스페이스 정리 중..."
kubectl delete namespace kserve --ignore-not-found=true
kubectl delete namespace knative-serving --ignore-not-found=true
kubectl delete namespace istio-system --ignore-not-found=true
kubectl delete namespace cert-manager --ignore-not-found=true

# 6. CRD 정리 (선택적)
read -p "CRD도 제거하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "CRD 제거 중..."
    kubectl delete crd $(kubectl get crd | grep -E "(kserve|knative|istio)" | awk '{print $1}') --ignore-not-found=true
    echo "CRD 제거 완료"
fi

# 7. PVC 정리 (선택적)
read -p "KServe 관련 PVC도 제거하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "PVC 제거 중..."
    kubectl delete pvc --all-namespaces -l app=kserve --ignore-not-found=true
    kubectl delete pvc --all-namespaces -l app=knative --ignore-not-found=true
    echo "PVC 제거 완료"
fi

echo "=== KServe 제거 완료 ==="

# 8. 정리 확인
echo ""
echo "=== 정리 확인 ==="
echo "남은 Pod 확인:"
kubectl get pods -A | grep -E "(cert-manager|istio|kserve|knative)" || echo "관련 Pod가 없습니다."

echo ""
echo "남은 서비스 확인:"
kubectl get svc -A | grep -E "(cert-manager|istio|kserve|knative)" || echo "관련 서비스가 없습니다."

echo ""
echo "=== 제거 완료 ==="
echo "KServe가 성공적으로 제거되었습니다." 