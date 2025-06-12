# GPU 세션 모니터링 시스템 가이드

## 개요

GPU 세션 모니터링 시스템은 Kubernetes 클러스터에서 GPU 리소스를 사용하는 프로세스와 Pod들을 실시간으로 추적하고 모니터링하는 시스템입니다. 이 시스템은 Prometheus와 연동하여 GPU 사용량, 메모리 점유율, Pod 정보 등을 수집하고 시각화할 수 있게 합니다.

## 주요 기능

### 1. 🔍 실시간 GPU 프로세스 추적
- **정확한 PID 매핑**: nvidia-smi와 Prometheus에서 동일한 PID 정보 제공
- **GPU별 프로세스 분리**: 각 GPU에서 실행중인 프로세스를 정확히 구분
- **Pod 정보 연결**: Kubernetes Pod와 GPU 프로세스를 자동으로 연결

### 2. 🎯 MIG(Multi-Instance GPU) 지원
- **자동 MIG 감지**: MIG 모드 활성화 여부를 자동으로 판단
- **MIG 인스턴스별 모니터링**: 각 MIG 인스턴스의 독립적인 프로세스 추적
- **호환성 보장**: MIG 비활성화 환경에서도 정상 작동

### 3. 📊 다양한 메트릭 수집
- **프로세스 정보**: PID, 명령어, 메모리 사용량
- **GPU 사용량**: GPU별 세션 수, 총 세션 수
- **Pod 연결 정보**: 네임스페이스, Pod 이름, 컨테이너 정보
- **상태 모니터링**: 활성/유휴 상태 구분

## 시스템 아키텍처

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   CronJob       │    │  Node Exporter   │    │   Prometheus    │
│ (GPU Collector) │───▶│ (Textfile Dir)   │───▶│   (Scraping)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                                               │
         ▼                                               ▼
┌─────────────────┐                              ┌─────────────────┐
│   nvidia-smi    │                              │     Grafana     │
│   (GPU Info)    │                              │ (Visualization) │
└─────────────────┘                              └─────────────────┘
```

## 작동 원리

### 1. 데이터 수집 프로세스

#### 1단계: MIG 모드 감지
```bash
# MIG 모드 확인
nvidia-smi --query-gpu=mig.mode.current --format=csv,noheader,nounits
```

#### 2단계: GPU 목록 동적 생성
```bash
# MIG 비활성화시
GPU 0, GPU 1, GPU 2, GPU 3

# MIG 활성화시 (예시)
MIG 0/0/0, MIG 0/1/0, GPU 1, GPU 2, GPU 3
```

#### 3단계: 프로세스 정보 수집
```bash
# MIG 환경
nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory

# 일반 환경  
nvidia-smi --query-compute-apps=gpu_bus_id,pid,process_name,used_gpu_memory
```

#### 4단계: Pod 정보 매핑
```bash
# /proc/{PID}/cgroup에서 Kubernetes Pod 정보 추출
/proc/12345/cgroup → pod-abc123-def456
```

### 2. 메트릭 생성

시스템은 다음과 같은 Prometheus 메트릭을 생성합니다:

#### GPU 프로세스 정보
```prometheus
gpu_process_info{
  gpu="0",
  pid="12345", 
  command="python",
  pod="training-pod-abc123",
  namespace="ml-workspace",
  container="pytorch",
  status="active",
  gpu_memory="1024MiB"
} 1
```

#### GPU 세션 수
```prometheus
gpu_session_count{gpu="0"} 2
gpu_session_count{gpu="1"} 0
gpu_total_sessions 2
```

#### 프로세스 사용률
```prometheus
gpu_process_utilization{gpu="0",pid="12345",...} 85
gpu_process_memory_utilization{gpu="0",pid="12345",...} 60
```

## 설정 및 배포

### 1. 기본 설정 (values.yaml)
```yaml
gpu-session-monitoring:
  enabled: true

collection:
  schedule: "*/1 * * * *"  # 1분마다 실행
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi" 
      cpu: "200m"

nodeSelector:
  accelerator: "nvidia"

tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

### 2. 배포 명령어
```bash
# Helm을 사용한 배포
helm upgrade --install gpu-monitoring . \
  --set gpu-session-monitoring.enabled=true \
  --namespace monitoring
```

## 모니터링 및 확인

### 1. 수집 상태 확인
```bash
# CronJob 실행 상태 확인
kubectl get cronjob gpu-session-metrics-collector

# 최근 실행 로그 확인
kubectl logs -l job-name=gpu-session-metrics-collector-<timestamp>
```

### 2. 메트릭 파일 확인
```bash
# 노드에서 직접 확인
cat /var/lib/node_exporter/textfile_collector/gpu_sessions.prom
```

### 3. Prometheus에서 조회
```prometheus
# GPU별 현재 세션 수
gpu_session_count

# 특정 GPU의 활성 프로세스
gpu_process_info{gpu="0", status="active"}

# 전체 GPU 세션 수
gpu_total_sessions
```

## MIG 환경에서의 동작

### MIG 비활성화 환경
```
GPU 라벨: gpu="0", gpu="1", gpu="2", gpu="3"
식별 방식: PCI Bus ID 기반
매핑: nvidia-smi bus_id ↔ GPU index
```

