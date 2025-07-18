# KServe Application

이 디렉토리는 KServe, Knative Serving, Istio, cert-manager를 포함한 ML 서빙 인프라를 Helm을 통해 관리합니다.

## 구성 요소

### 1. cert-manager (v1.13.3)
- SSL/TLS 인증서 자동 관리
- Let's Encrypt 통합 지원
- ClusterIssuer 자동 생성

### 2. Istio (v1.17.2)
- **istio-base**: Istio 기본 구성 요소
- **istiod**: Istio 컨트롤 플레인
- **knative-local-gateway**: Knative net-istio에서 생성된 로컬 게이트웨이

### 3. Knative Operator (v1.12.3)
- Knative Serving 생명주기 관리
- Knative Serving 자동 설치 및 구성
- Knative Serving 업데이트 및 관리

### 4. KServe (v0.15.2)
- ML 모델 서빙 플랫폼
- Knative Serving과 통합된 서버리스 기능
- 다중 프레임워크 지원 (TensorFlow, PyTorch, scikit-learn 등)

## 설치 순서

Helmfile이 자동으로 올바른 순서로 설치합니다:

1. cert-manager
2. Istio (base → istiod)
3. Knative Operator
4. KServe (Knative Serving 포함)

## 환경별 설정

### Online 환경
```bash
# 전체 설치
helmfile -e prod sync -l app=kserve

# 특정 컴포넌트만 설치
helmfile -e prod sync -l app=kserve,component=cert-manager
helmfile -e prod sync -l app=kserve,component=istio
helmfile -e prod sync -l app=kserve,component=knative-operator
helmfile -e prod sync -l app=kserve,component=kserve
```

### Offline 환경
```bash
# 전체 설치
helmfile -e astrago sync -l app=kserve

# 특정 컴포넌트만 설치
helmfile -e astrago sync -l app=kserve,component=cert-manager
helmfile -e astrago sync -l app=kserve,component=istio
helmfile -e astrago sync -l app=kserve,component=knative-operator
helmfile -e astrago sync -l app=kserve,component=kserve
```

## 설정

### values.yaml 주요 설정

```yaml
# 노드 선택자
nodeSelector: {}

# 톨러레이션
tolerations: []

# KServe 설정
kserve:
  storage:
    storageClass: "astrago-nfs-csi"
    size: "10Gi"
  
  modelRegistry:
    enabled: false
  
  monitoring:
    enabled: false
  
  security:
    enabled: false

# Knative Serving 설정
knative:
  serving:
    autoscaling:
      minScale: 0
      maxScale: 10
      target: 1

# Istio 설정
istio:
  gateway:
    serviceType: "LoadBalancer"
```

## 사용법

### 1. InferenceService 배포

```yaml
apiVersion: "serving.kserve.io/v1beta1"
kind: "InferenceService"
metadata:
  name: "sklearn-iris"
spec:
  predictor:
    sklearn:
      storageUri: "gs://kfserving-examples/models/sklearn/iris"
      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "1000m"
          memory: "2Gi"
```

### 2. 서비스 접근

```bash
# 서비스 URL 확인
kubectl get inferenceservice sklearn-iris

# 예측 요청
curl -X POST \
  http://sklearn-iris.default.svc.cluster.local/v1/models/sklearn-iris:predict \
  -H 'Content-Type: application/json' \
  -d '{
    "instances": [[6.8, 2.8, 4.8, 1.4]]
  }'
```

## 모니터링

### 1. Pod 상태 확인
```bash
# KServe 컨트롤러
kubectl get pods -n kserve

# Knative Serving
kubectl get pods -n knative-serving

# Knative Operator
kubectl get pods -n knative-operator

# Istio
kubectl get pods -n istio-system

# cert-manager
kubectl get pods -n cert-manager
```

### 2. 로그 확인
```bash
# KServe 컨트롤러 로그
kubectl logs -n kserve -l app=kserve-controller-manager

# Knative Serving 로그
kubectl logs -n knative-serving -l app=controller

# Knative Operator 로그
kubectl logs -n knative-operator -l app=knative-operator

# Istio 로그
kubectl logs -n istio-system -l app=istiod
```

## 트러블슈팅

### 1. 이미지 Pull 실패
- Harbor 레지스트리 설정 확인
- 필요한 이미지를 Harbor에 미리 푸시

### 2. Knative Route 생성 실패
- CRD 설치 확인: `kubectl get crd | grep knative`
- Knative Serving 재설치

### 3. Istio Gateway 연결 실패
- LoadBalancer 서비스 타입 확인
- 포트 매핑 확인

## 버전 호환성

| 구성 요소 | 버전 | Kubernetes 호환성 |
|-----------|------|-------------------|
| cert-manager | v1.13.3 | 1.25+ |
| Istio | 1.17.2 | 1.25+ |
| Knative Operator | 1.12.3 | 1.25+ |
| KServe | 0.15.2 | 1.25+ |
| Knative Serving | 1.12.3 | 1.25+ |

## 제거

```bash
# 전체 제거
helmfile -e <environment> destroy -l app=kserve

# 특정 컴포넌트만 제거
helmfile -e <environment> destroy -l app=kserve,component=kserve
helmfile -e <environment> destroy -l app=kserve,component=knative-operator
helmfile -e <environment> destroy -l app=kserve,component=istio
helmfile -e <environment> destroy -l app=kserve,component=cert-manager
``` 