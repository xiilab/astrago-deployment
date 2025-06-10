# 📦 Astrago 애플리케이션 구성요소 가이드

## 📋 개요

Astrago 플랫폼은 여러 개의 독립적인 애플리케이션들이 조합되어 완성된 AI/ML 플랫폼을 구성합니다. 이 문서는 각 구성요소의 역할, 설정, 관리 방법을 상세히 설명합니다.

## 🏗️ 애플리케이션 아키텍처

```mermaid
graph TB
    subgraph "스토리지 계층"
        CSI[CSI Driver NFS]
    end
    
    subgraph "인프라 계층"
        GPU[GPU Operator]
        MPI[MPI Operator]
        FLUX[Flux]
    end
    
    subgraph "모니터링 계층"
        PROM[Prometheus]
        GRAF[Grafana]
    end
    
    subgraph "인증 계층"
        KC[Keycloak]
    end
    
    subgraph "애플리케이션 계층"
        CORE[Astrago Core]
        BATCH[Astrago Batch]
        MONITOR[Astrago Monitor]
        FRONTEND[Astrago Frontend]
    end
    
    subgraph "레지스트리 계층"
        HARBOR[Harbor]
    end
    
    CSI --> CORE
    GPU --> BATCH
    MPI --> BATCH
    KC --> CORE
    PROM --> MONITOR
    HARBOR --> CORE
    FLUX --> CORE
```

## 📊 애플리케이션 목록

| 애플리케이션 | 타입 | 역할 | 우선순위 | 의존성 |
|-------------|------|------|----------|--------|
| CSI Driver NFS | 인프라 | 스토리지 프로비저닝 | 1 | NFS 서버 |
| GPU Operator | 인프라 | GPU 리소스 관리 | 2 | NVIDIA 드라이버 |
| Prometheus | 모니터링 | 메트릭 수집 | 3 | - |
| Keycloak | 인증 | 사용자 인증/인가 | 4 | 데이터베이스 |
| MPI Operator | 인프라 | 분산 컴퓨팅 | 5 | - |
| Flux | GitOps | 지속적 배포 | 6 | Git 저장소 |
| Harbor | 레지스트리 | 컨테이너 이미지 저장 | 7 | - |
| Astrago | 애플리케이션 | 메인 플랫폼 | 8 | 모든 인프라 |

## 🔧 개별 애플리케이션 상세

### 1. CSI Driver NFS

#### 📋 개요

Kubernetes CSI(Container Storage Interface) 드라이버로 NFS 스토리지를 동적으로 프로비저닝합니다.

#### ⚙️ 설정

```yaml
# applications/csi-driver-nfs/helmfile.yaml
releases:
- name: csi-driver-nfs
  namespace: kube-system
  chart: csi-driver-nfs/csi-driver-nfs
  values:
  - storageClasses:
    - name: astrago-nfs-csi
      server: "{{ .Values.nfs.server }}"
      share: "{{ .Values.nfs.basePath }}"
      reclaimPolicy: Retain
      volumeBindingMode: Immediate
```

#### 🔍 관리 명령어

```bash
# 설치
helmfile -e astrago -l app=csi-driver-nfs sync

# 상태 확인
kubectl get pods -n kube-system | grep csi-nfs
kubectl get storageclass | grep nfs

# StorageClass 테스트
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: astrago-nfs-csi
EOF
```

#### 🚨 문제 해결

```bash
# CSI 드라이버 로그 확인
kubectl logs -n kube-system -l app=csi-nfs-controller

# NFS 연결 테스트
showmount -e {{ .Values.nfs.server }}
```

### 2. Keycloak

#### 📋 개요

오픈소스 신원 및 접근 관리 솔루션으로 Astrago의 인증 시스템을 담당합니다.

#### ⚙️ 설정

```yaml
# applications/keycloak/values.yaml
keycloak:
  auth:
    adminUser: "{{ .Values.keycloak.adminUser }}"
    adminPassword: "{{ .Values.keycloak.adminPassword }}"
  
  postgresql:
    enabled: false
  
  externalDatabase:
    host: mariadb
    port: 3306
    user: keycloak
    database: keycloak
    password: "{{ .Values.keycloak.dbPassword }}"
  
  service:
    type: NodePort
    nodePorts:
      http: "{{ .Values.keycloak.servicePort }}"
```

