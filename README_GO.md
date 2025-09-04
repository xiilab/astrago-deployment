# Astrago Chart Sync Tool (Go Version)

Helm 차트 동기화 도구의 Go 버전입니다. 오프라인/에어갭 환경을 위해 외부 Helm 차트를 로컬로 다운로드하고 관리합니다.

## 특징

- 🚀 **고성능**: Go로 작성되어 빠른 실행 속도
- 📦 **네이티브 Helm 통합**: Helm 라이브러리 직접 사용
- 🔒 **체크섬 검증**: 차트 무결성 자동 검증
- 🔧 **Chart.lock 자동 수정**: 오프라인 환경을 위한 자동 설정
- 📋 **버전 관리**: versions.lock 파일로 체계적 관리

## 설치

### 사전 요구사항
- Go 1.21 이상
- Helm 3.x

### 빌드
```bash
# 의존성 설치
make deps

# 바이너리 빌드
make build

# 시스템에 설치 (옵션)
make install
```

## 사용법

### 차트 다운로드
```bash
./chart-sync download
# 또는
make run-download
```

### 체크섬 검증
```bash
./chart-sync validate
# 또는
make run-validate
```

### 다운로드된 차트 목록 확인
```bash
./chart-sync list
# 또는
make run-list
```

### Chart.lock 수정
```bash
./chart-sync fix-locks
# 또는
make run-fix-locks
```

### 차트 정리
```bash
./chart-sync clean
# 또는
make run-clean
```

## 설정

### charts.json
차트 정보를 정의하는 설정 파일:

```json
{
  "repositories": {
    "bitnami": "https://charts.bitnami.com/bitnami",
    "prometheus-community": "https://prometheus-community.github.io/helm-charts"
  },
  "charts": {
    "keycloak": {
      "repository": "bitnami",
      "version": "21.4.4"
    },
    "kube-prometheus-stack": {
      "repository": "prometheus-community", 
      "version": "61.9.0"
    }
  }
}
```

## 프로젝트 구조

```
.
├── cmd/
│   └── chart-sync/
│       └── main.go          # 메인 진입점
├── internal/
│   ├── cmd/                 # CLI 명령어
│   │   ├── download.go
│   │   ├── validate.go
│   │   ├── list.go
│   │   ├── clean.go
│   │   └── fixlocks.go
│   ├── config/              # 설정 관리
│   │   └── charts.go
│   ├── helm/                # Helm 클라이언트
│   │   └── client.go
│   ├── chart/               # 차트 수정
│   │   └── modifier.go
│   └── lock/                # versions.lock 관리
│       └── manager.go
├── go.mod                   # Go 모듈 정의
├── Makefile                 # 빌드 자동화
└── charts.json              # 차트 설정
```

## 주요 기능

### 1. 차트 다운로드
- charts.json에 정의된 모든 차트 다운로드
- 자동으로 의존성 해결
- 버전별 디렉토리 생성

### 2. 오프라인 모드 지원
- Chart.yaml의 repository를 `file://charts/<name>`으로 자동 변경
- Chart.lock 재생성으로 로컬 차트 참조

### 3. 무결성 검증
- SHA256 체크섬으로 차트 무결성 확인
- versions.lock 파일에 체크섬 저장

## 장점 (vs Bash 스크립트)

1. **성능**: 컴파일된 바이너리로 빠른 실행
2. **안정성**: 타입 안정성과 에러 처리
3. **네이티브 통합**: Helm Go 라이브러리 직접 사용
4. **유지보수**: 구조화된 코드로 확장 용이
5. **테스트**: Go 테스트 프레임워크 활용 가능

## 개발

### 테스트 실행
```bash
make test
```

### 새 명령어 추가
1. `internal/cmd/` 디렉토리에 새 파일 생성
2. `cobra.Command` 구조체 구현
3. `cmd/chart-sync/main.go`에 명령어 등록

## 라이선스

Astrago 프로젝트의 일부로 제공됩니다.