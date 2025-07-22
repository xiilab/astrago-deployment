# Uyuni Theme 자동화 설정 가이드

## 개요

이 문서는 Uyuni Keycloak 테마 자동화 설정을 위한 가이드입니다. uyuni-login-theme 레포지토리에서 테마가 변경될 때마다 Docker 이미지가 자동으로 빌드되고, astrago-deployment에서는 최신 이미지를 동적으로 가져와서 사용합니다.

## 워크플로우 동작 방식

### 1. uyuni-login-theme 워크플로우 → astrago-deployment 워크플로우

#### **1단계: uyuni-login-theme (테마 변경 감지)**
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

#### **2단계: astrago-deployment (자동 배포)**
```
브랜치 푸시 또는 수동 실행
    ↓
GitHub Actions 워크플로우 실행
    ↓
Docker Hub에서 최신 커밋 해시 태그 조회
    ↓
values.yaml 파일 자동 업데이트
    ↓
monochart 파일 생성
    ↓
변경사항 자동 커밋
```

## 변경된 파일 목록

### 1. uyuni-login-theme 레포지토리 변경사항

#### 1.1 새로 생성된 파일
- **`Dockerfile.keycloak`**: Keycloak 테마 Docker 이미지 빌드용

#### 1.2 수정된 파일들
- **`.github/workflows/build.yaml`**: Docker 이미지 빌드 및 푸시 단계 추가

**주요 변경 내용:**
```yaml
# 기존 JAR 빌드 단계들 유지
- run: npm install
- run: DISABLE_ESLINT_PLUGIN=true npm run build
- run: DISABLE_ESLINT_PLUGIN=true npx keycloakify
- run: mv build_keycloak/target/astrago-*.jar build_keycloak/target/keycloak-theme.jar

# 새로 추가된 Docker 이미지 빌드 단계들
- name: Set up Docker Buildx
- name: Log in to Docker Hub
- name: Set version (4자리 커밋 해시)
- name: Build and push Docker image
```

### 2. astrago-deployment 레포지토리 변경사항

#### 2.1 새로 생성된 파일
- **`.github/workflows/keycloak-theme-deploy.yml`**: `feature/keycloak-astrago-theme` 브랜치 전용 워크플로우
- **`scripts/offline-uyuni-theme.sh`**: 오프라인 환경 테마 업데이트 스크립트
- **`scripts/test-uyuni-integration.sh`**: 테마 통합 테스트 스크립트
- **`docs/uyuni-theme-automation-setup.md`**: 설정 가이드 문서

#### 2.2 수정된 파일들
- **`applications/keycloak/values.yaml.gotmpl`**: Keycloak 이미지 설정 추가, JAR 다운로드 로직 제거
- **`.github/workflows/develop-deploy.yml`**: 동적 태그 업데이트 로직 추가
- **`.github/workflows/develop2-deploy.yml`**: 동적 태그 업데이트 로직 추가
- **`.github/workflows/production-deploy.yml`**: 동적 태그 업데이트 로직 추가
- **`environments/common/values.yaml`**: keycloak.themeVersion 필드 자동 업데이트
- **`environments/dev/values.yaml`**: Keycloak 이미지 설정 추가
- **`environments/dev2/values.yaml`**: Keycloak 이미지 설정 추가
- **`environments/stage/values.yaml`**: Keycloak 이미지 설정 추가
- **`environments/prod/values.yaml`**: Keycloak 이미지 설정 추가
- **`README.md`**: Uyuni 테마 자동화 링크 추가

#### 2.3 삭제된 파일
- **`.github/workflows/uyuni-theme-monochart.yml`**: 복잡한 기존 워크플로우 (삭제됨)
- **`Dockerfile.keycloak`**: 로컬 임시 파일 (삭제됨)

## 주요 개선사항

### 1. 아키텍처 개선
| 구분 | 기존 방식 | 새로운 방식 |
|------|-----------|-------------|
| **테마 배포** | JAR 다운로드 | Docker 이미지 |
| **버전 관리** | 하드코딩 | 동적 커밋 해시 |
| **자동화** | 수동 업데이트 | 자동 감지 및 업데이트 |
| **성능** | 런타임 다운로드 | 미리 빌드된 이미지 |
| **안정성** | 네트워크 의존성 | 로컬 이미지 사용 |

