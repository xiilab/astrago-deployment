# 🚀 Kserve 설치 준비 분석 결과

## 📋 개요

이 문서는 Astrago-deployment 환경에서 Kserve를 설치하기 위한 종합적인 분석 결과를 담고 있습니다. Kserve는 Kubernetes 기반의 머신러닝 모델 서빙 플랫폼으로, Knative Serving을 기반으로 구축됩니다.

## 🎯 분석 목표

1. **Kserve 최신 버전 및 호환성 확인**
2. **K8s 클러스터 요구사항 조사**
3. **필요한 종속성 및 전제 조건 파악**
4. **설치 옵션 및 구성 방법 조사**

---

## 1. Kserve 최신 버전 및 호환성 확인

### ✅ 현재 클러스터 환경

#### **Kubernetes 클러스터 정보**
```yaml
Kubernetes Version: v1.28.6 (최신 안정 버전)
Node Configuration:
  - master: control-plane
  - worker1: worker node
  - worker2: worker node
Container Runtime: containerd
Network Plugin: Calico
Storage Class: astrago-nfs-csi (NFS CSI Driver)
```

#### **하드웨어 리소스**
```yaml
Per Node Resources:
  CPU: 64 cores
  Memory: 450GB+ RAM
  GPU: 4x NVIDIA GPUs
  Storage: 422GB+ ephemeral storage
  Pods: 110 pods capacity
```

#### **Kserve 최신 버전 정보**
```yaml
Latest Version: v0.15.2 (2024년 7월 기준)
Kubernetes Compatibility: v1.26+ ✅
Installation Methods:
  - Helm Chart
  - YAML Manifests
  - Operator-based
```

### 🔍 호환성 분석 결과

| 구성요소 | 현재 버전 | Kserve 요구사항 | 호환성 |
|---------|----------|----------------|--------|
| Kubernetes | v1.28.6 | v1.26+ | ✅ **호환** |
| Container Runtime | containerd | containerd/cri-o | ✅ **호환** |
| GPU Support | NVIDIA 4x/노드 | NVIDIA GPU | ✅ **호환** |
| Storage | NFS CSI | PVC 지원 | ✅ **호환** |

---

## 2. K8s 클러스터 요구사항 조사

### ✅ 기본 요구사항 충족 상태

#### **Kubernetes 요구사항**
- ✅ **버전**: v1.28.6 (v1.26+ 요구사항 충족)
- ✅ **API 서버**: 정상 동작
- ✅ **etcd**: 클러스터 상태 정상
- ✅ **kubelet**: 모든 노드에서 정상 동작

#### **리소스 요구사항**
- ✅ **CPU**: 충분한 리소스 (각 노드 64 CPU)
- ✅ **메모리**: 충분한 리소스 (각 노드 450GB+)
- ✅ **GPU**: NVIDIA GPU 4개/노드 (Kserve GPU 추론 지원)
- ✅ **스토리지**: NFS CSI Driver (영구 스토리지 지원)

#### **네트워킹 요구사항**
- ✅ **Service Mesh**: Calico 네트워크 플러그인
- ✅ **Load Balancer**: MetalLB 또는 클라우드 제공자 LB
- ✅ **Ingress**: NGINX Ingress Controller

### ⚠️ 추가 필요 구성요소

#### **현재 미설치된 핵심 구성요소**
```yaml
Missing Components:
  - Knative Serving: Kserve의 핵심 의존성
  - Istio: 서비스 메시 (선택적)
  - Cert-manager: TLS 인증서 관리 (선택적)
  - Kserve CRDs: Custom Resource Definitions
```

---

## 3. 필요한 종속성 및 전제 조건 파악

### 🔧 핵심 의존성 분석

#### **1. Knative Serving (필수)**
```yaml
Component: Knative Serving
Version: v1.14.0 (최신)
Purpose: Kserve의 기본 서빙 인프라
Kubernetes Compatibility: v1.28.6과 호환
Installation: YAML manifests 또는 Helm chart
```

#### **2. Istio (권장)**
```yaml
Component: Istio Service Mesh
Version: v1.21.0 (최신)
Purpose: 서비스 메시 및 트래픽 관리
Integration: Knative와 통합 지원
Installation: Helm chart 또는 istioctl
```

#### **3. Cert-manager (선택)**
```yaml
Component: Cert-manager
Version: v1.14.0 (최신)
Purpose: TLS 인증서 자동 관리
Environment: 프로덕션 환경 권장
Installation: Helm chart
```

### 📦 이미지 요구사항

#### **Knative Serving 이미지**
```yaml
Required Images:
  - gcr.io/knative-releases/knative.dev/serving/cmd/activator:v1.14.0
  - gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler:v1.14.0
  - gcr.io/knative-releases/knative.dev/serving/cmd/controller:v1.14.0
  - gcr.io/knative-releases/knative.dev/serving/cmd/webhook:v1.14.0
  - gcr.io/knative-releases/knative.dev/net-istio/cmd/webhook:v1.14.0
```

