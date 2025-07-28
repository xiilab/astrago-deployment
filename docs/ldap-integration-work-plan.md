# LDAP 연동 작업 계획 - BE-231

## 📋 Linear 이슈 정보

- **이슈 ID**: BE-231
- **제목**: [두산] LDAP 계정 연동 - Keycloak User Federation 구현
- **프로젝트**: AstraGo Infra
- **담당자**: 김수현
- **우선순위**: High
- **마감일**: 2025-07-31
- **상태**: Todo
- **Git 브랜치**: `feature/ldap-conn`

## 🎯 목표

- LDAP 서버와 Keycloak 간의 User Federation 설정
- 기존 LDAP 계정 정보를 AstraGo 2.0과 연동
- 사용자 정보 실시간 동기화 및 관리
- **중요**: 기존 Keycloak 설정과 호환성 유지
- **추가**: OpenLDAP 설치부터 Helmfile 관리까지 완전 자동화

## 🔧 기술 요구사항

### Keycloak User Federation
- LDAP Provider 설정 및 구성
- 사용자 속성 매핑 (User Attribute Mapping)
- 그룹 및 역할 매핑 (Group/Role Mapping)

### LDAP 연동 설정
- LDAP 서버 연결 설정
- SSL/TLS 보안 연결 구성
- 인증 방식 설정 (Simple, SASL 등)

### OpenLDAP 관리
- OpenLDAP Helm Chart 설치 및 설정
- LDAP 데이터베이스 초기화
- 사용자/그룹 데이터 관리
- 백업 및 복구 전략

## 📋 작업 계획

### Phase 1: 환경 설정 및 기본 구조 (1-2일)

#### 1.1 브랜치 및 환경 준비
- [x] `feature/ldap-conn` 브랜치 생성
- [x] 기본 LDAP 설정 파일 구조 확인
- [ ] LDAP 서버 정보 수집 (두산 환경)
  - LDAP 서버 주소 및 포트
  - 바인드 DN 및 패스워드
  - 사용자/그룹 베이스 DN
  - SSL/TLS 설정 정보

#### 1.2 Keycloak 기존 설정 분석
- [ ] 현재 Keycloak Helm 설정 분석
- [ ] 기존 테마 및 커스텀 설정 확인
- [ ] 호환성 검토 및 충돌 방지 방안 수립

#### 1.3 OpenLDAP 설치 계획
- [ ] OpenLDAP Helm Chart 선택 및 검토
- [ ] LDAP 데이터베이스 스키마 설계
- [ ] 초기 사용자/그룹 데이터 구조 정의
- [ ] 백업 및 복구 전략 수립

### Phase 2: OpenLDAP 설치 및 설정 (2-3일)

#### 2.1 OpenLDAP Helm Chart 추가
- [ ] `applications/openldap/` 디렉토리 생성
- [ ] OpenLDAP Helm Chart 설정 파일 작성
- [ ] `helmfile.yaml`에 OpenLDAP 애플리케이션 추가
- [ ] 환경별 OpenLDAP 설정 구성

#### 2.2 OpenLDAP 설정 파일 구현
- [ ] `applications/openldap/values.yaml.gotmpl` 생성
  - LDAP 관리자 계정 설정
  - 데이터베이스 설정
  - SSL/TLS 설정
  - 백업 설정
- [ ] `applications/openldap/templates/` 디렉토리 구성
  - ConfigMap 템플릿
  - Secret 템플릿
  - Service 템플릿
  - Ingress 템플릿 (필요시)

#### 2.3 LDAP 데이터 초기화
- [ ] 초기 LDAP 스키마 정의
- [ ] 기본 사용자/그룹 데이터 생성
- [ ] LDAP 관리 도구 설정
- [ ] 데이터 검증 스크립트 작성

### Phase 3: LDAP 설정 파일 구현 (2-3일)

#### 3.1 환경별 설정 파일 구성
- [x] `environments/common/values.yaml` - LDAP 기본 설정 추가
- [x] `environments/dev/values.yaml` - 개발환경 LDAP 활성화
- [ ] `environments/prod/values.yaml` - 운영환경 LDAP 설정
- [ ] `environments/stage/values.yaml` - 스테이징환경 LDAP 설정

#### 3.2 Keycloak Helm Values 템플릿 수정
- [ ] `applications/keycloak/values.yaml.gotmpl` 수정
  - LDAP 환경변수 추가
  - LDAP ConfigMap 설정
  - postStart 훅에 LDAP 설정 스크립트 추가

#### 3.3 LDAP 설정 스크립트 생성
- [ ] `applications/keycloak/templates/ldap-configmap.yaml` 생성
  - LDAP Provider 설정 스크립트
  - 사용자/그룹 동기화 스크립트
  - 연결 테스트 스크립트

### Phase 4: 핵심 기능 구현 (3-4일)