### 2. 워크플로우 개선
- **단순화**: 복잡한 웹훅 제거, 기존 패턴 활용
- **효율성**: JAR 다운로드 제거로 컨테이너 시작 시간 단축
- **정확성**: 4자리 커밋 해시로 정확한 버전 추적
- **유연성**: 환경별로 다른 태그 사용 가능

### 3. 개발자 경험 개선
- **자동화**: 테마 변경시 자동으로 최신 이미지 사용
- **롤백**: 이전 커밋 해시로 쉽게 되돌릴 수 있음
- **테스트**: 통합 테스트 스크립트 제공
- **문서화**: 상세한 설정 가이드 제공

## 설정 단계

### 1. uyuni-login-theme 레포지토리 설정

#### 1.1 Dockerfile.keycloak 추가

uyuni-login-theme 레포지토리에 다음 Dockerfile을 추가하세요:

```dockerfile
# Use the same base image as astrago-deployment
FROM bitnami/keycloak:latest

# Switch to root for file operations
USER root

# Copy the built JAR file directly
COPY build_keycloak/target/keycloak-theme.jar /opt/bitnami/keycloak/providers/keycloak-theme.jar

# Set proper permissions
RUN chown -R 1001:1001 /opt/bitnami/keycloak/providers/keycloak-theme.jar

# Switch back to non-root user
USER 1001

# Expose the default Keycloak port
EXPOSE 8080

# Use the default Keycloak entrypoint
ENTRYPOINT ["/opt/bitnami/scripts/keycloak/entrypoint.sh"]
CMD ["/opt/bitnami/scripts/keycloak/run.sh"]
```

#### 1.2 기존 build.yaml 워크플로우 수정

uyuni-login-theme 레포지토리의 `.github/workflows/build.yaml` 파일을 수정하세요:

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    name: Create Release and Docker Image
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [18.18.2]
    steps:
      # 기존 JAR 빌드 단계들
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Use Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}

      - run: npm install
      - run: DISABLE_ESLINT_PLUGIN=true npm run build
      - run: DISABLE_ESLINT_PLUGIN=true npx keycloakify
      - run: mv build_keycloak/target/retrocompat-*.jar build_keycloak/target/retrocompat-keycloak-theme.jar
      - run: mv build_keycloak/target/astrago-*.jar build_keycloak/target/keycloak-theme.jar
      
      # 새로 추가할 Docker 이미지 빌드 단계들
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      
      - name: Set version (4자리 커밋 해시)
        id: version
        run: |
          VERSION=$(git rev-parse --short=4 HEAD)
          echo "version=$VERSION" >> $GITHUB_OUTPUT
          echo "Using version: $VERSION"
      
      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile.keycloak
          push: true
          tags: |
            xiilab/astrago-keycloak-theme:${{ steps.version.outputs.version }}
```

#### 1.3 Docker Hub Secrets 설정

uyuni-login-theme 레포지토리에서:
1. **Settings** → **Secrets and variables** → **Actions**
2. 다음 시크릿 추가:
   - `DOCKERHUB_USERNAME`: Docker Hub 사용자명
   - `DOCKERHUB_TOKEN`: Docker Hub 액세스 토큰

### 2. astrago-deployment 레포지토리 설정

#### 2.1 values.yaml.gotmpl 수정 완료

`applications/keycloak/values.yaml.gotmpl` 파일이 이미 수정되어 있습니다:
- `xiilab/astrago-keycloak-theme` 이미지 사용
- JAR 다운로드 관련 initContainer 및 volumes 제거
- 동적 이미지 태그 사용

**변경 내용:**
```yaml
# Use custom Keycloak image with theme
image:
  repository: "{{ .Values.keycloak.image.repository | default \"xiilab/astrago-keycloak-theme\" }}"
  tag: "{{ .Values.keycloak.image.tag | default \"latest\" }}"
  pullPolicy: "{{ .Values.keycloak.image.pullPolicy | default \"Always\" }}"
