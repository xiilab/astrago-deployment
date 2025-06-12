# GPU Process Exporter

GPU 프로세스 정보를 Prometheus 메트릭으로 수집하고 내보내는 exporter

## 개요

이 모듈은 Kubernetes 클러스터의 GPU에서 실행 중인 프로세스 정보를 모니터링하여 다음 정보를 Prometheus 메트릭으로 수집합니다:

- **GPU별 활성 프로세스 수**: 각 GPU에서 실행 중인 프로세스 수
- **프로세스별 상세 정보**: PID, 프로세스 이름, Pod 정보, 네임스페이스
- **GPU/메모리 사용률**: 프로세스별 GPU 및 메모리 사용률
- **실시간 모니터링**: 1분마다 자동 업데이트
- **MIG 지원**: NVIDIA Multi-Instance GPU 환경 지원

## 아키텍처

```
AstraGo ← Prometheus ← Node Exporter ← GPU Process Exporter (CronJob)
                                    ↑
                               nvidia-smi
```

## 수집되는 메트릭

### 1. 기본 프로세스 카운트

```prometheus
gpu_process_count{gpu="0"} 1
gpu_total_processes 3
```

### 2. 프로세스 정보

```prometheus
gpu_process_info{
    gpu="1",
    pid="gpu1_12345",
    command="python3",
    pod="workload-pod",
    namespace="workspace",
    container="gpu-container",
    status="active",
    gpu_memory="2048MiB"
} 1
```

### 3. 프로세스별 GPU 사용률

```prometheus
gpu_process_utilization{
    gpu="1",
    pid="gpu1_12345",
    command="python3",
    pod="workload-pod",
    namespace="workspace"
} 75
```

### 4. 프로세스별 메모리 사용률

```prometheus
gpu_process_memory_utilization{
    gpu="1",
    pid="gpu1_12345",
    command="python3",
    pod="workload-pod",
    namespace="workspace"
} 45
```

## 배포 방법

### 1. 전체 스택 배포

```bash
./deploy_astrago.sh sync
```

### 2. GPU Process Exporter만 배포

```bash
./deploy_astrago.sh sync gpu-process-exporter
```

### 3. 삭제

```bash
./deploy_astrago.sh destroy gpu-process-exporter
```

## 설정 옵션

### values.yaml 주요 설정

```yaml
gpu-process-exporter:
  enabled: true

collection:
  schedule: "*/1 * * * *"  # 수집 주기 (1분마다)
  
gpu:
  count: 4                 # 모니터링할 GPU 수
  devices: [0, 1, 2, 3]   # GPU 장치 인덱스
```

## 모니터링 확인

### 1. Prometheus에서 메트릭 확인

```bash
# GPU 프로세스 수
curl "http://prometheus-url:30090/api/v1/query?query=gpu_process_count"

# 프로세스 정보
curl "http://prometheus-url:30090/api/v1/query?query=gpu_process_info"
```

### 2. CronJob 상태 확인

```bash
kubectl get cronjobs -n gpu-operator
kubectl get jobs -n gpu-operator
```

### 3. 로그 확인

```bash
kubectl logs -l job-name=gpu-process-metrics-collector -n gpu-operator
```

## 특징

### MIG (Multi-Instance GPU) 지원

- NVIDIA MIG 환경에서 인스턴스별 프로세스 추적
- UUID 기반 프로세스 매핑
- 동적 GPU/MIG 인스턴스 감지

### Pod 정보 연결

- cgroup 정보를 통한 Pod UID 추출
- Kubernetes 워크로드와 GPU 프로세스 연결
- 네임스페이스 및 컨테이너 정보 수집

## 의존성

- **NVIDIA GPU Driver**: nvidia-smi 명령어 사용
- **Node Exporter**: textfile collector를 통한 커스텀 메트릭 수집
- **Prometheus**: 메트릭 저장 및 조회

## 트러블슈팅

### 메트릭이 수집되지 않는 경우

1. Node Exporter에 textfile collector가 활성화되어 있는지 확인
2. CronJob이 정상 실행되는지 확인
3. GPU 노드에 nvidia.com/gpu.present 라벨이 있는지 확인

### 프로세스 정보가 없는 경우

1. 실제 GPU 워크로드가 실행 중인지 확인
2. nvidia-smi 명령어가 정상 동작하는지 확인
3. GPU 드라이버가 정상 설치되어 있는지 확인

### MIG 환경에서 문제가 있는 경우

1. MIG 모드가 활성화되어 있는지 확인
2. MIG 인스턴스가 생성되어 있는지 확인
3. UUID 기반 매핑이 정상 동작하는지 로그 확인
