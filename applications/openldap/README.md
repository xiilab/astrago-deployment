# LDAP Integration Deployment Guide

## 개요

이 디렉토리는 AstraGo와 LDAP 통합을 위한 모든 배포 설정 파일들을 포함합니다.

## 파일 구조

```
deployment/
├── README.md                    # 이 파일
├── ldap-deployment.yaml         # LDAP 통합을 위한 모든 Kubernetes 리소스
└── scripts/                     # 배포 및 관리 스크립트
    ├── deploy-ldap.sh          # LDAP 배포 스크립트
    ├── deploy-keycloak-ldap.sh # Keycloak LDAP 연동 스크립트
    └── manage-users.sh         # 사용자 관리 스크립트
```

## 주요 구성 요소

### 1. OpenLDAP 서버
- **Namespace**: `ldap`
- **Chart**: `stable/openldap`
- **도메인**: `example.com`
- **관리자 계정**: `cn=admin,dc=example,dc=com`
- **비밀번호**: `admin`

### 2. phpLDAPadmin
- **Namespace**: `ldap`
- **Chart**: `cetic/phpldapadmin`
- **웹 UI**: LDAP 관리 인터페이스
- **접속**: `http://phpldapadmin.ldap.svc.cluster.local`

### 3. Keycloak LDAP 연동
- **Namespace**: `keycloak`
- **Provider ID**: `ldap`
- **연결 URL**: `ldap://ldap-openldap.ldap.svc.cluster.local:389`
- **사용자 DN**: `ou=users,dc=example,dc=com`

## 배포 방법

### 1. Helmfile을 사용한 배포 (권장)

```bash
# OpenLDAP 배포
cd applications/openldap
helmfile apply

# Keycloak LDAP 연동 배포
cd applications/keycloak
helmfile apply
```

### 2. 수동 배포

```bash
# LDAP 네임스페이스 생성
kubectl apply -f deployment/ldap-deployment.yaml

# OpenLDAP 설치
helm install ldap-openldap stable/openldap -n ldap \
  --set LDAP_DOMAIN=example.com \
  --set LDAP_TLS=false \
  --set persistence.enabled=true \
  --set persistence.storageClass=astrago-nfs-csi \
  --set adminPassword=admin \
  --set configPassword=admin

# phpLDAPadmin 설치
helm install phpldapadmin cetic/phpldapadmin -n ldap \
  --set env.PHPLDAPADMIN_LDAP_HOSTS=ldap-openldap.ldap.svc.cluster.local
```

## 설정 파일

### 환경별 설정

#### 개발 환경 (`environments/dev/values.yaml`)
```yaml
ldap:
  enabled: true
  serverUrl: "ldap://ldap-openldap.ldap.svc.cluster.local:389"
  bindDn: "cn=admin,dc=example,dc=com"
  bindPassword: "admin"
  userSearchBase: "ou=users,dc=example,dc=com"
  groupSearchBase: "ou=groups,dc=example,dc=com"
```

#### 운영 환경 (`environments/prod/values.yaml`)
```yaml
ldap:
  enabled: true
  serverUrl: "ldaps://ldap.company.com:636"
  bindDn: "cn=serviceaccount,dc=company,dc=com"
  bindPassword: "${LDAP_BIND_PASSWORD}"
  userSearchBase: "ou=users,dc=company,dc=com"
  groupSearchBase: "ou=groups,dc=company,dc=com"
```

## 사용자 관리

### 1. 사용자 생성

```bash
# 스크립트 사용
./scripts/create_ldap_user.sh username email firstname lastname password

# 직접 LDAP 명령어 사용
kubectl exec -n ldap deployment/ldap-openldap -- ldapadd -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w admin << EOF
dn: uid=newuser,ou=users,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: top
cn: New User
sn: User
uid: newuser
mail: newuser@example.com
userPassword: password123
signUpPath: ASTRAGO
workspaceCreateLimit: 10
approvalYN: true
EOF
```

### 2. 기본 속성 추가

```bash
# 모든 사용자에게 기본 속성 추가
./scripts/add_default_attributes.sh
```

### 3. 사용자 검색

```bash
# 모든 사용자 조회
kubectl exec -n ldap deployment/ldap-openldap -- ldapsearch -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w admin -b "ou=users,dc=example,dc=com" "(objectClass=inetOrgPerson)"
```

## Keycloak 연동 설정

### 1. LDAP Provider 설정

