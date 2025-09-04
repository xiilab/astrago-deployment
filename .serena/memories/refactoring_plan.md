# Helmfile 리팩토링 실행 계획

## 현재 작업 상태
- ✅ 현황 분석 완료
- ✅ 문제점 도출 완료
- ✅ 솔루션 설계 완료
- ✅ 상세 문서 작성 완료
- ⏳ 실제 구현 대기 중

## 다음 단계 작업

### 1. 새 구조 생성 (Phase 1)
```bash
# 새 디렉토리 구조 생성
mkdir -p helmfile/{environments,releases,charts,values,scripts}
mkdir -p helmfile/environments/{base,dev,stage,prod}
mkdir -p helmfile/releases/{infrastructure,monitoring,security,applications}
mkdir -p helmfile/charts/{external,custom,patches}
mkdir -p helmfile/values/{templates,schemas}
```

### 2. 파일럿 마이그레이션 (Phase 2)
- CSI Driver NFS부터 시작 (가장 간단)
- 테스트 및 검증
- 문제점 수정

### 3. 전체 마이그레이션 (Phase 3-4)
- 인프라 → 모니터링 → 보안 → 애플리케이션 순서
- 각 단계별 검증

## 주요 결정 사항

### 차트 커스터마이징 방식
- **선택**: Helm Post-rendering with Kustomize
- **이유**: 원본 차트 유지, 패치만 관리, 업그레이드 용이

### 디렉토리 위치
- **선택**: `/helmfile` 디렉토리로 중앙화
- **이유**: 관련 파일 집중, 관리 용이성

### 환경 관리
- **선택**: 계층적 values 구조 (base + 환경별 오버라이드)
- **이유**: 중복 제거, 일관성 유지

## 리스크 관리
1. 기존 구조와 병렬 운영으로 안전성 확보
2. 단계별 마이그레이션으로 리스크 분산
3. 각 단계별 롤백 계획 수립

## 검증 체크리스트
- [ ] helmfile lint 통과
- [ ] helmfile diff로 변경사항 확인
- [ ] 개발 환경 배포 테스트
- [ ] 모든 파드 정상 구동 확인
- [ ] 기능 테스트 통과

## 문서 위치
- 상세 분석 문서: `/docs/roadmap/helmfile-refactoring-analysis.md`
- Linear 이슈: BE-384