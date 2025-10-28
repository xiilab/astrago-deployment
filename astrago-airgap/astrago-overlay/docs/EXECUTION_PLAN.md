# 🚀 Astrago Helm Chart Image Extractor - 실행 계획서

> **Version 1.0.0 | 2024년 10월**
> **프로젝트 기간: 6-7주** (Phase 0: 3일 + Phase 1-5: 5-6주)

## 📌 Executive Summary

본 문서는 Astrago Helm Chart Image Extractor의 **구체적인 실행 계획**을 정의합니다.
[TECHNICAL_SPECIFICATION_V2.md](./TECHNICAL_SPECIFICATION_V2.md)의 요구사항을 바탕으로 작성되었으며,
일별/주별 상세 작업 계획, 코드 구현 가이드, 검증 체크포인트를 포함합니다.

### 프로젝트 목표
- **핵심 기능**: Helmfile 기반 자동 이미지 추출 (95%+ 커버리지)
- **성능 목표**: 50개 차트 < 1초 (병렬 처리)
- **품질 목표**: 테스트 커버리지 80%+, 보안 검증 통과

### 타임라인 개요
```
Phase 0 (3일)   : Critical Fixes - 구현 전 필수 수정
Phase 1 (2주)   : 핵심 기능 구현 - MVP 개발
Phase 2 (1주)   : 테스트 및 검증 - 품질 확보
Phase 3 (1주)   : 최적화 - 성능 개선
Phase 4 (1주)   : 문서화 및 배포 - 프로덕션 준비
Phase 5 (1주)   : 예비 기간 - 버퍼 및 리팩토링
```

---

## 🚨 Phase 0: Critical Fixes & Gap Analysis (Day 1-5)

**목표**: 구현 전 반드시 해결해야 할 5가지 Critical 이슈 수정 + 이미지 추출 Gap 해결
**기간**: 5일 (기존 3일 → 5일로 확대)
**담당**: 전체 팀
**우선순위**: P0 (최고)

### Gap Analysis 결과 반영

**검증 일자**: 2024년 10월 24일
**누락 이미지**: 33개 (Helm 차트 관리 이미지)
**현재 커버리지**: 29% (18/61개)
**목표 커버리지**: 95%+ (58/61개)

**누락 원인**:
1. Go Template 변수 미해석 (6개) - P0
2. 중첩 Values 구조 미탐색 (6개) - P0
3. Harbor 멀티 컴포넌트 (10개) - P1
4. Operator별 명명 규칙 (7개) - P1
5. Manifest Regex 한계 (4개) - P2

### Day 1: Quick Wins (3시간)

#### 09:00-09:10 | Issue #1: Helm SDK 버전 통일 ✅
**소요 시간**: 10분 | **ROI**: ⭐⭐⭐⭐⭐

```bash
# 1. go.mod 수정
cd astrago-airgap/astrago-overlay
go get helm.sh/helm/v3@v3.14.0
go get github.com/rs/zerolog@v1.31.0

# 2. Import 확인
grep -r "helm.sh/helm/v3" . --include="*.go"

# 3. 검증
go mod tidy
go build ./...
go test ./...
```

**검증 기준**: 
- [ ] `go.mod`에 `helm.sh/helm/v3 v3.14.0` 존재
- [ ] 모든 빌드 성공
- [ ] 기존 테스트 통과

---

#### 09:10-09:15 | Issue #3: 기본 출력 경로 수정 ✅
**소요 시간**: 5분 | **ROI**: ⭐⭐⭐⭐⭐

```go
// cmd/extractor/main.go 수정
rootCmd.Flags().StringP("output", "o", "kubespray-offline/imagelists/astrago.txt", "출력 파일")

// 디렉토리 자동 생성 함수 추가
func ensureOutputDir(outputPath string) error {
    dir := filepath.Dir(outputPath)
    if err := os.MkdirAll(dir, 0755); err != nil {
        return fmt.Errorf("failed to create output directory: %w", err)
    }
    return nil
}

// run() 함수에서 호출
func run(cmd *cobra.Command, args []string) error {
    outputPath, _ := cmd.Flags().GetString("output")
    
    if err := ensureOutputDir(outputPath); err != nil {
        return err
    }
    
    // ... 기존 로직
}
```

**검증 기준**:
- [ ] 기본 실행 시 `kubespray-offline/imagelists/astrago.txt` 생성
- [ ] 디렉토리 미존재 시 자동 생성
- [ ] 커스텀 경로 `-o custom/path.txt` 동작

---

#### 09:15-09:45 | Issue #2: CLI 옵션 명칭 통일 ✅
**소요 시간**: 30분 | **ROI**: ⭐⭐⭐⭐

```go
// cmd/extractor/main.go

// 1. 플래그 정의 수정
rootCmd.Flags().StringP("format", "F", "text", "출력 형식 (text|json|yaml)")
rootCmd.Flags().Bool("json", false, "JSON 형식 출력 (deprecated: use --format json)")

// 2. run() 함수 수정
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
        return writeTextFormat(images, outputPath)
    case "json":
        return writeJSONFormat(images, outputPath)
    case "yaml":
        return writeYAMLFormat(images, outputPath)
    default:
        return fmt.Errorf("unsupported format: %s", format)
    }
}
```

**검증 기준**:
- [ ] `--format text` 동작
- [ ] `--format json` 동작
- [ ] `--format yaml` 동작
- [ ] `--json` 사용 시 deprecated 경고 출력

---

#### 10:00-12:00 | Issue #4: action.Configuration 초기화 🔧
**소요 시간**: 2시간 | **ROI**: ⭐⭐⭐⭐⭐

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

// Render() 함수 수정
func (r *Renderer) Render(ctx context.Context, release *discovery.Release) (string, error) {
    // action.Install 생성 (DryRun)
    install := action.NewInstall(r.helmConfig)
    install.DryRun = true
    install.ClientOnly = true
    install.ReleaseName = release.Name
    install.Namespace = release.Namespace

    // Values 병합
    values, err := r.mergeValues(release)
    if err != nil {
        return "", fmt.Errorf("failed to merge values: %w", err)
    }

    // Chart 로드
    chartPath, err := install.LocateChart(release.Chart, r.config.Settings)
    if err != nil {
        return "", fmt.Errorf("failed to locate chart: %w", err)
    }

    chart, err := loader.Load(chartPath)
    if err != nil {
        return "", fmt.Errorf("failed to load chart: %w", err)
    }

    // 렌더링 실행
    rel, err := install.Run(chart, values)
    if err != nil {
        return "", fmt.Errorf("failed to render chart: %w", err)
    }

    return rel.Manifest, nil
}
```

**검증 기준**:
- [ ] `renderer_test.go`에서 New() 테스트 통과
- [ ] NPE 없이 Render() 실행 성공
- [ ] DryRun 모드에서 클러스터 접근 없이 동작

---

### Day 2-3: Core Implementation (1-2일)

#### Day 2: 09:00-17:00 | Issue #5: Helmfile 파싱 구현 🔧
**소요 시간**: 1-2일 | **ROI**: ⭐⭐⭐⭐⭐

##### Morning Session (09:00-12:00): Helmfile 파싱 기본 구현

```go
// internal/discovery/discovery.go

import (
    "encoding/json"
    "os/exec"
)

