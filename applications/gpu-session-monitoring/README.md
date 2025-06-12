# GPU Session Monitoring

Linear BE-102: 각 GPU/MIG에 연결된 사용자 수 및 세션별 리소스 사용량 모니터링

## 개요

이 모듈은 Kubernetes 클러스터의 GPU 리소스를 모니터링하여 다음 정보를 Prometheus 메트릭으로 수집합니다:

- **GPU별 활성 세션 수**: 각 GPU에서 실행 중인 프로세스 수
- **프로세스별 상세 정보**: PID, 프로세스 이름, Pod 정보, 네임스페이스
- **GPU/메모리 사용률**: 프로세스별 GPU 및 메모리 사용률
- **실시간 모니터링**: 1분마다 자동 업데이트

## 아키텍처

```
AstraGo ← Prometheus ← Node Exporter ← GPU Session Collector (CronJob)
                                    ↑
                               DCGM Exporter
```

## 수집되는 메트릭

### 1. 기본 세션 카운트
```prometheus
gpu_session_count{gpu="0"} 1
gpu_total_sessions 3
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
    status="active"
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

### 2. GPU 세션 모니터링만 배포
```bash
./deploy_astrago.sh sync gpu-session-monitoring
```

### 3. 삭제
```bash
./deploy_astrago.sh destroy gpu-session-monitoring
```

## 설정 옵션

### values.yaml 주요 설정
```yaml
gpu-session-monitoring:
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
# GPU 세션 수
curl "http://prometheus-url:30090/api/v1/query?query=gpu_session_count"

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
kubectl logs -l job-name=gpu-session-metrics-collector -n gpu-operator
```

## 의존성

- **NVIDIA GPU Operator**: GPU 메트릭 수집을 위한 DCGM Exporter
- **Prometheus**: 메트릭 저장 및 조회
- **Node Exporter**: textfile collector를 통한 커스텀 메트릭 수집

## 트러블슈팅

### 메트릭이 수집되지 않는 경우
1. Node Exporter에 textfile collector가 활성화되어 있는지 확인
2. CronJob이 정상 실행되는지 확인
3. GPU 노드에 nvidia.com/gpu.present 라벨이 있는지 확인

### 프로세스 정보가 없는 경우
1. 실제 GPU 워크로드가 실행 중인지 확인
2. DCGM Exporter가 정상 동작하는지 확인
3. Prometheus 서비스 연결 상태 확인 