Keycloak Admin Console에서 다음 설정:

- **Connection URL**: `ldap://ldap-openldap.ldap.svc.cluster.local:389`
- **Bind DN**: `cn=admin,dc=example,dc=com`
- **Bind Password**: `admin`
- **Users DN**: `ou=users,dc=example,dc=com`
- **Username LDAP attribute**: `uid`
- **RDN LDAP attribute**: `uid`
- **UUID LDAP attribute**: `entryUUID`
- **User object classes**: `inetOrgPerson, organizationalPerson, person, top`
- **User LDAP filter**: `(objectClass=inetOrgPerson)`
- **Edit mode**: `WRITABLE`
- **Vendor**: `Other`

### 2. 동기화 설정

- **Import users**: 활성화
- **Sync registrations**: 비활성화
- **Periodic full sync**: 24시간
- **Periodic changed users sync**: 5분

## 모니터링

### 1. 헬스 체크

```bash
# LDAP 서버 상태 확인
kubectl exec -n ldap deployment/ldap-openldap -- ldapsearch -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w admin -b "dc=example,dc=com" "(objectClass=*)"

# Keycloak LDAP 연결 테스트
kubectl exec -n keycloak keycloak-0 -- /opt/bitnami/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password xiirocks
```

### 2. 로그 확인

```bash
# OpenLDAP 로그
kubectl logs -n ldap deployment/ldap-openldap

# Keycloak 로그
kubectl logs -n keycloak keycloak-0

# phpLDAPadmin 로그
kubectl logs -n ldap deployment/phpldapadmin
```

## 문제 해결

### 1. 연결 문제

**증상**: `UnknownHost` 오류
**해결**: 올바른 서비스 주소 사용
```yaml
connectionUrl: "ldap://ldap-openldap.ldap.svc.cluster.local:389"
```

### 2. 인증 문제

**증상**: `AuthenticationFailure` 오류
**해결**: 올바른 Bind DN과 패스워드 확인
```yaml
bindDn: "cn=admin,dc=example,dc=com"
bindPassword: "admin"
```

### 3. 패스워드 변경 실패

**증상**: `Could not modify attribute` 오류
**해결**: 
- `Edit mode`: `WRITABLE`로 설정
- `Vendor`: `Other`로 설정
- Advanced 설정에서 패스워드 정책 비활성화

### 4. 사용자 생성 실패

**증상**: `unknown_error` 오류
**해결**: 
- First Name, Last Name을 비워두지 않기
- 모든 필수 필드 입력
- Base64 인코딩 문제 확인

## 보안 고려사항

### 1. 운영 환경
- TLS/SSL 활성화
- 강력한 패스워드 정책
- 접근 권한 최소화
- 정기적인 백업

### 2. 개발 환경
- 현재 설정으로 충분
- 테스트용 계정 사용
- 로컬 네트워크 접근만 허용

## 백업 및 복구

### 1. LDAP 데이터 백업

```bash
# 전체 LDAP 데이터 백업
kubectl exec -n ldap deployment/ldap-openldap -- ldapsearch -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w admin -b "dc=example,dc=com" > ldap-backup.ldif
```

### 2. 설정 백업

```bash
# Helm values 백업
helm get values ldap-openldap -n ldap > ldap-values-backup.yaml
helm get values keycloak -n keycloak > keycloak-values-backup.yaml
```

### 3. 복구

```bash
# LDAP 데이터 복구
kubectl exec -n ldap deployment/ldap-openldap -- ldapadd -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w admin -f ldap-backup.ldif
```

## 성능 최적화

### 1. 연결 풀링
- `connectionPooling`: `true`
- `connectionPoolingMaxSize`: `20`
- `connectionPoolingInitSize`: `5`

### 2. 동기화 최적화
- `batchSizeForSync`: `1000`
- `fullSyncPeriod`: `86400` (24시간)
- `changedSyncPeriod`: `300` (5분)

### 3. 캐시 설정
- `cachePolicy`: `DEFAULT`
- `maxLifespan`: `3600` (1시간)

## 참고 자료

- [OpenLDAP 공식 문서](https://www.openldap.org/doc/)
- [Keycloak LDAP 문서](https://www.keycloak.org/docs/latest/server_admin/#_ldap)
- [Helm 공식 문서](https://helm.sh/docs/)
- [Kubernetes 공식 문서](https://kubernetes.io/docs/) 