```

#### 2.2 Keycloak Theme 전용 워크플로우

`feature/keycloak-astrago-theme` 브랜치 전용 워크플로우가 생성되었습니다:
- `keycloak-theme-deploy.yml`: Keycloak 테마 자동화 (feature/keycloak-astrago-theme 브랜치)

**주요 기능:**
- 모든 환경(dev, dev2, stage, prod)의 values.yaml 업데이트
- 모든 환경의 monochart 파일 생성
- 동적 태그 업데이트
- keycloak.themeVersion 자동 업데이트

#### 2.3 기존 워크플로우 업데이트

기존 워크플로우들에 동적 태그 업데이트 기능이 추가되었습니다:
- `develop-deploy.yml`: dev 환경 (develop 브랜치)
- `develop2-deploy.yml`: dev2 환경 (master 브랜치)
- `production-deploy.yml`: stage/prod 환경 (master 브랜치)

**추가된 기능:**
```yaml
# Update Keycloak image tag with latest commit hash
- name: Update Keycloak image tag
  run: |
    # Get latest commit hash tag from Docker Hub (excluding 'latest')
    LATEST_TAG=$(curl -s "https://registry.hub.docker.com/v2/repositories/xiilab/astrago-keycloak-theme/tags/" | jq -r '.results[] | select(.name != "latest") | .name' | head -1)
    
    if [ -z "$LATEST_TAG" ]; then
      echo "No commit hash tag found, using latest"
      LATEST_TAG="latest"
    fi
    
    echo "Latest Keycloak image tag: $LATEST_TAG"
    
    # Update environment values
    yq eval '.keycloak.image.repository = "xiilab/astrago-keycloak-theme"' -i environments/$ENV/values.yaml
    yq eval ".keycloak.image.tag = \"$LATEST_TAG\"" -i environments/$ENV/values.yaml
    yq eval '.keycloak.image.pullPolicy = "Always"' -i environments/$ENV/values.yaml
```

#### 2.4 환경별 values.yaml 설정

각 환경의 `values.yaml`에서 Keycloak 이미지 설정이 자동으로 업데이트됩니다:

```yaml
keycloak:
  image:
    repository: "xiilab/astrago-keycloak-theme"
    tag: "a1b2"  # 자동으로 최신 4자리 커밋 해시로 업데이트
    pullPolicy: "Always"
  themeVersion: "a1b2"  # common/values.yaml에서도 자동 업데이트
```

**참고**: 태그는 워크플로우 실행시 Docker Hub에서 최신 커밋 해시를 자동으로 가져와서 업데이트됩니다.

## 워크플로우 정상작동 확인 방법

### 1. uyuni-login-theme 워크플로우 테스트

#### **1단계: 릴리즈 태그 생성**
```bash
# uyuni-login-theme 레포지토리에서
git tag v1.0.6.4
git push origin v1.0.6.4
```

#### **2단계: GitHub Actions 확인**
1. **GitHub 레포지토리** → **Actions** 탭
2. **Build and Release** 워크플로우 실행 확인
3. **단계별 실행 상태** 확인:
   - ✅ Checkout code
   - ✅ Use Node.js
   - ✅ npm install
   - ✅ npm run build
   - ✅ npx keycloakify
   - ✅ Set up Docker Buildx
   - ✅ Log in to Docker Hub
   - ✅ Set version
   - ✅ Build and push Docker image

#### **3단계: Docker Hub 확인**
1. **Docker Hub** → **xiilab/astrago-keycloak-theme** 레포지토리
2. **Tags** 탭에서 새 이미지 확인
3. **4자리 커밋 해시 태그** (예: `a1b2`) 확인

### 2. astrago-deployment 워크플로우 테스트

#### **1단계: 브랜치 푸시**
```bash
# astrago-deployment 레포지토리에서
git push origin feature/keycloak-astrago-theme
```

#### **2단계: GitHub Actions 확인**
1. **GitHub 레포지토리** → **Actions** 탭
2. **Keycloak Theme Automation** 워크플로우 실행 확인
3. **단계별 실행 상태** 확인:
   - ✅ Checkout code
   - ✅ install helmfile and yq
   - ✅ Update Keycloak image tag
   - ✅ Generate monochart files
   - ✅ Commit changes

#### **3단계: 변경사항 확인**
1. **values.yaml 파일**에서 이미지 태그 업데이트 확인
2. **monochart 파일**에서 새로운 이미지 사용 확인
3. **커밋 메시지**에서 업데이트된 태그 확인

### 3. 수동 워크플로우 실행 테스트

#### **GitHub Actions에서 수동 실행:**
1. **Actions** 탭 → **워크플로우 선택**
2. **Run workflow** 버튼 클릭
3. **브랜치 선택** → **Run workflow**
4. **실행 로그** 확인

### 4. 로그 확인 포인트

#### **성공적인 실행 로그:**
```bash
# uyuni-login-theme 워크플로우
Using version: a1b2
Pushing image to Docker Hub...

