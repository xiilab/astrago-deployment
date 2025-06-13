# Loki Stack

완전한 로깅 솔루션 - Loki와 Promtail을 포함한 Kubernetes 로그 수집 및 저장 시스템

## 개요

Loki Stack은 Kubernetes 클러스터의 모든 로그를 수집, 저장, 조회할 수 있는 완전한 로깅 솔루션입니다.

### 주요 구성요소

- **Loki**: 로그 저장소 및 쿼리 엔진 (Prometheus와 유사한 라벨 기반)
- **Promtail**: 로그 수집 에이전트 (모든 노드에서 DaemonSet으로 실행)

### 주요 기능

- **라벨 기반 로그 저장**: Prometheus와 동일한 라벨링 시스템
- **효율적인 압축**: 로그 데이터의 효율적인 저장
- **LogQL**: 강력한 로그 쿼리 언어
- **Grafana 통합**: Grafana에서 로그 시각화 및 대시보드 구성
- **자동 로그 수집**: Kubernetes Pod 로그 자동 수집
- **시스템 로그 수집**: 노드 시스템 로그 수집

## 아키텍처

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kubernetes    │    │     Promtail     │    │      Loki       │
│      Pods       │───▶│   (DaemonSet)    │───▶│  (SingleBinary) │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                        ┌──────────────────┐    ┌─────────────────┐
                        │   System Logs    │    │   Grafana       │
                        │   (/var/log)     │    │ (Log Queries)   │
                        └──────────────────┘    └─────────────────┘
```

## 설치 및 설정

### 1. 기본 설치

```bash
# 전체 스택 설치
./deploy_astrago.sh sync

# Loki Stack만 설치
./deploy_astrago.sh sync loki-stack
```

### 2. 설정 커스터마이징

**environments/[환경]/values.yaml:**

```yaml
# Loki 설정
loki:
  enabled: true
  retentionPeriod: "744h"  # 31일
  replicas: 1
  resources:
    limits:
      cpu: "1000m"
      memory: "2Gi"
    requests:
      cpu: "500m"
      memory: "1Gi"
  persistence:
    enabled: true
    size: "10Gi"
    storageClass: ""

# Promtail 설정
promtail:
  enabled: true
  resources:
    limits:
      cpu: "200m"
      memory: "256Mi"
    requests:
      cpu: "100m"
      memory: "128Mi"
  extraScrapeConfigs: []
