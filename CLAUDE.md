# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🚀 Astrago 배포 시스템 개요

이 저장소는 **Astrago AI/ML 플랫폼**을 Kubernetes 환경에 배포하는 종합적인 배포 도구입니다. Helmfile 기반의 GitOps 배포 방식을 사용하며, 온라인/오프라인 배포를 모두 지원합니다.

## 🏗️ 아키텍처 구조

### 핵심 디렉토리 구조
```
astrago-deployment/
├── helmfile/                    # Helmfile 기반 배포 설정
│   ├── helmfile.yaml.gotmpl    # 메인 배포 설정 (4계층 구조)
│   ├── charts/                 # Helm 차트들 (internal/external)
│   ├── environments/           # 환경별 설정
│   │   ├── common/            # 공통 설정
│   │   ├── base/              # 기본 환경 설정
│   │   └── customers/         # 고객별 커스터마이징 설정
│   ├── values/                # 애플리케이션별 values 파일들
│   └── addons/                # ConfigMap 및 추가 설정들
├── tools/                      # 배포 도구들 (helm, helmfile, kubectl, yq)
├── ansible/                    # Ansible 플레이북들 (GPU, NFS 설치)
├── scripts/                    # 유틸리티 스크립트들
└── docs/                       # 상세 문서들
```

### 4계층 배포 아키텍처
Helmfile은 다음 4개 계층으로 구성되어 있습니다:
1. **Tier 1: Infrastructure** - NFS, GPU Operator 등 인프라
2. **Tier 2: Monitoring** - Prometheus, Grafana 모니터링 스택
3. **Tier 3: Security** - Keycloak, Harbor, Flux 보안 서비스
4. **Tier 4: Applications** - Astrago 메인 애플리케이션

## 📋 주요 개발 명령어

### 배포 스크립트 사용법
```bash
# 기본 배포 스크립트 (권장)
./deploy_astrago_v3.sh init <customer>     # 새 고객 환경 초기화
./deploy_astrago_v3.sh deploy [customer]   # 환경 배포
./deploy_astrago_v3.sh destroy [customer]  # 환경 삭제
./deploy_astrago_v3.sh list                # 고객 환경 목록 조회
./deploy_astrago_v3.sh update-tools        # 도구 업데이트

# 고객별 환경 초기화 예시
./deploy_astrago_v3.sh init samsung --ip 10.1.2.3 --nfs-server 10.1.2.4 --nfs-path /samsung-vol

# 기본 환경 배포 (브랜치 기반)
./deploy_astrago_v3.sh deploy

# 특정 고객 환경 배포
./deploy_astrago_v3.sh deploy samsung
```

### Helmfile 직접 사용법
```bash
cd helmfile/

# 기본 환경 배포
helmfile -e default apply

# 특정 애플리케이션만 배포/업데이트
helmfile -e default apply --selector tier=monitoring    # Prometheus만
helmfile -e default apply --selector app=astrago        # Astrago만
helmfile -e default apply --selector tier=infrastructure # 인프라만

# 고객 환경 배포
CUSTOMER_NAME="samsung" helmfile -e customer apply

# 전체 삭제
helmfile -e default destroy

# 템플릿 생성 (배포 전 확인)
helmfile -e default template > /tmp/rendered.yaml

# 환경 변수 값 확인
helmfile -e default build
```

### 차트 동기화
```bash
# 외부 차트 업데이트
cd helmfile/
make sync    # chart-sync를 통해 외부 차트들 동기화

# 수동 차트 동기화
./chart-sync/sync-charts.sh
```

### 도구 관리
```bash
# 도구 다운로드/업데이트 (helm, helmfile, kubectl, yq)
tools/download-binaries.sh

# 특정 OS용 도구 확인
ls tools/linux/    # Linux용 바이너리들
ls tools/darwin/   # macOS용 바이너리들
```

### 오프라인 배포
```bash
# 오프라인 배포 스크립트
./offline_deploy_astrago.sh

# 에어갭 환경 배포
cd airgap/
# 에어갭 관련 설정 및 배포 수행
```

