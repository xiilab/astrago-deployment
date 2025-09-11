# Astrago GitOps Repository Structure

## 저장소명: `astrago-gitops`

```
astrago-gitops/
├── README.md                          # 저장소 개요 및 사용법
├── DEPLOYMENT.md                      # 고객 배포 가이드
├── VERSION.md                         # LTS 버전 정보
│
├── releases/                          # LTS 릴리스별 관리
│   ├── v1.0/                         # LTS 1.0 (현재 stabilize/1.0 → release/1.0)
│   │   ├── applications/
│   │   │   ├── astrago-app.yaml      # Astrago 메인 애플리케이션
│   │   │   ├── harbor-app.yaml       # Harbor 레지스트리
│   │   │   ├── prometheus-app.yaml   # 모니터링 스택
│   │   │   └── flux-app.yaml         # Flux GitOps
│   │   ├── clusters/
│   │   │   ├── production-cluster.yaml    # 운영 클러스터 설정
│   │   │   └── staging-cluster.yaml       # 스테이징 클러스터 설정
│   │   ├── projects/
│   │   │   └── astrago-project.yaml  # ArgoCD 프로젝트 설정
│   │   └── values/                   # 환경별 values 파일
│   │       ├── production/
│   │       │   ├── astrago-values.yaml
│   │       │   ├── harbor-values.yaml
│   │       │   └── prometheus-values.yaml
│   │       └── staging/
│   │           ├── astrago-values.yaml
│   │           └── harbor-values.yaml
│   └── v1.1/                         # 향후 LTS 1.1 (준비)
│       └── ... (동일 구조)
│
├── overlays/                          # 고객별 커스터마이징
│   ├── customer-a/                   # 고객 A 전용 설정
│   │   ├── kustomization.yaml
│   │   ├── cluster-config.yaml
│   │   └── custom-values/
│   │       ├── astrago-custom.yaml
│   │       └── monitoring-custom.yaml
│   ├── customer-b/                   # 고객 B 전용 설정
│   │   └── ...
│   └── default/                      # 기본 고객 설정 템플릿
│       └── ...
│
├── base/                             # 공통 베이스 설정
│   ├── applications/
│   │   ├── base-astrago-app.yaml    # 기본 애플리케이션 템플릿
│   │   └── base-monitoring-app.yaml  # 기본 모니터링 템플릿
│   ├── clusters/
│   │   └── base-cluster-template.yaml
│   └── projects/
│       └── base-project-template.yaml
│
├── scripts/                          # 유틸리티 스크립트
│   ├── deploy-to-customer.sh        # 고객별 배포 스크립트
│   ├── validate-manifests.sh        # 매니페스트 검증
│   └── backup-configs.sh            # 설정 백업
│
├── docs/                             # 고객 문서화
│   ├── deployment-guide.md          # 배포 가이드
│   ├── troubleshooting.md           # 트러블슈팅
│   ├── architecture.md              # 아키텍처 설명
│   └── customer-examples/           # 고객 사례
│       ├── on-premises.md
│       └── cloud.md
│
└── .github/                          # GitHub Actions (선택적)
    └── workflows/
        ├── validate-pr.yaml         # PR 검증
        └── sync-from-release.yaml   # release 브랜치 동기화
```

## 브랜치 전략

### Main Branches
- `main`: 안정화된 LTS 배포 매니페스트
- `develop`: 개발 중인 GitOps 설정 (선택적)

### Release Branches  
- `release/v1.0`: LTS 1.0 전용 브랜치
- `release/v1.1`: LTS 1.1 전용 브랜치

## 워크플로우

1. **개발 단계**: `astrago-deployment/stabilize/1.0` → 테스트
2. **LTS 태그**: `astrago-deployment/release/1.0` 생성
3. **GitOps 동기화**: `astrago-gitops/releases/v1.0/` 업데이트
4. **고객 납품**: `astrago-gitops/overlays/customer-x/` 커스터마이징

## 고객별 배포 프로세스

1. **Base 설정**: `releases/v1.0/` 기반
2. **Overlay 적용**: `overlays/customer-a/` 커스터마이징
3. **클러스터 배포**: ArgoCD Application 생성
4. **모니터링**: 배포 상태 추적

## 보안 및 접근 제어

- **개발팀**: `astrago-deployment` 저장소 접근
- **운영팀**: `astrago-gitops` 저장소 관리
- **고객**: 필요한 `overlays/` 디렉토리만 접근