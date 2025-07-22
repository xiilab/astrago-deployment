# Uyuni Theme 자동화 설정 가이드

## 📋 개요

이 가이드는 uyuni-login-theme에서 테마 변경이 감지되면 자동으로 Docker 이미지를 빌드하고 astrago-deployment의 monochart 파일들을 업데이트하는 자동화 워크플로우 설정 방법을 설명합니다.

## 🎯 워크플로우 동작 과정

1. **uyuni-login-theme**의 `feature/keycloak-astrago-theme` 브랜치에서 테마 파일 변경 감지
2. **astrago-deployment**의 `feature/keycloak-astrago-theme` 브랜치 워크플로우 자동 트리거
3. **uyuni-login-theme**의 `feature/keycloak-astrago-theme` 브랜치 체크아웃하여 최신 버전 확인
4. **Dockerfile.keycloak**로 도커 이미지 빌드 (JAR 파일 다운로드 포함)
5. **Docker Hub**에 `xiilab/astrago-keycloak:버전` 푸시
6. **astrago-deployment**의 모든 환경 `values.yaml` 업데이트
7. **monochart/*/keycloak/*.yaml** 파일들 자동 생성 (테마 관련 부분만)
8. 변경사항 자동 커밋 및 태그 생성

## 🔧 수동 설정 필요 항목

### 1. uyuni-login-theme 레포지토리 설정

#### 1.1 Dockerfile.keycloak 파일 추가

uyuni-login-theme 레포지토리 루트에 `Dockerfile.keycloak` 파일을 생성하세요:

```dockerfile
# Use the same base image as astrago-deployment
FROM bitnami/keycloak:latest

# Install wget for downloading JAR file
USER root
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV THEME_VERSION=${THEME_VERSION:-latest}
ENV THEME_URL="https://github.com/xiilab/uyuni-login-theme/releases/download/v${THEME_VERSION}/keycloak-theme.jar"

# Download the theme JAR file
RUN mkdir -p /opt/bitnami/keycloak/providers/ && \
    wget -O /opt/bitnami/keycloak/providers/keycloak-theme.jar "${THEME_URL}" && \
    chown -R 1001:1001 /opt/bitnami/keycloak/providers/keycloak-theme.jar

# Switch back to non-root user
USER 1001

# Expose the default Keycloak port
EXPOSE 8080

# Use the default Keycloak entrypoint
ENTRYPOINT ["/opt/bitnami/scripts/keycloak/entrypoint.sh"]
CMD ["/opt/bitnami/scripts/keycloak/run.sh"]
```

#### 1.2 웹훅 설정

uyuni-login-theme 레포지토리에서 다음 설정을 진행하세요:

1. **Settings** → **Webhooks** → **Add webhook** 클릭
2. 다음 정보 입력:
   - **Payload URL**: `https://api.github.com/repos/xiilab/astrago-deployment/dispatches`
   - **Content type**: `application/json`
   - **Secret**: (선택사항) 보안을 위한 시크릿 설정
   - **Events**: 
     - ✅ **Pushes** (코드 변경시 트리거)
     - ✅ **Releases** (릴리즈 생성시 트리거)
3. **Add webhook** 클릭

### 2. astrago-deployment 레포지토리 설정

#### 2.1 GitHub Secrets 설정

astrago-deployment 레포지토리에서 다음 설정을 진행하세요:

1. **Settings** → **Secrets and variables** → **Actions** 클릭
2. **New repository secret** 클릭하여 다음 시크릿들을 추가:

   **DOCKERHUB_USERNAME**
   - Name: `DOCKERHUB_USERNAME`
   - Value: `your-dockerhub-username`

   **DOCKERHUB_TOKEN**
   - Name: `DOCKERHUB_TOKEN`
   - Value: `your-dockerhub-access-token`

#### 2.2 Docker Hub 액세스 토큰 생성 (필요시)

Docker Hub 액세스 토큰이 없다면:

1. [Docker Hub](https://hub.docker.com) 로그인
2. **Account Settings** → **Security** → **New Access Token**
3. 토큰 이름 입력 (예: `astrago-deployment`)
4. 토큰 생성 후 복사하여 GitHub Secrets에 저장

## ✅ 설정 체크리스트

### uyuni-login-theme 레포지토리
- [ ] `Dockerfile.keycloak` 파일이 루트 디렉토리에 존재
- [ ] 웹훅이 설정되어 있음 (Payload URL: astrago-deployment/dispatches)
- [ ] 웹훅 이벤트가 Pushes와 Releases로 설정됨
- [ ] 웹훅이 활성 상태임

### astrago-deployment 레포지토리
- [ ] `DOCKERHUB_USERNAME` 시크릿이 설정됨
- [ ] `DOCKERHUB_TOKEN` 시크릿이 설정됨
- [ ] `.github/workflows/uyuni-theme-monochart.yml` 파일이 존재함
- [ ] `applications/keycloak/values.yaml.gotmpl` 파일이 수정됨 (wget 제거됨)

## 🧪 테스트 방법

### 1. 수동 워크플로우 실행 테스트

1. astrago-deployment 레포지토리 → **Actions** 탭
2. **Uyuni Theme Monochart Generation** 워크플로우 선택
3. **Run workflow** 클릭
4. 다음 설정으로 테스트:
   - **Theme Version**: `latest` 또는 특정 버전 (예: `v1.0.6.3`)
   - **Update Mode**: `theme-only`
5. **Run workflow** 클릭하여 실행

### 2. 자동 트리거 테스트

1. uyuni-login-theme의 `feature/keycloak-astrago-theme` 브랜치에서 새로운 릴리즈 생성
2. astrago-deployment의 `feature/keycloak-astrago-theme` 브랜치 Actions 탭에서 워크플로우 자동 실행 확인
3. 생성된 Docker 이미지 확인: `docker.io/xiilab/astrago-keycloak:버전`
4. monochart 파일 업데이트 확인

## 🔍 문제 해결

### 워크플로우가 실행되지 않는 경우
- [ ] uyuni-login-theme 웹훅 설정 확인
- [ ] 웹훅 페이로드 URL이 정확한지 확인
- [ ] 웹훅 이벤트가 올바르게 설정되었는지 확인

### Docker 이미지 빌드 실패
- [ ] Docker Hub 로그인 정보 확인
- [ ] `DOCKERHUB_USERNAME`과 `DOCKERHUB_TOKEN` 시크릿 확인
- [ ] uyuni-login-theme의 `Dockerfile.keycloak` 파일 존재 확인

### Monochart 파일 업데이트 실패
- [ ] astrago-deployment 레포지토리 권한 확인
- [ ] 기존 monochart 파일 존재 확인
- [ ] yq 도구 설치 확인

## 📝 참고사항

### 워크플로우 모드
- **theme-only** (기본값): 테마 관련 부분만 업데이트 (빠름, 안전함)
- **full-regenerate**: 전체 YAML 파일 재생성 (완전함, 느림)

### 자동화된 변경사항
- Docker 이미지 태그 업데이트
- 기존 wget initContainer 제거
- 기존 theme 볼륨 마운트 제거
- 환경별 values.yaml 파일 업데이트
- monochart 파일 자동 커밋 및 태그 생성

### 수동 개입이 필요한 경우
- 새로운 환경 추가시 (dev, dev2, stage, prod 외)
- Keycloak 기본 설정 변경시
- PostgreSQL 설정 변경시
- 기타 인프라 설정 변경시

## 🎉 완료 후 확인사항

설정이 완료되면 다음을 확인하세요:

1. **uyuni-login-theme**의 `feature/keycloak-astrago-theme` 브랜치에서 테마 변경시 자동으로 워크플로우 실행
2. **Docker Hub**에 새로운 이미지 푸시
3. **astrago-deployment**의 `feature/keycloak-astrago-theme` 브랜치 monochart 파일 자동 업데이트
4. **Git 커밋** 및 **태그** 자동 생성

이제 uyuni 테마 변경이 완전히 자동화됩니다! 🚀

## 📝 브랜치 제한 사항

- **uyuni-login-theme**: `feature/keycloak-astrago-theme` 브랜치의 변경사항만 감지
- **astrago-deployment**: `feature/keycloak-astrago-theme` 브랜치에서만 워크플로우 실행
- **다른 브랜치**: master, develop 등 다른 브랜치의 변경사항은 감지하지 않음 