// Release 구조체 정의
type Release struct {
    Name      string   `json:"name"`
    Chart     string   `json:"chart"`
    Namespace string   `json:"namespace"`
    Values    []string `json:"values"`
    Version   string   `json:"version"`
}

func (d *Discoverer) parseHelmfile() ([]Release, error) {
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

**검증 단계**:
```bash
# 1. Helmfile 설치 확인
which helmfile

# 2. 수동 테스트
helmfile -f test/fixtures/helmfile.yaml -e default list --output json

# 3. 단위 테스트
go test -v ./internal/discovery/... -run TestParseHelmfile
```

---

##### Afternoon Session (13:00-17:00): Values 병합 로직 구현

```go
// internal/discovery/values.go

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

**검증 단계**:
```bash
# 1. Values 병합 테스트
go test -v ./internal/discovery/... -run TestLoadReleaseValues

# 2. 통합 테스트
./extract-images \
    --helmfile test/fixtures/helmfile.yaml \
    --environment default \
    --verbose
```

---

#### Day 3: 09:00-17:00 | 통합 테스트 및 검증 🧪

##### Morning Session (09:00-12:00): 통합 테스트

```bash
# 1. 전체 빌드
make build-all

# 2. 기본 실행 테스트
./extract-images \
    --helmfile ../../helmfile/helmfile.yaml.gotmpl \
    --environment default \
    --verbose

# 3. 출력 형식 테스트
./extract-images --format text -o test-text.txt
./extract-images --format json -o test-json.json
./extract-images --format yaml -o test-yaml.yaml

# 4. 에러 케이스 테스트
./extract-images --helmfile nonexistent.yaml  # 예상: 에러 메시지
./extract-images --format invalid             # 예상: unsupported format
```

---

##### Afternoon Session (13:00-17:00): 문서 업데이트

**작업 항목**:
1. README.md 업데이트 (설치 가이드, 사용 예시)
2. CHANGELOG.md 작성 (Phase 0 변경 사항)
3. Gap Analysis 문서 업데이트

---

### Day 4-5: Image Extraction Gap 해결 🔧

**목표**: 누락된 33개 이미지 추출 로직 구현
**우선순위**: P0 (Go Template, 중첩 Values) → P1 (Harbor, Operator) → P2 (Regex)

#### Day 4 (09:00-17:00): P0 이슈 해결

##### Morning Session (09:00-12:00): Gap #1 - Go Template 변수 해석

**작업 내용**:
```go
// internal/discovery/template.go (신규 생성)

import (
    "bytes"
    "text/template"
)

// renderGoTemplate은 Helmfile Go template 변수를 평가합니다
func (d *Discoverer) renderGoTemplate(content string, envValues map[string]interface{}) (string, error) {
    tmpl, err := template.New("values").Parse(content)
    if err != nil {
        return "", fmt.Errorf("template parse failed: %w", err)
    }

    var buf bytes.Buffer
    if err := tmpl.Execute(&buf, envValues); err != nil {
        return "", fmt.Errorf("template execute failed: %w", err)
    }

    return buf.String(), nil
}

// loadAndRenderValues는 values 파일을 로드하고 템플릿을 렌더링합니다
func (d *Discoverer) loadAndRenderValues(valuesPath string) (map[string]interface{}, error) {
    // 1. values 파일 읽기
    data, err := os.ReadFile(valuesPath)
    if err != nil {
        return nil, err
    }

    // 2. .gotmpl 파일이면 Go template 렌더링
    if strings.HasSuffix(valuesPath, ".gotmpl") {
        // 환경 values 로드
        envValues, err := d.loadEnvironmentValues()
        if err != nil {
            return nil, err
        }

        // Template 렌더링
        rendered, err := d.renderGoTemplate(string(data), envValues)
        if err != nil {
            return nil, err
        }
        data = []byte(rendered)
    }

    // 3. YAML 파싱
    var values map[string]interface{}
    if err := yaml.Unmarshal(data, &values); err != nil {
        return nil, err
    }

    return values, nil
}
```

**검증**:
```bash
# Astrago 이미지 추출 테스트
./extract-images --helmfile ../../helmfile/helmfile.yaml.gotmpl -e default | grep "ghcr.io/xiilab/astrago"

# 예상 출력:
# ghcr.io/xiilab/astrago-backend:batch-stage-1.0-b506f250
# ghcr.io/xiilab/astrago-backend:core-stage-1.0-b506f250
# ghcr.io/xiilab/astrago-backend:monitor-stage-1.0-b506f250
# ghcr.io/xiilab/astrago-frontend:frontend-stage-1.0-0b7146d6
```

---

##### Afternoon Session (13:00-17:00): Gap #2 - 중첩 Values 재귀 탐색

**작업 내용**:
```go
// pkg/patterns/recursive.go (신규 생성)

// ExtractImagesRecursive는 중첩 구조를 재귀적으로 탐색하여 이미지를 추출합니다
func ExtractImagesRecursive(data interface{}, depth int, maxDepth int) []string {
    if depth > maxDepth {
        return nil
    }

    var images []string

    switch v := data.(type) {
    case map[string]interface{}:
        // 현재 레벨에서 이미지 패턴 체크
        if img := tryExtractImage(v); img != "" {
            images = append(images, img)
        }

        // 재귀적으로 하위 레벨 탐색
        for _, value := range v {
            childImages := ExtractImagesRecursive(value, depth+1, maxDepth)
            images = append(images, childImages...)
        }

    case []interface{}:
        // 배열의 각 항목 탐색
        for _, item := range v {
            childImages := ExtractImagesRecursive(item, depth+1, maxDepth)
            images = append(images, childImages...)
        }
    }

    return images
}
```

**configs/operators.yaml 업데이트**:
```yaml
gpu-operator:
  enabled: true
  images:
    # 기존 2-depth 경로
    - path: operator.repository
      tag_path: operator.version
    - path: driver.repository
      tag_path: driver.version
    # 신규 3-4 depth 경로 추가
    - path: driver.manager.image.repository
      tag_path: driver.manager.image.tag
    - path: toolkit.image.repository
      tag_path: toolkit.image.tag
    - path: devicePlugin.image.repository
      tag_path: devicePlugin.image.tag
    - path: dcgmExporter.image.repository
      tag_path: dcgmExporter.image.tag
    - path: migManager.image.repository
      tag_path: migManager.image.tag
    - path: validator.driver.image.repository
      tag_path: validator.driver.image.tag
```

**검증**:
```bash
# GPU Operator 이미지 추출 테스트
./extract-images --helmfile ../../helmfile/helmfile.yaml.gotmpl | grep "nvcr.io/nvidia"

# 예상 출력 (6개 추가):
# nvcr.io/nvidia/cloud-native/vgpu-device-manager:v0.2.4
# nvcr.io/nvidia/k8s/container-toolkit:v1.14.6-ubuntu20.04
# nvcr.io/nvidia/cloud-native/dcgm:3.3.5-1-ubuntu22.04
# nvcr.io/nvidia/k8s-device-plugin:v0.14.5
# nvcr.io/nvidia/cloud-native/k8s-mig-manager:v0.5.5-ubuntu20.04
# nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04
```

---

#### Day 5 (09:00-17:00): P1/P2 이슈 해결 및 최종 검증

##### Morning Session (09:00-12:00): Gap #3 & #4 - Harbor 및 Operator 패턴

**configs/operators.yaml에 추가**:
```yaml
# Harbor - 모든 컴포넌트 매핑
harbor:
  enabled: true
  images:
    # 기존 설정 유지
    - path: core.image.repository
      tag_path: core.image.tag
    - path: portal.image.repository
      tag_path: portal.image.tag
    # 신규 컴포넌트 추가
    - path: database.internal.image.repository
      tag_path: database.internal.image.tag
    - path: redis.internal.image.repository
      tag_path: redis.internal.image.tag
    - path: registry.registry.image.repository
      tag_path: registry.registry.image.tag
    - path: registry.controller.image.repository
      tag_path: registry.controller.image.tag
    - path: jobservice.image.repository
      tag_path: jobservice.image.tag
    - path: exporter.image.repository
      tag_path: exporter.image.tag
    - path: nginx.image.repository
      tag_path: nginx.image.tag

# Calico
calico:
  enabled: true
  aliases: ["tigera-operator"]
  images:
    - path: node.image
      tag_path: node.tag
    - path: cni.image
      tag_path: cni.tag
    - path: kubeControllers.image
      tag_path: kubeControllers.tag

# cert-manager
cert-manager:
  enabled: true
  images:
    - path: image.repository
      tag_path: image.tag
    - path: webhook.image.repository
      tag_path: webhook.image.tag
    - path: cainjector.image.repository
      tag_path: cainjector.image.tag

# MPI Operator (기존 설정 보강)
mpi-operator:
  enabled: true
  images:
    - path: image.repository
      tag_path: image.tag
    - path: kubectlDeliveryImage
      tag_path: kubectlDeliveryImageTag
```

---

##### Afternoon Session (13:00-17:00): Gap #5 - Regex 패턴 확장 및 최종 검증

**pkg/patterns/patterns.go 업데이트**:
```go
// ExtractFromManifest - 확장된 이미지 필드 패턴
func ExtractFromManifest(manifest string) []string {
    images := make(map[string]bool)

    // 패턴 1: 표준 image: 필드
    imageRegex1 := regexp.MustCompile(`(?m)^\s*image:\s*["']?([^\s"']+)["']?`)

    // 패턴 2: 확장 필드 (themeImage, configReloaderImage 등)
    imageRegex2 := regexp.MustCompile(`(?m)^\s*\w*[Ii]mage:\s*["']?([^\s"']+)["']?`)

    // 패턴 3: repository + tag 조합
    repoTagRegex := regexp.MustCompile(`(?m)^\s*repository:\s*["']?([^\s"']+)["']?.*\n.*tag:\s*["']?([^\s"']+)["']?`)

    // 모든 패턴 적용
    for _, regex := range []*regexp.Regexp{imageRegex1, imageRegex2} {
        matches := regex.FindAllStringSubmatch(manifest, -1)
        for _, match := range matches {
            if len(match) > 1 && isValidImage(match[1]) {
                images[match[1]] = true
            }
        }
    }

    // repository + tag 조합 처리
    matches := repoTagRegex.FindAllStringSubmatch(manifest, -1)
    for _, match := range matches {
        if len(match) == 3 {
            img := fmt.Sprintf("%s:%s", match[1], match[2])
            if isValidImage(img) {
                images[img] = true
            }
        }
    }

    result := make([]string, 0, len(images))
    for img := range images {
        result = append(result, img)
    }
    return result
}
```

**최종 검증**:
```bash
# 1. 전체 이미지 추출
./extract-images \
    --helmfile ../../helmfile/helmfile.yaml.gotmpl \
    --environment default \
    --output /tmp/final-test.txt

# 2. 커버리지 계산
TOTAL_IMAGES=61
EXTRACTED=$(wc -l < /tmp/final-test.txt)
COVERAGE=$(awk "BEGIN {printf \"%.1f\", ($EXTRACTED/$TOTAL_IMAGES)*100}")

echo "📊 최종 커버리지: $COVERAGE% ($EXTRACTED/$TOTAL_IMAGES)"

# 3. 목표 달성 확인 (95% = 58개 이상)
if [ "$EXTRACTED" -ge 58 ]; then
    echo "✅ 커버리지 목표 달성!"
else
    echo "❌ 커버리지 부족: $(($EXTRACTED - 58))개 추가 필요"
fi

# 4. 누락 이미지 재확인
kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u > /tmp/cluster-images.txt
comm -23 /tmp/cluster-images.txt /tmp/final-test.txt | grep -v "registry.k8s.io" > /tmp/still-missing.txt

echo "🔍 여전히 누락된 이미지: $(wc -l < /tmp/still-missing.txt)개"
cat /tmp/still-missing.txt
```

---

### Phase 0 최종 완료 기준 (Day 5 종료 시점)

**Critical Fixes (Day 1-3)**:
- [ ] **빌드 성공**: 모든 플랫폼에서 빌드 성공
- [ ] **테스트 통과**: 모든 단위 테스트 통과
- [ ] **통합 테스트 성공**: 실제 helmfile.yaml로 이미지 추출 성공
- [ ] **문서 업데이트**: 3개 문서 모두 v2.0.0으로 통일
- [ ] **검증 완료**: 5가지 검증 항목 모두 통과

**Gap Analysis 해결 (Day 4-5)**:
- [ ] **Go Template 변수 해석**: Astrago 이미지 6개 추출 성공
- [ ] **중첩 Values 탐색**: GPU Operator 이미지 6개 추출 성공
- [ ] **Harbor 컴포넌트**: Harbor 이미지 10개 추출 성공
- [ ] **Operator 패턴**: Calico, cert-manager, MPI 이미지 7개 추출 성공
- [ ] **Regex 확장**: 비표준 필드 이미지 4개 추출 성공
- [ ] **최종 커버리지**: 95% 이상 (58/61개 이상) 달성
- [ ] **문서 업데이트**: Gap Analysis 결과 반영 완료

---

## 🏗️ Phase 1: 핵심 기능 구현 (Week 1-2)

**목표**: MVP (Minimum Viable Product) 개발
**기간**: 2주 (10 업무일)
**담당**: 개발 팀
**우선순위**: P1

### Week 1: 기본 아키텍처 구현

#### Day 1-2 (Week 1): Application Layer 구현

**작업 내용**:
```go
// cmd/extractor/main.go

var rootCmd = &cobra.Command{
    Use:   "extract-images",
    Short: "Helm 차트에서 컨테이너 이미지 추출",
    Long: `Helmfile 기반 Helm 차트에서 컨테이너 이미지를 추출합니다.
오프라인 배포를 위한 이미지 리스트를 생성합니다.`,
    RunE: run,
}

func init() {
    // 필수 플래그
    rootCmd.Flags().StringP("helmfile", "f", "", "Helmfile 경로 (필수)")
    rootCmd.MarkFlagRequired("helmfile")

    // 선택 플래그
    rootCmd.Flags().StringP("environment", "e", "default", "Helmfile 환경")
    rootCmd.Flags().StringP("output", "o", "kubespray-offline/imagelists/astrago.txt", "출력 파일")
    rootCmd.Flags().StringP("format", "F", "text", "출력 형식 (text|json|yaml)")
    rootCmd.Flags().BoolP("verbose", "v", false, "상세 로그 출력")
    rootCmd.Flags().BoolP("parallel", "p", true, "병렬 처리 활성화")
    rootCmd.Flags().IntP("workers", "w", 5, "병렬 워커 수")
    
    // Deprecated 플래그 (하위 호환성)
    rootCmd.Flags().Bool("json", false, "JSON 형식 출력 (deprecated: use --format json)")
}

func run(cmd *cobra.Command, args []string) error {
    // Config 생성
    cfg := buildConfig(cmd)

    // Discovery 생성
    discoverer := discovery.New(cfg)

    // 차트 발견
    releases, err := discoverer.Discover(cmd.Context())
    if err != nil {
        return fmt.Errorf("차트 발견 실패: %w", err)
    }

    // Renderer 생성
    renderer := renderer.New(cfg)

    // Extractor 생성
    extractor := extractor.New(cfg)

    // 이미지 추출
    images, err := extractor.Extract(cmd.Context(), releases, renderer)
    if err != nil {
        return fmt.Errorf("이미지 추출 실패: %w", err)
    }

    // 결과 출력
    writer := writer.New(cfg)
    if err := writer.Write(images); err != nil {
        return fmt.Errorf("출력 실패: %w", err)
    }

    return nil
}
```

**검증 기준**:
- [ ] CLI 플래그 파싱 성공
- [ ] Config 생성 및 검증 성공
- [ ] 기본 실행 흐름 동작

---

#### Day 3-4 (Week 1): Core Layer - Discovery 구현

**작업 내용**:
```go
// internal/discovery/discovery.go

type Discoverer struct {
    config *config.Config
    logger *zerolog.Logger
}

func New(cfg *config.Config) *Discoverer {
    logger := zerolog.New(os.Stderr).With().Timestamp().Logger()
    if !cfg.Verbose {
        logger = logger.Level(zerolog.WarnLevel)
    }
    
    return &Discoverer{
        config: cfg,
        logger: &logger,
    }
}

func (d *Discoverer) Discover(ctx context.Context) ([]*Release, error) {
    d.logger.Info().Str("helmfile", d.config.HelmfilePath).Msg("Helmfile 파싱 시작")

    // Helmfile 파싱
    releases, err := d.parseHelmfile()
    if err != nil {
        return nil, err
    }

    d.logger.Info().Int("count", len(releases)).Msg("릴리즈 발견 완료")

    // Values 로드 (병렬)
    var wg sync.WaitGroup
    sem := make(chan struct{}, d.config.Workers)
    
    for i := range releases {
        wg.Add(1)
        go func(release *Release) {
            defer wg.Done()
            sem <- struct{}{}
            defer func() { <-sem }()

            values, err := d.loadReleaseValues(*release)
            if err != nil {
                d.logger.Warn().Err(err).Str("release", release.Name).Msg("Values 로드 실패")
                return
            }
            
            release.MergedValues = values
        }(&releases[i])
    }
    
    wg.Wait()

    return releases, nil
}
```

**검증 기준**:
- [ ] Helmfile 파싱 성공 (helmfile list --output json)
- [ ] Release 구조체 생성 성공
- [ ] Values 병합 로직 동작
- [ ] 병렬 처리 동작 확인

---

#### Day 5 (Week 1): Core Layer - Renderer 구현

**작업 내용**:
```go
// internal/renderer/renderer.go

type Renderer struct {
    config     *config.Config
    helmConfig *action.Configuration
    valueOpts  *values.Options
    logger     *zerolog.Logger
}

func (r *Renderer) Render(ctx context.Context, release *discovery.Release) (string, error) {
    r.logger.Info().
        Str("release", release.Name).
        Str("chart", release.Chart).
        Msg("차트 렌더링 시작")

    // action.Install 생성
    install := action.NewInstall(r.helmConfig)
    install.DryRun = true
    install.ClientOnly = true
    install.ReleaseName = release.Name
    install.Namespace = release.Namespace

    // Chart 로드
    chartPath, err := install.LocateChart(release.Chart, r.config.Settings)
    if err != nil {
        return "", fmt.Errorf("chart locate 실패: %w", err)
    }

    chart, err := loader.Load(chartPath)
    if err != nil {
        return "", fmt.Errorf("chart load 실패: %w", err)
    }

    // 렌더링
    rel, err := install.Run(chart, release.MergedValues)
    if err != nil {
        return "", fmt.Errorf("rendering 실패: %w", err)
    }

    r.logger.Info().
        Str("release", release.Name).
        Int("manifest_size", len(rel.Manifest)).
        Msg("렌더링 완료")

    return rel.Manifest, nil
}
```

**검증 기준**:
- [ ] Helm SDK action.Install 동작
- [ ] Chart 로드 성공
- [ ] Manifest 렌더링 성공
- [ ] DryRun 모드 검증

---

### Week 2: 이미지 추출 및 출력 구현

#### Day 6-7 (Week 2): Core Layer - Extractor 구현

**작업 내용**:
```go
// internal/extractor/extractor.go

type Extractor struct {
    config   *config.Config
    patterns []*regexp.Regexp
    logger   *zerolog.Logger
}

func New(cfg *config.Config) *Extractor {
    patterns := []*regexp.Regexp{
        // Pattern 1: repository/image:tag
        regexp.MustCompile(`(?m)^\s*image:\s*"?([a-zA-Z0-9\-._/]+:[a-zA-Z0-9\-._]+)"?`),
        // Pattern 2: repository: + tag:
        regexp.MustCompile(`(?m)^\s*repository:\s*"?([a-zA-Z0-9\-._/]+)"?.*\n.*tag:\s*"?([a-zA-Z0-9\-._]+)"?`),
        // Pattern 3: registry + image + tag
        regexp.MustCompile(`(?m)^\s*registry:\s*"?([a-zA-Z0-9\-._]+)"?.*\n.*image:\s*"?([a-zA-Z0-9\-._/]+)"?.*\n.*tag:\s*"?([a-zA-Z0-9\-._]+)"?`),
    }

    logger := zerolog.New(os.Stderr).With().Timestamp().Logger()
    if !cfg.Verbose {
        logger = logger.Level(zerolog.WarnLevel)
    }

    return &Extractor{
        config:   cfg,
        patterns: patterns,
        logger:   &logger,
    }
}

func (e *Extractor) Extract(ctx context.Context, releases []*discovery.Release, renderer *renderer.Renderer) ([]string, error) {
    imageSet := make(map[string]struct{})
    var mu sync.Mutex

    // 병렬 처리
    var wg sync.WaitGroup
    sem := make(chan struct{}, e.config.Workers)

    for _, release := range releases {
        wg.Add(1)
        go func(rel *discovery.Release) {
            defer wg.Done()
            sem <- struct{}{}
            defer func() { <-sem }()

            // 렌더링
            manifest, err := renderer.Render(ctx, rel)
            if err != nil {
                e.logger.Warn().Err(err).Str("release", rel.Name).Msg("렌더링 실패")
                return
            }

            // 이미지 추출
            images := e.extractFromManifest(manifest)

            // 결과 병합
            mu.Lock()
            for _, img := range images {
                imageSet[img] = struct{}{}
            }
            mu.Unlock()

            e.logger.Info().
                Str("release", rel.Name).
                Int("images", len(images)).
                Msg("이미지 추출 완료")
        }(release)
    }

    wg.Wait()

    // Set to Slice
    images := make([]string, 0, len(imageSet))
    for img := range imageSet {
        images = append(images, img)
    }

    // 정렬
    sort.Strings(images)

    e.logger.Info().Int("total", len(images)).Msg("전체 이미지 추출 완료")

    return images, nil
}

func (e *Extractor) extractFromManifest(manifest string) []string {
    var images []string

    for _, pattern := range e.patterns {
        matches := pattern.FindAllStringSubmatch(manifest, -1)
        for _, match := range matches {
            if len(match) > 1 {
                // Pattern에 따라 이미지 조합
                img := e.buildImageString(match)
                if img != "" {
                    images = append(images, img)
                }
            }
        }
    }

    return images
}

func (e *Extractor) buildImageString(match []string) string {
    // match[0]: 전체 매치
    // match[1:]: 캡처 그룹들
    
    if len(match) == 2 {
        // Pattern 1: repository/image:tag
        return match[1]
    } else if len(match) == 3 {
        // Pattern 2: repository + tag
        return fmt.Sprintf("%s:%s", match[1], match[2])
    } else if len(match) == 4 {
        // Pattern 3: registry + image + tag
        return fmt.Sprintf("%s/%s:%s", match[1], match[2], match[3])
    }

    return ""
}
```

**검증 기준**:
- [ ] 정규식 패턴 매칭 동작
- [ ] 3가지 이미지 패턴 모두 추출
- [ ] 중복 제거 동작
- [ ] 병렬 처리 동작

---

#### Day 8-9 (Week 2): Data Layer - Writer 구현

**작업 내용**:
```go
// internal/writer/writer.go

type Writer struct {
    config *config.Config
    logger *zerolog.Logger
}

func (w *Writer) Write(images []string) error {
    // 출력 디렉토리 생성
    if err := w.ensureOutputDir(); err != nil {
        return err
    }

    // Format에 따른 출력
    switch w.config.Format {
    case "text":
        return w.writeText(images)
    case "json":
        return w.writeJSON(images)
    case "yaml":
        return w.writeYAML(images)
    default:
        return fmt.Errorf("unsupported format: %s", w.config.Format)
    }
}

func (w *Writer) writeText(images []string) error {
    f, err := os.Create(w.config.OutputPath)
    if err != nil {
        return fmt.Errorf("파일 생성 실패: %w", err)
    }
    defer f.Close()

    for _, img := range images {
        if _, err := fmt.Fprintln(f, img); err != nil {
            return fmt.Errorf("쓰기 실패: %w", err)
        }
    }

    w.logger.Info().
        Str("path", w.config.OutputPath).
        Int("images", len(images)).
        Msg("Text 형식 출력 완료")

    return nil
}

func (w *Writer) writeJSON(images []string) error {
    type Output struct {
        Images []ImageInfo `json:"images"`
    }

    type ImageInfo struct {
        Registry   string `json:"registry"`
        Repository string `json:"repository"`
        Tag        string `json:"tag"`
        Full       string `json:"full"`
    }

    output := Output{Images: make([]ImageInfo, 0, len(images))}

    for _, img := range images {
        info := w.parseImageString(img)
        output.Images = append(output.Images, info)
    }

    data, err := json.MarshalIndent(output, "", "  ")
    if err != nil {
        return fmt.Errorf("JSON 마샬링 실패: %w", err)
    }

    if err := os.WriteFile(w.config.OutputPath, data, 0644); err != nil {
        return fmt.Errorf("파일 쓰기 실패: %w", err)
    }

    w.logger.Info().
        Str("path", w.config.OutputPath).
        Int("images", len(images)).
        Msg("JSON 형식 출력 완료")

    return nil
}

func (w *Writer) parseImageString(img string) ImageInfo {
    // registry/repository:tag 파싱
    parts := strings.Split(img, "/")
    
    var registry, repository, tag string
    
    if len(parts) == 1 {
        // image:tag
        repoTag := strings.Split(parts[0], ":")
        repository = repoTag[0]
        if len(repoTag) > 1 {
            tag = repoTag[1]
        }
    } else if len(parts) == 2 {
        // registry/image:tag
        registry = parts[0]
        repoTag := strings.Split(parts[1], ":")
        repository = repoTag[0]
        if len(repoTag) > 1 {
            tag = repoTag[1]
        }
    } else {
        // registry/namespace/image:tag
        registry = parts[0]
        repoTag := strings.Split(parts[len(parts)-1], ":")
        repository = strings.Join(parts[1:len(parts)-1], "/") + "/" + repoTag[0]
        if len(repoTag) > 1 {
            tag = repoTag[1]
        }
    }

    return ImageInfo{
        Registry:   registry,
        Repository: repository,
        Tag:        tag,
        Full:       img,
    }
}
```

**검증 기준**:
- [ ] Text 형식 출력 성공
- [ ] JSON 형식 출력 성공
- [ ] YAML 형식 출력 성공
- [ ] 이미지 파싱 정확성 검증

---

#### Day 10 (Week 2): 통합 테스트 및 Week 2 마무리

**작업 내용**:
```bash
# 1. 전체 통합 테스트
make test-integration

# 2. 실제 환경 테스트
./extract-images \
    --helmfile ../../helmfile/helmfile.yaml.gotmpl \
    --environment default \
    --output /tmp/astrago-images.txt \
    --verbose

# 3. 성능 테스트
time ./extract-images \
    --helmfile ../../helmfile/helmfile.yaml.gotmpl \
    --environment default \
    --workers 10

# 4. 출력 검증
wc -l /tmp/astrago-images.txt  # 이미지 개수
head -n 10 /tmp/astrago-images.txt  # 샘플 확인
```

**Phase 1 완료 기준**:
- [ ] 모든 레이어 구현 완료
- [ ] 기본 기능 동작 (이미지 추출)
- [ ] 3가지 출력 형식 지원
- [ ] 병렬 처리 동작
- [ ] 실제 helmfile로 테스트 성공

---

## 🧪 Phase 2: 테스트 및 검증 (Week 3)

**목표**: 품질 확보 및 안정성 검증
**기간**: 1주 (5 업무일)
**담당**: QA 팀 + 개발 팀
**우선순위**: P1

### Day 11-12: 단위 테스트 작성 (목표 커버리지 80%+)

#### Discovery Layer 테스트

```go
// internal/discovery/discovery_test.go

func TestParseHelmfile(t *testing.T) {
    tests := []struct {
        name        string
        helmfile    string
        environment string
        wantCount   int
        wantErr     bool
    }{
        {
            name:        "기본 helmfile",
            helmfile:    "testdata/helmfile.yaml",
            environment: "default",
            wantCount:   5,
            wantErr:     false,
        },
        {
            name:        "존재하지 않는 파일",
            helmfile:    "nonexistent.yaml",
            environment: "default",
            wantCount:   0,
            wantErr:     true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            cfg := &config.Config{
                HelmfilePath: tt.helmfile,
                Environment:  tt.environment,
            }
            
            d := New(cfg)
            releases, err := d.parseHelmfile()

            if (err != nil) != tt.wantErr {
                t.Errorf("parseHelmfile() error = %v, wantErr %v", err, tt.wantErr)
                return
            }

            if len(releases) != tt.wantCount {
                t.Errorf("parseHelmfile() count = %d, want %d", len(releases), tt.wantCount)
            }
        })
    }
}