### GUI 인스톨러
```bash
# GUI 기반 설치 (TUI)
python3 astrago_gui_installer.py

# 또는 쉘 스크립트로
./run_gui_installer.sh
```

## 🔧 테스트 및 검증

### 배포 상태 확인
```bash
# Kubernetes 리소스 상태 확인
kubectl get pods -A
kubectl get svc -A
kubectl get pvc -A

# Ingress 및 네트워크 상태 확인 (신규 추가)
kubectl get ingress -A
kubectl get svc -n ingress-nginx

# Helmfile 배포 상태 확인
cd helmfile/
helmfile -e default status

# 특정 네임스페이스 상태 확인
kubectl get all -n astrago
kubectl get all -n prometheus
kubectl get all -n keycloak

# Ingress 접근성 테스트 (신규 추가)
curl -H "Host: demo.astrago.ai" http://$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/
```

### 로그 확인
```bash
# 애플리케이션 로그 확인
kubectl logs -n astrago deployment/astrago-core
kubectl logs -n keycloak deployment/keycloak
kubectl logs -n prometheus deployment/prometheus-server

# 실시간 로그 추적
kubectl logs -n astrago deployment/astrago-core -f
```

### 설정 검증
```bash
# Helmfile 템플릿 검증
cd helmfile/
helmfile -e default lint

# YAML 문법 검증
yq eval . environments/base/values.yaml

# 차트 의존성 확인
helm dependency list charts/astrago/
```

## 🌐 Ingress 기반 접근

### 기본 접근 방법
- **LoadBalancer IP로 직접 접근**: `http://10.61.3.163/` (IP는 환경별 상이)
- **Host 헤더 필요**: `demo.astrago.ai` 또는 환경별 설정된 도메인
- **단일 진입점**: 모든 API와 프론트엔드가 통합된 접근점

### 주요 엔드포인트
- **프론트엔드**: `http://IP/`
- **Core API**: `http://IP/api/v1/core/`
- **Monitor API**: `http://IP/api/v1/monitor/`
- **Batch API**: `http://IP/api/v1/batch/`
- **Report API**: `http://IP/api/v1/report/`
- **WebSocket**: `ws://IP/ws/workload/`

### 접근 테스트 명령어
```bash
# Host 헤더를 포함한 접근 (필수)
curl -H "Host: demo.astrago.ai" http://10.61.3.163/

# API 엔드포인트 테스트
curl -H "Host: demo.astrago.ai" http://10.61.3.163/api/v1/core/

# Ingress 상태 확인
kubectl get ingress -n astrago
kubectl describe ingress astrago-ingress -n astrago

# LoadBalancer IP 확인
kubectl get svc -n ingress-nginx
```

### 환경별 Ingress 설정
```yaml
# 기본 환경 (모든 IP 허용) - base/values.yaml
ingress:
  enabled: true
  host: ""  # 모든 Host에서 접근 허용

# 고객 환경 (특정 도메인) - customers/xiilab/values.yaml
ingress:
  enabled: true
  host: "demo.astrago.ai"  # 특정 도메인만 허용

# TLS 인증서 환경
ingress:
  enabled: true
  host: "secure.astrago.com"
  tls:
    enabled: true
    secretName: "astrago-tls-cert"
```

## 📁 환경별 설정 관리

### 환경 종류
- `default`: 기본 환경 (브랜치 기반)
- `dev/dev2`: 개발 환경
- `stage`: 스테이징 환경  
- `prod`: 프로덕션 환경
- `customers/*/`: 고객별 커스터마이징 환경

### 설정 우선순위
1. `environments/common/values.yaml` (공통 기본값)
2. `environments/base/values.yaml` (기본 환경값)
3. `environments/customers/<customer>/values.yaml` (고객별 오버라이드)

### 새 환경 추가시 주의사항
- `helmfile/environments/customers/` 하위에 고객별 디렉토리 생성
- `values.yaml`에서 `externalIP`, `nfs.server`, `nfs.basePath` 필수 설정
- 필요시 `helmfile.yaml.gotmpl`에 새 환경 정의 추가

