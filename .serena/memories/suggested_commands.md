# Astrago Deployment 개발 명령어

## Helmfile 명령어
```bash
# 환경별 배포
helmfile -e dev apply
helmfile -e stage apply
helmfile -e prod apply

# 차이점 확인 (배포 전 필수)
helmfile -e dev diff

# 특정 릴리즈만 적용
helmfile -e dev -l app=astrago apply

# 린트 (문법 검증)
helmfile -e dev lint

# 템플릿 렌더링 확인
helmfile -e dev template

# 동기화
helmfile -e dev sync

# 삭제
helmfile -e dev destroy
```

## Helm 명령어
```bash
# 차트 의존성 업데이트
helm dependency update applications/astrago/astrago

# 차트 패키징
helm package applications/astrago/astrago

# 값 검증
helm lint applications/astrago/astrago

# 설치된 릴리즈 확인
helm list -A

# 릴리즈 상태 확인
helm status astrago -n astrago
```

## Git 명령어
```bash
# 브랜치 생성
git checkout -b feature/helmfile-refactoring

# 상태 확인
git status

# 변경사항 확인
git diff

# 커밋
git add .
git commit -m "refactor: helmfile structure reorganization"

# 푸시
git push origin feature/helmfile-refactoring
```

## Kubernetes 명령어
```bash
# 네임스페이스 확인
kubectl get ns

# 파드 상태 확인
kubectl get pods -A

# 로그 확인
kubectl logs -n astrago deployment/astrago-core

# 리소스 상태 확인
kubectl get all -n astrago

# 이벤트 확인
kubectl get events -n astrago --sort-by='.lastTimestamp'
```

## 유틸리티 명령어
```bash
# YAML 검증
yamllint helmfile.yaml

# YAML 포맷팅
yq eval '.' helmfile.yaml

# 파일 검색
find . -name "*.yaml" -type f

# 패턴 검색
grep -r "gpu-operator" --include="*.yaml"

# 디렉토리 구조 확인
tree -L 3 applications/
```

## Darwin (macOS) 특화 명령어
```bash
# 파일 시스템 이벤트 모니터링
fswatch -r helmfile/

# 프로세스 확인
ps aux | grep helm

# 포트 확인
lsof -i :8080

# 디스크 사용량
du -sh applications/*
```