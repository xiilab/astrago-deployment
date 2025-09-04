# Astrago Deployment Helmfile 리팩토링 분석

## 핵심 요구사항
- **오프라인 환경 지원 필수** (Airgap 환경)
- 고객 커스터마이징 요청 대응
- 차트 업그레이드 용이성
- 독립적 차트 관리 체계

## 현재 구조의 문제점

### 1. 폴더 구조의 복잡성
- 루트 디렉토리에 helmfile.yaml 위치
- applications/ 폴더 아래 각 애플리케이션별 helmfile.yaml 중복
- environments/, monochart/, tools/, scripts/ 등이 루트에 산재
- helmfile 관련 파일들이 여러 위치에 분산

### 2. 차트 관리의 어려움
- 외부 차트와 커스텀 차트가 혼재
- 로컬 차트들이 applications/[app-name]/[chart-name] 구조로 중첩
- 차트 버전 관리가 명확하지 않음
- 커스터마이징된 부분과 원본 차트의 분리 불명확

### 3. 업그레이드의 어려움
- 외부 차트 버전 업그레이드 시 영향도 파악 어려움
- 차트 의존성 관리가 체계적이지 않음
- 오프라인 환경에서 차트 업데이트 복잡

## 제안하는 새로운 구조

```
helmfile/
├── helmfile.yaml                 # 메인 helmfile
├── environments/                 # 환경별 설정
│   ├── base/                    # 공통 기본 설정
│   ├── dev/
│   ├── stage/
│   └── prod/
├── releases/                     # 릴리즈 정의
│   ├── infrastructure/          # 인프라 관련
│   ├── monitoring/              # 모니터링 관련
│   ├── security/                # 보안 관련
│   └── applications/            # 애플리케이션
├── charts/                      # 차트 관리
│   ├── external/               # 외부 차트 (로컬 저장)
│   │   ├── gpu-operator-v25.3.2/
│   │   ├── prometheus-45.7.1/
│   │   └── versions.lock       # 버전 및 체크섬 관리
│   ├── custom/                 # 커스텀 차트
│   └── patches/                # 차트 커스터마이징 패치
└── scripts/                    # 관리 스크립트
    ├── sync-charts.sh          # 온라인에서 차트 다운로드
    └── validate.sh             # 검증 스크립트
```

## 오프라인 환경 지원 전략

### 차트 관리 방식
1. **모든 외부 차트를 로컬에 저장**
   - charts/external/ 디렉토리에 버전별로 저장
   - 온라인 환경에서 sync-charts.sh로 일괄 다운로드
   - versions.lock 파일로 버전 및 체크섬 관리

2. **로컬 차트 참조**
   ```yaml
   releases:
     - name: gpu-operator
       chart: ../../charts/external/gpu-operator-v25.3.2
   ```

3. **커스터마이징은 Kustomize 패치로 관리**
   - 원본 차트는 수정하지 않음
   - patches/ 디렉토리에 패치만 관리
   - 업그레이드 시 패치만 재적용

## 차트 업그레이드 프로세스

1. **온라인 환경에서**
   - 새 버전 차트 다운로드
   - versions.lock 업데이트
   - 테스트 환경에서 검증

2. **오프라인 환경으로 이전**
   - charts/external/ 전체를 패키징
   - 오프라인 환경에 배포
   - helmfile apply로 적용

## 마이그레이션 계획

### Phase 1: 준비 (1주차)
- 새 구조 생성
- sync-charts.sh 스크립트 개발
- 외부 차트 다운로드 및 로컬 저장

### Phase 2: 파일럿 (2주차)
- CSI Driver NFS로 시작
- 개발 환경 테스트

### Phase 3: 전체 마이그레이션 (3-4주차)
- 인프라 → 모니터링 → 애플리케이션 순
- 각 단계별 검증

### Phase 4: 환경별 적용 (5-6주차)
- dev → stage → prod 순차 적용

## 기대 효과
- 오프라인 배포 준비 시간: 1일 → 30분 (97% 감소)
- 차트 업그레이드 시간: 4시간 → 1시간 (75% 감소)
- Airgap 환경 완벽 지원
- 체계적인 버전 관리