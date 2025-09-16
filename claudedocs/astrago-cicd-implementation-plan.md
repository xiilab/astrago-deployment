# Astrago CI/CD 파이프라인 구현 실행 계획

## 📋 구현 개요

**목표**: Astrago Backend/Frontend 저장소에 GitHub Actions 기반 CI/CD 파이프라인을 구현하여 완전한 자동 배포 시스템 구축

**현재 상태**:
- ✅ 설계 완료 ([astrago-cicd-design.md](./astrago-cicd-design.md))
- ✅ Linear 이슈 등록 완료 (BE-577, BE-578, BE-579, BE-580)
- ✅ ArgoCD 배포 시스템 동작 중 (stabilize/1.0 브랜치)

## 🚀 Phase별 구현 계획

### Phase 1: GitHub Secrets 설정 (BE-579) 🔐
**우선순위**: `Urgent` | **소요시간**: `30분` | **의존성**: `없음`

#### 작업 내용
1. **GitHub Personal Access Token 생성**
   ```
   GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens

   GHCR_TOKEN:
   - Repository access: xiilab organization repositories
   - Permissions: packages:write, contents:read

   DEPLOY_TOKEN:
   - Repository access: xiilab/astrago-deployment
   - Permissions: contents:write
   ```

2. **Repository Secrets 설정**
   - `xiilab/astrago-backend`: GHCR_TOKEN, DEPLOY_TOKEN
   - `xiilab/astrago-frontend`: GHCR_TOKEN, DEPLOY_TOKEN

3. **권한 검증**
   - GitHub Package Registry 접근 테스트
   - Deployment 저장소 업데이트 권한 확인

#### 완료 조건
- [ ] GHCR_TOKEN 생성 및 설정 완료
- [ ] DEPLOY_TOKEN 생성 및 설정 완료
- [ ] 권한 테스트 성공

---

### Phase 2: Backend CI/CD 구현 (BE-577) 🛠️
**우선순위**: `High` | **소요시간**: `2-3시간` | **의존성**: `Phase 1 완료`

#### 작업 내용
1. **GitHub Actions 워크플로우 생성**
   ```yaml
   # .github/workflows/ci-cd.yml
   name: CI/CD Pipeline
   on:
     push:
       branches: [stabilize/1.0]
   jobs:
     build-and-deploy:
       runs-on: ubuntu-latest
   ```

2. **Docker 이미지 빌드 구현**
   - core, batch, monitor 컴포넌트 개별 빌드
   - 이미지 태그: `{component}-stage-{git-sha:8}`
   - GitHub Package Registry 푸시

3. **Deployment 저장소 연동**
   - GitHub API를 통한 values.yaml 업데이트
   - 자동 커밋 및 푸시 로직

#### 기술적 고려사항
- **Dockerfile 경로 확인**: 각 컴포넌트별 Dockerfile 위치
- **빌드 컨텍스트**: 모노레포 구조에 맞는 빌드 설정
- **Cross-repository 업데이트**: GitHub API SHA 기반 안전한 업데이트

#### 완료 조건
- [ ] GitHub Actions 워크플로우 파일 생성 완료
- [ ] 3개 컴포넌트 Docker 이미지 빌드 성공
- [ ] ghcr.io 푸시 성공
- [ ] deployment 저장소 values.yaml 자동 업데이트 성공
- [ ] 개별 파이프라인 테스트 성공

---

### Phase 3: Frontend CI/CD 구현 (BE-578) 🎨
**우선순위**: `High` | **소요시간**: `1-2시간` | **의존성**: `Phase 1 완료` (Phase 2와 병렬 가능)

#### 작업 내용
1. **GitHub Actions 워크플로우 생성**
   - Frontend 전용 빌드 파이프라인
   - Node.js 환경 설정 및 의존성 설치
   - 프로덕션 빌드 실행

2. **Docker 이미지 빌드 구현**
   - Multi-stage Docker build (빌드 + 서빙 단계)
   - 이미지 태그: `frontend-stage-{git-sha:8}`
   - 정적 파일 최적화

3. **Deployment 저장소 연동**
   - Frontend imageTag 자동 업데이트
   - Backend와 독립적인 배포 프로세스

#### 기술적 고려사항
- **Node.js 버전**: package.json 호환 버전 확인
- **빌드 스크립트**: npm run build 명령어 확인
- **웹서버 설정**: nginx 또는 정적 파일 서빙 설정