#### 4.1 LDAP Provider 설정
- [ ] Keycloak LDAP User Federation Provider 생성
- [ ] LDAP 서버 연결 설정
- [ ] 바인드 인증 설정
- [ ] SSL/TLS 보안 설정

#### 4.2 사용자 속성 매핑
- [ ] LDAP 속성 → Keycloak 속성 매핑 구현
- [ ] 필수 속성 매핑 (uid, mail, cn, sn)
- [ ] 사용자 정의 속성 매핑
- [ ] 속성 동기화 설정

#### 4.3 그룹 및 역할 연동
- [ ] LDAP 그룹 → Keycloak 그룹 매핑
- [ ] 역할 기반 접근 제어 설정
- [ ] 그룹 멤버십 자동 동기화
- [ ] 권한 상속 설정

### Phase 5: 동기화 및 모니터링 (2-3일)

#### 5.1 실시간 동기화 구현
- [ ] 사용자 정보 실시간 동기화
- [ ] 패스워드 변경 감지 및 반영
- [ ] 그룹 멤버십 변경 자동 업데이트
- [ ] 동기화 주기 설정

#### 5.2 인증 및 권한 관리
- [ ] LDAP 기반 인증 플로우 구현
- [ ] 사용자 세션 관리
- [ ] 권한 변경 시 자동 업데이트
- [ ] 로그아웃 처리

#### 5.3 연동 모니터링
- [ ] LDAP 연결 상태 모니터링
- [ ] 동기화 이력 관리
- [ ] 에러 로깅 및 알림
- [ ] 헬스체크 엔드포인트

### Phase 6: 테스트 및 검증 (2-3일)

#### 6.1 단위 테스트
- [ ] LDAP 연결 테스트
- [ ] 사용자 인증 테스트
- [ ] 그룹 동기화 테스트
- [ ] 속성 매핑 테스트

#### 6.2 통합 테스트
- [ ] Keycloak과 AstraGo 연동 테스트
- [ ] 전체 인증 플로우 테스트
- [ ] 권한 기반 접근 제어 테스트
- [ ] 성능 테스트

#### 6.3 자동화 테스트 스크립트
- [ ] `scripts/test-ldap-integration.sh` 생성
- [ ] CI/CD 파이프라인에 테스트 추가
- [ ] 테스트 결과 리포트 생성

### Phase 7: 문서화 및 배포 (2-3일)

#### 7.1 상세 가이드 문서 작성
- [ ] `docs/ldap-integration.md` - 사용자 가이드
  - **UI를 통한 LDAP 설정 방법**
  - **Helm을 통한 LDAP 설정 방법**
  - **CLI를 통한 LDAP 설정 방법**
  - **OpenLDAP 설치 및 설정 가이드**
  - **Helmfile을 통한 완전 자동화 가이드**
- [ ] `docs/ldap-troubleshooting.md` - 문제 해결 가이드
- [ ] `docs/openldap-management.md` - OpenLDAP 관리 가이드
- [ ] API 문서 업데이트
- [ ] 배포 가이드 작성

#### 7.2 배포 준비
- [ ] 환경별 배포 스크립트 작성
- [ ] 롤백 계획 수립
- [ ] 모니터링 대시보드 설정
- [ ] 알림 설정

## 🎨 주요 기능 상세

