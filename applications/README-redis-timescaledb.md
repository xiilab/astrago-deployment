# 🗄️ Redis & TimescaleDB 애플리케이션 가이드

## 📋 개요

이 문서는 AstraGo 플랫폼에 새로 추가된 **Redis**와 **TimescaleDB** 로컬 헬름 차트 애플리케이션의 사용 방법을 설명합니다.

## 🏗️ 애플리케이션 구조

### 📦 Redis

```
applications/redis/
├── helmfile.yaml              # Redis 릴리스 설정
├── values.yaml.gotmpl         # 환경별 동적 설정
└── redis/                     # Redis 헬름 차트
    ├── Chart.yaml             # 차트 메타데이터
    ├── values.yaml            # 기본 설정값
    └── templates/             # Kubernetes 매니페스트 템플릿
        ├── _helpers.tpl       # 헬퍼 함수
        ├── secret.yaml        # 인증 정보
        ├── configmap.yaml     # Redis 설정
        ├── service.yaml       # Redis 서비스
        └── statefulset.yaml   # Redis StatefulSet
```

### 🐘 TimescaleDB

```
applications/timescaledb/
├── helmfile.yaml              # TimescaleDB 릴리스 설정
├── values.yaml.gotmpl         # 환경별 동적 설정
└── timescaledb/               # TimescaleDB 헬름 차트
    ├── Chart.yaml             # 차트 메타데이터
    ├── values.yaml            # 기본 설정값
    └── templates/             # Kubernetes 매니페스트 템플릿
        ├── _helpers.tpl       # 헬퍼 함수
        ├── secret.yaml        # 인증 정보
        ├── configmap.yaml     # PostgreSQL/TimescaleDB 설정
        ├── service.yaml       # TimescaleDB 서비스
        └── statefulset.yaml   # TimescaleDB StatefulSet
```

## 🚀 배포 방법

### 1. 전체 애플리케이션 배포

```bash
# 모든 애플리케이션 배포 (Redis와 TimescaleDB 포함)
helmfile -e dev sync

# 특정 환경으로 배포
helmfile -e stage sync
helmfile -e prod sync
```

### 2. 개별 애플리케이션 배포

```bash
# Redis만 배포
helmfile -e dev -l app=redis sync

# TimescaleDB만 배포
helmfile -e dev -l app=timescaledb sync
```

### 3. 특정 네임스페이스에 배포

```bash
# Redis 네임스페이스에 배포
helm install redis applications/redis/redis -n redis --create-namespace

# TimescaleDB 네임스페이스에 배포
helm install timescaledb applications/timescaledb/timescaledb -n timescaledb --create-namespace
```

## ⚙️ 환경별 설정

### 📝 기본 설정 (environments/common/values.yaml)

#### Redis 설정

```yaml
redis:
  enabled: true
  password: "redis123!"
  persistence:
    size: "10Gi"
  resources:
    limits:
      cpu: "1000m"
      memory: "1Gi"
    requests:
      cpu: "100m"
      memory: "128Mi"
  config:
    maxmemory: "1gb"
    maxmemoryPolicy: "allkeys-lru"
    save: "900 1 300 10 60 10000"
```

#### TimescaleDB 설정

```yaml
timescaledb:
  enabled: true
  superuserPassword: "timescale123!"
  database: "timescaledb"
  username: "timescale"
  password: "timescale123!"
  persistence:
    size: "50Gi"
  resources:
    limits:
      cpu: "2000m"
      memory: "4Gi"
    requests:
      cpu: "500m"
      memory: "1Gi"
```

### 🔧 환경별 커스터마이징

환경별 설정 파일에서 다음과 같이 오버라이드할 수 있습니다:

```yaml
# environments/prod/values.yaml
redis:
  password: "super-secure-redis-password"
  persistence:
    size: "100Gi"
  resources:
    limits:
      cpu: "2000m"
      memory: "4Gi"

timescaledb:
  superuserPassword: "super-secure-postgres-password"
  password: "secure-user-password"
  persistence:
    size: "500Gi"
  resources:
    limits:
      cpu: "4000m"
      memory: "8Gi"
```

## 🔗 연결 정보

### Redis 연결

```bash
# 클러스터 내에서 연결
redis://redis.redis.svc.cluster.local:6379

# 패스워드 인증
AUTH <password>

# 상태 확인
kubectl get pods -n redis
kubectl logs -f redis-0 -n redis
```

### TimescaleDB 연결

