# Linear 워크플로 규칙

## 기본 정보
- **사용자 ID**: m.kwon
- **팀**: Back-end 팀
- **워크플로**: Triage → 담당자 할당

## 이슈 등록 규칙

### 1. 기본 설정
- **Reporter**: m.kwon
- **Team**: Back-end
- **Initial Status**: Triage
- **Assignee**: 미할당 (Triage에서 결정)

### 2. 이슈 구조
```markdown
**Title**: [BE-XXX-N] 간결한 제목

**Description**:
## Objective
목적 명시

## Background  
배경 설명

## Tasks
- [ ] 구체적 작업 목록

## Dependencies
- BE-XXX-Y (선행 이슈)

## Acceptance Criteria
- [ ] 완료 조건

## Definition of Done
- [ ] 최종 검증 조건
```

### 3. 라벨 규칙
- **우선순위**: High, Medium, Low
- **타입**: infrastructure, automation, testing, migration
- **페이즈**: phase-1, phase-2, phase-3, phase-4

### 4. 등록 프로세스
1. Triage 상태로 등록
2. 팀 회의에서 담당자 할당
3. 담당자가 In Progress로 변경
4. 완료 시 Done으로 변경

### 5. 의존성 관리
- Dependencies 필드에 선행 이슈 명시
- 블로킹 이슈 발생 시 즉시 공유
- 크리티컬 패스 이슈는 우선순위 High

## 예시 등록 포맷
```
Title: [BE-384-1] Create new helmfile directory structure
Team: Back-end
Status: Triage
Priority: High
Labels: infrastructure, refactoring, phase-1
Reporter: m.kwon
Assignee: (미할당)
```