### MIG 활성화 환경
```
GPU 라벨: gpu="0_0_0", gpu="0_1_0", gpu="1", gpu="2"
식별 방식: GPU UUID 기반  
매핑: nvidia-smi uuid ↔ MIG instance
```

### MIG 설정 예시
```bash
# MIG 모드 활성화
nvidia-smi -mig 1 -i 0

# MIG 인스턴스 생성 (1g.5gb 프로필 2개)
nvidia-smi mig -cgi 1g.5gb,1g.5gb -i 0

# 결과 확인
nvidia-smi -L
# GPU 0: A100-PCIE-40GB (UUID: GPU-...)
#   MIG 1g.5gb     Device  0: (UUID: MIG-...)
#   MIG 1g.5gb     Device  1: (UUID: MIG-...)
```

## 문제 해결

### 1. 메트릭이 수집되지 않는 경우

**증상**: Prometheus에서 gpu_* 메트릭이 보이지 않음

**해결방법**:
```bash
# 1. CronJob 상태 확인
kubectl describe cronjob gpu-session-metrics-collector

# 2. Pod 실행 로그 확인  
kubectl logs -l job-name=gpu-session-metrics-collector-<latest>

# 3. Node Exporter textfile 디렉터리 확인
ls -la /var/lib/node_exporter/textfile_collector/

# 4. nvidia-smi 접근 권한 확인
kubectl exec -it <gpu-pod> -- nvidia-smi
```

### 2. PID가 일치하지 않는 경우

**증상**: nvidia-smi와 Prometheus의 PID가 다름

**원인**: 이전 버전의 가짜 PID 생성 로직 사용

**해결방법**:
```bash
# 최신 버전으로 업데이트
helm upgrade gpu-monitoring . --reuse-values

# CronJob 수동 실행으로 테스트
kubectl create job --from=cronjob/gpu-session-metrics-collector test-job
```

### 3. MIG 환경에서 GPU 인식 오류

**증상**: MIG 인스턴스가 올바르게 표시되지 않음

**확인사항**:
```bash
# MIG 모드 상태 확인
nvidia-smi --query-gpu=mig.mode.current --format=csv

# MIG 인스턴스 목록 확인
nvidia-smi -L | grep MIG

# 컨테이너에서 MIG 접근 가능 여부 확인
kubectl exec -it <monitoring-pod> -- nvidia-smi -L
```

## 성능 고려사항

### 1. 수집 주기 조정
```yaml
# 높은 빈도 (실시간성 중요)
schedule: "*/30 * * * *"  # 30초마다

# 일반적인 사용
schedule: "*/1 * * * *"   # 1분마다 (기본값)

# 낮은 빈도 (리소스 절약)
schedule: "*/5 * * * *"   # 5분마다
```

### 2. 리소스 할당
```yaml
resources:
  requests:
    memory: "64Mi"    # 최소 요구사항
    cpu: "50m"
  limits:
    memory: "256Mi"   # nvidia-smi 실행을 위한 충분한 메모리
    cpu: "200m"       # 텍스트 처리를 위한 CPU
```

## 메트릭 활용 예시

### Grafana 대시보드 쿼리

#### 1. GPU 사용률 현황
```prometheus
# GPU별 활성 세션 수
sum by (gpu) (gpu_session_count)

# 전체 GPU 사용률
(sum(gpu_session_count) / count(gpu_session_count)) * 100
```

#### 2. Pod별 GPU 사용 현황
```prometheus
# Pod별 GPU 메모리 사용량
sum by (pod, namespace) (
  gpu_process_info{status="active"} * on(gpu,pid) group_left(gpu_memory) 
  gpu_process_info{status="active"}
)
```

#### 3. 유휴 GPU 감지
```prometheus
# 유휴 상태인 GPU 수
count(gpu_session_count == 0)

# 유휴 GPU 목록
gpu_process_info{status="idle"}
```

### 알람 설정 예시

```yaml
# GPU 사용률이 90% 이상일 때 알람
- alert: HighGPUUtilization
  expr: (sum(gpu_session_count) / count(gpu_session_count)) > 0.9
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "GPU utilization is high ({{ $value }}%)"

# 특정 GPU에서 장시간 동일 프로세스 실행 시 알람  
- alert: LongRunningGPUProcess
  expr: changes(gpu_process_info{status="active"}[1h]) == 0
  for: 2h
  labels:
    severity: info
  annotations:
    summary: "Long running process on GPU {{ $labels.gpu }}"
```

## 최신 업데이트 내역

### v2.0 (현재 버전)
- ✅ MIG(Multi-Instance GPU) 지원 추가
- ✅ 동적 GPU 감지 기능
- ✅ 정확한 PID 매핑 구현
- ✅ Pod 정보 자동 연결
- ✅ UUID 기반 MIG 인스턴스 식별

### v1.0 (이전 버전)
- ❌ 가짜 PID 생성 (수정됨)
- ❌ 하드코딩된 GPU 인덱스 (개선됨)
- ❌ MIG 미지원 (추가됨)

---

**문의사항이나 이슈가 있으시면 GitHub Issues나 Slack #gpu-monitoring 채널을 통해 연락해 주세요.** 