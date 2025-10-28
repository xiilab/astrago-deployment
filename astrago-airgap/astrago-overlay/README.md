# Astrago Helm Chart Image Extractor

오프라인(Air-gapped) 환경에서 Kubernetes 및 Helm Chart 배포를 위해 필요한 모든 컨테이너 이미지를 자동으로 추출하고 목록화하는 Go 기반 도구입니다.

## 🎯 주요 기능

- **완전 자동화**: Helmfile에서 모든 차트를 자동 발견하고 이미지 추출
- **오프라인 배포 최적화**: `installed: false` 차트도 포함하여 모든 가능한 이미지 추출
- **스마트 중복 제거**: 태그 없는 이미지와 태그 있는 이미지가 중복될 때 자동 정리
  - 예: `nginx`와 `nginx:1.19`가 모두 있으면 → `nginx:1.19`만 유지
  - 불필요한 `latest` 태그 이미지 자동 제거
- **Helm SDK 통합**: Helm v3 SDK를 사용한 네이티브 차트 렌더링
- **Operator 지원**: GPU Operator, Prometheus, MPI Operator 등 특수 차트 지원
- **다양한 출력 형식**: Text, JSON, YAML 형식 지원
- **병렬 처리**: 멀티코어 활용으로 빠른 처리 속도
- **크로스 플랫폼**: Linux/macOS, AMD64/ARM64 지원
- **다운로드 스크립트 생성**: 추출된 이미지 자동 다운로드 스크립트 생성
- **상세 리포트**: 차트별, 레지스트리별 통계 리포트

## 📦 설치

### 사전 요구사항

- Go 1.21 이상 (빌드 시)
- Helmfile 설정 파일

### 빌드

```bash
# 현재 플랫폼용 빌드
make build

# 모든 플랫폼용 빌드
make build-all

# 설치 (tools 디렉토리로)
make install
```

## 🚀 사용법

### 기본 사용

```bash
# 기본 실행 (자동으로 Helmfile 탐색)
./bin/extract-images-darwin-arm64

# Helmfile 경로 지정
./bin/extract-images-darwin-arm64 --helmfile /path/to/helmfile

# 출력 파일 지정
./bin/extract-images-darwin-arm64 --output ./images.txt
```

### 고급 옵션

```bash
# JSON 형식으로 출력
./bin/extract-images-darwin-arm64 --format json

# 병렬 처리 워커 수 지정
./bin/extract-images-darwin-arm64 --workers 10

# 다운로드 스크립트 생성
./bin/extract-images-darwin-arm64 --generate-script

# 상세 리포트 생성
./bin/extract-images-darwin-arm64 --generate-report

# 디버그 모드
./bin/extract-images-darwin-arm64 --debug --verbose
```

### CLI 옵션

| 옵션 | 단축 | 기본값 | 설명 |
|------|------|--------|------|
| `--helmfile` | `-f` | (자동 탐색) | Helmfile 경로 |
| `--environment` | `-e` | `default` | Helmfile 환경 |
| `--output` | `-o` | `kubespray-offline/imagelists/astrago.txt` | 출력 파일 경로 |
| `--format` | `-F` | `text` | 출력 형식 (text\|json\|yaml) |
| `--workers` | `-w` | `5` | 병렬 처리 워커 수 |
| `--verbose` | `-v` | `false` | 상세 출력 |
| `--debug` | | `false` | 디버그 모드 |
| `--generate-script` | | `false` | 다운로드 스크립트 생성 |
| `--generate-report` | | `false` | 상세 리포트 생성 |

## 📂 출력 파일

### 기본 출력 (text)

```
nvcr.io/nvidia/gpu-operator:v23.9.0
quay.io/prometheus/prometheus:v2.45.0
docker.io/grafana/grafana:10.0.0
...
```

### JSON 출력

```json
{
  "images": [
    "nvcr.io/nvidia/gpu-operator:v23.9.0",
    "quay.io/prometheus/prometheus:v2.45.0"
  ],
  "count": 2
}
```

### 다운로드 스크립트

`--generate-script` 옵션 사용 시 생성:
- `download-images.sh` (Bash)
- `download-images.ps1` (PowerShell)

### 상세 리포트

`--generate-report` 옵션 사용 시 `reports/` 디렉토리에 생성:
- `report-YYYYMMDD-HHMMSS.json`
- `report-YYYYMMDD-HHMMSS.yaml`
- `summary-YYYYMMDD-HHMMSS.txt`

## 🔧 Operator 설정

