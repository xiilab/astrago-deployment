# Uyuni Theme 자동화 설정 가이드

## 개요

이 문서는 Uyuni Keycloak 테마 자동화 설정을 위한 가이드입니다. uyuni-login-theme 레포지토리에서 테마가 변경될 때마다 astrago-deployment의 monochart 파일들이 자동으로 업데이트됩니다.

## 아키텍처

1. **uyuni-login-theme**: 테마 파일 관리 및 Docker 이미지 빌드
2. **Docker Hub**: xiilab/astrago-keycloak 이미지 저장소
3. **astrago-deployment**: 기존 워크플로우에 테마 업데이트 로직 통합

## 설정 단계

### 1. uyuni-login-theme 레포지토리 설정

#### 1.1 Dockerfile.keycloak 추가

uyuni-login-theme 레포지토리에 다음 Dockerfile을 추가하세요:

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

#### 1.2 웹훅 설정 (선택사항)

uyuni-login-theme 레포지토리에서 웹훅을 설정하면 테마 변경시 즉시 트리거할 수 있습니다:

1. **Settings** → **Webhooks** → **Add webhook** 클릭
2. 다음 정보 입력:
   - **Payload URL**: `https://api.github.com/repos/xiilab/astrago-deployment/dispatches`
   - **Content type**: `application/json`
   - **Events**: **Pushes** 선택
3. **Branch filter**: `feature/keycloak-astrago-theme` 설정
4. **Add webhook** 클릭

### 2. astrago-deployment 레포지토리 설정

#### 2.1 Keycloak Theme 전용 워크플로우

`feature/keycloak-astrago-theme` 브랜치 전용 워크플로우가 생성되었습니다:
- `keycloak-theme-deploy.yml`: Keycloak 테마 자동화 (feature/keycloak-astrago-theme 브랜치)

#### 2.2 기존 워크플로우

기존 워크플로우들은 원래대로 유지됩니다:
- `develop-deploy.yml`: dev 환경 (develop 브랜치)
- `develop2-deploy.yml`: dev2 환경 (master 브랜치)
- `production-deploy.yml`: stage/prod 환경 (master 브랜치)

#### 2.3 동작 방식

Keycloak Theme 워크플로우는 다음 순서로 실행됩니다:
1. **helmfile 및 yq 설치**
2. **Docker Hub에서 최신 테마 버전 확인**
3. **모든 환경의 values.yaml 파일들 업데이트**
4. **모든 환경의 monochart 파일들 생성**
5. **변경사항 자동 커밋**

## 동작 방식

### 1. 테마 버전 업데이트
- Docker Hub API를 통해 xiilab/astrago-keycloak의 최신 태그 확인
- `environments/common/values.yaml`의 `keycloak.themeVersion` 업데이트
- 각 환경별 `values.yaml`의 Keycloak 이미지 설정 업데이트:
  - `keycloak.image.repository`: `xiilab/astrago-keycloak`
  - `keycloak.image.tag`: 최신 버전
  - `keycloak.image.pullPolicy`: `Always`

### 2. Monochart 생성
- 기존 helmfile 명령으로 monochart 파일들 생성
- 업데이트된 테마 설정이 자동으로 반영됨

## 테스트 방법

### 1. 수동 테스트
1. astrago-deployment 레포지토리에서 **Actions** 탭으로 이동
2. **Keycloak Theme Automation** 워크플로우 선택
3. **Run workflow** 클릭
4. 워크플로우 실행 결과 확인

### 2. 자동 테스트
1. uyuni-login-theme에서 테마 파일 변경
2. 변경사항을 `feature/keycloak-astrago-theme` 브랜치에 push
3. astrago-deployment의 Keycloak Theme 워크플로우 자동 실행 확인

## 브랜치 제한

- **uyuni-login-theme**: `feature/keycloak-astrago-theme` 브랜치만 처리
- **astrago-deployment**: 
  - `feature/keycloak-astrago-theme` 브랜치 → keycloak-theme-deploy.yml (Keycloak 테마 전용)
  - `develop` 브랜치 → develop-deploy.yml (기존)
  - `master` 브랜치 → develop2-deploy.yml, production-deploy.yml (기존)

## 문제 해결

### 1. 워크플로우 실행 실패
- GitHub Actions 로그 확인
- Docker Hub 연결 상태 확인
- yq 설치 실패 시 수동 설치 확인

### 2. 테마 버전 업데이트 실패
- Docker Hub API 응답 확인
- values.yaml 파일 경로 확인
- yq 명령어 구문 확인

### 3. Monochart 생성 실패
- helmfile 설치 상태 확인
- 환경별 values.yaml 파일 존재 확인
- Keycloak 앱 설정 확인

## 주의사항

1. **브랜치 제한**: `feature/keycloak-astrago-theme` 브랜치에서만 동작
2. **Docker Hub 의존성**: xiilab/astrago-keycloak 이미지가 Docker Hub에 있어야 함
3. **전용 워크플로우**: Keycloak 테마 전용 워크플로우로 분리
4. **자동 커밋**: 변경사항이 자동으로 커밋되고 push됨 