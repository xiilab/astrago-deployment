# Uyuni Theme 자동화 설정 가이드

## 개요

Uyuni Keycloak 테마 자동화 시스템: `uyuni-login-theme`에서 테마 변경 → Docker 이미지 빌드 → `astrago-deployment`에서 자동 배포

## 🔄 워크플로우 흐름

### **1단계: uyuni-login-theme (테마 변경 감지)**
```
릴리즈 태그 생성 (v1.0.6.4)
    ↓
GitHub Actions build.yaml 실행
    ↓
JAR 파일 빌드 (npm run build → keycloakify)
    ↓
Docker 이미지 빌드 (Dockerfile.keycloak)
    ↓
Docker Hub에 푸시 (xiilab/astrago-keycloak-theme:a1b2)
```

### **2단계: astrago-deployment (자동 배포)**
```
브랜치 푸시 또는 수동 실행
    ↓
GitHub Actions 워크플로우 실행
    ↓
common/values.yaml에서 themeVersion 읽기
    ↓
모든 환경의 values.yaml 파일 자동 업데이트
    ↓
monochart 파일 생성
    ↓
변경사항 자동 커밋
```

## 📁 주요 파일 변경사항

### **uyuni-login-theme 레포지토리**

#### **새로 생성**
- `Dockerfile.keycloak`: Keycloak 테마 Docker 이미지 빌드용

#### **수정**
- `.github/workflows/build.yaml`: Docker 이미지 빌드 및 푸시 단계 추가

### **astrago-deployment 레포지토리**

#### **새로 생성**
- `.github/workflows/keycloak-theme-deploy.yml`: `feature/keycloak-astrago-theme` 브랜치 전용
- `scripts/offline-uyuni-theme.sh`: 오프라인 환경 테마 업데이트
- `scripts/test-uyuni-integration.sh`: 테마 통합 테스트

#### **수정**
- `applications/keycloak/values.yaml.gotmpl`: Keycloak 이미지 설정, JAR 다운로드 제거
- `.github/workflows/*-deploy.yml`: themeVersion 기반 태그 업데이트 로직
- `environments/common/values.yaml`: keycloak.themeVersion (중앙 관리)
- `environments/*/values.yaml`: Keycloak 이미지 설정 자동 업데이트

## ⚙️ 설정 단계

### **1. uyuni-login-theme 설정**

#### **Dockerfile.keycloak 생성**
```dockerfile
FROM bitnami/keycloak:latest
USER root
COPY build_keycloak/target/keycloak-theme.jar /opt/bitnami/keycloak/providers/keycloak-theme.jar
RUN chown -R 1001:1001 /opt/bitnami/keycloak/providers/keycloak-theme.jar
USER 1001
EXPOSE 8080
ENTRYPOINT ["/opt/bitnami/scripts/keycloak/entrypoint.sh"]
CMD ["/opt/bitnami/scripts/keycloak/run.sh"]
```

#### **build.yaml 워크플로우 수정**
```yaml
# 기존 JAR 빌드 단계들 유지
- run: npm install
- run: DISABLE_ESLINT_PLUGIN=true npm run build
- run: DISABLE_ESLINT_PLUGIN=true npx keycloakify

# 새로 추가된 Docker 이미지 빌드 단계들
- name: Set up Docker Buildx
- name: Log in to Docker Hub
- name: Set version (4자리 커밋 해시)
- name: Build and push Docker image
```

#### **Docker Hub Secrets 설정**
- `DOCKERHUB_USERNAME`: Docker Hub 사용자명
- `DOCKERHUB_TOKEN`: Docker Hub 액세스 토큰

### **2. astrago-deployment 설정**

#### **중앙 집중식 버전 관리**
```yaml
# environments/common/values.yaml
keycloak:
  themeVersion: "latest"  # 모든 환경의 기준 버전
```

#### **워크플로우 자동화**
```yaml
# 모든 워크플로우에서 themeVersion 기반 업데이트
- name: Update Keycloak image tag
  run: |
    THEME_VERSION=$(yq eval '.keycloak.themeVersion' environments/common/values.yaml)
    yq eval ".keycloak.image.tag = \"$THEME_VERSION\"" -i environments/{env}/values.yaml
```

## 🎯 주요 개선사항

| 구분 | 기존 방식 | 새로운 방식 |
|------|-----------|-------------|
| **테마 배포** | JAR 다운로드 | Docker 이미지 |
| **버전 관리** | 하드코딩 | 중앙 집중식 themeVersion |
| **자동화** | 수동 업데이트 | 자동 감지 및 업데이트 |
| **성능** | 런타임 다운로드 | 미리 빌드된 이미지 |
| **안정성** | 네트워크 의존성 | 로컬 이미지 사용 |

## 🧪 테스트 방법

### **1. uyuni-login-theme 테스트**
```bash
# 릴리즈 태그 생성
git tag v1.0.6.4
git push origin v1.0.6.4

# GitHub Actions 확인
# Docker Hub에서 새 이미지 확인 (4자리 커밋 해시 태그)
```

### **2. astrago-deployment 테스트**
```bash
# 브랜치 푸시
git push origin feature/keycloak-astrago-theme

# GitHub Actions 확인
# values.yaml 파일에서 이미지 태그 업데이트 확인
# monochart 파일에서 새로운 이미지 사용 확인
```

## 🔒 브랜치 제한

- **uyuni-login-theme**: 릴리즈 태그(`v*`) 생성시에만 이미지 빌드
- **astrago-deployment**: 
  - `feature/keycloak-astrago-theme` → keycloak-theme-deploy.yml (Keycloak 테마 전용)
  - `develop` → develop-deploy.yml (기존 + themeVersion 기반 업데이트)
  - `master` → develop2-deploy.yml, production-deploy.yml (기존 + themeVersion 기반 업데이트)

## ✅ 설정 체크리스트

### **uyuni-login-theme 레포지토리**
- [ ] `Dockerfile.keycloak` 파일 생성
- [ ] `.github/workflows/build.yaml` 파일 수정 (Docker 빌드 단계 추가)
- [ ] Docker Hub Secrets 설정 (`DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`)

### **astrago-deployment 레포지토리**
- [ ] `applications/keycloak/values.yaml.gotmpl` 파일 수정 완료
- [ ] `.github/workflows/keycloak-theme-deploy.yml` 파일 생성 완료
- [ ] 기존 워크플로우들에 themeVersion 기반 업데이트 로직 추가 완료
- [ ] `environments/common/values.yaml`에서 themeVersion 설정 완료

### **테스트**
- [ ] uyuni-login-theme에서 릴리즈 태그 생성 테스트
- [ ] Docker Hub에 이미지 푸시 확인
- [ ] astrago-deployment에서 themeVersion 기반 업데이트 테스트
- [ ] monochart 파일 생성 확인
- [ ] 모든 환경의 이미지 태그 동기화 확인

## ⚠️ 주의사항

1. **릴리즈 태그**: uyuni-login-theme에서 릴리즈 태그(`v*`) 생성시에만 Docker 이미지 빌드
2. **Docker Hub 의존성**: xiilab/astrago-keycloak-theme 이미지가 Docker Hub에 있어야 함
3. **이미지 태그**: 4자리 커밋 해시 태그 사용으로 정확한 버전 추적
4. **중앙 관리**: common/values.yaml의 themeVersion이 모든 환경의 기준
5. **동기화**: 모든 환경의 이미지 태그가 themeVersion과 동기화됨 