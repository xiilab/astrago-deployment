# 🌍 Astrago 환경 설정 가이드

## 📋 개요

Astrago는 다양한 환경(개발, 스테이징, 프로덕션)에서 배포할 수 있도록 유연한 환경 설정을 제공합니다. 이 문서는 각 환경별 설정 방법과 최적화 전략을 안내합니다.

## 🏗️ 환경 구조

```
environments/
├── common/           # 공통 설정
│   └── values.yaml
├── dev/             # 개발 환경
│   └── values.yaml
├── dev2/            # 개발 환경 2
│   └── values.yaml
├── stage/           # 스테이징 환경
│   └── values.yaml
├── prod/            # 프로덕션 환경
│   └── values.yaml
├── seoultech/       # 서울과기대 환경
│   └── values.yaml
└── astrago/         # 배포시 생성되는 환경
    └── values.yaml
```

## 🔧 환경 설정 방법

### 1. 공통 설정 (common/values.yaml)

모든 환경에서 공통으로 사용되는 설정입니다.

```yaml
# environments/common/values.yaml
keycloak:
  themeVersion: v1.1.5

# 공통 리소스 제한
resources:
  defaultLimits:
    cpu: "1000m"
    memory: "2Gi"
  defaultRequests:
    cpu: "100m"
    memory: "256Mi"

# 공통 보안 설정
security:
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
```

### 2. 개발 환경 (dev/values.yaml)

개발 환경에 최적화된 설정입니다.

```yaml
# environments/dev/values.yaml
# 외부 접근 IP (개발 서버)
externalIP: "10.61.3.10"

# 개발용 NFS 설정
nfs:
  storageClassName: astrago-nfs-csi-dev
  server: "10.61.3.20"
  basePath: "/nfs-dev/astrago"

# 개발용 Keycloak 설정
keycloak:
  adminUser: admin
  adminPassword: devpass123
  servicePort: 30001
  realm: astrago-dev
  
# 개발용 Astrago 설정
astrago:
  servicePort: 30080
  userInitPassword: astrago
  replicas: 1  # 개발환경은 단일 인스턴스
  
  # 개발용 이미지 태그
  core:
    imageTag: "core-v1.0.80-dev"
  batch:
    imageTag: "batch-v1.0.80-dev"
  monitor:
    imageTag: "monitor-v1.0.80-dev"
  frontend:
    imageTag: "frontend-v1.0.50-dev"

# 개발용 리소스 제한 (낮음)
resources:
  limits:
    cpu: "500m"
    memory: "1Gi"
  requests:
    cpu: "100m"
    memory: "256Mi"

# 개발용 모니터링 설정
prometheus:
  retention: "7d"  # 7일간 데이터 보관
  storageSize: "10Gi"

# 개발용 GPU 설정 (비활성화)
gpu-operator:
  enabled: false

# 개발용 디버그 설정
debug:
  enabled: true
  logLevel: "DEBUG"
```

### 3. 스테이징 환경 (stage/values.yaml)

프로덕션과 유사한 환경에서 테스트를 위한 설정입니다.

```yaml
# environments/stage/values.yaml
# 스테이징 서버 IP
externalIP: "10.61.3.11"

# 스테이징용 NFS 설정
nfs:
  storageClassName: astrago-nfs-csi-stage
  server: "10.61.3.21"
  basePath: "/nfs-stage/astrago"

# 스테이징용 Keycloak 설정
keycloak:
  adminUser: admin
  adminPassword: stagepass123
  servicePort: 30001
  realm: astrago-stage
  
# 스테이징용 Astrago 설정
astrago:
  servicePort: 30080
  userInitPassword: astrago
  replicas: 2  # 고가용성 테스트를 위한 이중화
  
  # 스테이징용 이미지 태그
  core:
    imageTag: "core-v1.0.80-stage"
  batch:
    imageTag: "batch-v1.0.80-stage"
  monitor:
    imageTag: "monitor-v1.0.80-stage"
  frontend:
    imageTag: "frontend-v1.0.50-stage"

# 스테이징용 리소스 제한 (중간)
resources:
  limits:
    cpu: "1000m"
    memory: "2Gi"
  requests:
    cpu: "200m"
    memory: "512Mi"

# 스테이징용 모니터링 설정
prometheus:
  retention: "15d"  # 15일간 데이터 보관
  storageSize: "50Gi"

# 스테이징용 GPU 설정 (테스트용)
gpu-operator:
  enabled: true
  testMode: true

# 스테이징용 로드 밸런서
loadBalancer:
  enabled: true
  type: "MetalLB"
  ipRange: "10.61.3.100-10.61.3.105"
```