```

## 로그 수집 범위

### 1. Kubernetes Pod 로그

- **경로**: `/var/log/pods/*/*.log`
- **형식**: CRI 로그 형식 자동 파싱
- **라벨**: namespace, pod, container, app 등

### 2. 시스템 로그

- **경로**: `/var/log/syslog`
- **라벨**: job=kubernetes-system

### 3. 수집되는 라벨 정보

```
{
  namespace="default",
  pod="my-app-12345",
  container="app",
  app="my-application",
  node_name="worker-1",
  job="default/my-app"
}
```

## LogQL 쿼리 예시

### 기본 쿼리

```logql
# 특정 네임스페이스의 모든 로그
{namespace="gpu-operator"}

# 특정 Pod의 로그
{pod="gpu-process-metrics-collector-12345"}

# 특정 앱의 로그
{app="loki-stack"}

# 에러 로그만 필터링
{namespace="default"} |= "error"

# 정규식으로 필터링
{namespace="default"} |~ "ERROR|WARN"
```

### 고급 쿼리

```logql
# 시간대별 로그 카운트
count_over_time({namespace="gpu-operator"}[5m])

# 에러 로그 비율
rate({namespace="default"} |= "error" [5m])

# 특정 패턴 추출
{namespace="default"} | json | line_format "{{.level}}: {{.message}}"

# 메트릭 생성
sum(rate({namespace="gpu-operator"}[5m])) by (pod)
```

## Grafana 통합

### 1. 데이터소스 추가

```yaml
# Grafana에서 Loki 데이터소스 설정
URL: http://loki-stack-loki.loki-stack.svc:3100
Access: Server (default)
```

### 2. 대시보드 예시

#### 로그 볼륨 패널

```logql
sum(rate({namespace=~".+"}[5m])) by (namespace)
```

#### 에러 로그 추적

```logql
{namespace="gpu-operator"} |= "error" | line_format "{{.timestamp}} [{{.level}}] {{.message}}"
```

#### Pod별 로그 분포

```logql
topk(10, sum(rate({namespace="default"}[5m])) by (pod))
```

## 모니터링 및 알람

### 1. Prometheus 메트릭

Loki와 Promtail은 자체 메트릭을 노출합니다:

```prometheus
# Loki 메트릭
loki_ingester_streams_total
loki_distributor_lines_received_total
loki_query_duration_seconds

# Promtail 메트릭
promtail_targets_active_total
promtail_read_lines_total
promtail_sent_entries_total
```

### 2. 알람 예시

```yaml
# 로그 수집 중단 알람
- alert: PromtailDown
  expr: up{job="promtail"} == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Promtail is down on {{ $labels.instance }}"

# 높은 에러 로그 비율
- alert: HighErrorLogRate
  expr: rate({namespace="default"} |= "error" [5m]) > 0.1
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "High error log rate in {{ $labels.namespace }}"
```

## 성능 최적화

### 1. 리소스 조정

```yaml
# 대용량 환경
loki:
  resources:
    limits:
      cpu: "2000m"
      memory: "4Gi"
    requests:
      cpu: "1000m"
      memory: "2Gi"
  persistence:
    size: "50Gi"

# 소규모 환경
loki:
  resources:
    limits:
      cpu: "500m"
      memory: "1Gi"
    requests:
      cpu: "250m"
      memory: "512Mi"
  persistence:
    size: "5Gi"
```

### 2. 보존 기간 설정

```yaml
loki:
  retentionPeriod: "168h"  # 7일 (짧은 보존)
  # retentionPeriod: "2160h"  # 90일 (긴 보존)
```

### 3. Promtail 필터링

```yaml
promtail:
  extraScrapeConfigs:
    # 특정 네임스페이스만 수집
    - job_name: important-apps
      kubernetes_sd_configs:
        - role: pod
          namespaces:
            names: ["production", "gpu-operator"]
      pipeline_stages:
        - cri: {}
        # 에러 로그만 수집
        - match:
            selector: '{job="important-apps"}'
            stages:
            - regex:
                expression: '.*(?P<level>ERROR|WARN).*'
            - labels:
                level:
```

## 트러블슈팅

### 1. Loki가 시작되지 않는 경우

```bash
# Loki Pod 상태 확인
kubectl get pods -n loki-stack

# Loki 로그 확인
kubectl logs -n loki-stack loki-stack-loki-0

# 스토리지 확인
kubectl get pvc -n loki-stack
```

### 2. Promtail이 로그를 수집하지 않는 경우

```bash
# Promtail DaemonSet 확인
kubectl get daemonset -n loki-stack

# Promtail 로그 확인
kubectl logs -n loki-stack -l app.kubernetes.io/name=promtail

# 타겟 확인
curl http://promtail-pod:3101/targets
```

### 3. 로그가 Grafana에서 보이지 않는 경우

```bash
# Loki 연결 테스트
curl http://loki-stack-loki.loki-stack.svc:3100/ready

# 라벨 확인
curl http://loki-stack-loki.loki-stack.svc:3100/loki/api/v1/labels

# 쿼리 테스트
curl -G -s "http://loki-stack-loki.loki-stack.svc:3100/loki/api/v1/query" \
  --data-urlencode 'query={namespace="default"}'
```

## 보안 고려사항

### 1. 네트워크 정책

```yaml
# Loki 접근 제한
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: loki-access
  namespace: loki-stack
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: loki
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: grafana
    - namespaceSelector:
        matchLabels:
          name: loki-stack
```

### 2. RBAC 설정

Promtail은 Pod 로그에 접근하기 위해 적절한 권한이 필요합니다:

```yaml
# 자동으로 생성되는 RBAC 권한
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
```

## 확장 기능

### 1. 멀티테넌시

```yaml
loki:
  loki:
    auth_enabled: true
    # 테넌트별 설정 추가
```

### 2. 외부 스토리지 연동

```yaml
loki:
  loki:
    storage_config:
      aws:
        s3: s3://my-loki-bucket
        region: us-west-2
```

### 3. 고가용성 구성

```yaml
loki:
  deploymentMode: Distributed
  # 분산 모드 설정
```

---

**관련 문서:**

- [LogQL 쿼리 가이드](https://grafana.com/docs/loki/latest/logql/)
- [Grafana Loki 통합](https://grafana.com/docs/grafana/latest/datasources/loki/)
- [Architecture Guide](../docs/architecture.md)
