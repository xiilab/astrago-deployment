## CI/CD 구축 로드맵 문서 (2025)

### 문서 목적
브랜치/고객 다양성을 고려해 GitFlow 정착, 에페메럴 클러스터 기반 테스트, ChatOps 및 LLM 보조를 통합한 효율적 CI/CD 체계를 정의한다.

### 범위
- GitFlow/브랜치·태깅·릴리즈 규칙
- 에페메럴 클러스터(Kind/K3d/Cluster API) 파이프라인
- ArgoCD ApplicationSet 기반 다환경 배포 템플릿
- Slack ChatOps(버튼/Slash Command) 트리거/상태조회
- LLM 보조(CI 요약/릴리즈노트/PR 리뷰 힌트)
- 테스트 매트릭스(스모크/E2E/퍼포먼스)

### 메타데이터 제안
- 팀: Back-end Team
- 라벨: 📈 Improvement, 🚀 Feature
- 상위 에픽 추정치: 0 point (하위 이슈 합산)

---

### [Epic] CI/CD 구축 (0 point)
다브랜치·다고객 상황에서도 안정적/재현 가능한 배포와 신속한 피드백을 제공하는 파이프라인 수립.

---

### [C1] GitFlow/브랜치·태깅·릴리즈 규칙 수립

## 🎯 이슈 요약
브랜치 전략, 버전 태깅, 배포 규칙 표준화

## 📋 상세 설명
### 현재 상황
- 고객별/브랜치별 혼재, 표준 미흡

### 기대 결과
- `main`/`develop`/`release/*`/`hotfix/*` 보호 규칙
- 태그/이미지 태깅 규칙 정립, 체인지로그 표준화
- ArgoCD 컨트롤 플레인을 클라우드로 이전해 중앙집중형 CD 운영(멀티 클러스터 관리)
- 온프렘/고객 클러스터는 Pull 모델로 안전 연결, 클라우드에서 정책/승인 일원화

## 🔧 작업 범위
### 주요 작업
- [ ] 전략 문서/체크리스트/예시 수립
- [ ] 보호 규칙/코드오너스 설정
- [ ] 클라우드 상 ArgoCD 컨트롤 플레인 구축(HA/백업/모니터링)
- [ ] 멀티 클러스터 등록/권한 경계(AppProject/RBAC), 네트워크 접속 모델(VPN/WireGuard/클러스터 토큰) 정의
- [ ] SSO(OIDC) 연동 및 비밀 관리(SOPS/ExternalSecrets/KMS) 표준화

### 기술적 요구사항
- GitHub 보호 규칙, Conventional Commits 권장
- ArgoCD ApplicationSet, AppProject, Cluster registration, Repo/Helm creds
- 클라우드 네트워크/보안: VPC/VPN, 방화벽, 프록시, 감사 로깅

## 📎 참고자료
- 기존 브랜치/태그 이력
- ArgoCD 운영 가이드, AppProject/AppSet 베스트 프랙티스

## ⚠️ 주의사항
- 리포 다수인 경우 Cross-repo 정합성
- 고객 데이터/메타데이터 외부 반출 금지, 레이턴시/비용 고려
- 자격증명 회전/만료, 승인 플로우/감사 추적 강화

우선순위: High  
담당자: TBD  
시작일: YYYY-MM-DD  
완료 예정일: YYYY-MM-DD  
예상 소요 시간: 1 point

---

### [C2] 에페메럴 클러스터 생성/파괴 파이프라인(Kind/K3d/Cluster API)

## 🎯 이슈 요약
브랜치/PR 단위로 임시 쿠버네티스 클러스터를 생성/테스트/폐기

## 📋 상세 설명
### 현재 상황
- 고정 클러스터에 다중 배포 어려움

### 기대 결과
- 단일 호스트/VM에서 다중 클러스터 병렬 테스트
- 비용 최소화, 자동 폐기(타임아웃/웹훅)

## 🔧 작업 범위
### 주요 작업
- [ ] GitHub Actions 워크플로우 구현
- [ ] 캐시/이미지 프리로드 최적화
- [ ] 테스트 로그/아티팩트 업로드

### 기술적 요구사항
- Kind/K3d, Docker 레지스트리 미러/프록시

## 📎 참고자료
- `airgap/`, `kubespray/` (필요 시)

## ⚠️ 주의사항
- 노드 리소스/포트 충돌/네트워크 격리

우선순위: High  
담당자: TBD  
시작일: YYYY-MM-DD  
완료 예정일: YYYY-MM-DD  
예상 소요 시간: 3 point

---

### [C3] ArgoCD ApplicationSet로 다환경/다가격 배포 템플릿화

## 🎯 이슈 요약
고객/환경 매트릭스를 ApplicationSet으로 매개변수화

## 📋 상세 설명
### 현재 상황
- 환경별 수동 오버라이드/중복