func TestLoadReleaseValues(t *testing.T) {
    // Values 병합 테스트
    tests := []struct {
        name      string
        release   Release
        wantKey   string
        wantValue interface{}
    }{
        {
            name: "단일 values 파일",
            release: Release{
                Values: []string{"testdata/values.yaml"},
            },
            wantKey:   "image.repository",
            wantValue: "nginx",
        },
        {
            name: "다중 values 병합",
            release: Release{
                Values: []string{
                    "testdata/values-base.yaml",
                    "testdata/values-override.yaml",
                },
            },
            wantKey:   "image.tag",
            wantValue: "1.21",  // override 값
        },
    }

    // 테스트 구현...
}
```

#### Extractor Layer 테스트

```go
// internal/extractor/extractor_test.go

func TestExtractFromManifest(t *testing.T) {
    tests := []struct {
        name     string
        manifest string
        want     []string
    }{
        {
            name: "단일 이미지",
            manifest: `
apiVersion: v1
kind: Pod
metadata:
  name: test
spec:
  containers:
  - image: nginx:1.21
    name: nginx
`,
            want: []string{"nginx:1.21"},
        },
        {
            name: "repository + tag 분리",
            manifest: `
image:
  repository: redis
  tag: "6.2"
`,
            want: []string{"redis:6.2"},
        },
        {
            name: "registry + repository + tag",
            manifest: `
registry: gcr.io
image: my-app/backend
tag: v1.0.0
`,
            want: []string{"gcr.io/my-app/backend:v1.0.0"},
        },
    }

    cfg := &config.Config{}
    e := New(cfg)

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := e.extractFromManifest(tt.manifest)
            if !reflect.DeepEqual(got, tt.want) {
                t.Errorf("extractFromManifest() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

**Day 11-12 완료 기준**:
- [ ] Discovery 테스트 커버리지 > 80%
- [ ] Renderer 테스트 커버리지 > 70%
- [ ] Extractor 테스트 커버리지 > 90%
- [ ] Writer 테스트 커버리지 > 80%

---

### Day 13-14: 통합 테스트 및 E2E 테스트

#### E2E 테스트 시나리오

```bash
#!/bin/bash
# test/e2e/test_full_workflow.sh

set -e

echo "🧪 E2E 테스트 시작"

# 1. 기본 실행
echo "Test 1: 기본 실행"
./extract-images \
    --helmfile test/fixtures/helmfile.yaml \
    --environment default \
    --output /tmp/test1.txt

# 검증
if [ ! -f /tmp/test1.txt ]; then
    echo "❌ 출력 파일 생성 실패"
    exit 1
fi

IMAGE_COUNT=$(wc -l < /tmp/test1.txt)
if [ "$IMAGE_COUNT" -lt 10 ]; then
    echo "❌ 이미지 개수 부족: $IMAGE_COUNT"
    exit 1
fi

echo "✅ Test 1 통과: $IMAGE_COUNT 개 이미지 추출"

# 2. JSON 형식
echo "Test 2: JSON 형식"
./extract-images \
    --helmfile test/fixtures/helmfile.yaml \
    --environment default \
    --format json \
    --output /tmp/test2.json

# JSON 검증
if ! jq . /tmp/test2.json > /dev/null 2>&1; then
    echo "❌ JSON 파싱 실패"
    exit 1
fi

echo "✅ Test 2 통과: JSON 형식 출력 성공"

# 3. YAML 형식
echo "Test 3: YAML 형식"
./extract-images \
    --helmfile test/fixtures/helmfile.yaml \
    --environment default \
    --format yaml \
    --output /tmp/test3.yaml

# YAML 검증
if ! yq eval . /tmp/test3.yaml > /dev/null 2>&1; then
    echo "❌ YAML 파싱 실패"
    exit 1
fi

echo "✅ Test 3 통과: YAML 형식 출력 성공"

# 4. 병렬 처리
echo "Test 4: 병렬 처리"
time ./extract-images \
    --helmfile test/fixtures/helmfile.yaml \
    --environment default \
    --workers 10 \
    --output /tmp/test4.txt

echo "✅ Test 4 통과: 병렬 처리 성공"

# 5. 에러 케이스
echo "Test 5: 에러 케이스"
if ./extract-images --helmfile nonexistent.yaml 2>/dev/null; then
    echo "❌ 에러 처리 실패"
    exit 1
fi

echo "✅ Test 5 통과: 에러 처리 정상"

echo "🎉 모든 E2E 테스트 통과"
```

**Day 13-14 완료 기준**:
- [ ] E2E 테스트 스크립트 작성
- [ ] 모든 시나리오 통과
- [ ] 에러 케이스 검증
- [ ] 성능 기준 만족 (< 1초)

---

### Day 15: 보안 검증 및 Week 3 마무리

#### 보안 체크리스트

```bash
# 1. 정적 분석
gosec ./...

# 2. 의존성 취약점 검사
go list -json -m all | nancy sleuth

# 3. 경로 검증
# internal/validator/validator.go 구현 검증
go test -v ./internal/validator/...

# 4. 입력 검증
# - Helmfile 경로 검증
# - 환경 변수 검증
# - 출력 경로 검증
```

**보안 검증 항목**:
- [ ] Path Traversal 방어 구현
- [ ] 입력 검증 로직 구현
- [ ] 의존성 취약점 없음
- [ ] 정적 분석 통과

---

## ⚡ Phase 3: 최적화 (Week 4)

**목표**: 성능 목표 달성 (50개 차트 < 1초)
**기간**: 1주 (5 업무일)
**담당**: 개발 팀
**우선순위**: P2

### Day 16-17: 성능 프로파일링

```bash
# 1. CPU 프로파일링
go test -cpuprofile=cpu.prof -bench=. ./internal/extractor

# 2. 메모리 프로파일링
go test -memprofile=mem.prof -bench=. ./internal/extractor

# 3. 프로파일 분석
go tool pprof -http=:8080 cpu.prof
go tool pprof -http=:8081 mem.prof

# 4. 벤치마크
go test -bench=. -benchmem ./...
```

**최적화 대상 식별**:
- [ ] CPU 병목 지점 식별
- [ ] 메모리 할당 병목 식별
- [ ] I/O 대기 시간 측정
- [ ] 병렬화 효율 측정

---

### Day 18-19: 병렬 처리 최적화

```go
// internal/extractor/parallel.go

type WorkerPool struct {
    workers   int
    taskQueue chan *Task
    results   chan *Result
    wg        sync.WaitGroup
}

func NewWorkerPool(workers int) *WorkerPool {
    return &WorkerPool{
        workers:   workers,
        taskQueue: make(chan *Task, workers*2),
        results:   make(chan *Result, workers*2),
    }
}

func (p *WorkerPool) Start(ctx context.Context) {
    for i := 0; i < p.workers; i++ {
        p.wg.Add(1)
        go p.worker(ctx)
    }
}

func (p *WorkerPool) worker(ctx context.Context) {
    defer p.wg.Done()

    for {
        select {
        case <-ctx.Done():
            return
        case task, ok := <-p.taskQueue:
            if !ok {
                return
            }
            
            result := p.processTask(task)
            p.results <- result
        }
    }
}

func (p *WorkerPool) Submit(task *Task) {
    p.taskQueue <- task
}

func (p *WorkerPool) Wait() {
    close(p.taskQueue)
    p.wg.Wait()
    close(p.results)
}
```

**최적화 목표**:
- [ ] 워커 풀 구현
- [ ] 작업 큐 최적화
- [ ] 컨텍스트 기반 취소 지원
- [ ] 성능 목표 달성 (< 1초)

---

### Day 20: 캐싱 및 메모리 최적화

```go
// internal/cache/cache.go

type Cache struct {
    mu    sync.RWMutex
    data  map[string]*CacheEntry
    maxSize int
}

type CacheEntry struct {
    Value      interface{}
    Expiry     time.Time
    AccessTime time.Time
}

func NewCache(maxSize int) *Cache {
    return &Cache{
        data:    make(map[string]*CacheEntry),
        maxSize: maxSize,
    }
}

func (c *Cache) Get(key string) (interface{}, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()

    entry, ok := c.data[key]
    if !ok {
        return nil, false
    }

    // 만료 확인
    if time.Now().After(entry.Expiry) {
        delete(c.data, key)
        return nil, false
    }

    // 접근 시간 업데이트
    entry.AccessTime = time.Now()

    return entry.Value, true
}

func (c *Cache) Set(key string, value interface{}, ttl time.Duration) {
    c.mu.Lock()
    defer c.mu.Unlock()

    // 캐시 크기 제한
    if len(c.data) >= c.maxSize {
        c.evict()
    }

    c.data[key] = &CacheEntry{
        Value:      value,
        Expiry:     time.Now().Add(ttl),
        AccessTime: time.Now(),
    }
}

func (c *Cache) evict() {
    // LRU 방식으로 제거
    var oldestKey string
    var oldestTime time.Time

    for key, entry := range c.data {
        if oldestTime.IsZero() || entry.AccessTime.Before(oldestTime) {
            oldestKey = key
            oldestTime = entry.AccessTime
        }
    }

    if oldestKey != "" {
        delete(c.data, oldestKey)
    }
}
```

**최적화 항목**:
- [ ] Chart 캐싱 구현
- [ ] Values 캐싱 구현
- [ ] Manifest 캐싱 구현
- [ ] LRU 방식 구현

---

## 📚 Phase 4: 문서화 및 배포 준비 (Week 5)

**목표**: 프로덕션 준비 완료
**기간**: 1주 (5 업무일)
**담당**: 개발 팀 + 문서 팀
**우선순위**: P1

### Day 21-22: 사용자 문서 작성

#### README.md 업데이트

```markdown
# Astrago Helm Chart Image Extractor

Helmfile 기반 Helm 차트에서 컨테이너 이미지를 자동으로 추출하는 도구입니다.
오프라인/에어갭 Kubernetes 환경 배포를 위한 이미지 리스트를 생성합니다.

## 🚀 주요 기능

- ✅ Helmfile 자동 파싱 및 차트 발견
- ✅ Helm SDK 기반 차트 렌더링 (95%+ 커버리지)
- ✅ 병렬 처리로 빠른 실행 (50개 차트 < 1초)
- ✅ 다양한 출력 형식 (text, JSON, YAML)
- ✅ 중복 제거 및 정렬

## 📦 설치

### 바이너리 다운로드
```bash
# Linux (amd64)
wget https://github.com/astrago/image-extractor/releases/latest/download/extract-images-linux-amd64
chmod +x extract-images-linux-amd64
sudo mv extract-images-linux-amd64 /usr/local/bin/extract-images

# Linux (arm64)
wget https://github.com/astrago/image-extractor/releases/latest/download/extract-images-linux-arm64
chmod +x extract-images-linux-arm64
sudo mv extract-images-linux-arm64 /usr/local/bin/extract-images

# macOS (amd64)
wget https://github.com/astrago/image-extractor/releases/latest/download/extract-images-darwin-amd64
chmod +x extract-images-darwin-amd64
sudo mv extract-images-darwin-amd64 /usr/local/bin/extract-images

# macOS (arm64 / Apple Silicon)
wget https://github.com/astrago/image-extractor/releases/latest/download/extract-images-darwin-arm64
chmod +x extract-images-darwin-arm64
sudo mv extract-images-darwin-arm64 /usr/local/bin/extract-images
```

### 소스에서 빌드
```bash
git clone https://github.com/astrago/image-extractor.git
cd image-extractor
make build
```

## 🔧 사용법

### 기본 사용
```bash
extract-images --helmfile helmfile.yaml
```

### 고급 옵션
```bash
extract-images \
    --helmfile helmfile.yaml \
    --environment production \
    --output images.txt \
    --format text \
    --workers 10 \
    --verbose
```

### 출력 형식

**Text (기본)**:
```
nvcr.io/nvidia/driver:550.127.05
quay.io/prometheus/prometheus:v2.45.0
gcr.io/kaniko-project/executor:v1.9.0
```

**JSON**:
```json
{
  "images": [
    {
      "registry": "nvcr.io",
      "repository": "nvidia/driver",
      "tag": "550.127.05",
      "full": "nvcr.io/nvidia/driver:550.127.05"
    }
  ]
}
```

**YAML**:
```yaml
images:
  - registry: nvcr.io
    repository: nvidia/driver
    tag: 550.127.05
    full: nvcr.io/nvidia/driver:550.127.05
```

## 📖 문서

- [설치 가이드](docs/installation.md)
- [사용 가이드](docs/usage.md)
- [기술 명세서](docs/TECHNICAL_SPECIFICATION_V2.md)
- [아키텍처](docs/ARCHITECTURE.md)
- [문제 해결](docs/troubleshooting.md)

## 🤝 기여하기

기여는 언제나 환영합니다! [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요.

## 📄 라이선스

Apache License 2.0 - 자세한 내용은 [LICENSE](LICENSE)를 참조하세요.
```

---

### Day 23: API 문서 및 개발자 가이드

#### 개발자 가이드 작성

```markdown
# 개발자 가이드

## 아키텍처 개요

### 3-Layer 아키텍처

```
┌─────────────────────────────────────┐
│      Application Layer              │
│  - CLI Interface (Cobra)            │
│  - Configuration Management         │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│         Core Layer                  │
│  - Discovery (Helmfile 파싱)        │
│  - Renderer (Helm SDK)              │
│  - Extractor (정규식)                │
└─────────────────────────────────────┘
                 ↓
┌─��───────────────────────────────────┐
│        Data Layer                   │
│  - Parser (YAML)                    │
│  - Validator (보안)                  │
│  - Writer (출력)                     │
└─────────────────────────────────────┘
```

### 패키지 구조

```
cmd/extractor/          # CLI 진입점
internal/
  ├── config/          # 설정 관리
  ├── discovery/       # 차트 발견
  ├── renderer/        # 차트 렌더링
  ├── extractor/       # 이미지 추출
  ├── parser/          # YAML 파싱
  ├── validator/       # 입력 검증
  ├── writer/          # 출력 처리
  └── cache/           # 캐싱
```

## 개발 환경 설정

### 필수 도구
- Go 1.21+
- Make
- Docker (테스트용)
- Helmfile

### 개발 서버 실행
```bash
# 의존성 설치
make deps

# 빌드
make build

# 테스트
make test

# 린트
make lint
```

## 코드 스타일 가이드

### Go 코드 스타일
- [Effective Go](https://golang.org/doc/effective_go.html) 준수
- `gofmt` 사용
- `golangci-lint` 통과

### 커밋 메시지
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type**:
- feat: 새로운 기능
- fix: 버그 수정
- docs: 문서 변경
- test: 테스트 추가/수정
- refactor: 리팩토링

## 테스트 가이드

### 단위 테스트
```bash
go test -v ./internal/...
```

### 통합 테스트
```bash
make test-integration
```

### 커버리지
```bash
make coverage
```

## 릴리즈 프로세스

1. 버전 태그 생성: `git tag v1.0.0`
2. GitHub Actions 자동 빌드
3. 바이너리 업로드 및 릴리즈 노트 작성
```

---

### Day 24-25: CI/CD 파이프라인 구축

#### GitHub Actions 워크플로우

```yaml
# .github/workflows/ci.yml

name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Install dependencies
        run: |
          go mod download
          go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

      - name: Run tests
        run: make test

      - name: Run linter
        run: make lint

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.out

  build:
    name: Build
    runs-on: ubuntu-latest
    needs: test
    strategy:
      matrix:
        os: [linux, darwin]
        arch: [amd64, arm64]
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Build
        env:
          GOOS: ${{ matrix.os }}
          GOARCH: ${{ matrix.arch }}
        run: |
          make build
          mv bin/extract-images bin/extract-images-${{ matrix.os }}-${{ matrix.arch }}

      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: extract-images-${{ matrix.os }}-${{ matrix.arch }}
          path: bin/extract-images-${{ matrix.os }}-${{ matrix.arch }}
```

```yaml
# .github/workflows/release.yml

name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    name: Release
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Build all platforms
        run: make build-all

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            bin/extract-images-linux-amd64
            bin/extract-images-linux-arm64
            bin/extract-images-darwin-amd64
            bin/extract-images-darwin-arm64
          body: |
            ## Changes
            ${{ github.event.head_commit.message }}
            
            ## Installation
            Download the binary for your platform and run:
            ```bash
            chmod +x extract-images-<platform>-<arch>
            sudo mv extract-images-<platform>-<arch> /usr/local/bin/extract-images
            ```
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**CI/CD 완료 기준**:
- [ ] CI 파이프라인 구축 (테스트, 린트)
- [ ] 릴리즈 워크플로우 구축
- [ ] 자동 빌드 및 배포
- [ ] 코드 커버리지 리포팅

---

## 🔄 Phase 5: 예비 기간 및 리팩토링 (Week 6)

**목표**: 버퍼 기간 및 코드 품질 개선
**기간**: 1주 (5 업무일)
**담당**: 개발 팀
**우선순위**: P3

### Day 26-27: 코드 리뷰 및 리팩토링

**리팩토링 체크리스트**:
- [ ] 중복 코드 제거
- [ ] 함수 복잡도 감소 (cyclomatic complexity < 10)
- [ ] 변수/함수명 개선
- [ ] 주석 보완
- [ ] 에러 메시지 개선

---

### Day 28-29: 품질 개선 (Optional)

#### 개선 항목

**#1: Operator 이미지 외부화**
```yaml
# docs/data/operators/gpu-operator.yaml
images:
  - nvcr.io/nvidia/driver:550.127.05
  - nvcr.io/nvidia/k8s-device-plugin:v0.14.5
  - nvcr.io/nvidia/gpu-feature-discovery:v0.8.2
```

```go
// internal/extractor/operator.go

func (e *Extractor) loadOperatorImages() ([]string, error) {
    data, err := os.ReadFile("docs/data/operators/gpu-operator.yaml")
    if err != nil {
        return nil, err
    }

    var config struct {
        Images []string `yaml:"images"`
    }

    if err := yaml.Unmarshal(data, &config); err != nil {
        return nil, err
    }

    return config.Images, nil
}
```

**#2: 패턴 커버리지 보강**
- `global.image.registry` 지원
- `ephemeralContainers` 추출
- 중첩 키 강화

**#3: Digest/OCI 참조 지원**
```go
// 예: nginx@sha256:abc123...
func (e *Extractor) extractDigest(manifest string) []string {
    pattern := regexp.MustCompile(`image:\s*"?([a-zA-Z0-9\-._/]+@sha256:[a-f0-9]{64})"?`)
    // ... 구현
}
```

---

### Day 30: 최종 검증 및 배포

**최종 체크리스트**:
- [ ] 모든 테스트 통과 (단위, 통합, E2E)
- [ ] 커버리지 목표 달성 (80%+)
- [ ] 성능 목표 달성 (< 1초)
- [ ] 문서 완성도 검증
- [ ] CI/CD 파이프라인 동작
- [ ] 보안 검증 완료
- [ ] 릴리즈 노트 작성
- [ ] 프로덕션 배포

---

## 📊 프로젝트 관리

### 주간 체크포인트

**매주 금요일 17:00**: 주간 리뷰 미팅
- 완료된 작업 리뷰
- 다음 주 계획 수립
- 이슈 및 블로커 논의
- 타임라인 조정

### 리스크 관리

| 리스크 | 확률 | 영향도 | 대응 계획 |
|--------|------|--------|----------|
| Helmfile API 변경 | Low | High | 버전 고정 + 릴리즈 노트 모니터링 |
| 성능 목표 미달 | Medium | Medium | Phase 3에서 최적화 집중 |
| 테스트 커버리지 부족 | Low | Medium | Phase 2에서 TDD 강화 |
| 인력 부족 | Medium | High | Phase 5를 버퍼로 활용 |

### 커뮤니케이션 계획

**일일 스탠드업** (매일 10:00, 15분):
- 어제 완료한 작업
- 오늘 할 작업
- 블로커 및 이슈

**주간 리뷰** (매주 금요일 17:00, 1시간):
- 주간 진행 상황
- 타임라인 검토
- 다음 주 계획

**문서 공유**:
- Confluence/Notion에 진행 상황 실시간 업데이트
- GitHub Issues로 작업 추적
- Slack으로 즉각적인 소통

---

## 🎯 성공 지표

### 기능적 지표
- [ ] Helmfile 자동 파싱 성공률 > 99%
- [ ] 이미지 추출 커버리지 > 95%
- [ ] 중복 제거 정확도 100%
- [ ] 3가지 출력 형식 지원

### 비기능적 지표
- [ ] 실행 시간 < 1초 (50개 차트)
- [ ] 메모리 사용량 < 100MB
- [ ] 테스트 커버리지 > 80%
- [ ] 보안 취약점 0개

### 품질 지표
- [ ] 코드 리뷰 승인율 100%
- [ ] CI/CD 파이프라인 성공률 > 95%
- [ ] 문서 완성도 > 90%
- [ ] 사용자 만족도 > 4.0/5.0

---

## 📝 변경 이력

| 버전 | 날짜 | 작성자 | 변경 내용 |
|------|------|--------|----------|
| 1.0.0 | 2024-10-24 | System Architect | 초기 작성 |
| 1.0.1 | 2024-10-24 | System Architect | Phase 0 확장 (Day 1-3 → Day 1-5), Gap Analysis 해결 계획 추가 |

---

## 📚 참고 문서

- [TECHNICAL_SPECIFICATION_V2.md](./TECHNICAL_SPECIFICATION_V2.md) - 기술 명세서 v2.0.1
- [PHASE_0_CRITICAL_FIXES.md](./PHASE_0_CRITICAL_FIXES.md) - 구현 전 필수 수정 사항
- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) - 구현 계획 v2.0.0
- [ARCHITECTURE.md](./ARCHITECTURE.md) - 아키텍처 가이드 v2.0.0

---

**문의**: Astrago 개발팀
**라이선스**: Apache License 2.0
