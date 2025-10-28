# 🚨 Phase 0: Critical Fixes - 구현 전 필수 수정 사항

> **Version 2.0.0 | 2024년 10월**
> **우선순위: P0 (최고)** - 실제 구현 전 반드시 완료해야 함

## 📌 Executive Summary

본 문서는 실제 구현 전 **반드시 수정해야 할 5가지 Critical 이슈**를 정의합니다.
GPT-5 코드 리뷰 및 문서 정합성 분석 결과를 바탕으로 작성되었습니다.

**예상 소요 시간: 2-3일**
**영향도: High** - 수정하지 않으면 런타임 크래시, 기능 동작 불가, UX 혼란 발생

---

## ✅ Critical Issue 체크리스트

### Issue #1: Helm SDK 버전 통일 🔴

**문제:**
- 기술 명세서: `helm.sh/helm/v3@v3.14.0`
- 구현 계획서: `helm.sh/helm/v3@v3.13.0`
- 버전 불일치로 인한 API 차이 → 런타임 에러 가능

**영향도:** 🔴 Critical
- 런타임 크래시 가능
- 빌드 실패 가능 (go.mod 고정)
- 테스트 환경과 프로덕션 환경 불일치

**해결 방법:**
```bash
# go.mod 수정
go get helm.sh/helm/v3@v3.14.0

# 모든 import 확인
grep -r "helm.sh/helm/v3" . --include="*.go"
```

**검증:**
```bash
go mod tidy
go build ./...
go test ./...
```

**소요 시간:** 10분
**ROI:** ⭐⭐⭐⭐⭐

**상태:** [ ] 완료

---

### Issue #2: CLI 옵션 명칭 통일 🔴

**문제:**
- 구현 계획 코드: `--json` 플래그만 존재, `--format` 미정의
- 기술 명세: `--format text|json|yaml` 표준화
- UX 혼란 (사용자가 어떤 옵션 사용해야 할지 모름)

**영향도:** 🟡 Medium
- 사용자 경험 저하
- 문서와 코드 불일치
- 확장성 부족 (YAML 지원 시 새 플래그 필요)

**해결 방법:**
```go
// cmd/extractor/main.go
rootCmd.Flags().StringP("format", "F", "text", "출력 형식 (text|json|yaml)")
rootCmd.Flags().Bool("json", false, "JSON 형식 출력 (deprecated: use --format json)")

// run() 함수에서 처리
func run(cmd *cobra.Command, args []string) error {
    format, _ := cmd.Flags().GetString("format")
    jsonFlag, _ := cmd.Flags().GetBool("json")

    // 하위 호환성 유지
    if jsonFlag {
        fmt.Fprintln(os.Stderr, "Warning: --json is deprecated, use --format json")
        format = "json"
    }

    // format에 따라 출력 처리
    switch format {
    case "text":
        // text output
    case "json":
        // json output
    case "yaml":
        // yaml output
    default:
        return fmt.Errorf("unsupported format: %s", format)
    }
}
```

**검증:**
```bash
./extract-images --format text
./extract-images --format json
./extract-images --format yaml
./extract-images --json  # deprecated 경고 확인
```

**소요 시간:** 30분
**ROI:** ⭐⭐⭐⭐

**상태:** [ ] 완료

---

### Issue #3: 기본 출력 경로 통일 🔴

**문제:**
- 기술 명세: `./kubespray-offline/imagelists/astrago.txt`
- 구현 계획 코드: 기본값 `images.txt`
- 기존 워크플로우와의 통합 실패

**영향도:** 🟡 Medium
- 사용자가 수동으로 경로 변경 필요
- 기존 스크립트와 호환 불가
- 오프라인 배포 워크플로우 중단

**해결 방법:**
```go
// cmd/extractor/main.go
rootCmd.Flags().StringP("output", "o", "kubespray-offline/imagelists/astrago.txt", "출력 파일")

// 출력 전 디렉토리 자동 생성
func ensureOutputDir(outputPath string) error {
    dir := filepath.Dir(outputPath)
    if err := os.MkdirAll(dir, 0755); err != nil {
        return fmt.Errorf("failed to create output directory: %w", err)
    }
    return nil
}
```

**검증:**
```bash
# 기본 경로 확인
./extract-images
ls -la kubespray-offline/imagelists/astrago.txt

# 커스텀 경로도 동작 확인
./extract-images -o custom-path/images.txt
```

**소요 시간:** 5분
**ROI:** ⭐⭐⭐⭐⭐

**상태:** [ ] 완료

---

### Issue #4: Helm action.Configuration 초기화 누락 🔴

**문제:**
- 구현 계획의 `Renderer`에서 `action.Configuration`에 대한 `Init` 호출 없음
- `RESTClientGetter` 설정 누락
- DryRun/ClientOnly 모드여도 NPE (Null Pointer Exception) 가능