### 4. 프로덕션 환경 (prod/values.yaml)

프로덕션 환경에 최적화된 설정입니다.

```yaml
# environments/prod/values.yaml
# 프로덕션 서버 IP
externalIP: "10.61.3.12"

# 프로덕션용 NFS 설정
nfs:
  storageClassName: astrago-nfs-csi
  server: "10.61.3.22"
  basePath: "/nfs-prod/astrago"

# 프로덕션용 Keycloak 설정
keycloak:
  adminUser: admin
  adminPassword: xiirocks  # 강력한 패스워드 사용
  servicePort: 30001
  realm: astrago
  
# 프로덕션용 Astrago 설정
astrago:
  servicePort: 30080
  userInitPassword: astrago
  replicas: 3  # 고가용성을 위한 3중화
  
  # 프로덕션용 이미지 태그 (최신 안정 버전)
  core:
    imageTag: "core-v1.0.80"
  batch:
    imageTag: "batch-v1.0.80"
  monitor:
    imageTag: "monitor-v1.0.80"
  frontend:
    imageTag: "frontend-v1.0.50"

# 프로덕션용 리소스 제한 (높음)
resources:
  limits:
    cpu: "2000m"
    memory: "4Gi"
  requests:
    cpu: "500m"
    memory: "1Gi"

# 프로덕션용 모니터링 설정
prometheus:
  retention: "30d"  # 30일간 데이터 보관
  storageSize: "200Gi"
  
# 프로덕션용 GPU 설정
gpu-operator:
  enabled: true
  nodeSelector:
    gpu-node: "true"

# 프로덕션용 보안 설정
security:
  networkPolicy:
    enabled: true
  podSecurityPolicy:
    enabled: true
  tls:
    enabled: true
    certManager: true

# 프로덕션용 백업 설정
backup:
  enabled: true
  schedule: "0 2 * * *"  # 매일 새벽 2시
  retention: "30d"
  
# 프로덕션용 로드 밸런서
loadBalancer:
  enabled: true
  type: "MetalLB"
  ipRange: "10.61.3.200-10.61.3.210"
```

## 🚀 환경별 배포 방법

### 개발 환경 배포
```bash
# 개발 환경 배포
helmfile -e dev sync

# 특정 애플리케이션만 배포
helmfile -e dev -l app=astrago sync
```

### 스테이징 환경 배포
```bash
# 스테이징 환경 배포
helmfile -e stage sync

# 점진적 배포 (Canary)
helmfile -e stage -l app=astrago sync --set replicas=1
helmfile -e stage -l app=astrago sync --set replicas=2
```

### 프로덕션 환경 배포
```bash
# 프로덕션 환경 배포 (신중히)
helmfile -e prod diff  # 변경사항 확인
helmfile -e prod sync

# 롤백 준비
helmfile -e prod list
```

## 🔧 환경별 최적화 전략

### 개발 환경 최적화
- **리소스 절약**: 최소한의 리소스로 실행
- **빠른 재시작**: 개발 효율성을 위한 빠른 배포
- **디버그 모드**: 상세한 로그 및 디버그 정보
- **단일 인스턴스**: 복잡성 제거

### 스테이징 환경 최적화
- **프로덕션 유사성**: 프로덕션과 유사한 환경
- **테스트 지원**: 자동화된 테스트 환경
- **성능 테스트**: 부하 테스트 및 성능 측정
- **보안 테스트**: 보안 취약점 검사