# astrago-deployment 워크플로우
Latest Keycloak image tag: a1b2
Updated dev environment with tag: a1b2
Generated monochart for dev environment
```

#### **문제 발생시 확인사항:**
- **Docker Hub 로그인**: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` 시크릿 확인
- **이미지 빌드**: Dockerfile 경로 및 JAR 파일 존재 확인
- **태그 조회**: Docker Hub API 응답 확인
- **파일 업데이트**: yq 명령어 실행 결과 확인

## 동작 방식

### 1. 테마 변경 감지
- uyuni-login-theme의 릴리즈 태그(`v*`) 생성시
- GitHub Actions 워크플로우 자동 실행

### 2. JAR 빌드 및 Docker 이미지 생성
- 기존 JAR 빌드 단계 실행
- 빌드된 JAR를 Dockerfile로 복사하여 이미지 생성
- Docker Hub에 `xiilab/astrago-keycloak-theme:a1b2` (4자리 커밋 해시) 푸시

### 3. astrago-deployment에서 사용
- 기존 워크플로우 실행시 Docker Hub에서 최신 커밋 해시 태그 자동 가져오기
- values.yaml 파일의 Keycloak 이미지 태그 자동 업데이트
- monochart 생성시 최신 이미지 사용

## 테스트 방법

### 1. uyuni-login-theme 테스트
1. `feature/keycloak-astrago-theme` 브랜치에서 테마 파일 변경
2. 릴리즈 태그 생성 (예: `v1.0.6.4`)
3. GitHub Actions에서 JAR 빌드 및 Docker 이미지 빌드 확인
4. Docker Hub에서 새 이미지 확인 (4자리 커밋 해시 태그)

### 2. astrago-deployment 테스트
1. **Keycloak Theme 전용 워크플로우**: `feature/keycloak-astrago-theme` 브랜치에서 실행
2. **기존 워크플로우**: develop-deploy, develop2-deploy, production-deploy
3. 생성된 monochart 파일에서 이미지 태그 확인
4. 최신 이미지가 사용되는지 확인

## 브랜치 제한

- **uyuni-login-theme**: 릴리즈 태그(`v*`) 생성시에만 이미지 빌드
- **astrago-deployment**: 
  - `feature/keycloak-astrago-theme` 브랜치 → keycloak-theme-deploy.yml (Keycloak 테마 전용)
  - `develop` 브랜치 → develop-deploy.yml (기존 + 동적 태그 업데이트)
  - `master` 브랜치 → develop2-deploy.yml, production-deploy.yml (기존 + 동적 태그 업데이트)

## 장점

1. **간단함**: 웹훅 설정 불필요
2. **안정성**: 기존 워크플로우 구조 유지
3. **자동화**: 테마 변경시 자동으로 최신 이미지 사용
4. **유연성**: 환경별로 다른 태그 사용 가능
5. **정확한 버전 추적**: 4자리 커밋 해시로 정확한 버전 관리
6. **롤백 가능**: 이전 커밋 해시로 쉽게 되돌릴 수 있음
7. **효율성**: JAR 다운로드 제거로 컨테이너 시작 시간 단축

## 주의사항

1. **릴리즈 태그**: uyuni-login-theme에서 릴리즈 태그(`v*`) 생성시에만 Docker 이미지 빌드
2. **Docker Hub 의존성**: xiilab/astrago-keycloak-theme 이미지가 Docker Hub에 있어야 함
3. **이미지 태그**: 4자리 커밋 해시 태그 사용으로 정확한 버전 추적
4. **Pull Policy**: `Always`로 설정하여 최신 이미지 보장
5. **JAR 파일**: Dockerfile에서 빌드된 JAR를 직접 복사하여 사용

## 수동 설정 체크리스트

### uyuni-login-theme 레포지토리
- [ ] `Dockerfile.keycloak` 파일 생성
- [ ] `.github/workflows/build.yaml` 파일 수정 (Docker 빌드 단계 추가)
- [ ] Docker Hub Secrets 설정 (`DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`)

### astrago-deployment 레포지토리
- [ ] `applications/keycloak/values.yaml.gotmpl` 파일 수정 완료
- [ ] `.github/workflows/keycloak-theme-deploy.yml` 파일 생성 완료
- [ ] 기존 워크플로우들에 동적 태그 업데이트 로직 추가 완료

### 테스트
- [ ] uyuni-login-theme에서 릴리즈 태그 생성 테스트
- [ ] Docker Hub에 이미지 푸시 확인
- [ ] astrago-deployment에서 동적 태그 업데이트 테스트
- [ ] monochart 파일 생성 확인 