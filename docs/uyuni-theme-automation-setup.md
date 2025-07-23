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
    ↓
ArgoCD가 monochart/theme/keycloak/ 감지
    ↓
Kubernetes 클러스터에 자동 배포
```

## 🎯 상세 워크플로우 동작 과정

### **1단계: uyuni-login-theme 워크플로우 상세**

#### **GitHub Actions build.yaml 실행 과정**
1. **트리거 조건**: 릴리즈 태그(`v*`) 생성시에만 실행
2. **환경 설정**: Node.js 18, Docker Buildx 설정
3. **빌드 과정**:
   ```bash
   npm install
   DISABLE_ESLINT_PLUGIN=true npm run build
   DISABLE_ESLINT_PLUGIN=true npx keycloakify
   ```
4. **Docker 이미지 빌드**:
   - `Dockerfile.keycloak` 사용
   - 베이스 이미지: `bitnami/keycloak:latest`
   - JAR 파일을 `/opt/bitnami/keycloak/providers/`에 복사
5. **Docker Hub 푸시**:
   - 이미지명: `xiilab/astrago-keycloak-theme`
   - 태그: 4자리 커밋 해시 (예: `45fc`)

#### **Dockerfile.keycloak 상세**
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

### **2단계: astrago-deployment 워크플로우 상세**

#### **워크플로우별 동작**
1. **keycloak-theme-deploy.yml** (`feature/keycloak-astrago-theme` 브랜치)
2. **develop-deploy.yml** (`develop` 브랜치)
3. **production-deploy.yml** (`master` 브랜치)

#### **상세 실행 과정**
1. **환경 설정**:
   ```bash
   # Helmfile 및 yq 설치
   wget https://github.com/helmfile/helmfile/releases/download/v0.159.0/helmfile_0.159.0_linux_amd64.tar.gz
   wget https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64
   ```

2. **themeVersion 기반 이미지 태그 업데이트**:
   ```bash
   # common/values.yaml에서 themeVersion 읽기
   THEME_VERSION=$(yq eval '.keycloak.themeVersion' environments/common/values.yaml)
   
   # 환경별 values.yaml 업데이트
   yq eval '.keycloak.image.repository = "xiilab/astrago-keycloak-theme"' -i environments/{env}/values.yaml
   yq eval ".keycloak.image.tag = \"$THEME_VERSION\"" -i environments/{env}/values.yaml
   yq eval '.keycloak.image.pullPolicy = "Always"' -i environments/{env}/values.yaml
   ```

3. **Monochart 파일 생성**:
   ```bash
   helmfile -e {environment} -l app=keycloak template > monochart/{environment}/keycloak/keycloak.yaml
   ```

4. **자동 커밋 및 푸시**:
   ```yaml
   - uses: stefanzweifel/git-auto-commit-action@v5
     with:
       commit_message: commit monochart.yaml
   ```

## 🔗 ArgoCD와 Kubernetes 클러스터 연동 과정

### **ArgoCD Application 설정**
ArgoCD는 `monochart/theme/keycloak/` 디렉토리를 지속적으로 모니터링하며, 변경사항이 감지되면 자동으로 Kubernetes 클러스터에 배포합니다.

#### **ArgoCD Application YAML 예시**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak-theme
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/astrago-deployment
    targetRevision: HEAD
    path: monochart/theme/keycloak
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### **Kubernetes 클러스터에서의 변경사항 적용 과정**

#### **1. ArgoCD 감지 및 동기화**
- ArgoCD가 Git 저장소의 `monochart/theme/keycloak/keycloak.yaml` 변경 감지
- 변경된 YAML 파일을 Kubernetes API 서버에 적용

#### **2. Kubernetes 리소스 업데이트**
```yaml
# keycloak.yaml의 주요 변경 부분
spec:
  template:
    spec:
      containers:
        - name: keycloak
          image: docker.io/xiilab/astrago-keycloak-theme:45fc  # 새로운 이미지 태그
          imagePullPolicy: Always
```

#### **3. StatefulSet 롤링 업데이트**
1. **새 Pod 생성**: 새로운 이미지로 Pod 생성 시작
2. **헬스체크**: 새 Pod가 Ready 상태가 될 때까지 대기
3. **기존 Pod 종료**: 이전 Pod 종료
4. **서비스 전환**: 트래픽이 새 Pod로 전환

#### **4. Keycloak 컨테이너 시작 과정**
```yaml
lifecycle:
  postStart:
    exec:
      command:
        - /bin/bash
        - -c
        - |
          echo "Starting postStart script" > /opt/bitnami/keycloak/poststart.log
          until curl -sSf http://localhost:8080/auth/realms/master > /dev/null; do
            echo "Waiting for Keycloak to be ready..." >> /opt/bitnami/keycloak/poststart.log
            sleep 5
          done
          /opt/bitnami/keycloak/bin/kcadm.sh update realms/master -s sslRequired=NONE --server http://localhost:8080/auth/ --realm master --user admin --password "xiirocks" >> /opt/bitnami/keycloak/poststart.log 2>&1
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