```bash
# 클러스터 내에서 연결
postgresql://timescale:password@timescaledb.timescaledb.svc.cluster.local:5432/timescaledb

# psql을 사용한 연결
kubectl exec -it timescaledb-0 -n timescaledb -- psql -U timescale -d timescaledb

# 상태 확인
kubectl get pods -n timescaledb
kubectl logs -f timescaledb-0 -n timescaledb
```

## 📊 모니터링

### Redis 모니터링

```bash
# Redis 정보 확인
kubectl exec -it redis-0 -n redis -- redis-cli info

# Redis 메모리 사용량
kubectl exec -it redis-0 -n redis -- redis-cli info memory

# Redis 연결 상태
kubectl exec -it redis-0 -n redis -- redis-cli ping
```

### TimescaleDB 모니터링

```bash
# 데이터베이스 상태 확인
kubectl exec -it timescaledb-0 -n timescaledb -- pg_isready

# TimescaleDB 확장 확인
kubectl exec -it timescaledb-0 -n timescaledb -- psql -U timescale -d timescaledb -c "SELECT * FROM pg_extension WHERE extname = 'timescaledb';"

# 데이터베이스 크기 확인
kubectl exec -it timescaledb-0 -n timescaledb -- psql -U timescale -d timescaledb -c "SELECT pg_size_pretty(pg_database_size('timescaledb'));"
```

## 🔧 운영 가이드

### 백업 및 복원

#### Redis 백업

```bash
# Redis 데이터 백업
kubectl exec redis-0 -n redis -- redis-cli BGSAVE

# 백업 파일 확인
kubectl exec redis-0 -n redis -- ls -la /data/
```

#### TimescaleDB 백업

```bash
# 데이터베이스 덤프
kubectl exec timescaledb-0 -n timescaledb -- pg_dump -U timescale timescaledb > backup.sql

# 복원
kubectl exec -i timescaledb-0 -n timescaledb -- psql -U timescale timescaledb < backup.sql
```

### 스케일링

#### 리소스 증가

```yaml
# environments/{환경}/values.yaml에서 리소스 조정
redis:
  resources:
    limits:
      cpu: "2000m"
      memory: "4Gi"

timescaledb:
  resources:
    limits:
      cpu: "4000m"
      memory: "8Gi"
```

#### 스토리지 확장

```bash
# PVC 크기 확인
kubectl get pvc -n redis
kubectl get pvc -n timescaledb

# 스토리지 클래스가 확장을 지원하는 경우 PVC 수정
kubectl patch pvc data-redis-0 -n redis -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
```

## 🔒 보안 설정

### Redis 보안

- **패스워드 인증**: 기본적으로 활성화됨
- **네트워크 격리**: Kubernetes 네트워크 정책 적용 권장
- **TLS 암호화**: 필요시 Redis 설정에서 활성화

### TimescaleDB 보안

- **사용자 인증**: PostgreSQL 기본 인증 사용
- **연결 암호화**: SSL/TLS 지원
- **백업 암호화**: 민감한 데이터는 암호화된 백업 권장

## 🚨 트러블슈팅

### 일반적인 문제

1. **팟이 시작되지 않는 경우**

   ```bash
   kubectl describe pod redis-0 -n redis
   kubectl describe pod timescaledb-0 -n timescaledb
   ```

2. **PVC 마운트 문제**

   ```bash
   kubectl get pvc -n redis
   kubectl get pvc -n timescaledb
   ```

3. **연결 실패**

   ```bash
   # 서비스 확인
   kubectl get svc -n redis
   kubectl get svc -n timescaledb
   
   # 네트워크 정책 확인
   kubectl get networkpolicy -n redis
   kubectl get networkpolicy -n timescaledb
   ```

## 📚 참고 자료

### Redis

- [Redis 공식 문서](https://redis.io/documentation)
- [Redis 설정 가이드](https://redis.io/topics/config)
- [Redis 모니터링](https://redis.io/topics/monitoring)

### TimescaleDB

- [TimescaleDB 공식 문서](https://docs.timescale.com/)
- [PostgreSQL 문서](https://www.postgresql.org/docs/)
- [TimescaleDB 최적화 가이드](https://docs.timescale.com/timescaledb/latest/how-to-guides/configuration/)

---

## 🤝 지원

문제가 발생하거나 추가 기능이 필요한 경우:

- 🐛 버그 리포트: GitHub Issues
- 💬 질문 및 토론: GitHub Discussions
- 📧 기술 지원: <devops@astrago.com>

---
*최종 업데이트: 2024년 12월*