#### **Istio 이미지**
```yaml
Required Images:
  - docker.io/istio/pilot:1.21.0
  - docker.io/istio/proxyv2:1.21.0
  - docker.io/istio/install-cni:1.21.0
  - docker.io/istio/citadel:1.21.0
  - docker.io/istio/galley:1.21.0
```

#### **Kserve 이미지**
```yaml
Required Images:
  - kserve/kserve:latest
  - kserve/agent:latest
  - kserve/logger:latest
  - kserve/batcher:latest
```

### 🔒 보안 요구사항

#### **RBAC 설정**
```yaml
Required Permissions:
  - ClusterRole: kserve-admin
  - ClusterRoleBinding: kserve-admin-binding
  - ServiceAccount: kserve-controller-manager
  - Namespace: kserve-system
```

#### **네트워크 정책**
```yaml
Network Policies:
  - Ingress traffic control
  - Egress traffic control
  - Pod-to-pod communication
  - External API access
```

---

## 4. 설치 옵션 및 구성 방법 조사

### 🚀 권장 설치 방법

#### **방법 1: Helm Chart 사용 (권장)**

##### **단계별 설치 과정**
```bash
# 1. Helm repository 추가
helm repo add knative https://storage.googleapis.com/knative-releases/charts/helm/
helm repo add kserve https://kserve.github.io/helm-charts/
helm repo update

# 2. Knative Serving 설치
helm install knative-serving knative/serving \
  --namespace knative-serving \
  --create-namespace \
  --version 1.14.0

# 3. Istio 설치 (선택)
helm install istio-base istio/base \
  --namespace istio-system \
  --create-namespace \
  --version 1.21.0

helm install istiod istio/istiod \
  --namespace istio-system \
  --version 1.21.0

# 4. Kserve 설치
helm install kserve kserve/kserve \
  --namespace kserve-system \
  --create-namespace \
  --version 0.15.2
```

#### **방법 2: YAML 매니페스트 사용**

##### **Knative Serving 설치**
```bash
# Knative Serving Core
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.0/serving-core.yaml

# Knative Serving HPA
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.0/serving-hpa.yaml

# Knative Net Istio
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.14.0/istio.yaml
```

##### **Kserve 설치**
```bash
# Kserve CRD 및 컨트롤러
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.15.2/kserve.yaml
```

### 🔧 Astrago-deployment 통합 방안

#### **1. 새로운 애플리케이션 디렉토리 구조**
```
applications/
├── knative-serving/          # Knative Serving Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── istio/                    # Istio Helm chart (선택)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── kserve/                   # Kserve Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
└── cert-manager/             # Cert-manager (선택)
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
```

#### **2. 이미지 리스트 파일 추가**
```
airgap/kubespray-offline/imagelists/
├── knative-serving.txt       # Knative 관련 이미지
├── istio.txt                # Istio 관련 이미지
├── kserve.txt               # Kserve 관련 이미지
└── cert-manager.txt         # Cert-manager 이미지
```

#### **3. Helmfile 통합 설정**
```yaml
# applications/kserve/helmfile.yaml
repositories:
  - name: knative
    url: https://storage.googleapis.com/knative-releases/charts/helm/
  - name: istio
    url: https://istio-release.storage.googleapis.com/charts
  - name: kserve
    url: https://kserve.github.io/helm-charts/

releases:
  - name: knative-serving
    namespace: knative-serving
    chart: knative/serving
    version: 1.14.0
    values:
      - values/knative-serving.yaml
    
  - name: istio-base
    namespace: istio-system
    chart: istio/base
    version: 1.21.0
    
  - name: istiod
    namespace: istio-system
    chart: istio/istiod
    version: 1.21.0
    dependsOn:
      - istio-base
    
  - name: kserve
    namespace: kserve-system
    chart: kserve/kserve
    version: 0.15.2
    dependsOn:
      - knative-serving
      - istiod
    values:
      - values/kserve.yaml
```

#### **4. Airgap 지원 설정**
```yaml
# environments/airgap/values.yaml
knative-serving:
  image:
    registry: "10.61.3.31:35000"
    repository: "knative/serving"
    tag: "v1.14.0"

istio:
  image:
    registry: "10.61.3.31:35000"
    repository: "istio"
    tag: "1.21.0"

kserve:
  image:
    registry: "10.61.3.31:35000"
    repository: "kserve"
    tag: "v0.15.2"
```

---

## 🎯 권장 작업 계획

### **Phase 1: 기본 구성요소 설치 (1-2일)**

#### **1단계: Knative Serving 설치**
```bash
# Knative Serving Core 설치
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.0/serving-core.yaml

# 설치 확인
kubectl get pods -n knative-serving
kubectl get crd | grep knative
```

#### **2단계: Istio 설치 (선택)**
```bash
# Istio 설치
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.14.0/istio.yaml

# 설치 확인
kubectl get pods -n istio-system
```

#### **3단계: Kserve 설치**
```bash
# Kserve 설치
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.15.2/kserve.yaml

# 설치 확인
kubectl get pods -n kserve-system
kubectl get crd | grep kserve
```

