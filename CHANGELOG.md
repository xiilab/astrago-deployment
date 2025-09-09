# Astrago Deployment 개선사항 및 변경점

## 📋 개요
Astrago 배포 시스템의 **Helmfile 구조를 대대적으로 개편**하고, NodePort 방식에서 **Ingress Nginx + Host Network** 방식으로 전환하며, 오프라인 환경 지원을 강화하였습니다.

---

## 🎯 주요 개선사항

### 1. **Helmfile 구조 통합 및 간소화**
**문제**: 분산되고 복잡한 환경 설정
```
# 기존 구조 (복잡하고 중복)
helmfile/environments/
├── dev/values.yaml        # 개발환경
├── dev2/values.yaml       # 개발환경2  
├── stage/values.yaml      # 스테이징
├── prod/values.yaml       # 프로덕션
├── astrago/values.yaml    # 아스트라고 전용
├── seoultech/values.yaml  # 서울과기대 전용
└── common/values.yaml     # 공통 (거의 사용안함)
```

**해결**: 브랜치 기반 + 고객 오버라이드 패턴
```
# 개선된 구조 (간단하고 명확)
helmfile/environments/
├── base/values.yaml           # 브랜치별 기본값
├── common/values.yaml         # 공통 설정
└── customers/                 # 고객별 오버라이드
    └── astrago/values.yaml    # 고객 특화 설정만
```

**핵심 변화**:
- **493줄 감소**: 중복 설정 대폭 제거
- **브랜치 연동**: main=dev, stabilize=stage, release=prod
- **고객 패턴**: base + customer override로 유연한 확장

### 2. **외부 IP 하드코딩 제거**
**문제**: Frontend 환경변수에 `KEYCLOAK_HOST`, `NEXTAUTH_URL` 하드코딩 필요
```yaml
# 기존 방식 (문제점)
- name: KEYCLOAK_HOST
  value: http://192.168.1.100:30080/auth/  # 하드코딩!
- name: NEXTAUTH_URL
  value: http://192.168.1.100:30080        # 하드코딩!
```

**해결**: 동적 URL 처리 방식 도입
- 브라우저 URL (`window.location.origin`) 활용
- X-Forwarded-Proto 헤더로 HTTP/HTTPS 자동 감지
- 설치 시 IP 주소 고민 불필요

### 3. **Values Templates 중앙화**
**문제**: 각 차트마다 분산된 설정 파일
- 차트별로 개별 values 파일 관리
- 버전별 폴더 구조로 복잡성 증가
- 설정 변경 시 여러 파일 수정 필요

**해결**: `helmfile/values/` 중앙화
```
helmfile/values/
├── astrago.yaml.gotmpl      # 메인 애플리케이션
├── keycloak.yaml.gotmpl     # 인증 서버
├── harbor.yaml.gotmpl       # 컨테이너 레지스트리
├── prometheus.yaml.gotmpl   # 모니터링
└── ...
```

**장점**:
- **중앙 관리**: 모든 values를 한 곳에서 관리
- **템플릿 엔진**: Go template으로 동적 설정
- **버전 통합**: 버전별 분리 제거

### 4. **Ingress 기반 아키텍처 전환**
**기존**: NodePort 방식
- 각 서비스마다 개별 포트 할당
- 방화벽 설정 복잡
- 포트 충돌 가능성

**개선**: Ingress Nginx + Host Network
- 80/443 포트 단일 진입점
- Path 기반 라우팅
```
/auth/*     → Keycloak
/astrago/*  → Astrago Frontend  
/api/core/* → Backend Core
```
- DNS 설정 불필요 (IP 주소로 직접 접속)

### 5. **통합 배포 스크립트 (v3)**

**기존**: 여러 개의 산발된 스크립트들
- `deploy_astrago.sh`, `deploy_astrago_v2.sh`
- `offline_deploy_astrago.sh`
- `install_helmfile.sh`, `package-for-offline.sh`

**개선**: 단일 통합 스크립트
```bash
./deploy_astrago_v3.sh <command> [options]

# 주요 명령어
init <customer>     # 고객 환경 초기화
deploy [customer]   # 배포 (기본/고객환경)
destroy [customer]  # 환경 삭제
list               # 고객 환경 목록
update-tools       # 도구 업데이트
```

### 6. **오프라인 환경 지원 강화**

#### 4.1 자동 바이너리 관리
**기존**: 수동 설치 및 시스템 의존
- sudo 권한 필요
- `/usr/local/bin/`에 직접 설치
- 시스템 환경 오염

**개선**: 격리된 바이너리 관리
- sudo 권한 불필요
- 프로젝트 내 `tools/` 디렉토리 격리
- PATH 환경변수로 런타임 연결

#### 4.2 Helm Diff Plugin 오프라인 지원
**신규 기능**: 완전 오프라인 환경에서 `helmfile diff` 사용 가능
```bash
# 온라인 환경에서 한 번만 실행
./deploy_astrago_v3.sh update-tools

# 오프라인 환경에서 diff 확인 가능
helmfile diff
helmfile apply
```

**구현 방식**:
- Helm Diff Plugin 자동 다운로드 및 설치
- 플랫폼별 바이너리 지원 (macOS, Linux)
- 올바른 플러그인 구조 및 메타데이터 생성