### 1. LDAP 연동 설정
- LDAP 서버 연결 구성 (ldap:// 또는 ldaps://)
- 바인드 DN 및 패스워드 설정
- 사용자 검색 베이스 DN 설정
- 연결 타임아웃 및 재시도 설정

### 2. 사용자 속성 매핑
- LDAP 속성 → Keycloak 속성 매핑
- 필수 속성 (uid, mail, cn, sn) 매핑
- 사용자 정의 속성 매핑
- 속성 동기화 주기 설정

### 3. 그룹 및 역할 연동
- LDAP 그룹 → Keycloak 그룹 매핑
- 역할 기반 접근 제어 설정
- 그룹 멤버십 자동 동기화
- 권한 상속 및 우선순위 처리

### 4. 실시간 동기화
- 사용자 정보 실시간 동기화
- 패스워드 변경 감지 및 반영
- 그룹 멤버십 변경 자동 업데이트
- 동기화 이력 관리

### 5. 인증 및 권한 관리
- LDAP 기반 인증 플로우
- 사용자 세션 관리
- 권한 변경 시 자동 업데이트
- 로그아웃 및 세션 만료 처리

### 6. 연동 모니터링
- LDAP 연결 상태 모니터링
- 동기화 이력 관리
- 에러 로깅 및 알림
- 성능 메트릭 수집

### 7. OpenLDAP 관리
- OpenLDAP Helm Chart 설치 및 설정
- LDAP 데이터베이스 초기화 및 관리
- 사용자/그룹 데이터 CRUD 작업
- 백업 및 복구 자동화
- 모니터링 및 로깅

## 📚 가이드 문서 상세 계획

### 7.1 LDAP 설정 방법별 가이드

#### UI를 통한 LDAP 설정
- Keycloak Admin Console 접속 방법
- User Federation Provider 생성 단계
- LDAP 연결 설정 (Connection Settings)
- 사용자 속성 매핑 (User Attribute Mapping)
- 그룹 매핑 (Group Mapping)
- 동기화 설정 (Synchronization Settings)
- 테스트 및 검증 방법

#### Helm을 통한 LDAP 설정
- Helm values 파일 구성 방법
- 환경변수 설정 (extraEnvVars)
- ConfigMap을 통한 설정 주입
- postStart 훅을 통한 자동 설정
- Helm upgrade/downgrade 시나리오
- 설정 변경 시 롤백 방법

#### CLI를 통한 LDAP 설정
- kcadm.sh를 사용한 LDAP Provider 생성
- REST API를 통한 설정 변경
- 스크립트 기반 자동화 방법
- 배치 처리를 통한 대량 설정
- 설정 백업 및 복원 방법

### 7.2 OpenLDAP 설치 및 관리 가이드

#### OpenLDAP Helm Chart 설치
- Helm Chart 선택 및 검토
- values.yaml 설정 방법
- 환경별 설정 차이점
- 설치 전 검증 사항
- 설치 후 검증 방법

#### LDAP 데이터베이스 관리
- 초기 스키마 설정
- 기본 사용자/그룹 생성
- 데이터 백업 및 복원
- 성능 튜닝 방법
- 보안 설정 가이드

#### Helmfile을 통한 완전 자동화
- helmfile.yaml 구성 방법
- 환경별 values 파일 관리
- 의존성 관리 (OpenLDAP → Keycloak)
- 배포 순서 및 전략
- 롤백 및 업그레이드 방법

## ✅ 완료 조건

- [ ] Keycloak User Federation 설정 완료
- [ ] LDAP 서버 연결 및 인증 확인
- [ ] 사용자 속성 매핑 구현
- [ ] 그룹 및 역할 매핑 구현
- [ ] 실시간 동기화 테스트 완료
- [ ] 연동 모니터링 시스템 구축
- [ ] 기존 Keycloak 설정과 호환성 확인
- [ ] OpenLDAP Helm Chart 설치 및 설정 완료
- [ ] UI/Helm/CLI 설정 방법 가이드 작성
- [ ] Helmfile 자동화 가이드 작성
- [ ] 문서화 완료

## 🔗 관련 시스템

- LDAP Directory Server (두산 환경)
- OpenLDAP Helm Chart
- Keycloak Identity Provider
- AstraGo 2.0 인증 시스템
- 사용자 관리 시스템
- 모니터링 시스템
- Helmfile 배포 시스템

## ⚠️ 주의사항

### 기존 Keycloak 설정 호환성
- 현재 Keycloak 테마 설정 유지
- 기존 사용자 데이터 보존
- 인증 플로우 변경 최소화
- AstraGo 클라이언트 연동 유지

### 보안 고려사항
- LDAP 패스워드 암호화 저장
- SSL/TLS 연결 필수
- 접근 권한 최소화 원칙
- 감사 로그 기록
- OpenLDAP 보안 설정

### 성능 고려사항
- 동기화 주기 최적화
- 대용량 사용자 처리
- 네트워크 지연 고려
- 리소스 사용량 모니터링
- OpenLDAP 성능 튜닝

### 자동화 고려사항
- Helmfile 의존성 관리
- 배포 순서 최적화
- 롤백 전략 수립
- 설정 변경 추적
- 환경별 설정 분리

## 📅 예상 일정

- **Phase 1**: 1-2일 (환경 설정)
- **Phase 2**: 2-3일 (OpenLDAP 설치)
- **Phase 3**: 2-3일 (설정 파일)
- **Phase 4**: 3-4일 (핵심 기능)
- **Phase 5**: 2-3일 (동기화/모니터링)
- **Phase 6**: 2-3일 (테스트)
- **Phase 7**: 2-3일 (문서화/배포)

**총 예상 기간**: 14-21일 (마감일 2025-07-31 고려 시 집중 진행 필요)

## 🚀 다음 단계

1. 두산 환경 LDAP 서버 정보 수집
2. 현재 Keycloak 설정 상세 분석
3. OpenLDAP Helm Chart 선택 및 검토
4. Phase 1 작업 시작
5. 정기적인 진행 상황 업데이트

## 📋 추가 작업 항목

### OpenLDAP 관련
- [ ] OpenLDAP Helm Chart 검토 및 선택
- [ ] LDAP 스키마 설계
- [ ] 초기 데이터 구조 정의
- [ ] 백업/복구 전략 수립
- [ ] 모니터링 설정

### 가이드 문서 관련
- [ ] UI 설정 스크린샷 및 단계별 가이드
- [ ] Helm 설정 예제 파일
- [ ] CLI 스크립트 예제
- [ ] Helmfile 구성 예제
- [ ] 문제 해결 FAQ 