### **Phase 2: Astrago-deployment 통합 (2-3일)**

#### **1단계: 디렉토리 구조 생성**
```bash
# 애플리케이션 디렉토리 생성
mkdir -p applications/{knative-serving,istio,kserve,cert-manager}

# 이미지 리스트 파일 생성
touch airgap/kubespray-offline/imagelists/{knative-serving,istio,kserve,cert-manager}.txt
```

#### **2단계: Helm chart 설정**
```bash
# Helm chart 다운로드 및 설정
helm pull knative/serving --untar --destination applications/knative-serving/
helm pull istio/base --untar --destination applications/istio/
helm pull kserve/kserve --untar --destination applications/kserve/
```

#### **3단계: Helmfile 통합**
```bash
# Helmfile 설정 파일 생성
touch applications/kserve/helmfile.yaml
touch applications/kserve/values/{knative-serving,istio,kserve}.yaml
```

### **Phase 3: 테스트 및 검증 (1-2일)**

#### **1단계: 기본 모델 서빙 테스트**
```yaml
# test-model.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-iris
spec:
  predictor:
    sklearn:
      storageUri: gs://kfserving-examples/models/sklearn/iris
```

#### **2단계: GPU 추론 테스트**
```yaml
# gpu-test-model.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: pytorch-cifar10
spec:
  predictor:
    pytorch:
      storageUri: gs://kfserving-examples/models/pytorch/cifar10
      resources:
        limits:
          nvidia.com/gpu: 1
```

#### **3단계: 스케일링 테스트**
```bash
# 부하 테스트
kubectl run load-test --image=busybox --rm -it --restart=Never -- \
  wget -qO- http://sklearn-iris.default.svc.cluster.local/v1/models/sklearn-iris:predict
```

---

## 📊 리소스 요구사항

### **최소 시스템 요구사항**

| 구성요소 | CPU | 메모리 | 스토리지 | GPU |
|---------|-----|--------|----------|-----|
| **Knative Serving** | 2 cores | 4GB | 10GB | - |
| **Istio** | 1 core | 2GB | 5GB | - |
| **Kserve** | 1 core | 2GB | 5GB | - |
| **모델 서빙** | 1-4 cores | 2-8GB | 1-10GB | 0-4 |

### **권장 시스템 요구사항**

| 구성요소 | CPU | 메모리 | 스토리지 | GPU |
|---------|-----|--------|----------|-----|
| **Knative Serving** | 4 cores | 8GB | 20GB | - |
| **Istio** | 2 cores | 4GB | 10GB | - |
| **Kserve** | 2 cores | 4GB | 10GB | - |
| **모델 서빙** | 4-16 cores | 8-32GB | 10-100GB | 1-8 |

---

## 🔍 모니터링 및 로깅

### **Prometheus 메트릭**
```yaml
# Knative Serving 메트릭
- knative_serving_activator_*
- knative_serving_autoscaler_*
- knative_serving_controller_*

# Kserve 메트릭
- kserve_*
- inference_service_*
- model_*
```

### **Grafana 대시보드**
```yaml
# 대시보드 구성
- Knative Serving Overview
- Kserve Model Performance
- GPU Utilization
- Request Latency
- Error Rate
```

---

## 🛡️ 보안 고려사항

### **네트워크 보안**
```yaml
# Network Policies
- Pod-to-pod communication control
- External API access restrictions
- Ingress/Egress traffic filtering
```

### **RBAC 설정**
```yaml
# Role-based Access Control
- Kserve admin role
- Model developer role
- Read-only role
```

### **TLS/SSL 설정**
```yaml
# Certificate Management
- Cert-manager integration
- Automatic certificate renewal
- mTLS for service-to-service communication
```

---

## 📝 다음 단계

### **즉시 실행 가능한 작업**
1. **Knative Serving 설치** - 기본 인프라 구축
2. **간단한 모델 서빙 테스트** - 기능 검증
3. **GPU 추론 테스트** - 성능 확인

### **장기 계획**
1. **Astrago-deployment 통합** - 완전한 통합
2. **Airgap 지원** - 오프라인 환경 지원
3. **모니터링 대시보드** - 운영 도구 구축
4. **자동화 스크립트** - 배포 자동화

---

## 🔗 참고 자료

### **공식 문서**
- [Kserve Documentation](https://kserve.github.io/website/)
- [Knative Serving Documentation](https://knative.dev/docs/serving/)
- [Istio Documentation](https://istio.io/docs/)

### **GitHub 저장소**
- [Kserve GitHub](https://github.com/kserve/kserve)
- [Knative Serving GitHub](https://github.com/knative/serving)
- [Istio GitHub](https://github.com/istio/istio)

### **커뮤니티**
- [Kserve Slack](https://kserve.slack.com/)
- [Knative Slack](https://slack.knative.dev/)
- [Istio Slack](https://slack.istio.io/)

---

*이 문서는 Astrago-deployment 환경에서 Kserve 설치를 위한 종합적인 분석 결과를 담고 있습니다. 실제 설치 시에는 환경에 맞게 설정을 조정하시기 바랍니다.* 