#### 🔧 초기 설정

```bash
# Realm 생성
curl -X POST "http://{{ .Values.externalIP }}:30001/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "astrago",
    "enabled": true
  }'

# 클라이언트 생성
curl -X POST "http://{{ .Values.externalIP }}:30001/admin/realms/astrago/clients" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "astrago-client",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "astragosecret"
  }'
```

#### 🔍 관리 명령어

```bash
# 설치
helmfile -e astrago -l app=keycloak sync

# 상태 확인
kubectl get pods -n astrago | grep keycloak
kubectl get svc keycloak -n astrago

# 관리자 콘솔 접속
echo "Keycloak Admin: http://{{ .Values.externalIP }}:30001"
echo "Username: {{ .Values.keycloak.adminUser }}"
echo "Password: {{ .Values.keycloak.adminPassword }}"
```

### 3. Prometheus

#### 📋 개요

시계열 데이터베이스 및 모니터링 시스템으로 Astrago 플랫폼의 메트릭을 수집하고 저장합니다.

#### ⚙️ 설정

```yaml
# applications/prometheus/values.yaml
kube-prometheus-stack:
  prometheus:
    prometheusSpec:
      retention: "{{ .Values.prometheus.retention | default "15d" }}"
      storageSpec:
        volumeClaimTemplate:
          spec:
            storageClassName: astrago-nfs-csi
            resources:
              requests:
                storage: "{{ .Values.prometheus.storageSize | default "50Gi" }}"
  
  grafana:
    enabled: true
    adminPassword: "{{ .Values.grafana.adminPassword | default "admin" }}"
    service:
      type: NodePort
      nodePort: 30003
```

#### 📊 주요 메트릭

```yaml
# 커스텀 메트릭 설정
additionalPrometheusRulesMap:
  astrago-rules:
    groups:
    - name: astrago
      rules:
      - record: astrago:job_total
        expr: sum(astrago_jobs_total) by (status)
      - record: astrago:resource_usage
        expr: avg(astrago_resource_usage_percent) by (type)
```

#### 🔍 관리 명령어

```bash
# 설치
helmfile -e astrago -l app=prometheus sync

# Prometheus 접속
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n astrago

# Grafana 접속
kubectl port-forward svc/prometheus-grafana 3000:80 -n astrago

# 메트릭 확인
curl http://{{ .Values.externalIP }}:9090/api/v1/query?query=up
```

### 4. GPU Operator

#### 📋 개요

NVIDIA GPU 리소스를 Kubernetes에서 관리하고 스케줄링하기 위한 오퍼레이터입니다.

#### ⚙️ 설정

```yaml
# applications/gpu-operator/values.yaml
gpu-operator:
  operator:
    defaultRuntime: containerd
  
  driver:
    enabled: true
    version: "{{ .Values.gpu.driverVersion | default "515.65.01" }}"
  
  toolkit:
    enabled: true
  
  devicePlugin:
    enabled: true
  
  nodeStatusExporter:
    enabled: true
```

#### 🔍 GPU 리소스 확인

```bash
# 설치
helmfile -e astrago -l app=gpu-operator sync

# GPU 노드 확인
kubectl get nodes -l nvidia.com/gpu.present=true

# GPU 리소스 확인
kubectl describe node <gpu-node> | grep nvidia.com/gpu

# GPU Pod 테스트
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:11.0-base
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
```

### 5. MPI Operator

#### 📋 개요

분산 컴퓨팅을 위한 MPI(Message Passing Interface) 작업을 Kubernetes에서 실행할 수 있게 해주는 오퍼레이터입니다.

#### ⚙️ 설정

```yaml
# applications/mpi-operator/values.yaml
mpi-operator:
  image:
    repository: mpioperator/mpi-operator
    tag: v0.4.0
  
  resources:
    limits:
      cpu: 100m
      memory: 300Mi
    requests:
      cpu: 100m
      memory: 200Mi
```

#### 🔍 MPI 작업 예시

```yaml
# MPI Job 예시
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
metadata:
  name: pi-calculation
spec:
  slotsPerWorker: 1
  runPolicy:
    cleanPodPolicy: Running
  mpiReplicaSpecs:
    Launcher:
      replicas: 1
      template:
        spec:
          containers:
          - image: mpioperator/mpi-pi
            name: mpi-launcher
            command:
            - mpirun
            - -n
            - "4"
            - /home/mpiuser/pi
    Worker:
      replicas: 2
      template:
        spec:
          containers:
          - image: mpioperator/mpi-pi
            name: mpi-worker
```