## 🛠️ 개발 워크플로우

### 차트 수정시
1. `helmfile/charts/astrago/` 또는 해당 차트 수정
2. `values/<app>.yaml.gotmpl` 설정 파일 조정
3. 템플릿 생성으로 검증: `helmfile template`
4. 배포 테스트: `helmfile apply`

### 환경 설정 변경시  
1. 해당 환경의 `values.yaml` 수정
2. 설정 검증: `helmfile build`
3. 특정 앱만 업데이트: `helmfile apply --selector app=<앱명>`

### 새 애플리케이션 추가시
1. `helmfile/charts/` 하위에 차트 추가 (또는 chart-sync 설정)
2. `helmfile/values/` 하위에 values 파일 생성
3. `helmfile.yaml.gotmpl`에 release 정의 추가
4. 적절한 tier와 needs 의존성 설정

## 🔍 문제 해결 및 디버깅

### 일반적인 문제들
- **Chart path 오류**: `helmfile.yaml.gotmpl`의 chart 경로 확인
- **Values 오버라이드 실패**: 환경별 values.yaml 우선순위 확인
- **의존성 오류**: needs 설정 및 네임스페이스 생성 순서 확인
- **도구 버전 불일치**: `tools/versions.conf` 확인 후 재다운로드

### Ingress 관련 문제 해결
- **접근 불가 (404 에러)**: Host 헤더 없이 접근시 발생, `curl -H "Host: 도메인"` 사용
- **LoadBalancer IP 미할당**: `kubectl get svc -n ingress-nginx` 확인, 인프라 LoadBalancer 지원 필요
- **라우팅 실패**: `kubectl describe ingress astrago-ingress -n astrago`로 백엔드 연결 상태 확인
- **WebSocket 연결 실패**: nginx ingress의 WebSocket 어노테이션 및 업스트림 연결 확인
- **파일 업로드 실패**: `proxy-body-size: "0"` 어노테이션이 적용되었는지 확인

### 디버깅 명령어
```bash
# 상세 로그와 함께 배포
helmfile -e default apply --debug

# 특정 리소스 상태 확인
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# 차트 렌더링 확인
helm template <release-name> <chart-path> -f <values-file>

# Ingress 관련 디버깅
kubectl get ingress -A                           # 모든 Ingress 리소스 확인
kubectl describe ingress astrago-ingress -n astrago  # Ingress 상세 정보
kubectl get svc -n ingress-nginx                 # nginx-ingress 서비스 상태
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx  # nginx 로그 확인

# 네트워크 연결 테스트
curl -v -H "Host: demo.astrago.ai" http://LOADBALANCER-IP/  # 접근 테스트
kubectl port-forward -n astrago svc/astrago-frontend 3000:3000  # 직접 서비스 테스트
```

## 💡 모범 사례

1. **환경 분리**: 개발/스테이징/프로덕션 환경을 명확히 분리하고 각각 다른 values를 사용
2. **점진적 배포**: 먼저 템플릿 생성으로 검증 후 실제 배포
3. **의존성 관리**: Tier 기반 배포 순서를 지키고 needs 설정 활용
4. **백업**: 중요한 설정 변경 전 현재 상태 백업
5. **모니터링**: 배포 후 반드시 상태 확인 및 로그 검토
6. **Ingress 관리**: Host 헤더 설정을 환경에 맞게 조정하고 LoadBalancer IP 할당 확인
7. **접근성 테스트**: 배포 후 반드시 실제 접근 가능성을 curl이나 브라우저로 검증

## 🔗 관련 문서
- [상세 설치 가이드](docs/installation-guide.md)
- [아키텍처 가이드](docs/architecture.md)  
- [문제 해결 가이드](docs/troubleshooting.md)
- [GPU 프로세스 모니터링](docs/GPU-Process-Monitoring-Guide.md)
- [오프라인 배포 가이드](docs/offline-deployment.md)