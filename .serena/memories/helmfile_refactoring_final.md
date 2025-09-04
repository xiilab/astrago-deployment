# Helmfile 리팩토링 최종안

## 핵심 구조
```
astrago-deployment/
├── helmfile/                    # Helmfile 관련 모든 파일
│   ├── helmfile.yaml            # 메인 파일 (모든 releases 정의)
│   ├── charts/                  # 차트 저장소
│   │   ├── external/           # 외부 차트 (로컬 저장)
│   │   ├── custom/             # 커스텀 차트
│   │   └── patches/            # Kustomize 패치
│   ├── values/                  # 값 템플릿
│   └── environments/            # 환경별 설정
├── scripts/                     # 관리 스크립트
├── kubespray/                   # (기존 유지)
├── airgap/                      # (기존 유지)
└── docs/                        # (기존 유지)
```

## 주요 특징
1. **완전한 중앙화**: Helmfile 관련 모든 것이 helmfile/ 디렉토리에
2. **단일 helmfile.yaml**: 모든 releases를 한 파일에 정의
3. **오프라인 우선**: 모든 외부 차트를 로컬에 저장
4. **명확한 분리**: kubespray, airgap과 완전히 독립

## helmfile.yaml 내 경로
- 모든 경로는 helmfile.yaml 기준 상대 경로
- `./charts/external/gpu-operator-v25.3.2`
- `values/templates/astrago.yaml.gotmpl`
- `environments/prod/values.yaml`

## 배포 방법
```bash
# Option 1: helmfile 디렉토리에서
cd helmfile/
helmfile -e prod apply

# Option 2: 루트에서 직접
helmfile -f helmfile/helmfile.yaml -e prod apply
```

## 장점
- 루트 디렉토리 깔끔함
- Helmfile 관련 파일 완전 격리
- 다른 컴포넌트와 충돌 없음
- 관리 및 백업 용이

## 마이그레이션 우선순위
1. helmfile/ 디렉토리 구조 생성
2. 차트 다운로드 (sync-charts.sh)
3. helmfile.yaml 작성 (모든 releases)
4. 환경별 테스트
5. 기존 구조 제거