**영향도:** 🔴 Critical
- 런타임 크래시 (NPE)
- Helm SDK 동작 불가
- 차트 렌더링 실패

**해결 방법:**
```go
// internal/renderer/renderer.go
import (
    "helm.sh/helm/v3/pkg/action"
    "helm.sh/helm/v3/pkg/cli"
)

func New(cfg *config.Config) (*Renderer, error) {
    // Helm CLI 환경 설정
    settings := cli.New()

    // action.Configuration 초기화 (필수)
    helmConfig := new(action.Configuration)

    // DryRun 모드로 초기화 (클러스터 접근 불필요)
    if err := helmConfig.Init(
        settings.RESTClientGetter(),
        settings.Namespace(),
        os.Getenv("HELM_DRIVER"), // 기본값: "secret"
        func(format string, v ...interface{}) {
            if cfg.Verbose {
                log.Printf(format, v...)
            }
        },
    ); err != nil {
        return nil, fmt.Errorf("failed to initialize Helm configuration: %w", err)
    }

    return &Renderer{
        config:     cfg,
        helmConfig: helmConfig,
        valueOpts:  new(values.Options),
    }, nil
}
```

**대체 방법 (Engine 렌더러):**
```go
// 클러스터 접근이 완전히 불필요한 경우
import "helm.sh/helm/v3/pkg/engine"

func (r *Renderer) renderWithEngine(chart *chart.Chart, values map[string]interface{}) (string, error) {
    engine := engine.Engine{
        Strict: true,
        LintMode: false,
    }

    files, err := engine.Render(chart, values)
    if err != nil {
        return "", fmt.Errorf("chart rendering failed: %w", err)
    }

    // manifests 결합
    var manifests strings.Builder
    for _, content := range files {
        manifests.WriteString(content)
        manifests.WriteString("\n---\n")
    }

    return manifests.String(), nil
}
```

**검증:**
```bash
# 단위 테스트
go test -v ./internal/renderer/...

# 통합 테스트
./extract-images --helmfile test/fixtures/helmfile.yaml
```

**소요 시간:** 2-4시간
**ROI:** ⭐⭐⭐⭐⭐

**상태:** [ ] 완료

---

### Issue #5: Helmfile 파싱 미구현 🔴

**문제:**
- 구현 계획의 `parseHelmfile()`는 주석 상태
- 현재 빈 결과 반환 (`releases := []Release{}`)
- **핵심 기능이 동작하지 않음**

**영향도:** 🔴 Critical
- 기능이 전혀 동작하지 않음
- 차트 발견 불가
- 이미지 추출 불가

**해결 방법:**
```go
// internal/discovery/discovery.go
import (
    "encoding/json"
    "os/exec"
)

func (d *Discoverer) parseHelmfile() ([]Release, error) {
    // 임시 구조체 정의
    type Release struct {
        Name      string   `json:"name"`
        Chart     string   `json:"chart"`
        Namespace string   `json:"namespace"`
        Values    []string `json:"values"`
        Version   string   `json:"version"`
    }

    // Helmfile 실행으로 releases 정보 가져오기
    cmd := exec.Command("helmfile",
        "-f", d.config.HelmfilePath,
        "-e", d.config.Environment,
        "list",
        "--output", "json",
    )

    if d.config.Verbose {
        fmt.Printf("🔍 Helmfile 실행: %s\n", cmd.String())
    }

    // 명령어 실행
    output, err := cmd.Output()
    if err != nil {
        if exitErr, ok := err.(*exec.ExitError); ok {
            return nil, fmt.Errorf("helmfile 실행 실패: %w\nStderr: %s", err, string(exitErr.Stderr))
        }
        return nil, fmt.Errorf("helmfile 실행 실패: %w", err)
    }

    // JSON 파싱
    var releases []Release
    if err := json.Unmarshal(output, &releases); err != nil {
        return nil, fmt.Errorf("helmfile JSON 파싱 실패: %w", err)
    }

    if d.config.Verbose {
        fmt.Printf("✅ %d개 릴리즈 발견\n", len(releases))
    }

    return releases, nil
}
```

**Values 경로 병합 처리:**
```go
func (d *Discoverer) loadReleaseValues(release Release) (map[string]interface{}, error) {
    mergedValues := make(map[string]interface{})

    // values 파일들을 순서대로 병합
    for _, valuesPath := range release.Values {
        data, err := os.ReadFile(valuesPath)
        if err != nil {
            if d.config.Verbose {
                fmt.Printf("⚠️  Values 파일 읽기 실패 [%s]: %v\n", valuesPath, err)
            }
            continue
        }

        var values map[string]interface{}
        if err := yaml.Unmarshal(data, &values); err != nil {
            return nil, fmt.Errorf("values YAML 파싱 실패 [%s]: %w", valuesPath, err)
        }

        // Deep merge
        mergedValues = deepMerge(mergedValues, values)
    }

    return mergedValues, nil
}

func deepMerge(dst, src map[string]interface{}) map[string]interface{} {
    for key, srcVal := range src {
        if dstVal, ok := dst[key]; ok {
            // 둘 다 map이면 재귀 병합
            if srcMap, ok := srcVal.(map[string]interface{}); ok {
                if dstMap, ok := dstVal.(map[string]interface{}); ok {
                    dst[key] = deepMerge(dstMap, srcMap)
                    continue
                }
            }
        }
        // 덮어쓰기
        dst[key] = srcVal
    }
    return dst
}
```

