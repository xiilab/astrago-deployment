# GPU Process Monitoring Guide

완전한 GPU 프로세스 모니터링 솔루션 가이드

## 개요

GPU Process Exporter는 Kubernetes 클러스터에서 GPU 프로세스 정보를 실시간으로 수집하고 Prometheus 메트릭으로 내보내는 시스템입니다.

### 주요 기능

- **실시간 프로세스 추적**: nvidia-smi를 통한 GPU 프로세스 모니터링
- **Pod 정보 매핑**: cgroup을 통한 Kubernetes Pod과 GPU 프로세스 연결
- **MIG 지원**: Multi-Instance GPU 환경에서의 프로세스 추적
- **메트릭 내보내기**: Node Exporter textfile collector를 통한 Prometheus 연동

## 아키텍처

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kubernetes    │    │  GPU Process     │    │   Prometheus    │
│     Pods        │───▶│    Exporter      │───▶│    Metrics      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                        ┌──────────────────┐
                        │   nvidia-smi     │
                        │   GPU Driver     │
                        └──────────────────┘
```

## 설치 및 설정

### 1. 기본 설치

```bash
# 전체 스택 설치
./deploy_astrago.sh sync

# GPU Process Exporter만 설치
./deploy_astrago.sh sync gpu-process-exporter
```

### 2. 설정 커스터마이징

**environments/[환경]/values.yaml:**

```yaml
gpu-process-exporter:
  enabled: true
  
collection:
  schedule: "*/1 * * * *"  # 1분마다 수집
  resources:
    limits:
      cpu: 100m
      memory: 64Mi
      
gpu:
  count: 4                 # GPU 개수
  devices: [0, 1, 2, 3]   # 모니터링할 GPU 인덱스
```

## 수집되는 메트릭

### 1. 프로세스 카운트 메트릭

```prometheus
# GPU별 활성 프로세스 수
gpu_process_count{gpu="0"} 2

# 전체 GPU 프로세스 수
gpu_total_processes 5
```

### 2. 프로세스 정보 메트릭

```prometheus
gpu_process_info{
    gpu="1",
    pid="12345", 
    command="python3",
    pod="training-job-abc123",
    namespace="ml-workloads",
    container="pytorch",
    status="active",
    gpu_memory="4096MiB"
} 1
```

### 3. 리소스 사용률 메트릭

```prometheus
# GPU 사용률 (%)
gpu_process_utilization{
    gpu="1",
    pid="12345",
    command="python3",
    pod="training-job-abc123",
    namespace="ml-workloads"
} 85

# GPU 메모리 사용률 (%)
gpu_process_memory_utilization{
    gpu="1", 
    pid="12345",
    command="python3",
    pod="training-job-abc123",
    namespace="ml-workloads"
} 60
```

## MIG 환경 지원

### MIG 설정 확인

```bash
# MIG 모드 상태 확인
nvidia-smi --query-gpu=mig.mode.current --format=csv,noheader

# MIG 인스턴스 목록
nvidia-smi -L | grep MIG
```

### MIG 메트릭 예시

```prometheus
# MIG 인스턴스별 프로세스 (gpu="0_1_2" 형태)
gpu_process_count{gpu="0_1_2"} 1

gpu_process_info{
    gpu="0_1_2",
    pid="67890",
    command="tensorflow",
    status="active"
} 1
```

## 모니터링 대시보드

### Prometheus 쿼리 예시

```promql
# GPU별 프로세스 수 합계
sum by (gpu) (gpu_process_count)

# 네임스페이스별 GPU 사용률
avg by (namespace) (gpu_process_utilization)

# 활성 GPU 프로세스가 있는 Pod 목록
count by (pod) (gpu_process_info{status="active"})

# GPU 메모리 사용량이 높은 프로세스 (>80%)
gpu_process_memory_utilization > 80
```

### Grafana 대시보드 설정

**패널 예시:**

1. **GPU 프로세스 카운트 타임시리즈**

   ```promql
   gpu_process_count
   ```

2. **네임스페이스별 GPU 사용률 히트맵**

   ```promql
   avg by (namespace) (gpu_process_utilization)
   ```

3. **프로세스별 메모리 사용률 테이블**

   ```promql
   gpu_process_memory_utilization
   ```

## 트러블슈팅

### 메트릭이 수집되지 않는 경우

1. **CronJob 상태 확인:**

```bash
kubectl get cronjobs -n gpu-operator
kubectl get jobs -n gpu-operator
```

2. **로그 확인:**

```bash
kubectl logs -l job-name=gpu-process-metrics-collector -n gpu-operator
```

3. **Node Exporter textfile 확인:**

```bash
kubectl exec -it [node-exporter-pod] -- ls -la /var/lib/node_exporter/textfile_collector/
```

### nvidia-smi 관련 문제

1. **GPU 드라이버 상태:**

```bash
kubectl exec -it [gpu-node] -- nvidia-smi
```

2. **권한 문제:**

```bash
# GPU 노드에서 실행
ls -la /dev/nvidia*
```

### Pod 매핑이 안 되는 경우

1. **cgroup 마운트 확인:**

```bash
kubectl describe pod gpu-process-metrics-collector -n gpu-operator
```

2. **hostPID 설정 확인:**

```yaml
spec:
  hostPID: true  # 반드시 true여야 함
```

## 성능 최적화

### 수집 주기 조정

```yaml
collection:
  schedule: "*/2 * * * *"  # 2분마다 수집으로 변경
```

### 리소스 제한 최적화

```yaml
collection:
  resources:
    limits:
      cpu: 200m      # CPU 제한 증가
      memory: 128Mi  # 메모리 제한 증가
```

### GPU 필터링

```yaml
gpu:
  devices: [0, 1]  # 특정 GPU만 모니터링
```

## 보안 고려사항

### 권한 최소화

- CronJob은 필요한 최소 권한만 부여
- hostPID는 프로세스 정보 수집에만 사용
- GPU 노드 접근은 읽기 전용으로 제한

### 민감한 정보 보호

- 프로세스 명령줄에서 비밀번호 등 제외
- Pod 이름과 네임스페이스 정보만 수집
- 실제 프로세스 데이터는 수집하지 않음

## 확장 가능성

### 커스텀 메트릭 추가

스크립트를 수정하여 추가 메트릭 수집 가능:

```bash
# GPU 온도 정보 추가
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader

# GPU 전력 사용량 추가  
nvidia-smi --query-gpu=power.draw --format=csv,noheader
```

### 다중 클러스터 지원

Federation을 통한 여러 클러스터 통합 모니터링

---

**관련 문서:**

- [GPU Process Monitoring QuickStart](GPU-Process-Monitoring-QuickStart.md)
- [Architecture Guide](architecture.md)
- [Troubleshooting Guide](troubleshooting.md)
