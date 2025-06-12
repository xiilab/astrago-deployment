# GPU 세션 모니터링 빠른 시작 가이드

## ⚡ 3분만에 시작하기

### 1단계: 활성화
```yaml
# values.yaml 또는 환경별 설정
gpu-session-monitoring:
  enabled: true
```

### 2단계: 배포
```bash
helm upgrade --install astrago . --reuse-values
```

### 3단계: 확인
```bash
# 수집기 동작 확인
kubectl get cronjob gpu-session-metrics-collector

# 메트릭 확인
kubectl logs -l job-name=gpu-session-metrics-collector-$(date +%s | tail -c 5)
```

## 🎯 주요 메트릭

### Prometheus에서 바로 사용할 수 있는 쿼리들

#### 현재 GPU 사용 현황
```prometheus
# GPU별 활성 프로세스 수
gpu_session_count

# 전체 GPU 사용률 (%)
(sum(gpu_session_count) / count(gpu_session_count)) * 100

# 유휴 GPU 개수
count(gpu_session_count == 0)
```

#### 프로세스 정보
```prometheus
# 활성 프로세스 목록 (PID와 명령어 포함)
gpu_process_info{status="active"}

# GPU별 메모리 사용량 (MiB)
gpu_process_info{status="active", gpu_memory!="0MiB"}
```

#### Pod 정보
```prometheus
# Pod별 GPU 사용 현황  
gpu_process_info{status="active", pod!="unknown"}

# 네임스페이스별 GPU 사용량
sum by (namespace) (gpu_process_info{status="active"})
```

## 🔍 문제 해결

### 메트릭이 안 보인다면?
```bash
# 1. CronJob 상태 확인
kubectl describe cronjob gpu-session-metrics-collector

# 2. 최신 실행 로그 확인
kubectl logs $(kubectl get pods -l job-name -o name | tail -1)

# 3. Node Exporter 연결 확인
curl http://<node-ip>:9100/metrics | grep gpu_
```

### nvidia-smi와 PID가 다르다면?
```bash
# nvidia-smi로 실제 PID 확인
nvidia-smi --query-compute-apps=pid,process_name --format=csv

# Prometheus에서 확인
gpu_process_info{status="active"}

# 같은 PID가 나와야 정상!
```

## 🎨 Grafana 대시보드

### 기본 패널들

#### 1. GPU 사용률 (Stat Panel)
```prometheus
Query: (sum(gpu_session_count) / count(gpu_session_count)) * 100
Unit: Percent (0-100)
```

#### 2. GPU별 활성 세션 (Bar Gauge)
```prometheus
Query: gpu_session_count
Legend: GPU {{gpu}}
```

#### 3. 활성 프로세스 테이블 (Table Panel)
```prometheus
Query: gpu_process_info{status="active"}
Columns: gpu, pid, command, pod, gpu_memory
```

#### 4. 시간별 사용 추이 (Time Series)
```prometheus
Query: sum(gpu_session_count)
Title: "Total GPU Sessions Over Time"
```

## 📋 자주 사용하는 알람

### Prometheus AlertManager 규칙

```yaml
# alerts.yaml
groups:
- name: gpu-monitoring
  rules:
  # GPU 사용률 높음
  - alert: HighGPUUsage
    expr: (sum(gpu_session_count) / count(gpu_session_count)) > 0.8
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "GPU usage is {{ $value | humanizePercentage }}"
      
  # 장시간 실행 프로세스
  - alert: StuckGPUProcess  
    expr: changes(gpu_process_info{status="active"}[2h]) == 0
    for: 30m
    labels:
      severity: info
    annotations:
      summary: "Process {{ $labels.pid }} stuck on GPU {{ $labels.gpu }}"
```

## 🏃‍♂️ 고급 사용법

### MIG 환경에서 사용
```bash
# MIG 활성화 확인
nvidia-smi --query-gpu=mig.mode.current --format=csv

# MIG 인스턴스별 메트릭 확인
gpu_process_info{gpu=~".*_.*_.*"}  # MIG 인스턴스 (언더스코어 포함)
```

### 성능 최적화
```yaml
# 실시간 모니터링이 필요한 경우
collection:
  schedule: "*/30 * * * *"  # 30초마다

# 리소스 절약이 필요한 경우  
collection:
  schedule: "*/5 * * * *"   # 5분마다
  resources:
    limits:
      memory: "128Mi"
      cpu: "100m"
```

## 📞 지원

- 🐛 **버그 리포트**: GitHub Issues
- 💬 **질문**: Slack #gpu-monitoring
- 📖 **상세 문서**: [GPU-Session-Monitoring-Guide.md](./GPU-Session-Monitoring-Guide.md)

---

**🎉 축하합니다! 이제 GPU 리소스를 효과적으로 모니터링할 수 있습니다.** 