## 🔄 변경사항 상세 분석

### **1. 이미지 태그 변경 감지**
```yaml
# 변경 전 (environments/common/values.yaml)
keycloak:
  themeVersion: "a1b2" < 하드코딩

# 변경 후
keycloak:
  themeVersion: "45fc" < uyuni-login-theme workflow gitaction 에서 동적 변경해줌. 
```

### **2. 환경별 values.yaml 자동 업데이트**
```yaml
# 변경 전 (environments/theme/values.yaml)
keycloak:
  image:
    repository: xiilab/astrago-keycloak-theme
    tag: "a1b2"
    pullPolicy: Always

# 변경 후
keycloak:
  image:
    repository: xiilab/astrago-keycloak-theme
    tag: "45fc"  # themeVersion과 동기화
    pullPolicy: Always
```

### **3. Monochart 파일 생성**
```yaml
# monochart/theme/keycloak/keycloak.yaml
spec:
  template:
    spec:
      containers:
        - name: keycloak
          image: docker.io/xiilab/astrago-keycloak-theme:45fc  # 새로운 태그 적용
          imagePullPolicy: Always
```

### **4. Kubernetes 클러스터 반영**
- **StatefulSet 업데이트**: 새로운 이미지 태그로 Pod 재시작
- **ConfigMap 업데이트**: 환경 변수 및 설정 변경사항 적용
- **Service 유지**: 기존 서비스 설정 유지 (NodePort: 30001)

## 📊 AS-IS vs AS-WAS 비교

| 구분 | 기존 방식 (AS-WAS) | 새로운 방식 (AS-IS) |
|------|-------------------|-------------------|
| **테마 배포** | JAR 파일 다운로드 방식 | Docker 이미지 방식 |
| **버전 관리** | 하드코딩된 태그 | 중앙 집중식 themeVersion |
| **자동화** | 수동 업데이트 | 자동 감지 및 업데이트 |
| **성능** | 런타임 다운로드 | 미리 빌드된 이미지 |
| **안정성** | 네트워크 의존성 | 로컬 이미지 사용 |
| **배포 속도** | 느림 (다운로드 시간) | 빠름 (이미지 풀) |
| **롤백** | 복잡한 JAR 교체 | 간단한 이미지 태그 변경 |
| **모니터링** | 제한적 | 상세한 배포 상태 추적 |

### **주요 개선점**

#### **1. 배포 안정성 향상**
- **기존**: JAR 다운로드 실패시 배포 중단
- **개선**: Docker 이미지 미리 빌드로 안정성 확보

#### **2. 버전 관리 개선**
- **기존**: 각 환경별 개별 태그 관리
- **개선**: 중앙 집중식 themeVersion으로 일관성 확보

#### **3. 자동화 수준 향상**
- **기존**: 수동으로 각 환경 업데이트
- **개선**: GitOps 기반 자동 동기화

#### **4. 성능 최적화**
- **기존**: 매번 JAR 다운로드
- **개선**: 이미지 레이어 캐싱 활용

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

### **3. ArgoCD 동기화 테스트**
```bash
# ArgoCD Application 상태 확인
kubectl get applications -n argocd

# 동기화 상태 확인
argocd app sync keycloak-theme

# Pod 상태 확인
kubectl get pods -n keycloak
kubectl describe pod keycloak-0 -n keycloak
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

### **ArgoCD 설정**
- [ ] ArgoCD Application 등록 완료
- [ ] Git 저장소 연결 설정 완료
- [ ] 자동 동기화 정책 설정 완료

### **테스트**
- [ ] uyuni-login-theme에서 릴리즈 태그 생성 테스트
- [ ] Docker Hub에 이미지 푸시 확인
- [ ] astrago-deployment에서 themeVersion 기반 업데이트 테스트
- [ ] monochart 파일 생성 확인
- [ ] 모든 환경의 이미지 태그 동기화 확인
- [ ] ArgoCD 자동 동기화 테스트

## ⚠️ 주의사항

1. **릴리즈 태그**: uyuni-login-theme에서 릴리즈 태그(`v*`) 생성시에만 Docker 이미지 빌드
2. **Docker Hub 의존성**: xiilab/astrago-keycloak-theme 이미지가 Docker Hub에 있어야 함
3. **이미지 태그**: 4자리 커밋 해시 태그 사용으로 정확한 버전 추적
4. **중앙 관리**: common/values.yaml의 themeVersion이 모든 환경의 기준
5. **동기화**: 모든 환경의 이미지 태그가 themeVersion과 동기화됨
6. **ArgoCD 설정**: Git 저장소 접근 권한 및 자동 동기화 정책 확인 필요