### 기대 결과
- Git 데이터 소스로 자동 생성/싱크, 환경 추가 비용 감소

## 🔧 작업 범위
### 주요 작업
- [ ] ApplicationSet 매니페스트 설계
- [ ] 환경 변수/시크릿 인젝션 패턴 설계

### 기술적 요구사항
- ArgoCD, Kustomize/Helm 파라미터

## 📎 참고자료
- `applications/*/values.yaml.gotmpl`, `environments/*/values.yaml`

## ⚠️ 주의사항
- 드리프트 탐지/자동 수정 설정

우선순위: Normal  
담당자: TBD  
시작일: YYYY-MM-DD  
완료 예정일: YYYY-MM-DD  
예상 소요 시간: 2 point

---

### [C4] 슬랙 ChatOps(버튼/슬래시 커맨드)로 배포 트리거/상태 조회

## 🎯 이슈 요약
Slack에서 브랜치 선택 배포/상태 조회/롤백 실행

## 📋 상세 설명
### 현재 상황
- GitHub/UI 진입 필요 → 협업성 저하

### 기대 결과
- 슬랙 내 배포 버튼/커맨드로 표준 작업

## 🔧 작업 범위
### 주요 작업
- [ ] Slack App, OAuth/권한 구성
- [ ] GitHub Actions/ArgoCD 웹훅 연동

### 기술적 요구사항
- Slack Bolt/Workflow, GitHub App, ArgoCD API

## 📎 참고자료
- 내부 보안 가이드

## ⚠️ 주의사항
- RBAC/승인 플로우, 감사 로그

우선순위: Normal  
담당자: TBD  
시작일: YYYY-MM-DD  
완료 예정일: YYYY-MM-DD  
예상 소요 시간: 2 point

---

### [C5] 다중 OS/버전 에페메럴 클러스터 테스트(astrago-deployment)

## 🎯 이슈 요약
여러 OS 종류/버전에 대해 에페메럴 클러스터(Kind/K3d/VM 기반)로 `astrago-deployment` 설치·기동을 자동 검증

## 📋 상세 설명
### 현재 상황
- 단일/소수 환경에서만 테스트되어 OS별 차이(RHEL/Ubuntu/Debian, 커널/CRI 등)로 인한 회귀 가능성 존재

### 기대 결과
- PR/브랜치 단위로 대상 OS 매트릭스에서 병렬 스모크/E2E 스텝 수행
- 실패 원인/로그/아티팩트 자동 수집, 반복 가능 자동화

## 🔧 작업 범위
### 주요 작업
- [ ] 테스트 대상 OS/버전 매트릭스 정의(RHEL 계열, Ubuntu LTS 등)
- [ ] 에페메럴 인프라 선택 및 조합(Kind/K3d + 컨테이너 베이스, 또는 경량 VM)
- [ ] `astrago-deployment` 설치 시나리오 스크립트/헬스체크 표준화
- [ ] CI 워크플로우 작성(병렬 실행, 캐시/이미지 미러 최적화, 아티팩트 업로드)

### 기술적 요구사항
- Kind/K3d 또는 kvm/qemu 기반 경량 VM, Docker 레지스트리 미러/프록시, GitHub Actions 매트릭스 전략

## 📎 참고자료
- `applications/*`, `helmfile.yaml`, `environments/*/values.yaml`, `airgap/`

## ⚠️ 주의사항
- 리소스/시간 한도 관리, 네트워크/포트 충돌 회피, 폐쇄망 시 모의 미러 활용

우선순위: High  
담당자: TBD  
시작일: YYYY-MM-DD  
완료 예정일: YYYY-MM-DD  
예상 소요 시간: 3 point

---


### [C6] CI 테스트 매트릭스 표준화(스모크)

## 🎯 이슈 요약
스모크 테스트 레벨 정의와 자동화

## 📋 상세 설명
### 현재 상황
- 테스트 기준/레벨 혼재

### 기대 결과
- 빠른 실패/정확한 원인 파악, 회귀 방지

## 🔧 작업 범위
### 주요 작업
- [ ] 테스트 케이스 템플릿/샘플
- [ ] 결과 대시보드/알림 연계

### 기술적 요구사항
- K6/Locust(선택), junit 아티팩트, Grafana

## 📎 참고자료
- `docs/applications.md`

## ⚠️ 주의사항
- 에페메럴 환경에서의 실행 시간 최적화

우선순위: Normal  
담당자: TBD  
시작일: YYYY-MM-DD  
완료 예정일: YYYY-MM-DD  
예상 소요 시간: 2 point

---

### 마일스톤(제안)
- M1: GitFlow/규칙 수립(C1)
- M2: 에페메럴 클러스터/배포 템플릿(C2, C3)
- M3: ChatOps/LLM/테스트 매트릭스(C4, C5, C6)

---
