# 🔗 Prometheus ↔ Loki 자동 연동 가이드

## 📋 개요

이 문서는 Astrago 설치 시 Prometheus와 Loki가 자동으로 연동되도록 설정하는 방법을 설명합니다. 설정 완료 후에는 Grafana에서 별도 설정 없이 Loki 데이터소스를 사용할 수 있습니다.

## ⚡ 자동 연동 설치 방법

### 🚀 **방법 1: 전체 자동 설치 (권장)**

```bash
# 1. 환경 설정
./deploy_astrago.sh env

# 2. 전체 설치 (올바른 순서로 자동 설치됨)
./deploy_astrago.sh sync
```

**설치 순서:**

1. `loki-stack` → Loki 및 Promtail 설치
2. `prometheus` → Grafana에 Loki 데이터소스 자동 추가
3. 기타 애플리케이션들

### 🔧 **방법 2: 단계별 수동 설치**

```bash
# 1. Loki Stack 먼저 설치
./deploy_astrago.sh sync loki-stack

# 2. Loki 서비스 준비 대기 (30초)
sleep 30

# 3. Prometheus 설치 (Loki 데이터소스 자동 포함)
./deploy_astrago.sh sync prometheus

# 4. 나머지 애플리케이션 설치
./deploy_astrago.sh sync keycloak
./deploy_astrago.sh sync astrago
```

## 🔍 자동 연동 확인

### **1단계: Grafana 접속**

```bash
# Grafana URL 확인
echo "Grafana: http://$(kubectl get svc prometheus-grafana -n prometheus -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"

# 또는 NodePort 사용
kubectl get svc prometheus-grafana -n prometheus
```

### **2단계: 데이터소스 확인**

Grafana 웹 UI에서:

1. **Configuration** → **Data Sources**
2. 다음 데이터소스들이 자동으로 추가되어 있는지 확인:
   - ✅ **Prometheus** (기본 데이터소스)
   - ✅ **Loki** (로그 데이터소스)

### **3단계: 연동 테스트**

```bash
# Prometheus에서 Loki 메트릭 확인
curl -s "http://YOUR_IP:30090/api/v1/query?query=loki_build_info"

# Loki 서비스 상태 확인
kubectl get pods -n loki-stack
kubectl get svc -n loki-stack
```

## 📊 자동 추가되는 대시보드

설치 완료 후 Grafana에서 다음 대시보드들이 자동으로 사용 가능합니다:

### **Loki 폴더:**

- **Loki Logs Dashboard** (ID: 13639)
  - 실시간 로그 스트림
  - 네임스페이스별 로그 분류
  - 로그 레벨별 필터링

- **Loki Operational Dashboard** (ID: 14055)
  - Loki 서버 성능 메트릭
  - Promtail 수집 상태
  - 스토리지 사용량

## 🎯 유용한 LogQL 쿼리 예시

### **기본 로그 조회:**

```logql
# 모든 Astrago 로그
{namespace="astrago"}

# 특정 Pod 로그
{pod="astrago-core-xxx"}

# 에러 로그만 필터링
{namespace="astrago"} |= "error"
```

### **고급 로그 분석:**

```logql
# 시간당 에러 로그 수
sum(count_over_time({namespace="astrago"} |= "error" [1h]))

# 네임스페이스별 로그 볼륨
sum(rate({namespace=~".+"}[1m])) by (namespace)

# GPU 관련 로그
{namespace="gpu-operator"} |= "gpu"
```

## 🔧 설정 커스터마이징

### **Loki 데이터소스 설정 수정**

`applications/prometheus/values.yaml.gotmpl` 파일에서:

```yaml
grafana:
  datasources:
    datasources.yaml:
      datasources:
      - name: Loki
        type: loki
        url: http://loki-stack.loki-stack.svc.cluster.local:3100
        access: proxy
        jsonData:
          maxLines: 5000  # 최대 로그 라인 수 증가
          timeout: 60     # 타임아웃 설정
```

### **추가 대시보드 설정**

```yaml
grafana:
  dashboards:
    loki:
      custom-logs:
        gnetId: YOUR_DASHBOARD_ID
        revision: 1
        datasource: Loki
```

## 🚨 문제 해결

### **데이터소스가 자동 추가되지 않는 경우:**

```bash
# 1. Grafana Pod 재시작
kubectl rollout restart deployment prometheus-grafana -n prometheus

# 2. 설정 확인
kubectl get configmap prometheus-grafana -n prometheus -o yaml | grep -A 20 datasources

# 3. 수동으로 데이터소스 추가
curl -X POST http://YOUR_IP:30090/grafana/api/datasources \
  -H 'Content-Type: application/json' \
  -u admin:prom-operator \
  -d '{
    "name": "Loki",
    "type": "loki", 
    "url": "http://loki-stack.loki-stack.svc.cluster.local:3100",
    "access": "proxy"
  }'
```

### **Loki 연결 실패 시:**

```bash
# 1. Loki 서비스 상태 확인
kubectl get svc loki-stack -n loki-stack

# 2. 네트워크 연결 테스트
kubectl exec -it prometheus-grafana-xxx -n prometheus -- \
  curl -s http://loki-stack.loki-stack.svc.cluster.local:3100/ready

# 3. DNS 해결 확인
kubectl exec -it prometheus-grafana-xxx -n prometheus -- \
  nslookup loki-stack.loki-stack.svc.cluster.local
```

## 📈 모니터링 베스트 프랙티스

### **1. 통합 대시보드 구성**

- 상단: Prometheus 메트릭 (CPU, 메모리, GPU)
- 하단: 해당 시간대 Loki 로그 (에러, 경고)

### **2. 알림 설정**

```yaml
# Prometheus 알림 규칙
groups:
- name: loki-alerts
  rules:
  - alert: LokiDown
    expr: up{job="loki-stack/loki-stack"} == 0
    for: 5m
    annotations:
      summary: "Loki is down"
```

### **3. 로그 보존 정책**

```yaml
# Loki 설정
loki:
  limits_config:
    retention_period: 168h  # 7일 보존
    max_global_streams_per_user: 10000
```

## 🎉 완료

이제 Astrago 설치 시 Prometheus와 Loki가 자동으로 연동되어 통합 모니터링 환경이 구축됩니다!

**접속 정보:**

- **Grafana**: http://YOUR_IP:30090/grafana
- **Prometheus**: http://YOUR_IP:30090
- **Loki**: <http://loki-stack.loki-stack.svc.cluster.local:3100> (클러스터 내부)
