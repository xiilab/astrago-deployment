# Astrago ArgoCD 배포 설정

이 디렉토리는 현재 브랜치(stabilize/1.0)의 스테이징 환경 배포를 위한 ArgoCD 설정입니다.

## 브랜치별 환경 전략

| 브랜치 | 환경 | 클러스터 | 설정 파일 위치 | 용도 |
|--------|------|----------|---------------|------|
| `stabilize/1.0` | **Staging** | staging-k8s.company.com | 현재 브랜치 | RC 테스트, QA |
| `master` | **Development** | dev-k8s.company.com | master 브랜치 | 통합 테스트 |
| `release/1.0` | **Production** | prod-k8s.company.com | release/1.0 브랜치 | 고객 배포 |

## 현재 브랜치 설정 (stabilize/1.0)

```
argocd/
├── applications/
│   └── astrago-app.yaml          # ArgoCD Application (스테이징용)
├── clusters/
│   └── staging-cluster.yaml      # 스테이징 클러스터 연결 설정
├── values.yaml                   # 스테이징 환경 설정값들
└── README.md                     # 이 파일
```

## 배포되는 구성요소

현재 `helmfile/helmfile.yaml.gotmpl`에 정의된 모든 구성요소:

- **Astrago Core**: AI/ML 플랫폼 메인 서비스
- **Harbor**: Container Registry
- **Prometheus**: 모니터링 스택
- **Flux**: GitOps 컨트롤러
- **GPU Operator**: GPU 리소스 관리
- **Keycloak**: 인증/인가 시스템  
- **MPI Operator**: 분산 처리
- **NFS Provisioner**: 공유 스토리지

## 설정 방법

### 1. 스테이징 클러스터 준비

스테이징 클러스터에서 ArgoCD용 ServiceAccount 생성:

```bash
# 스테이징 클러스터에 접속하여 실행
kubectl create namespace argocd-system
kubectl create serviceaccount argocd-manager -n argocd-system
kubectl create clusterrolebinding argocd-manager \
  --clusterrole=cluster-admin \
  --serviceaccount=argocd-system:argocd-manager

# 토큰 생성 (8760시간 = 1년)
kubectl create token argocd-manager -n argocd-system --duration=8760h

# CA 인증서 추출
kubectl get secret argocd-manager-token -n argocd-system \
  -o jsonpath='{.data.ca\.crt}'
```

### 2. 클러스터 설정 업데이트

`clusters/staging-cluster.yaml`에서 실제 값으로 교체:

```bash
# 실제 토큰과 인증서로 교체
sed -i 's/{{ STAGING_CLUSTER_TOKEN }}/actual-token-here/g' \
  argocd/clusters/staging-cluster.yaml
  
sed -i 's/{{ STAGING_CLUSTER_CA_CERT }}/actual-ca-cert-base64/g' \
  argocd/clusters/staging-cluster.yaml
```

### 3. ArgoCD에 배포

```bash
# 클러스터 등록
kubectl apply -f argocd/clusters/staging-cluster.yaml

# 애플리케이션 등록  
kubectl apply -f argocd/applications/astrago-app.yaml
```

## 스테이징 환경 특징

- **자동 동기화**: 활성화 (RC 테스트용)
- **Prune**: 활성화 (불필요한 리소스 자동 정리)
- **Self-Heal**: 활성화 (드리프트 자동 복구)
- **이미지 태그**: `1.0-rc` (릴리즈 후보)
- **알림**: Slack #astrago-staging 채널
- **디버그 모드**: 활성화
- **테스트 데이터**: 포함

## LTS 워크플로우

```
1. stabilize/1.0 (현재) → 스테이징 배포 → RC 테스트
2. 테스트 완료 → 태그 생성 → master 머지
3. master → 개발 클러스터 배포 → 통합 테스트
4. master → release/1.0 브랜치 → 프로덕션 배포
```

## 다른 환경 설정

다른 브랜치로 전환하면 같은 구조의 파일들이 해당 환경에 맞는 설정을 가집니다:

- `master` 브랜치 → 개발 환경 설정
- `release/1.0` 브랜치 → 프로덕션 환경 설정

## 모니터링

### ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080 접속
```

### CLI 명령어
```bash
# 애플리케이션 상태 확인
argocd app get astrago-stabilize

# 수동 동기화
argocd app sync astrago-stabilize

# 로그 확인
argocd app logs astrago-stabilize
```

## 트러블슈팅

### 자주 발생하는 문제

1. **클러스터 연결 실패**
   - 토큰 만료 확인
   - 네트워크 연결 확인
   - CA 인증서 검증

2. **Helmfile 동기화 실패**
   - Helmfile 플러그인 설치 확인
   - 종속성 업데이트 상태 확인
   - 차트 저장소 접근 확인

3. **리소스 생성 실패**
   - 네임스페이스 권한 확인
   - 클러스터 리소스 권한 확인
   - 스토리지 클래스 존재 확인

### 로그 수집
```bash
# ArgoCD 컨트롤러 로그
kubectl logs -n argocd deployment/argocd-application-controller

# 애플리케이션별 로그
argocd app logs astrago-stabilize --follow
```