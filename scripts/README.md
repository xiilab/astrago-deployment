# Astrago Deployment Scripts

Astrago 배포를 위한 유틸리티 스크립트 모음

## 📁 스크립트 목록

### sync-charts.sh
오프라인/에어갭 배포를 위한 Helm 차트 동기화 스크립트

**주요 기능:**
- 외부 Helm 차트 자동 다운로드
- 버전 고정 및 무결성 검증
- 체크섬 기반 차트 검증
- 에러 처리 및 롤백 지원

**사용법:**
```bash
# 모든 차트 다운로드
./scripts/sync-charts.sh download

# 차트 무결성 검증
./scripts/sync-charts.sh validate

# 다운로드된 차트 목록 확인
./scripts/sync-charts.sh list

# 도움말
./scripts/sync-charts.sh help
```

**다운로드되는 차트:**
- prometheus-community/kube-prometheus-stack:61.9.0
- fluxcd-community/flux2:2.12.4
- harbor/harbor:1.14.2
- nvidia/gpu-operator:v24.9.0
- bitnami/keycloak:21.4.4

**출력 위치:**
- 차트: `helmfile/charts/external/`
- Lock 파일: `helmfile/charts/versions.lock`

## 🔧 요구사항

- Helm 3.x
- 인터넷 연결 (다운로드 시)
- bash 셸

## 📋 사용 시나리오

### 초기 설정
```bash
# 차트 다운로드
./scripts/sync-charts.sh download

# 검증
./scripts/sync-charts.sh validate
```

### 정기 동기화
```bash
# 차트 업데이트 확인 및 다운로드
./scripts/sync-charts.sh download

# 무결성 검증
./scripts/sync-charts.sh validate
```

### 에어갭 환경 준비
1. 인터넷 연결된 환경에서 차트 다운로드
2. `helmfile/charts/` 디렉토리 전체를 에어갭 환경으로 복사
3. 에어갭 환경에서 검증 실행

## ⚠️ 주의사항

- 차트 다운로드는 네트워크 상태에 따라 시간이 걸릴 수 있습니다
- versions.lock 파일을 임의로 수정하지 마세요
- 에어갭 환경에서는 validate 명령만 사용하세요