### 6. Harbor

#### 📋 개요

엔터프라이즈급 컨테이너 레지스트리로 Astrago 이미지를 안전하게 저장하고 관리합니다.

#### ⚙️ 설정

```yaml
# applications/harbor/values.yaml
harbor:
  expose:
    type: nodePort
    nodePort:
      name: harbor
      ports:
        http:
          port: 80
          nodePort: 30002
  
  externalURL: http://{{ .Values.externalIP }}:30002
  
  persistence:
    enabled: true
    persistentVolumeClaim:
      registry:
        storageClass: astrago-nfs-csi
        size: 100Gi
      chartmuseum:
        storageClass: astrago-nfs-csi
        size: 5Gi
      database:
        storageClass: astrago-nfs-csi
        size: 5Gi
      redis:
        storageClass: astrago-nfs-csi
        size: 5Gi
```

#### 🔧 초기 설정

```bash
# Harbor 로그인
docker login {{ .Values.externalIP }}:30002
# Username: admin
# Password: Harbor12345

# 프로젝트 생성
curl -X POST "http://{{ .Values.externalIP }}:30002/api/v2.0/projects" \
  -H "Authorization: Basic YWRtaW46SGFyYm9yMTIzNDU=" \
  -H "Content-Type: application/json" \
  -d '{"project_name":"astrago","public":false}'
```

### 7. Flux

#### 📋 개요

GitOps 도구로 Git 저장소의 변경사항을 자동으로 클러스터에 동기화합니다.

#### ⚙️ 설정

```yaml
# applications/flux/values.yaml
flux2:
  git:
    url: "{{ .Values.flux.gitUrl }}"
    branch: "{{ .Values.flux.branch | default "main" }}"
    path: "{{ .Values.flux.path | default "./clusters/astrago" }}"
  
  sourceController:
    create: true
  
  helmController:
    create: true
  
  kustomizeController:
    create: true
```

#### 🔧 GitOps 워크플로

```bash
# Flux 설치
helmfile -e astrago -l app=flux sync

# Git 저장소 설정
flux create source git astrago-config \
  --url=https://github.com/your-org/astrago-config \
  --branch=main \
  --interval=1m

# Kustomization 생성
flux create kustomization astrago \
  --target-namespace=astrago \
  --source=astrago-config \
  --path="./clusters/astrago" \
  --prune=true \
  --interval=5m
```

### 8. Astrago Core Platform

#### 📋 개요

Astrago의 핵심 애플리케이션으로 AI/ML 프로젝트 관리, 작업 스케줄링, 사용자 인터페이스를 제공합니다.

#### ⚙️ 주요 구성요소

##### 8.1 Astrago Core

```yaml
# Core 서비스 설정
astrago-core:
  image:
    repository: "{{ .Values.astrago.core.repository }}"
    tag: "{{ .Values.astrago.core.imageTag }}"
  
  service:
    type: ClusterIP
    port: 8080
  
  env:
    DATABASE_URL: "mysql://{{ .Values.astrago.mariadb.username }}:{{ .Values.astrago.mariadb.password }}@mariadb:3306/astrago"
    KEYCLOAK_URL: "http://keycloak:8080"
    KEYCLOAK_REALM: "{{ .Values.keycloak.realm }}"
```

##### 8.2 Astrago Batch

```yaml
# Batch 서비스 설정
astrago-batch:
  image:
    repository: "{{ .Values.astrago.batch.repository }}"
    tag: "{{ .Values.astrago.batch.imageTag }}"
  
  resources:
    limits:
      nvidia.com/gpu: 1
      memory: 8Gi
    requests:
      memory: 4Gi
```

##### 8.3 Astrago Monitor

```yaml
# Monitor 서비스 설정
astrago-monitor:
  image:
    repository: "{{ .Values.astrago.monitor.repository }}"
    tag: "{{ .Values.astrago.monitor.imageTag }}"
  
  env:
    PROMETHEUS_URL: "http://prometheus-kube-prometheus-prometheus:9090"
```