### 프로덕션 환경 최적화
- **고가용성**: 서비스 중단 최소화
- **성능 최적화**: 최대 처리량 및 최소 지연시간
- **보안 강화**: 다층 보안 체계
- **모니터링**: 실시간 모니터링 및 알림

## 🛡️ 환경별 보안 설정

### 개발 환경 보안
```yaml
# 개발용 보안 설정 (느슨함)
security:
  tls:
    enabled: false
  authentication:
    required: false
  networkPolicy:
    enabled: false
```

### 스테이징 환경 보안
```yaml
# 스테이징용 보안 설정 (중간)
security:
  tls:
    enabled: true
    selfsigned: true
  authentication:
    required: true
  networkPolicy:
    enabled: true
    allowExternal: true
```

### 프로덕션 환경 보안
```yaml
# 프로덕션용 보안 설정 (강함)
security:
  tls:
    enabled: true
    certManager: true
    issuer: "letsencrypt-prod"
  authentication:
    required: true
    mfa: true
  networkPolicy:
    enabled: true
    allowExternal: false
    whitelist:
      - "10.61.3.0/24"
```

## 📊 환경별 모니터링

### 개발 환경 모니터링
```yaml
monitoring:
  level: "basic"
  retention: "7d"
  alerts:
    enabled: false
  metrics:
    - "basic-health"
    - "error-rate"
```

### 스테이징 환경 모니터링
```yaml
monitoring:
  level: "detailed"
  retention: "15d"
  alerts:
    enabled: true
    severity: "warning"
  metrics:
    - "performance"
    - "resource-usage"
    - "error-rate"
    - "latency"
```

### 프로덕션 환경 모니터링
```yaml
monitoring:
  level: "comprehensive"
  retention: "30d"
  alerts:
    enabled: true
    severity: "critical"
    channels:
      - "slack"
      - "email"
      - "pagerduty"
  metrics:
    - "all-metrics"
  dashboards:
    - "business-metrics"
    - "sla-metrics"
    - "capacity-planning"
```

## 🔄 환경 간 승격 프로세스

### 1. 개발 → 스테이징
```bash
# 개발 환경에서 테스트 완료 후
git tag v1.0.81-dev
docker build -t astrago:v1.0.81-stage .
docker push registry.example.com/astrago:v1.0.81-stage

# 스테이징 배포
helmfile -e stage sync
```

### 2. 스테이징 → 프로덕션
```bash
# 스테이징에서 검증 완료 후
git tag v1.0.81
docker tag astrago:v1.0.81-stage astrago:v1.0.81
docker push astrago:v1.0.81

# 프로덕션 배포 (점진적)
helmfile -e prod diff
helmfile -e prod sync
```

## 🎯 환경별 성능 튜닝

### 개발 환경
- CPU: 0.1-0.5 cores
- Memory: 256MB-1GB
- Storage: 10GB
- Network: 기본 설정

### 스테이징 환경
- CPU: 0.5-2 cores
- Memory: 1GB-4GB
- Storage: 50GB
- Network: QoS 적용

### 프로덕션 환경
- CPU: 2-8 cores
- Memory: 4GB-16GB
- Storage: 200GB+ (SSD)
- Network: 전용 네트워크

## 🔧 환경 설정 관리 팁

### 1. 환경 변수 활용
```bash
# 환경 변수로 설정 오버라이드
export ASTRAGO_ENV=prod
export EXTERNAL_IP=10.61.3.12
./deploy_astrago.sh sync
```

### 2. 조건부 설정
```yaml
# values.yaml
{{- if eq .Values.environment "prod" }}
replicas: 3
{{- else }}
replicas: 1
{{- end }}
```

### 3. 설정 검증
```bash
# 설정 검증 스크립트
./scripts/validate-config.sh environments/prod/values.yaml
```

### 4. 환경 비교
```bash
# 환경 간 설정 비교
diff environments/stage/values.yaml environments/prod/values.yaml
``` 