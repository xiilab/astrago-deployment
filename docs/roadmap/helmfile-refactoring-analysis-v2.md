# Astrago Deployment Helmfile 리팩토링 분석 문서 v2

## 목차
1. [개요](#개요)
2. [현재 상태 분석](#현재-상태-분석)
3. [문제점 및 개선 필요사항](#문제점-및-개선-필요사항)
4. [제안하는 솔루션](#제안하는-솔루션)
5. [구현 전략](#구현-전략)
6. [마이그레이션 계획](#마이그레이션-계획)
7. [리스크 및 대응방안](#리스크-및-대응방안)
8. [기대 효과](#기대-효과)

---

## 개요

### 프로젝트 배경
- **프로젝트명**: Astrago Deployment
- **현재 이슈**: Linear BE-384
- **대상 범위**: Helmfile 기반 애플리케이션 배포 구조
- **문서 작성일**: 2025-09-03
- **작성 목적**: Helmfile 구조 리팩토링을 위한 현황 분석 및 개선 방안 수립

### 프로젝트 구성
Astrago Deployment는 3가지 주요 컴포넌트로 구성:
1. **Kubespray**: Kubernetes 클러스터 설치
2. **Airgap**: 오프라인 환경에서의 Kubernetes 준비 및 설치
3. **Helmfile**: Astrago 및 관련 플랫폼 설치 (**현재 리팩토링 대상**)

### 핵심 요구사항
- **오프라인 환경 지원 필수** (Airgap 환경에서도 동작)
- 설치형 솔루션으로서 고객 커스터마이징 요청 대응 필요
- 차트 버전 업그레이드 용이성 확보
- 헬름차트 커스터마이징 및 독립적 관리 체계 구축
- 구조의 단순성 유지 (복잡도 최소화)

---

## 현재 상태 분석

### 현재 디렉토리 구조

```
astrago-deployment/
├── helmfile.yaml                    # 메인 Helmfile (루트)
├── applications/                    # 애플리케이션별 차트 및 설정
│   ├── astrago/
│   │   ├── helmfile.yaml           # 개별 helmfile
│   │   ├── astrago/                # 로컬 차트
│   │   └── values.yaml.gotmpl
│   ├── gpu-operator/
│   │   ├── helmfile.yaml
│   │   ├── custom-gpu-operator/    # 커스텀 차트
│   │   └── values.yaml.gotmpl
│   └── [기타 애플리케이션들...]
├── environments/                    # 환경별 설정
│   ├── common/
│   ├── dev/
│   ├── stage/
│   └── prod/
├── monochart/                       # 모노차트 설정
├── tools/
├── scripts/
└── docs/
```

### 현재 관리 중인 애플리케이션

| 애플리케이션 | 타입 | 차트 소스 | 네임스페이스 | 우선순위 |
|-------------|------|-----------|--------------|---------|
| CSI Driver NFS | Infrastructure | Local | kube-system | 1 |
| GPU Operator | Infrastructure | Custom/External | gpu-operator | 1 |
| Flux | GitOps | Local | flux-system | 1 |
| Prometheus | Monitoring | External | monitoring | 2 |
| Loki Stack | Monitoring | External | monitoring | 2 |
| GPU Process Exporter | Monitoring | Local | monitoring | 2 |
| Keycloak | Security | External | keycloak | 3 |
| Harbor | Registry | External | harbor | 3 |
| MPI Operator | Compute | External | mpi-operator | 3 |
| Astrago | Core Application | Local | astrago | 4 |

---

## 문제점 및 개선 필요사항

### 1. 구조적 문제점

#### 1.1 파일 분산 및 중복
- **현황**
  - 루트와 applications 폴더에 중복된 helmfile.yaml 존재
  - 각 애플리케이션마다 별도의 helmfile.yaml 관리
  - Helmfile 관련 설정이 여러 위치에 분산

- **영향**
  - 전체 구조 파악 어려움
  - 설정 변경 시 여러 파일 수정 필요
  - 일관성 유지 어려움

#### 1.2 차트 관리의 비체계성
- **현황**
  - 외부 차트와 커스텀 차트가 혼재
  - 차트 버전 관리 체계 부재
  - 오프라인 환경 대응 미흡

- **영향**
  - Airgap 환경에서 배포 복잡
  - 차트 업그레이드 어려움
  - 버전 추적 불가

### 2. 운영상 문제점

#### 2.1 오프라인 환경 지원 미흡
- **현황**
  - 외부 차트 URL 직접 참조
  - 로컬 차트 저장 체계 없음
  - 버전 및 체크섬 관리 부재

- **영향**
  - Airgap 환경 배포 시 수동 작업 필요
  - 배포 일관성 보장 어려움
  - 보안 환경 대응 불가

#### 2.2 복잡한 구조
- **현황**
  - 깊은 폴더 구조
  - 분산된 helmfile 관리
  - 불명확한 의존성 관계

- **영향**
  - 학습 곡선 높음
  - 유지보수 어려움
  - 실수 가능성 증가

---

## 제안하는 솔루션

### 1. 단순화된 디렉토리 구조

```
astrago-deployment/
├── helmfile/                       # Helmfile 관련 모든 파일 중앙화
│   ├── helmfile.yaml               # 메인 helmfile (모든 releases 정의)
│   ├── charts/                     # 차트 저장소
│   │   ├── external/               # 외부 차트 (오프라인용 로컬 저장)
│   │   │   ├── gpu-operator-v25.3.2/
│   │   │   ├── kube-prometheus-stack-45.7.1/
│   │   │   ├── loki-stack-2.9.10/
│   │   │   ├── keycloak-18.4.0/
│   │   │   ├── harbor-1.13.1/
│   │   │   └── versions.lock      # 버전 및 체크섬 관리
│   │   ├── custom/                 # 커스텀 차트
│   │   │   ├── astrago/
│   │   │   ├── csi-driver-nfs/
│   │   │   └── gpu-process-exporter/
│   │   └── patches/                # 차트 커스터마이징 패치
│   │       ├── gpu-operator/
│   │       └── prometheus/
│   ├── values/                     # 공통 값 템플릿
│   │   ├── common/                 # 모든 환경 공통
│   │   └── templates/              # Go 템플릿
│   └── environments/               # 환경별 설정
│       ├── dev/
│       ├── stage/
│       └── prod/
├── scripts/                        # 관리 스크립트
│   ├── sync-charts.sh             # 차트 다운로드 (온라인 환경)
│   ├── validate.sh                # 설정 검증
│   └── package-offline.sh        # 오프라인 패키지 생성
├── kubespray/                     # (기존 유지)
├── airgap/                        # (기존 유지)
└── docs/                          # (기존 유지)
```

**핵심 포인트**: 
- Helmfile 관련 모든 것이 `helmfile/` 디렉토리 안에 집중
- 루트 디렉토리가 깔끔하게 정리됨
- 다른 컴포넌트(kubespray, airgap)와 명확히 분리

### 2. 통합된 helmfile.yaml 구조

```yaml
# helmfile/helmfile.yaml
environments:
  dev:
    values:
      - values/common/defaults.yaml
      - environments/dev/values.yaml
  stage:
    values:
      - values/common/defaults.yaml
      - environments/stage/values.yaml
  prod:
    values:
      - values/common/defaults.yaml
      - environments/prod/values.yaml
    secrets:
      - environments/prod/secrets.yaml

helmDefaults:
  wait: true
  waitForJobs: true
  timeout: 600
  createNamespace: true
  skipDeps: false

# 오프라인 환경을 위한 로컬 저장소 (필요시)
repositories:
  - name: local-external
    url: file://./charts/external

releases:
  #============================================================
  # Tier 1: Infrastructure (기반 인프라)
  #============================================================
  
  - name: csi-driver-nfs
    namespace: kube-system
    chart: ./charts/custom/csi-driver-nfs
    version: 4.5.0
    labels:
      tier: infrastructure
      priority: "1"
    values:
      - values/templates/csi-driver-nfs.yaml.gotmpl
    {{ if eq .Environment.Name "prod" }}
    set:
      - name: replicaCount
        value: 3
    {{ end }}

  - name: gpu-operator
    namespace: gpu-operator
    chart: ./charts/external/gpu-operator-v25.3.2
    labels:
      tier: infrastructure
      priority: "1"
    needs:
      - kube-system/csi-driver-nfs
    values:
      - values/templates/gpu-operator.yaml.gotmpl
    # Kustomize 패치 적용 (선택적)
    {{ if .Values.customization.enabled }}
    strategicMergePatches:
      - charts/patches/gpu-operator/custom-images.yaml
    {{ end }}

  - name: flux
    namespace: flux-system
    chart: ./charts/custom/flux
    version: 2.10.0
    labels:
      tier: infrastructure
      priority: "1"
    values:
      - values/templates/flux.yaml.gotmpl

  #============================================================
  # Tier 2: Monitoring (모니터링 스택)
  #============================================================
  
  - name: prometheus
    namespace: monitoring
    chart: ./charts/external/kube-prometheus-stack-45.7.1
    labels:
      tier: monitoring
      priority: "2"
    needs:
      - kube-system/csi-driver-nfs
    values:
      - values/templates/prometheus.yaml.gotmpl
    {{ if eq .Environment.Name "prod" }}
    set:
      - name: prometheus.prometheusSpec.retention
        value: 30d
      - name: prometheus.prometheusSpec.replicas
        value: 2
    {{ end }}

  - name: loki-stack
    namespace: monitoring
    chart: ./charts/external/loki-stack-2.9.10
    labels:
      tier: monitoring
      priority: "2"
    needs:
      - monitoring/prometheus
    values:
      - values/templates/loki-stack.yaml.gotmpl

  - name: gpu-process-exporter
    namespace: monitoring
    chart: ./charts/custom/gpu-process-exporter
    version: 1.2.0
    labels:
      tier: monitoring
      priority: "2"
    needs:
      - gpu-operator
      - monitoring/prometheus
    values:
      - values/templates/gpu-process-exporter.yaml.gotmpl

  #============================================================
  # Tier 3: Security & Registry
  #============================================================
  
  - name: keycloak
    namespace: keycloak
    chart: ./charts/external/keycloak-18.4.0
    labels:
      tier: security
      priority: "3"
    needs:
      - kube-system/csi-driver-nfs
    values:
      - values/templates/keycloak.yaml.gotmpl
    {{ if eq .Environment.Name "prod" }}
    set:
      - name: replicaCount
        value: 2
      - name: postgresql.enabled
        value: false  # 외부 DB 사용
    {{ end }}

  - name: harbor
    namespace: harbor
    chart: ./charts/external/harbor-1.13.1
    labels:
      tier: registry
      priority: "3"
    needs:
      - kube-system/csi-driver-nfs
    values:
      - values/templates/harbor.yaml.gotmpl

  - name: mpi-operator
    namespace: mpi-operator
    chart: ./charts/external/mpi-operator-0.4.0
    labels:
      tier: compute
      priority: "3"
    needs:
      - gpu-operator
    values:
      - values/templates/mpi-operator.yaml.gotmpl

  #============================================================
  # Tier 4: Applications (핵심 애플리케이션)
  #============================================================
  
  - name: astrago
    namespace: astrago
    chart: ./charts/custom/astrago
    version: {{ .Values.astrago.version | default "latest" }}
    labels:
      tier: application
      priority: "4"
    needs:
      - gpu-operator
      - monitoring/prometheus
      - keycloak/keycloak
    values:
      - values/templates/astrago.yaml.gotmpl
    hooks:
      - events: ["prepare"]
        command: "scripts/check-dependencies.sh"
        args: ["astrago"]
      - events: ["postsync"]
        command: "scripts/health-check.sh"
        args: ["astrago"]
```

### 3. 오프라인 환경 지원 체계

#### 3.1 차트 다운로드 스크립트

```bash
#!/bin/bash
# scripts/sync-charts.sh
# 온라인 환경에서 실행하여 오프라인용 차트 준비

set -e

CHARTS_DIR="helmfile/charts/external"
VERSIONS_LOCK="$CHARTS_DIR/versions.lock"

# 차트 정보 정의
declare -A CHARTS=(
    ["gpu-operator"]="nvidia/gpu-operator:v25.3.2"
    ["kube-prometheus-stack"]="prometheus-community/kube-prometheus-stack:45.7.1"
    ["loki-stack"]="grafana/loki-stack:2.9.10"
    ["keycloak"]="bitnami/keycloak:18.4.0"
    ["harbor"]="harbor/harbor:1.13.1"
    ["mpi-operator"]="mpi-operator/mpi-operator:0.4.0"
)

# Helm 저장소 추가
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add harbor https://helm.goharbor.io
helm repo add mpi-operator https://kubeflow.github.io/mpi-operator
helm repo update

# 기존 versions.lock 백업
if [ -f "$VERSIONS_LOCK" ]; then
    cp "$VERSIONS_LOCK" "$VERSIONS_LOCK.backup"
fi

# 새 versions.lock 시작
cat > "$VERSIONS_LOCK" <<EOF
# Chart Version Lock File
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# 
# This file tracks all external charts for offline deployment
charts:
EOF

# 차트 다운로드
for CHART_NAME in "${!CHARTS[@]}"; do
    IFS=':' read -r REPO_CHART VERSION <<< "${CHARTS[$CHART_NAME]}"
    
    echo "📦 Downloading $CHART_NAME version $VERSION..."
    
    # 차트 다운로드 및 압축 해제
    helm pull "$REPO_CHART" --version "$VERSION" --untar --untardir "$CHARTS_DIR"
    
    # 버전명 포함 디렉토리로 이름 변경
    if [ -d "$CHARTS_DIR/$CHART_NAME" ]; then
        rm -rf "$CHARTS_DIR/${CHART_NAME}-${VERSION}"
        mv "$CHARTS_DIR/$CHART_NAME" "$CHARTS_DIR/${CHART_NAME}-${VERSION}"
    fi
    
    # 체크섬 생성
    CHECKSUM=$(tar cf - "$CHARTS_DIR/${CHART_NAME}-${VERSION}" 2>/dev/null | sha256sum | cut -d' ' -f1)
    
    # versions.lock에 추가
    cat >> "$VERSIONS_LOCK" <<EOF
  - name: $CHART_NAME
    version: $VERSION
    repository: ${REPO_CHART%/*}
    chart: ${REPO_CHART#*/}
    downloaded: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
    checksum: sha256:$CHECKSUM
    directory: ${CHART_NAME}-${VERSION}
EOF
    
    echo "✅ Successfully downloaded $CHART_NAME-$VERSION"
done

echo "
📋 Summary:
- Downloaded ${#CHARTS[@]} charts
- Location: $CHARTS_DIR
- Version lock: $VERSIONS_LOCK
"
```

#### 3.2 오프라인 패키지 생성 스크립트

```bash
#!/bin/bash
# scripts/package-offline.sh
# 오프라인 배포용 패키지 생성

set -e

PACKAGE_NAME="astrago-deployment-offline-$(date +%Y%m%d).tar.gz"
TEMP_DIR=$(mktemp -d)

echo "📦 Creating offline deployment package..."

# 필요한 파일 복사
cp -r helmfile.yaml "$TEMP_DIR/"
cp -r helmfile/ "$TEMP_DIR/"
cp -r scripts/ "$TEMP_DIR/"

# Git 정보 포함
git rev-parse HEAD > "$TEMP_DIR/GIT_COMMIT"
git describe --tags --always > "$TEMP_DIR/GIT_VERSION"

# 패키지 생성
tar czf "$PACKAGE_NAME" -C "$TEMP_DIR" .

# 체크섬 생성
sha256sum "$PACKAGE_NAME" > "$PACKAGE_NAME.sha256"

# 정리
rm -rf "$TEMP_DIR"

echo "✅ Package created: $PACKAGE_NAME"
echo "📄 Checksum: $(cat $PACKAGE_NAME.sha256)"
```

### 4. 환경별 설정 관리 간소화

#### 4.1 공통 기본값 (helmfile/values/common/defaults.yaml)

```yaml
# 모든 환경 공통 설정
global:
  storageClass: nfs-client
  monitoring:
    enabled: true
    retention: 7d
  security:
    enabled: true
  ingress:
    enabled: true
    className: nginx
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

#### 4.2 환경별 오버라이드 (helmfile/environments/prod/values.yaml)

```yaml
# Production 환경 특화 설정
global:
  domain: astrago.io
  monitoring:
    retention: 30d
  highAvailability:
    enabled: true
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 4000m
      memory: 8Gi

# 애플리케이션별 프로덕션 설정
astrago:
  replicaCount: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
```

### 5. 커스터마이징 전략

#### 5.1 Kustomize 패치 방식 (권장)

```yaml
# helmfile/charts/patches/gpu-operator/custom-images.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
spec:
  template:
    spec:
      containers:
      - name: nvidia-device-plugin
        image: our-registry.io/nvidia/k8s-device-plugin:v0.14.0
```

#### 5.2 Values 오버라이드 방식

```yaml
# helmfile/values/templates/gpu-operator.yaml.gotmpl
driver:
  enabled: {{ .Values.gpu.driver.enabled | default true }}
  version: {{ .Values.gpu.driver.version | default "525.125.06" }}
  
{{ if eq .Environment.Name "prod" }}
# Production 전용 설정
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
{{ end }}
```

---

## 구현 전략

### 1. 단계별 접근

#### Phase 1: 준비 단계 (1주차)
- [ ] 새 디렉토리 구조 생성
- [ ] sync-charts.sh 스크립트 개발 및 테스트
- [ ] 온라인 환경에서 모든 외부 차트 다운로드
- [ ] 통합 helmfile.yaml 작성
- [ ] 검증 스크립트 개발

#### Phase 2: 파일럿 구현 (2주차)
- [ ] CSI Driver NFS를 통합 helmfile.yaml로 이전
- [ ] 개발 환경에서 배포 테스트
- [ ] 문제점 파악 및 수정
- [ ] GPU Operator 추가 이전

#### Phase 3: 전체 통합 (3-4주차)
- [ ] 모든 releases를 통합 helmfile.yaml로 이전
- [ ] Tier별 순차 테스트 (Infrastructure → Monitoring → Security → Applications)
- [ ] 의존성 관계 검증
- [ ] 환경별 설정 테스트

#### Phase 4: 환경별 배포 (5주차)
- [ ] 개발 환경 전체 전환
- [ ] 스테이징 환경 적용
- [ ] 성능 및 안정성 테스트
- [ ] 오프라인 환경 테스트

#### Phase 5: 프로덕션 적용 (6주차)
- [ ] 프로덕션 준비 체크리스트 확인
- [ ] 프로덕션 배포
- [ ] 모니터링 및 안정화

### 2. 검증 체계

#### 2.1 자동 검증 스크립트

```bash
#!/bin/bash
# scripts/validate.sh

set -e

ENV=${1:-dev}

echo "🔍 Validating Helmfile configuration for environment: $ENV"

# 1. Syntax validation
echo "✓ Checking YAML syntax..."
yamllint helmfile.yaml

# 2. Helmfile lint
echo "✓ Running helmfile lint..."
helmfile -e "$ENV" lint

# 3. Dry run
echo "✓ Performing dry run..."
helmfile -e "$ENV" diff --context 3

# 4. Dependency check
echo "✓ Checking release dependencies..."
helmfile -e "$ENV" deps

# 5. Template rendering test
echo "✓ Testing template rendering..."
helmfile -e "$ENV" template > /tmp/rendered.yaml
kubectl apply --dry-run=client -f /tmp/rendered.yaml

echo "✅ All validations passed!"
```

#### 2.2 CI/CD 파이프라인

```yaml
# .github/workflows/helmfile-ci.yml
name: Helmfile CI

on:
  pull_request:
    paths:
      - 'helmfile.yaml'
      - 'helmfile/**'
      - 'scripts/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [dev, stage, prod]
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup tools
        run: |
          # Helmfile 설치
          wget https://github.com/helmfile/helmfile/releases/download/v0.157.0/helmfile_linux_amd64
          chmod +x helmfile_linux_amd64
          sudo mv helmfile_linux_amd64 /usr/local/bin/helmfile
          
          # Helm 설치
          curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
          
          # kubectl 설치
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x kubectl
          sudo mv kubectl /usr/local/bin/
      
      - name: Validate configuration
        run: ./scripts/validate.sh ${{ matrix.environment }}
      
      - name: Security scan
        run: |
          # Trivy 설치 및 실행
          wget https://github.com/aquasecurity/trivy/releases/download/v0.45.0/trivy_0.45.0_Linux-64bit.tar.gz
          tar zxvf trivy_0.45.0_Linux-64bit.tar.gz
          ./trivy config helmfile.yaml
```

### 3. 배포 명령어 체계

```bash
# helmfile 디렉토리로 이동
cd helmfile/

# 전체 배포
helmfile -e prod apply

# Tier별 배포
helmfile -e prod -l tier=infrastructure apply
helmfile -e prod -l tier=monitoring apply
helmfile -e prod -l tier=security apply
helmfile -e prod -l tier=application apply

# 특정 애플리케이션만 배포
helmfile -e prod -l name=astrago apply

# 우선순위별 배포
helmfile -e prod -l priority=1 apply  # Infrastructure
helmfile -e prod -l priority=2 apply  # Monitoring
helmfile -e prod -l priority=3 apply  # Security & Registry
helmfile -e prod -l priority=4 apply  # Applications

# Dry-run
helmfile -e prod diff

# 삭제
helmfile -e prod destroy

# 또는 루트에서 직접 실행
helmfile -f helmfile/helmfile.yaml -e prod apply
```

---

## 마이그레이션 계획

### 타임라인

```
Week 1: 준비 단계
├─ 새 구조 생성
├─ 차트 다운로드
└─ 스크립트 개발

Week 2: 파일럿
├─ CSI Driver 이전
├─ GPU Operator 이전
└─ 테스트 및 검증

Week 3-4: 전체 통합
├─ 모든 애플리케이션 이전
├─ 통합 테스트
└─ 문제 해결

Week 5: 환경별 배포
├─ Dev 환경
├─ Stage 환경
└─ 오프라인 테스트

Week 6: 프로덕션
├─ 최종 검증
├─ 프로덕션 배포
└─ 모니터링
```

### 체크리스트

#### 마이그레이션 전
- [ ] 현재 상태 전체 백업
- [ ] 롤백 계획 수립
- [ ] 팀원 교육 완료
- [ ] 테스트 시나리오 준비

#### 마이그레이션 중
- [ ] 단계별 검증 수행
- [ ] 문제 발생 시 즉시 문서화
- [ ] 성능 메트릭 수집
- [ ] 보안 검증 수행

#### 마이그레이션 후
- [ ] 전체 기능 테스트
- [ ] 성능 비교 분석
- [ ] 문서 최종 업데이트
- [ ] 팀 회고 실시

---

## 리스크 및 대응방안

### 리스크 매트릭스

| 리스크 | 발생 가능성 | 영향도 | 대응 방안 |
|--------|------------|--------|-----------|
| 통합 helmfile.yaml 파일 크기 | 중 | 낮음 | 주석과 섹션 구분으로 가독성 확보 |
| 동시 수정 시 충돌 | 중 | 중 | Git 브랜치 전략 및 코드 리뷰 프로세스 |
| 의존성 문제 | 낮음 | 높음 | needs 필드 명확히 정의, 검증 강화 |
| 오프라인 배포 실패 | 낮음 | 높음 | 철저한 사전 테스트, 체크섬 검증 |
| 성능 저하 | 낮음 | 중 | 병렬 처리, 리소스 최적화 |

### 롤백 계획

#### 즉시 롤백 (Level 1)
```bash
# 이전 버전으로 Git 롤백
git checkout previous-version
helmfile -e prod apply
```

#### 부분 롤백 (Level 2)
```bash
# 특정 애플리케이션만 이전 버전으로
helmfile -e prod -l name=astrago destroy
cd applications/astrago
helmfile -e prod apply  # 기존 방식
```

#### 전체 롤백 (Level 3)
```bash
# 백업에서 전체 복구
tar xzf backup-20250903.tar.gz
./restore.sh
```

---

## 기대 효과

### 정량적 효과

| 지표 | 현재 | 목표 | 개선율 |
|------|------|------|--------|
| 전체 구조 파악 시간 | 2시간 | 10분 | 92% 감소 |
| 새 애플리케이션 추가 시간 | 4시간 | 30분 | 87.5% 감소 |
| 차트 업그레이드 시간 | 4시간 | 1시간 | 75% 감소 |
| 오프라인 배포 준비 | 1일 | 30분 | 97% 감소 |
| 설정 파일 수 | 20개 | 5개 | 75% 감소 |
| 코드 중복률 | 40% | 5% | 87.5% 감소 |

### 정성적 효과

1. **단순성과 명확성**
   - 단일 helmfile.yaml에서 전체 구조 파악
   - 명확한 Tier 구분으로 이해도 향상
   - 신규 팀원 온보딩 시간 단축

2. **오프라인 환경 완벽 지원**
   - Airgap 환경에서 완전한 배포 가능
   - 외부 의존성 제로
   - 보안 환경 요구사항 충족

3. **운영 효율성**
   - 중앙화된 관리로 일관성 확보
   - 자동화된 검증 프로세스
   - 빠른 문제 해결

4. **확장성과 유지보수성**
   - 새 애플리케이션 추가 용이
   - 버전 업그레이드 프로세스 표준화
   - 고객 커스터마이징 대응력 향상

### ROI 분석

```
투자 비용:
- 개발 시간: 6주 (2명) = 480시간
- 테스트 환경: 기존 인프라 활용
- 교육 시간: 16시간 (4명 × 4시간)
총 투자: 496시간

연간 절감 효과:
- 운영 시간 절감: 월 40시간 × 12 = 480시간
- 장애 대응 감소: 월 10시간 × 12 = 120시간
- 신규 고객 대응: 프로젝트당 20시간 절감 × 10 = 200시간
총 절감: 800시간/년

ROI = (800 - 496) / 496 × 100 = 61% (첫해)
2년차부터는 161% ROI
```

---

## 부록

### A. 명령어 퀵 레퍼런스

```bash
# 차트 동기화 (온라인 환경)
./scripts/sync-charts.sh

# 설정 검증
./scripts/validate.sh dev

# 오프라인 패키지 생성
./scripts/package-offline.sh

# 환경별 배포 (helmfile 디렉토리에서)
cd helmfile/
helmfile -e dev apply     # 개발
helmfile -e stage apply   # 스테이징
helmfile -e prod apply    # 프로덕션

# 또는 루트에서 실행
helmfile -f helmfile/helmfile.yaml -e dev apply

# 선택적 배포
cd helmfile/
helmfile -e prod -l tier=infrastructure apply
helmfile -e prod -l name=astrago apply

# 상태 확인
helmfile -e prod status
helmfile -e prod diff

# 삭제
helmfile -e prod destroy
```

### B. 트러블슈팅 가이드

| 문제 | 원인 | 해결 방법 |
|------|------|-----------|
| Chart not found | 차트 경로 오류 | sync-charts.sh 재실행, 경로 확인 |
| Timeout | 리소스 부족 | timeout 값 증가, 리소스 확인 |
| Dependency 오류 | needs 설정 오류 | 의존성 순서 확인, needs 필드 수정 |
| 오프라인 배포 실패 | 차트 누락 | versions.lock 확인, 재패키징 |
| Values 오버라이드 안됨 | 우선순위 문제 | values 배열 순서 확인 |

### C. 자주 묻는 질문 (FAQ)

**Q1: 왜 모든 releases를 하나의 파일에 정의하나요?**
> A: 전체 구조를 한눈에 파악할 수 있고, 의존성 관계가 명확해집니다. 10-15개 정도의 애플리케이션은 한 파일로도 충분히 관리 가능합니다.

**Q2: 파일이 너무 커지면 어떻게 하나요?**
> A: 필요시 include 방식으로 분리할 수 있지만, 현재 규모에서는 단일 파일이 더 효율적입니다.

**Q3: 오프라인 환경에서 차트 업데이트는?**
> A: 온라인 환경에서 sync-charts.sh로 새 버전 다운로드 → package-offline.sh로 패키징 → 오프라인 환경에 전달

**Q4: 고객별 커스터마이징은?**
> A: environments/ 아래 고객별 폴더 생성하여 values 오버라이드, 필요시 patches/ 활용

### D. 연락처 및 지원

- 프로젝트 리드: [담당자]
- 기술 지원: [이메일/슬랙]
- 이슈 트래커: Linear BE-384
- 문서: `/docs/roadmap/helmfile-refactoring-analysis-v2.md`

---

*이 문서는 지속적으로 업데이트됩니다. 최종 수정일: 2025-09-03*