**검증:**
```bash
# Helmfile 설치 확인
which helmfile

# 실제 helmfile로 테스트
helmfile -f test/fixtures/helmfile.yaml -e default list --output json

# 통합 테스트
./extract-images --helmfile test/fixtures/helmfile.yaml --verbose
```

**소요 시간:** 1-2일
**ROI:** ⭐⭐⭐⭐⭐

**상태:** [ ] 완료

---

## 📊 우선순위 및 실행 순서

### Day 1: Quick Wins (3시간)
```bash
09:00-09:10 ✅ Issue #1: Helm SDK 버전 통일 (10분)
09:10-09:15 ✅ Issue #3: 출력 경로 수정 (5분)
09:15-09:45 ✅ Issue #2: CLI 옵션 통일 (30분)
10:00-12:00 🔧 Issue #4: action.Configuration Init (2시간)
```

### Day 2-3: Core Implementation (1-2일)
```bash
Day 2:
09:00-12:00 🔧 Issue #5: Helmfile 파싱 구현 (3시간)
13:00-17:00 🔧 Values 병합 로직 구현 (4시간)

Day 3:
09:00-12:00 🧪 통합 테스트 작성 및 실행
13:00-17:00 📝 문서 업데이트 및 검증
```

---

## 🧪 통합 검증 체크리스트

### 1. 빌드 검증
```bash
# 모든 플랫폼 빌드
make build-all

# 예상 출력:
# ✅ linux/amd64
# ✅ linux/arm64
# ✅ darwin/amd64
# ✅ darwin/arm64
```

### 2. 기능 검증
```bash
# 기본 실행
./extract-images \
    --helmfile ../../helmfile/helmfile.yaml.gotmpl \
    --environment default \
    --verbose

# 예상 출력:
# 🔍 Helmfile 실행: helmfile -f ... -e default list --output json
# ✅ 15개 릴리즈 발견
# 🔧 15개 차트 렌더링 중...
# ✅ 127개 고유 이미지 추출 완료
# 📝 kubespray-offline/imagelists/astrago.txt 저장 완료
```

### 3. 출력 형식 검증
```bash
# Text 형식
./extract-images --format text -o test-text.txt
cat test-text.txt
# nvcr.io/nvidia/driver:550.127.05
# quay.io/prometheus/prometheus:v2.45.0
# ...

# JSON 형식
./extract-images --format json -o test-json.json
cat test-json.json
# {
#   "images": [
#     {
#       "registry": "nvcr.io",
#       "repository": "nvidia/driver",
#       "tag": "550.127.05",
#       "full": "nvcr.io/nvidia/driver:550.127.05"
#     }
#   ]
# }

# YAML 형식
./extract-images --format yaml -o test-yaml.yaml
cat test-yaml.yaml
# images:
#   - registry: nvcr.io
#     repository: nvidia/driver
#     tag: 550.127.05
#     full: nvcr.io/nvidia/driver:550.127.05
```

### 4. 에러 처리 검증
```bash
# Helmfile 없을 때
./extract-images --helmfile nonexistent.yaml
# Error: helmfile 실행 실패: ...

# 잘못된 형식
./extract-images --format invalid
# Error: unsupported format: invalid

# 권한 없는 출력 경로
./extract-images -o /root/images.txt
# Error: failed to create output directory: permission denied
```

---

## 📋 완료 기준

모든 Issue가 완료되고 아래 조건을 만족하면 Phase 0 완료:

- [ ] **빌드 성공**: 모든 플랫폼에서 빌드 성공
- [ ] **테스트 통과**: 모든 단위 테스트 통과
- [ ] **통합 테스트 성공**: 실제 helmfile.yaml로 이미지 추출 성공
- [ ] **문서 업데이트**: 3개 문서 모두 v2.0.0으로 통일
- [ ] **검증 완료**: 5가지 검증 항목 모두 통과

---

## 📚 관련 문서
- [TECHNICAL_SPECIFICATION_V2.md](./TECHNICAL_SPECIFICATION_V2.md)
- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)

---

## 🎯 다음 단계

Phase 0 완료 후:
- **Phase 1**: 핵심 기능 구현 (Week 1-2)
- **Phase 2-5**: 품질 개선 및 배포 (Week 3-6)

**예상 전체 기간: 6-7주** (Phase 0: 3일 + Phase 1-5: 5-6주)