#### 완료 조건
- [ ] GitHub Actions 워크플로우 파일 생성 완료
- [ ] Frontend Docker 이미지 빌드 성공
- [ ] ghcr.io 푸시 성공
- [ ] deployment 저장소 frontend 태그 업데이트 성공
- [ ] 개별 파이프라인 테스트 성공

---

### Phase 4: 통합 테스트 및 검증 (BE-580) ✅
**우선순위**: `High` | **소요시간**: `1-2시간` | **의존성**: `Phase 2, 3 완료`

#### 테스트 시나리오
1. **개별 파이프라인 검증**
   - Backend CI/CD 파이프라인 end-to-end 테스트
   - Frontend CI/CD 파이프라인 end-to-end 테스트

2. **ArgoCD 연동 검증**
   - values.yaml 변경 후 ArgoCD 자동 감지 확인
   - Kubernetes Pod 재시작 및 새 이미지 적용 확인
   - 애플리케이션 정상 동작 확인

3. **통합 시나리오 테스트**
   - Backend + Frontend 동시 변경 테스트
   - 롤백 시나리오 (이전 커밋으로 되돌리기) 테스트
   - 에러 상황 처리 테스트

#### 성능 검증
- **빌드 시간**: 5분 이내 달성
- **전체 배포 시간**: 10분 이내 달성
- **ArgoCD 동기화**: 2분 이내 완료

#### 완료 조건
- [ ] Backend/Frontend 개별 파이프라인 정상 동작 확인
- [ ] ArgoCD 자동 동기화 및 배포 성공 확인
- [ ] 동시 배포 시나리오 테스트 성공
- [ ] 롤백 시나리오 테스트 성공
- [ ] 성능 기준 달성 확인
- [ ] 최종 테스트 결과 문서화

## 🎯 성공 지표

### 정량적 기준
- **빌드 성공률**: 95% 이상
- **배포 성공률**: 99% 이상
- **전체 파이프라인 실행 시간**: 10분 이내
- **ArgoCD 동기화 시간**: 2분 이내

### 정성적 기준
- **개발자 경험**: 코드 푸시 후 자동 배포 완료
- **운영 안정성**: 장애 상황에서도 롤백 가능
- **모니터링**: 배포 상태 실시간 확인 가능

## ⚠️ 리스크 관리

### 잠재적 리스크와 대응 방안
1. **GitHub Package Registry 접근 권한 문제**
   - 대응: 토큰 권한을 단계적으로 테스트
   - 백업: Docker Hub 등 다른 레지스트리 사용

2. **Cross-repository 업데이트 실패**
   - 대응: GitHub API 상세 오류 처리 로직
   - 백업: 수동 deployment 저장소 업데이트

3. **ArgoCD 동기화 지연**
   - 대응: ArgoCD refresh API 강제 동기화
   - 모니터링: 배포 상태 실시간 확인

4. **Docker 이미지 크기 문제**
   - 대응: Multi-stage build 최적화
   - 모니터링: 이미지 크기 추적

## 📈 구현 후 기대 효과

### 개발 생산성 향상
- **수동 배포 작업 완전 제거**: 개발자는 코드만 커밋
- **빠른 피드백 루프**: 변경사항이 15분 내 자동 배포
- **일관된 배포 프로세스**: 인적 오류 최소화

### 운영 안정성 개선
- **추적 가능한 배포**: Git SHA 기반 명확한 버전 관리
- **쉬운 롤백**: 문제 발생 시 이전 커밋으로 빠른 복구
- **자동화된 품질 관리**: 일관된 빌드 및 배포 프로세스

### 확장성 확보
- **다중 환경 지원**: dev, stage, prod 환경별 자동 배포 준비
- **마이크로서비스 확장**: 새로운 서비스 추가 시 동일한 패턴 적용
- **팀 확장성**: 새로운 개발자도 쉽게 배포 프로세스 사용

## 🚀 다음 단계

**지금 바로 시작**: Phase 1 (GitHub Secrets 설정) 작업을 시작하여 BE-579 이슈를 해결하고, 순차적으로 다음 단계를 진행합니다.

모든 Phase가 완료되면, Astrago 프로젝트는 현대적이고 효율적인 CI/CD 파이프라인을 통해 안정적인 자동 배포 시스템을 갖추게 됩니다.

---

**생성일**: 2025-09-16
**작성자**: Claude Code
**관련 문서**: [astrago-cicd-design.md](./astrago-cicd-design.md)
**Linear 이슈**: BE-577, BE-578, BE-579, BE-580