##### 8.4 Astrago Frontend

```yaml
# Frontend 서비스 설정
astrago-frontend:
  image:
    repository: "{{ .Values.astrago.frontend.repository }}"
    tag: "{{ .Values.astrago.frontend.imageTag }}"
  
  service:
    type: NodePort
    port: 80
    nodePort: "{{ .Values.astrago.servicePort }}"
```

#### 🔍 관리 명령어

```bash
# 전체 설치
helmfile -e astrago -l app=astrago sync

# 개별 컴포넌트 재시작
kubectl rollout restart deployment/astrago-core -n astrago
kubectl rollout restart deployment/astrago-frontend -n astrago

# 로그 확인
kubectl logs -f deployment/astrago-core -n astrago
kubectl logs -f deployment/astrago-batch -n astrago

# 서비스 상태 확인
kubectl get pods,svc -n astrago -l app.kubernetes.io/name=astrago
```

## 🚀 배포 순서 및 의존성

### 1. 기본 인프라 설치

```bash
# 1. 스토리지 프로비저너
helmfile -e astrago -l app=csi-driver-nfs sync

# 2. 모니터링 시스템
helmfile -e astrago -l app=prometheus sync

# 3. 인증 시스템
helmfile -e astrago -l app=keycloak sync
```

### 2. 선택적 구성요소 설치

```bash
# GPU 환경인 경우
helmfile -e astrago -l app=gpu-operator sync

# 분산 컴퓨팅 사용시
helmfile -e astrago -l app=mpi-operator sync

# 프라이빗 레지스트리 필요시
helmfile -e astrago -l app=harbor sync

# GitOps 사용시
helmfile -e astrago -l app=flux sync
```

### 3. 메인 애플리케이션 설치

```bash
# Astrago 플랫폼 설치
helmfile -e astrago -l app=astrago sync
```

## 🔧 애플리케이션 관리

### 개별 애플리케이션 업그레이드

```bash
# 특정 앱 업그레이드
helmfile -e astrago -l app=prometheus sync

# 차트 버전 확인
helm list -n astrago

# 롤백
helm rollback prometheus 1 -n astrago
```

### 설정 변경

```bash
# values.yaml 수정 후 적용
vi environments/astrago/values.yaml
helmfile -e astrago -l app=astrago sync
```

### 리소스 스케일링

```bash
# Replica 수 조정
kubectl scale deployment astrago-core --replicas=3 -n astrago

# HPA 설정
kubectl autoscale deployment astrago-core --cpu-percent=70 --min=2 --max=10 -n astrago
```

## 📊 모니터링 및 로깅

### 애플리케이션 상태 모니터링

```bash
# 전체 상태 확인
kubectl get pods,svc,pvc -n astrago

# 리소스 사용량 확인
kubectl top pods -n astrago

# 이벤트 확인
kubectl get events -n astrago --sort-by=.metadata.creationTimestamp
```

### 로그 집계

```bash
# 모든 Astrago 컴포넌트 로그
kubectl logs -l app.kubernetes.io/name=astrago -n astrago --tail=100

# 특정 시간대 로그
kubectl logs deployment/astrago-core -n astrago --since=1h
```

## 🔒 보안 관리

### RBAC 설정

```yaml
# 서비스 계정 및 권한 설정
apiVersion: v1
kind: ServiceAccount
metadata:
  name: astrago-sa
  namespace: astrago
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: astrago-role
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "create", "delete"]
```

### 네트워크 정책

```yaml
# 네트워크 격리
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: astrago-network-policy
  namespace: astrago
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: astrago
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: astrago
```

## 📚 참고 자료

### 공식 문서

- [Kubernetes CSI Documentation](https://kubernetes-csi.github.io/docs/)
- [Keycloak Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
- [Kubeflow MPI Operator](https://github.com/kubeflow/mpi-operator)
- [Harbor Documentation](https://goharbor.io/docs/)
- [Flux Documentation](https://fluxcd.io/docs/)

### 유용한 명령어 모음

```bash
# 모든 애플리케이션 상태 확인
for app in csi-driver-nfs keycloak prometheus gpu-operator mpi-operator harbor flux astrago; do
  echo "=== $app ==="
  helmfile -e astrago -l app=$app status
done

# 리소스 사용량 요약
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory
```
