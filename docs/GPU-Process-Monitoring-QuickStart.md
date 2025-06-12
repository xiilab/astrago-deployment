# GPU Process Monitoring - QuickStart

5분만에 GPU 프로세스 모니터링 시작하기 🚀

## 📋 전제조건

- ✅ Kubernetes 클러스터 (GPU 노드 포함)
- ✅ NVIDIA GPU Driver 설치됨
- ✅ prometheus 및 node-exporter 배포됨

## 🚀 빠른 시작

### 1. GPU Process Exporter 배포

```bash
# AstraGo 프로젝트 클론
git clone <repository-url>
cd astrago-deployment

# GPU Process Exporter 배포
./deploy_astrago.sh sync gpu-process-exporter
```

### 2. 배포 상태 확인

```bash
# CronJob 상태 확인
kubectl get cronjobs -n gpu-operator

# NAME                             SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# gpu-process-metrics-collector    */1 * * * *   False     0        47s             2m
```

### 3. 메트릭 수집 확인

```bash
# 최근 실행된 Job 로그 확인
kubectl logs -l job-name=gpu-process-metrics-collector -n gpu-operator --tail=10

# 2024-01-15 10:30:02: GPU process metrics collected with MIG-aware GPU mapping
# gpu_process_count{gpu="0"} 2
# gpu_process_count{gpu="1"} 0
# gpu_total_processes 2
```

### 4. Prometheus에서 확인

```bash
# Port Forward (선택사항)
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n prometheus

# 브라우저에서 접속: http://localhost:9090
# 쿼리 실행: gpu_process_count
```

## 📊 주요 메트릭 확인

### GPU별 프로세스 수

```promql
gpu_process_count
```

### 활성 GPU 프로세스 정보

```promql
gpu_process_info{status="active"}
```

### 전체 GPU 프로세스 수

```promql
gpu_total_processes
```

## 🎯 테스트 워크로드 실행

GPU 프로세스 모니터링을 테스트하기 위해 간단한 워크로드를 실행해보세요:

```bash
# GPU 테스트 Pod 실행
kubectl run gpu-test --image=nvidia/cuda:11.8-runtime-ubuntu20.04 \
  --limits=nvidia.com/gpu=1 \
  --command -- /bin/bash -c "while true; do nvidia-smi; sleep 60; done"

# 1분 후 메트릭 확인
kubectl logs -l job-name=gpu-process-metrics-collector -n gpu-operator --tail=5
```

## 🔧 설정 커스터마이징

기본 설정을 변경하려면 `environments/[환경]/values.yaml` 파일을 수정하세요:

```yaml
gpu-process-exporter:
  enabled: true
  
collection:
  schedule: "*/2 * * * *"  # 2분마다 수집
  
gpu:
  count: 8                 # GPU 개수 변경
  devices: [0,1,2,3,4,5,6,7]  # 모니터링할 GPU
```

변경 후 재배포:

```bash
./deploy_astrago.sh sync gpu-process-exporter
```

## 🚨 문제 해결

### 메트릭이 수집되지 않는 경우

1. **GPU 드라이버 확인:**

```bash
kubectl exec -it <gpu-node> -- nvidia-smi
```

2. **CronJob 로그 확인:**

```bash
kubectl describe cronjob gpu-process-metrics-collector -n gpu-operator
kubectl logs -l job-name=gpu-process-metrics-collector -n gpu-operator
```

3. **Node Exporter textfile 확인:**

```bash
kubectl exec -it <node-exporter-pod> -n prometheus -- \
  cat /var/lib/node_exporter/textfile_collector/gpu_processes.prom
```

## ⚡ MIG 환경에서 사용

Multi-Instance GPU 환경에서는 자동으로 MIG 인스턴스를 감지합니다:

```bash
# MIG 모드 확인
nvidia-smi --query-gpu=mig.mode.current --format=csv,noheader

# MIG 인스턴스 목록
nvidia-smi -L | grep MIG
```

MIG 환경에서의 메트릭 예시:

```prometheus
gpu_process_count{gpu="0_1_0"} 1  # GPU 0의 첫 번째 MIG 인스턴스
gpu_process_count{gpu="0_1_1"} 0  # GPU 0의 두 번째 MIG 인스턴스
```

## 📈 Grafana 대시보드

Grafana에서 시각화하려면 다음 쿼리를 사용하세요:

### GPU 사용률 현황

```promql
sum by (gpu) (gpu_process_count)
```

### 네임스페이스별 GPU 사용량

```promql
count by (namespace) (gpu_process_info{status="active"})
```

### GPU 메모리 사용률 (높은 순)

```promql
topk(10, gpu_process_memory_utilization)
```

## 🎁 다음 단계

- 📖 [완전한 GPU Process Monitoring 가이드](GPU-Process-Monitoring-Guide.md) 읽기
- 🎯 커스텀 알람 설정하기
- 📊 고급 Grafana 대시보드 구성하기
- 🔧 성능 최적화 적용하기

---

**5분 안에 GPU 프로세스 모니터링이 준비되었습니다!** 🎉  
더 자세한 설정과 고급 기능은 [완전한 가이드](GPU-Process-Monitoring-Guide.md)를 참조하세요.
