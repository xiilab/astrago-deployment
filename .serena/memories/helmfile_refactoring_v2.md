# Helmfile 리팩토링 v2 - 단순화된 접근법

## 핵심 변경사항
- **단일 helmfile.yaml**: 모든 releases를 root helmfile.yaml에 정의
- **중앙화된 차트 관리**: helmfile/charts/ 디렉토리에 모든 차트 집중
- **오프라인 우선**: 모든 외부 차트를 로컬에 저장
- **구조 단순화**: 복잡한 폴더 구조 제거

## 새로운 구조
```
astrago-deployment/
├── helmfile.yaml            # 모든 releases 정의 (단일 파일)
├── helmfile/                # helmfile 관련 파일만
│   ├── charts/
│   │   ├── external/        # 다운로드한 외부 차트
│   │   ├── custom/          # 커스텀 차트
│   │   └── patches/         # Kustomize 패치
│   ├── values/              # 값 템플릿
│   └── environments/        # 환경별 설정
└── scripts/                 # 관리 스크립트
```

## helmfile.yaml 구조
- Tier 1: Infrastructure (CSI, GPU, Flux)
- Tier 2: Monitoring (Prometheus, Loki)
- Tier 3: Security & Registry (Keycloak, Harbor)
- Tier 4: Applications (Astrago)

각 release는 다음 포함:
- chart: 로컬 경로 (./helmfile/charts/...)
- labels: tier와 priority로 그룹화
- needs: 명확한 의존성 정의
- values: 환경별 오버라이드

## 장점
1. **단순성**: 한 파일에서 전체 구조 파악
2. **명확성**: Tier별 구분으로 이해 용이
3. **오프라인 지원**: 완전한 로컬 차트 관리
4. **유지보수 용이**: 중앙화된 관리

## 배포 명령어
```bash
# 전체 배포
helmfile -e prod apply

# Tier별 배포
helmfile -e prod -l tier=infrastructure apply

# 특정 앱만
helmfile -e prod -l name=astrago apply
```

## 마이그레이션 단계
1. Week 1: 새 구조 생성, 차트 다운로드
2. Week 2: 파일럿 (CSI, GPU Operator)
3. Week 3-4: 전체 통합
4. Week 5: 환경별 테스트
5. Week 6: 프로덕션 적용