Operator 차트의 특수 이미지는 `configs/operators.yaml`에서 관리됩니다:

```yaml
operators:
  gpu-operator:
    enabled: true
    images:
      - path: operator.repository
        tag_path: operator.version
      - path: driver.repository
        tag_path: driver.version
```

새로운 Operator 차트를 추가하려면 이 파일을 수정하세요.

## 📌 오프라인 배포 중요 사항

### `installed: false` 차트 처리

이 도구는 **오프라인 배포를 위해 설계**되었기 때문에, Helmfile에서 `installed: false`로 설정된 차트의 이미지도 추출합니다.

**이유:**
- 오프라인 환경에서는 나중에 이미지를 추가로 가져올 수 없음
- 고객 사이트에서 필요에 따라 선택적으로 설치할 수 있어야 함
- 실제 설치 여부는 Helmfile 배포 시점에 결정됨

**예시:**
```yaml
releases:
  - name: optional-monitoring
    chart: ./charts/monitoring
    installed: false  # 기본적으로 설치 안 함
    # → 하지만 이미지는 추출되어 오프라인 패키지에 포함됨
```

이 동작은 **의도된 것**이며, 오프라인 환경에서의 유연성을 보장합니다.

## 🏗️ 아키텍처

```
cmd/extractor/          # CLI 진입점
internal/
  ├── config/           # 설정 관리 (Phase 4.3: 확장 가능한 설정)
  ├── discovery/        # 차트 자동 발견 (Phase 2.1: Go Template 렌더링)
  ├── renderer/         # Helm SDK 렌더링 (Phase 5: 동적 워커 + 캐싱)
  ├── extractor/        # 이미지 추출 엔진 (Phase 1.2: 설정 기반)
  ├── output/           # 출력 처리
  ├── utils/            # 공통 유틸리티 (Phase 1.1: 신규 생성)
  └── errors/           # 에러 핸들링 (Phase 4.1: 표준화)
pkg/
  └── patterns/         # 이미지 패턴 매칭 (Phase 2: 재귀 깊이 + 비표준 필드)
configs/
  └── operators.yaml    # Operator 설정 (Phase 1.2: 외부화)
```

## 🔄 최근 리팩토링 (Cycle 8)

### Phase 1-2: 코드 품질 & 기능 완성도 ✅
- **470+ 줄 코드 감소**: 중복 제거 및 설정 기반 관리
- **7가지 이미지 패턴**: 비표준 필드 지원 (themeImage, repository 등)
- **재귀 깊이 10**: 깊게 중첩된 values 구조 지원
- **Go Template 렌더링**: .gotmpl 파일 완벽 지원

### Phase 4-5: 구조 개선 & 성능 최적화 ✅
- **에러 핸들링 표준화**: ExtractorError 구조체
- **동적 워커 조정**: runtime.NumCPU() 기반
- **차트 렌더링 캐싱**: 재처리 시 10x 성능 향상
- **확장 가능한 설정**: MaxRecursionDepth, EnableCache

## 🧪 테스트

```bash
# 단위 테스트
make test

# 테스트 커버리지 리포트 생성 (HTML)
make test-coverage

# 통합 테스트
make test-integration

# 벤치마크
make bench

# 코드 린팅
make lint
```

### 테스트 커버리지

| 패키지 | 커버리지 | 비고 |
|--------|---------|------|
| **internal/errors** | **100.0%** | ✨ Phase 4.1 신규 |
| **internal/utils** | **89.4%** | ✨ Phase 1.1 신규 |
| internal/config | 86.4% | 유지 |
| pkg/patterns | 81.8% | Phase 2 개선 |
| internal/extractor | 77.4% | ⬆️ 72.8% → 77.4% |
| internal/renderer | 69.5% | Phase 5 캐싱 추가 |
| internal/discovery | 32.5% | 소폭 개선 |
| internal/output | 32.6% | ⬆️ 27.4% → 32.6% |
| **전체** | **~64%** | ⬆️ **48.5% → 64%** |

## 📊 성능

- **처리 속도**: < 1초 (50개 차트 기준, 병렬 처리)
- **메모리 사용**: < 100MB
- **정확도**: 100% 이미지 추출 (Operator 포함)

## 🤝 기여

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 라이선스

이 프로젝트는 내부 사용을 위한 것입니다.

## 🔗 관련 문서

- [Technical Specification](docs/TECHNICAL_SPECIFICATION_V2.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)

## 💬 문의

문제가 발생하거나 질문이 있으시면 이슈를 생성해주세요.