### 5. **플랫폼 지원 확장**

**지원 플랫폼**:
- ✅ **macOS**: Intel (amd64), Apple Silicon (arm64)  
- ✅ **Linux**: x86_64 (amd64), ARM64

**자동 감지**:
- OS 및 아키텍처 자동 감지
- 플랫폼별 최적화된 바이너리 다운로드
- 크로스 플랫폼 호환성

---

## 🔧 기술적 변경사항

### 설정 파일 구조 개선

#### `tools/versions.conf` - 버전 중앙화
```bash
HELM_VERSION="3.18.5"
HELMFILE_VERSION="1.1.6"  
KUBECTL_VERSION="1.34.0"
YQ_VERSION="4.46.1"
HELM_DIFF_VERSION="3.12.5"  # 신규 추가
```

#### `tools/download-binaries.sh` - 통합 다운로드
- 모든 필수 도구 자동 다운로드
- Helm Diff Plugin 포함
- 플랫폼별 최적화
- 검증 로직 강화

#### `deploy_astrago_v3.sh` - 통합 배포 스크립트
- 고객 환경 관리 기능
- 자동 도구 설정
- 환경변수 격리
- 사용자 친화적 인터페이스

#### 차트 구조 재편성
**기존**: 분산된 applications 디렉토리
```
applications/
├── gpu-operator/
│   └── custom-gpu-operator/    # 커스텀 차트
├── keycloak/
├── astrago/
└── ...
```

**개선**: helmfile 하위 통합 관리
```
helmfile/
├── charts/                     # 차트 관리
│   ├── astrago/               # 메인 애플리케이션 차트
│   └── external/              # 오프라인용 외부 차트들
│       ├── keycloak/
│       ├── harbor/
│       └── ...
├── addons/                     # 애드온 설정
│   ├── gpu-operator/          # GPU MIG 설정 
│   └── keycloak/              # Realm 설정
└── ...
```

**장점**:
- **중앙화**: 모든 차트 관리를 helmfile 하위로 통합
- **역할 분리**: charts(차트) vs addons(설정) vs values(템플릿)
- **오프라인 지원**: external/ 폴더에 공식 차트들 사전 다운로드

### 환경 설정 개선

#### Frontend 동적 설정 (예정)
```yaml
# 기존: 하드코딩
- name: NEXTAUTH_URL
  value: http://192.168.1.100:30080

# 개선: 동적 처리  
- name: USE_DYNAMIC_URL
  value: "true"
- name: AUTO_DETECT_PROTOCOL
  value: "true"
```

#### Ingress 설정 (예정)
```yaml
ingress:
  enabled: true
  className: nginx
  hostNetwork: true  # Host Network 모드
  rules:
    - http:
        paths:
        - path: /auth(/|$)(.*)
          backend:
            service:
              name: keycloak
        - path: /astrago(/|$)(.*)  
          backend:
            service:
              name: astrago-frontend
```

---

## 🚀 설치 과정 비교

### 기존 방식 (복잡)
```bash
# 1. 도구 수동 설치
sudo ./tools/install_helmfile.sh

# 2. IP 주소 미리 확인
kubectl get nodes -o wide

# 3. 환경변수 수동 설정
export EXTERNAL_IP=192.168.1.100

# 4. 배포
helmfile apply
```

### 개선된 방식 (간단)
```bash
# 1. 고객 환경 초기화 (IP 자동 감지)
./deploy_astrago_v3.sh init samsung

# 2. 배포 (도구 자동 설정)
./deploy_astrago_v3.sh deploy samsung

# 또는 기본 환경
./deploy_astrago_v3.sh deploy
```

---

## ✅ 기대 효과

### 운영 편의성
- **설치 시간 단축**: IP 설정 과정 제거
- **실수 방지**: 하드코딩으로 인한 설정 오류 방지  
- **일관성**: 표준화된 배포 프로세스

### 기술적 이점
- **보안 강화**: sudo 권한 불필요
- **격리성**: 시스템 환경 오염 방지
- **확장성**: 다중 고객 환경 지원
- **유지보수성**: 중앙화된 버전 관리

### 고객 만족도
- **편의성**: DNS 설정 불필요
- **유연성**: HTTP/HTTPS 자동 대응
- **안정성**: 검증된 배포 프로세스

---

## 📌 다음 단계

### 예정된 작업 (Linear Issue BE-527)
1. **Ingress Controller 추가**
   - Helm Chart 구성
   - Host Network 모드 설정

2. **Frontend 동적 URL 처리 구현**  
   - Next.js 코드 수정
   - 런타임 URL 감지

3. **Path 기반 라우팅 설정**
   - Ingress 리소스 정의
   - 리버스 프록시 규칙

4. **테스트 및 검증**
   - 다양한 환경에서 배포 테스트
   - 기존 환경 마이그레이션 가이드

---

## 🎯 결론

이번 개선으로 **Astrago 배포 시스템이 더욱 간단하고 안정적**이 되었습니다:

- ✅ **설치 복잡도 대폭 감소**
- ✅ **오프라인 환경 완벽 지원**  
- ✅ **플랫폼 호환성 확장**
- ✅ **통합된 관리 도구**

향후 **Ingress 전환**이 완료되면 고객 현장에서의 설치 및 운영이 훨씬 수월해질 것으로 예상됩니다.