# 📋 Astrago Helm Chart Image Extractor - 구현 계획서
> **Implementation Plan and Roadmap**
> Version 2.0.0 | 2024년 10월

## 📌 Executive Summary

본 문서는 **Astrago Helm Chart Image Extractor** 시스템의 단계적 구현 계획을 상세히 정의합니다.
전체 프로젝트는 5개 Phase로 구성되며, 약 4-6주의 개발 기간이 예상됩니다.

### 🎯 구현 목표
- **Phase 1-2**: 핵심 기능 구현 (2주)
- **Phase 3**: 보완 기능 추가 (1주)
- **Phase 4**: 성능 최적화 (1주)
- **Phase 5**: 배포 및 안정화 (1-2주)

### 📊 성공 지표
- ✅ 모든 차트에서 100% 이미지 추출
- ✅ 실행 시간 < 1초 (50개 차트 기준, 병렬 처리)
- ✅ 메모리 사용량 < 100MB
- ✅ Cross-platform 지원 (Linux/macOS)
- ✅ 제로 수동 설정

---

## 📅 Phase 1: Foundation (Week 1)
> **기반 구조 및 핵심 모듈 구현**

### 1.1 프로젝트 초기화

#### 작업 목록
```bash
# 1. 프로젝트 구조 생성
mkdir -p cmd/extractor
mkdir -p internal/{config,discovery,renderer,extractor,output}
mkdir -p pkg/{helm,utils,patterns}
mkdir -p test/{unit,integration,fixtures}
mkdir -p scripts/{build,test,release}
mkdir -p docs/{api,guides}

# 2. Go 모듈 초기화
go mod init github.com/astrago/helm-image-extractor
go get helm.sh/helm/v3@v3.14.0
go get github.com/spf13/cobra@v1.7.0
go get github.com/spf13/viper@v1.16.0
go get gopkg.in/yaml.v3@v3.0.1
go get github.com/rs/zerolog@v1.31.0

# 3. 개발 도구 설정
touch Makefile
touch .gitignore
touch .golangci.yml
touch .goreleaser.yaml
```

#### 구현 파일

**`cmd/extractor/main.go`**
```go
package main

import (
    "fmt"
    "os"

    "github.com/astrago/helm-image-extractor/internal/config"
    "github.com/astrago/helm-image-extractor/internal/discovery"
    "github.com/astrago/helm-image-extractor/internal/renderer"
    "github.com/astrago/helm-image-extractor/internal/extractor"
    "github.com/astrago/helm-image-extractor/internal/output"
    "github.com/spf13/cobra"
)

var (
    version = "dev"
    commit  = "none"
    date    = "unknown"
)

func main() {
    rootCmd := &cobra.Command{
        Use:   "extract-images",
        Short: "Astrago Helm Chart 이미지 추출기",
        Long: `Helm 차트에서 컨테이너 이미지를 자동으로 추출하여
오프라인 Kubernetes 배포를 위한 이미지 목록을 생성합니다.`,
        Version: fmt.Sprintf("%s (commit: %s, built: %s)", version, commit, date),
        RunE:    run,
    }

    // 플래그 정의
    rootCmd.Flags().StringP("helmfile", "f", "", "Helmfile 경로")
    rootCmd.Flags().StringP("environment", "e", "default", "Helmfile 환경")
    rootCmd.Flags().StringP("output", "o", "kubespray-offline/imagelists/astrago.txt", "출력 파일")
    rootCmd.Flags().StringP("format", "F", "text", "출력 형식 (text|json|yaml)")
    rootCmd.Flags().StringP("platform", "p", "", "플랫폼 (linux/amd64)")
    rootCmd.Flags().BoolP("verbose", "v", false, "상세 출력")
    rootCmd.Flags().Bool("json", false, "JSON 형식 출력 (deprecated: use --format json)")

    if err := rootCmd.Execute(); err != nil {
        fmt.Fprintf(os.Stderr, "Error: %v\n", err)
        os.Exit(1)
    }
}

func run(cmd *cobra.Command, args []string) error {
    // 1. 설정 로드
    cfg, err := config.Load(cmd)
    if err != nil {
        return fmt.Errorf("설정 로드 실패: %w", err)
    }

    // 2. 차트 발견
    discoverer := discovery.New(cfg)
    charts, err := discoverer.Discover()
    if err != nil {
        return fmt.Errorf("차트 발견 실패: %w", err)
    }

    // 3. 차트 렌더링
    renderer := renderer.New(cfg)
    manifests, err := renderer.RenderAll(charts)
    if err != nil {
        return fmt.Errorf("차트 렌더링 실패: %w", err)
    }

    // 4. 이미지 추출
    extractor := extractor.New(cfg)
    images, err := extractor.ExtractAll(manifests, charts)
    if err != nil {
        return fmt.Errorf("이미지 추출 실패: %w", err)
    }

    // 5. 결과 출력
    outputter := output.New(cfg)
    if err := outputter.Write(images); err != nil {
        return fmt.Errorf("출력 실패: %w", err)
    }

    return nil
}
```

### 1.2 Configuration 모듈

**`internal/config/config.go`**
```go
package config

import (
    "fmt"
    "os"
    "path/filepath"
    "runtime"

    "github.com/spf13/cobra"
    "github.com/spf13/viper"
)

type Config struct {
    // 경로 설정
    HelmfilePath   string `mapstructure:"helmfile_path"`
    ChartsPath     string `mapstructure:"charts_path"`
    Environment    string `mapstructure:"environment"`
    OutputPath     string `mapstructure:"output_path"`

    // 플랫폼 설정
    Platform struct {
        OS   string `mapstructure:"os"`
        Arch string `mapstructure:"arch"`
    } `mapstructure:"platform"`

    // 실행 옵션
    Verbose     bool `mapstructure:"verbose"`
    Parallel    bool `mapstructure:"parallel"`
    Workers     int  `mapstructure:"workers"`

    // 출력 형식
    OutputFormat string `mapstructure:"output_format"` // text, json, yaml

    // 보완 추출 설정
    Supplemental struct {
        Enabled  bool     `mapstructure:"enabled"`
        Patterns []string `mapstructure:"patterns"`
    } `mapstructure:"supplemental"`

    // 캐시 설정
    Cache struct {
        Enabled bool   `mapstructure:"enabled"`
        Dir     string `mapstructure:"dir"`
        TTL     int    `mapstructure:"ttl"` // seconds
    } `mapstructure:"cache"`
}

func Load(cmd *cobra.Command) (*Config, error) {
    cfg := &Config{
        Parallel: true,
        Workers:  runtime.NumCPU(),
    }

    // 환경 변수 바인딩
    viper.SetEnvPrefix("EXTRACTOR")
    viper.AutomaticEnv()

    // 플래그 바인딩
    if err := viper.BindPFlags(cmd.Flags()); err != nil {
        return nil, err
    }

    // 설정 파일 로드 (옵션)
    configFile := viper.GetString("config")
    if configFile != "" {
        viper.SetConfigFile(configFile)
        if err := viper.ReadInConfig(); err != nil {
            return nil, fmt.Errorf("설정 파일 읽기 실패: %w", err)
        }
    }

    // Viper → Config 매핑
    if err := viper.Unmarshal(cfg); err != nil {
        return nil, err
    }

    // 기본값 설정
    if err := cfg.setDefaults(); err != nil {
        return nil, err
    }

    // 유효성 검증
    if err := cfg.validate(); err != nil {
        return nil, err
    }

    return cfg, nil
}

func (c *Config) setDefaults() error {
    // Helmfile 경로 자동 탐색
    if c.HelmfilePath == "" {
        if path := findHelmfile(); path != "" {
            c.HelmfilePath = path
        } else {
            return fmt.Errorf("Helmfile을 찾을 수 없습니다")
        }
    }

    // Charts 경로 설정
    if c.ChartsPath == "" {
        c.ChartsPath = filepath.Join(filepath.Dir(c.HelmfilePath), "charts")
    }

    // 플랫폼 기본값
    if c.Platform.OS == "" {
        c.Platform.OS = runtime.GOOS
    }
    if c.Platform.Arch == "" {
        c.Platform.Arch = runtime.GOARCH
    }

    // 캐시 디렉토리
    if c.Cache.Enabled && c.Cache.Dir == "" {
        homeDir, _ := os.UserHomeDir()
        c.Cache.Dir = filepath.Join(homeDir, ".cache", "helm-image-extractor")
    }

    // 보완 패턴 기본값
    if c.Supplemental.Enabled && len(c.Supplemental.Patterns) == 0 {
        c.Supplemental.Patterns = []string{
            "**/values.yaml",
            "**/values.yml",
            "**/config.yaml",
        }
    }

    return nil
}

func (c *Config) validate() error {
    // 필수 경로 확인
    if _, err := os.Stat(c.HelmfilePath); err != nil {
        return fmt.Errorf("Helmfile이 존재하지 않음: %s", c.HelmfilePath)
    }

    if _, err := os.Stat(c.ChartsPath); err != nil {
        return fmt.Errorf("Charts 디렉토리가 존재하지 않음: %s", c.ChartsPath)
    }

    // 출력 디렉토리 확인
    outputDir := filepath.Dir(c.OutputPath)
    if err := os.MkdirAll(outputDir, 0755); err != nil {
        return fmt.Errorf("출력 디렉토리 생성 실패: %w", err)
    }

    // Workers 범위 확인
    if c.Workers < 1 {
        c.Workers = 1
    } else if c.Workers > 32 {
        c.Workers = 32
    }

    return nil
}

func findHelmfile() string {
    // 현재 디렉토리부터 상위로 탐색
    dir, _ := os.Getwd()
    for {
        helmfile := filepath.Join(dir, "helmfile", "helmfile.yaml.gotmpl")
        if _, err := os.Stat(helmfile); err == nil {
            return helmfile
        }

        parent := filepath.Dir(dir)
        if parent == dir {
            break
        }
        dir = parent
    }
    return ""
}
```

### 1.3 Discovery 모듈

**`internal/discovery/discovery.go`**
```go
package discovery

import (
    "encoding/json"
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "strings"

    "github.com/astrago/helm-image-extractor/internal/config"
    "gopkg.in/yaml.v3"
)

type Chart struct {
    Name         string
    Path         string
    Version      string
    Type         ChartType
    Dependencies []Chart
    Values       map[string]interface{}
}

type ChartType int

const (
    ChartTypeLocal ChartType = iota
    ChartTypeRemote
    ChartTypeOperator
)

type Discoverer struct {
    config *config.Config
    cache  map[string]*Chart
}

func New(cfg *config.Config) *Discoverer {
    return &Discoverer{
        config: cfg,
        cache:  make(map[string]*Chart),
    }
}

func (d *Discoverer) Discover() ([]*Chart, error) {
    // 1. Helmfile 파싱
    releases, err := d.parseHelmfile()
    if err != nil {
        return nil, fmt.Errorf("Helmfile 파싱 실패: %w", err)
    }

    // 2. 차트 수집
    charts := make([]*Chart, 0)
    for _, release := range releases {
        chart, err := d.discoverChart(release)
        if err != nil {
            if d.config.Verbose {
                fmt.Printf("⚠️  차트 발견 실패 [%s]: %v\n", release.Name, err)
            }
            continue
        }
        charts = append(charts, chart)
    }

    // 3. 추가 차트 스캔 (charts/ 디렉토리)
    additionalCharts, err := d.scanChartsDirectory()
    if err != nil && d.config.Verbose {
        fmt.Printf("⚠️  추가 차트 스캔 실패: %v\n", err)
    }
    charts = append(charts, additionalCharts...)

    return charts, nil
}

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

func (d *Discoverer) discoverChart(release Release) (*Chart, error) {
    // 캐시 확인
    if cached, ok := d.cache[release.Chart]; ok {
        return cached, nil
    }

    chartPath := filepath.Join(d.config.ChartsPath, release.Chart)

    // Chart.yaml 파싱
    chartYaml := filepath.Join(chartPath, "Chart.yaml")
    if _, err := os.Stat(chartYaml); err != nil {
        return nil, fmt.Errorf("Chart.yaml 없음: %s", chartYaml)
    }

    chart := &Chart{
        Name: release.Name,
        Path: chartPath,
        Type: d.detectChartType(chartPath),
    }

    // Chart.yaml 읽기
    data, err := os.ReadFile(chartYaml)
    if err != nil {
        return nil, err
    }

    var chartMeta map[string]interface{}
    if err := yaml.Unmarshal(data, &chartMeta); err != nil {
        return nil, err
    }

    if version, ok := chartMeta["version"].(string); ok {
        chart.Version = version
    }

    // Dependencies 처리
    if deps, ok := chartMeta["dependencies"].([]interface{}); ok {
        for _, dep := range deps {
            if depMap, ok := dep.(map[string]interface{}); ok {
                if depName, ok := depMap["name"].(string); ok {
                    depChart, _ := d.discoverSubchart(chartPath, depName)
                    if depChart != nil {
                        chart.Dependencies = append(chart.Dependencies, *depChart)
                    }
                }
            }
        }
    }

    // values.yaml 로드
    valuesPath := filepath.Join(chartPath, "values.yaml")
    if data, err := os.ReadFile(valuesPath); err == nil {
        yaml.Unmarshal(data, &chart.Values)
    }

    // 캐시 저장
    d.cache[release.Chart] = chart

    return chart, nil
}

func (d *Discoverer) detectChartType(path string) ChartType {
    // Operator 패턴 감지
    operatorPatterns := []string{
        "gpu-operator",
        "prometheus-operator",
        "mpi-operator",
        "nfd", // node-feature-discovery
    }

    for _, pattern := range operatorPatterns {
        if strings.Contains(path, pattern) {
            return ChartTypeOperator
        }
    }

    // CRD 파일 존재 확인
    crdPath := filepath.Join(path, "crds")
    if info, err := os.Stat(crdPath); err == nil && info.IsDir() {
        return ChartTypeOperator
    }

    return ChartTypeLocal
}

func (d *Discoverer) discoverSubchart(parentPath, name string) (*Chart, error) {
    // charts/ 디렉토리에서 subchart 찾기
    subchartPath := filepath.Join(parentPath, "charts", name)
    if _, err := os.Stat(subchartPath); err == nil {
        return d.discoverChart(Release{
            Name:  name,
            Chart: subchartPath,
        })
    }

    // .tgz 파일 확인
    tgzPath := filepath.Join(parentPath, "charts", name+".tgz")
    if _, err := os.Stat(tgzPath); err == nil {
        // tgz 압축 해제 로직
        // 실제 구현 필요
    }

    return nil, fmt.Errorf("subchart not found: %s", name)
}

func (d *Discoverer) scanChartsDirectory() ([]*Chart, error) {
    charts := make([]*Chart, 0)

    // astrago/ 디렉토리 스캔
    astragoPath := filepath.Join(d.config.ChartsPath, "astrago")
    if _, err := os.Stat(astragoPath); err == nil {
        if chart, err := d.discoverChart(Release{
            Name:  "astrago",
            Chart: "astrago",
        }); err == nil {
            charts = append(charts, chart)
        }
    }

    // external/ 디렉토리 스캔
    externalPath := filepath.Join(d.config.ChartsPath, "external")
    err := filepath.Walk(externalPath, func(path string, info os.FileInfo, err error) error {
        if err != nil {
            return nil // 에러 무시하고 계속
        }

        if info.Name() == "Chart.yaml" {
            chartDir := filepath.Dir(path)
            rel, _ := filepath.Rel(d.config.ChartsPath, chartDir)

            if chart, err := d.discoverChart(Release{
                Name:  filepath.Base(chartDir),
                Chart: rel,
            }); err == nil {
                charts = append(charts, chart)
            }
        }

        return nil
    })

    if err != nil {
        return charts, fmt.Errorf("차트 디렉토리 스캔 실패: %w", err)
    }

    return charts, nil
}
```

### 1.4 테스트 프레임워크

**`test/unit/discovery_test.go`**
```go
package unit

import (
    "testing"
    "path/filepath"

    "github.com/astrago/helm-image-extractor/internal/config"
    "github.com/astrago/helm-image-extractor/internal/discovery"
    "github.com/stretchr/testify/assert"
)

func TestDiscovery(t *testing.T) {
    tests := []struct {
        name     string
        setup    func() *config.Config
        expected int
        wantErr  bool
    }{
        {
            name: "기본 차트 발견",
            setup: func() *config.Config {
                return &config.Config{
                    HelmfilePath: filepath.Join("testdata", "helmfile.yaml"),
                    ChartsPath:   filepath.Join("testdata", "charts"),
                }
            },
            expected: 5,
            wantErr:  false,
        },
        {
            name: "Operator 차트 감지",
            setup: func() *config.Config {
                return &config.Config{
                    HelmfilePath: filepath.Join("testdata", "helmfile-operator.yaml"),
                    ChartsPath:   filepath.Join("testdata", "charts"),
                }
            },
            expected: 3,
            wantErr:  false,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            cfg := tt.setup()
            d := discovery.New(cfg)

            charts, err := d.Discover()

            if tt.wantErr {
                assert.Error(t, err)
            } else {
                assert.NoError(t, err)
                assert.Len(t, charts, tt.expected)
            }
        })
    }
}
```

### 1.5 Makefile

**`Makefile`**
```makefile
.PHONY: all build test clean install

# 변수 정의
BINARY_NAME := extract-images
VERSION := $(shell git describe --tags --always --dirty)
BUILD_TIME := $(shell date -u '+%Y-%m-%d_%H:%M:%S')
COMMIT := $(shell git rev-parse --short HEAD)
LDFLAGS := -ldflags "-X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(BUILD_TIME)"

# Go 환경 변수
GO := go
GOFLAGS := -v
GOTEST := $(GO) test -v -race -coverprofile=coverage.out

# 기본 타겟
all: test build

# 빌드
build:
	@echo "🔨 Building $(BINARY_NAME)..."
	$(GO) build $(GOFLAGS) $(LDFLAGS) -o bin/$(BINARY_NAME) cmd/extractor/main.go

# 크로스 컴파일
build-all:
	@echo "🔨 Building for multiple platforms..."
	GOOS=linux GOARCH=amd64 $(GO) build $(LDFLAGS) -o bin/$(BINARY_NAME)-linux-amd64 cmd/extractor/main.go
	GOOS=linux GOARCH=arm64 $(GO) build $(LDFLAGS) -o bin/$(BINARY_NAME)-linux-arm64 cmd/extractor/main.go
	GOOS=darwin GOARCH=amd64 $(GO) build $(LDFLAGS) -o bin/$(BINARY_NAME)-darwin-amd64 cmd/extractor/main.go
	GOOS=darwin GOARCH=arm64 $(GO) build $(LDFLAGS) -o bin/$(BINARY_NAME)-darwin-arm64 cmd/extractor/main.go

# 테스트
test:
	@echo "🧪 Running tests..."
	$(GOTEST) ./...

# 통합 테스트
test-integration:
	@echo "🧪 Running integration tests..."
	$(GOTEST) ./test/integration/... -tags=integration

# 벤치마크
bench:
	@echo "📊 Running benchmarks..."
	$(GO) test -bench=. -benchmem ./...

# 정적 분석
lint:
	@echo "🔍 Running linter..."
	golangci-lint run

# 포맷팅
fmt:
	@echo "✨ Formatting code..."
	$(GO) fmt ./...
	goimports -w .

# 의존성 업데이트
deps:
	@echo "📦 Updating dependencies..."
	$(GO) mod download
	$(GO) mod tidy
	$(GO) mod verify

# 설치
install: build
	@echo "📦 Installing $(BINARY_NAME)..."
	cp bin/$(BINARY_NAME) /usr/local/bin/

# 정리
clean:
	@echo "🧹 Cleaning..."
	rm -rf bin/ coverage.out dist/

# 도움말
help:
	@echo "Available targets:"
	@echo "  make build       - Build the binary"
	@echo "  make build-all   - Build for all platforms"
	@echo "  make test        - Run unit tests"
	@echo "  make test-integration - Run integration tests"
	@echo "  make bench       - Run benchmarks"
	@echo "  make lint        - Run linter"
	@echo "  make fmt         - Format code"
	@echo "  make deps        - Update dependencies"
	@echo "  make install     - Install binary"
	@echo "  make clean       - Clean build artifacts"
```

### 📊 Phase 1 검증 체크리스트

- [ ] 프로젝트 구조 생성 완료
- [ ] Go 모듈 및 의존성 설정
- [ ] 기본 CLI 인터페이스 동작
- [ ] Configuration 로드 및 검증
- [ ] Discovery 모듈 차트 탐색
- [ ] 단위 테스트 통과
- [ ] Makefile 빌드 성공

---

## 📅 Phase 2: Core Implementation (Week 2)
> **핵심 렌더링 및 추출 엔진 구현**

### 2.1 Renderer 모듈

**`internal/renderer/renderer.go`**
```go
package renderer

import (
    "bytes"
    "context"
    "fmt"
    "sync"

    "helm.sh/helm/v3/pkg/action"
    "helm.sh/helm/v3/pkg/chart"
    "helm.sh/helm/v3/pkg/chart/loader"
    "helm.sh/helm/v3/pkg/cli"
    "helm.sh/helm/v3/pkg/cli/values"
    "helm.sh/helm/v3/pkg/getter"

    "github.com/astrago/helm-image-extractor/internal/config"
    "github.com/astrago/helm-image-extractor/internal/discovery"
)

type Renderer struct {
    config      *config.Config
    helmConfig  *action.Configuration
    valueOpts   *values.Options
}

type RenderResult struct {
    Chart     *discovery.Chart
    Manifests string
    Error     error
}

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

func (r *Renderer) RenderAll(charts []*discovery.Chart) ([]*RenderResult, error) {
    if r.config.Parallel {
        return r.renderParallel(charts)
    }
    return r.renderSequential(charts)
}

func (r *Renderer) renderParallel(charts []*discovery.Chart) ([]*RenderResult, error) {
    var wg sync.WaitGroup
    results := make([]*RenderResult, len(charts))

    // Worker pool
    jobs := make(chan int, len(charts))

    // Workers 시작
    for w := 0; w < r.config.Workers; w++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for idx := range jobs {
                result := r.renderChart(charts[idx])
                results[idx] = result
            }
        }()
    }

    // Jobs 전송
    for i := range charts {
        jobs <- i
    }
    close(jobs)

    wg.Wait()
    return results, nil
}

func (r *Renderer) renderSequential(charts []*discovery.Chart) ([]*RenderResult, error) {
    results := make([]*RenderResult, 0, len(charts))

    for _, chart := range charts {
        result := r.renderChart(chart)
        results = append(results, result)
    }

    return results, nil
}

func (r *Renderer) renderChart(chart *discovery.Chart) *RenderResult {
    result := &RenderResult{Chart: chart}

    // Helm 차트 로드
    chartObj, err := loader.Load(chart.Path)
    if err != nil {
        result.Error = fmt.Errorf("차트 로드 실패: %w", err)
        return result
    }

    // Values 병합
    vals, err := r.mergeValues(chart, chartObj)
    if err != nil {
        result.Error = fmt.Errorf("values 병합 실패: %w", err)
        return result
    }

    // 렌더링 액션 생성
    client := action.NewInstall(r.helmConfig)
    client.DryRun = true
    client.ReleaseName = chart.Name
    client.Namespace = "default"
    client.Replace = true
    client.ClientOnly = true

    // 렌더링 실행
    release, err := client.Run(chartObj, vals)
    if err != nil {
        result.Error = fmt.Errorf("렌더링 실패: %w", err)
        return result
    }

    // Manifests 수집
    var buf bytes.Buffer
    fmt.Fprintln(&buf, release.Manifest)

    // Hooks manifests 포함
    for _, hook := range release.Hooks {
        fmt.Fprintln(&buf, "---")
        fmt.Fprintln(&buf, hook.Manifest)
    }

    result.Manifests = buf.String()
    return result
}

func (r *Renderer) mergeValues(chartInfo *discovery.Chart, chartObj *chart.Chart) (map[string]interface{}, error) {
    // 기본 values
    vals := make(map[string]interface{})

    // Chart의 기본 values
    if chartObj.Values != nil {
        for k, v := range chartObj.Values {
            vals[k] = v
        }
    }

    // 사용자 정의 values 오버라이드
    if chartInfo.Values != nil {
        for k, v := range chartInfo.Values {
            vals[k] = v
        }
    }

    // 플랫폼별 values 적용
    if r.config.Platform.OS != "" {
        if platformVals, ok := vals["platform"].(map[string]interface{}); ok {
            if osVals, ok := platformVals[r.config.Platform.OS].(map[string]interface{}); ok {
                for k, v := range osVals {
                    vals[k] = v
                }
            }
        }
    }

    return vals, nil
}

// Helm SDK를 사용하지 않는 대체 렌더링 (Fallback)
func (r *Renderer) renderWithHelmfile(chart *discovery.Chart) (*RenderResult, error) {
    // helmfile template 명령 실행
    // exec.Command 사용
    return nil, nil
}
```

### 2.2 Extractor 모듈

**`internal/extractor/extractor.go`**
```go
package extractor

import (
    "bufio"
    "fmt"
    "regexp"
    "strings"
    "sync"

    "gopkg.in/yaml.v3"

    "github.com/astrago/helm-image-extractor/internal/config"
    "github.com/astrago/helm-image-extractor/internal/discovery"
    "github.com/astrago/helm-image-extractor/internal/renderer"
    "github.com/astrago/helm-image-extractor/pkg/patterns"
)

type Extractor struct {
    config         *config.Config
    imagePatterns  []*regexp.Regexp
    uniqueImages   sync.Map
}

type Image struct {
    Registry   string
    Repository string
    Tag        string
    Full       string
    Source     string // 추출된 위치
}

func New(cfg *config.Config) *Extractor {
    e := &Extractor{
        config: cfg,
    }
    e.compilePatterns()
    return e
}

func (e *Extractor) compilePatterns() {
    // 이미지 패턴 정규표현식
    patterns := []string{
        `image:\s*["']?([^"'\s]+)["']?`,
        `image:\s*\{\{-?\s*\.Values\.([^\s}]+)\s*-?\}\}`,
        `"image":\s*"([^"]+)"`,
    }

    for _, pattern := range patterns {
        if re, err := regexp.Compile(pattern); err == nil {
            e.imagePatterns = append(e.imagePatterns, re)
        }
    }
}

func (e *Extractor) ExtractAll(results []*renderer.RenderResult, charts []*discovery.Chart) ([]*Image, error) {
    images := make([]*Image, 0)

    // 1. Manifest에서 추출
    for _, result := range results {
        if result.Error != nil {
            continue
        }

        manifestImages := e.extractFromManifests(result.Manifests, result.Chart.Name)
        images = append(images, manifestImages...)
    }

    // 2. Operator 차트 보완 추출
    if e.config.Supplemental.Enabled {
        for _, chart := range charts {
            if chart.Type == discovery.ChartTypeOperator {
                supplementalImages := e.extractFromValues(chart)
                images = append(images, supplementalImages...)
            }
        }
    }

    // 3. 중복 제거
    uniqueImages := e.deduplicateImages(images)

    // 4. 정렬
    sortedImages := e.sortImages(uniqueImages)

    return sortedImages, nil
}

func (e *Extractor) extractFromManifests(manifests string, source string) []*Image {
    images := make([]*Image, 0)

    // YAML 문서 분리
    docs := strings.Split(manifests, "---")

    for _, doc := range docs {
        if strings.TrimSpace(doc) == "" {
            continue
        }

        // YAML 파싱
        var obj map[string]interface{}
        if err := yaml.Unmarshal([]byte(doc), &obj); err != nil {
            continue
        }

        // Container 이미지 추출
        images = append(images, e.extractImagesFromObject(obj, source)...)
    }

    return images
}

func (e *Extractor) extractImagesFromObject(obj map[string]interface{}, source string) []*Image {
    images := make([]*Image, 0)

    // Pod spec 찾기
    spec := e.findPodSpec(obj)
    if spec == nil {
        return images
    }

    // Containers 처리
    if containers, ok := spec["containers"].([]interface{}); ok {
        for _, container := range containers {
            if containerMap, ok := container.(map[string]interface{}); ok {
                if imageStr, ok := containerMap["image"].(string); ok {
                    image := e.parseImage(imageStr)
                    image.Source = source
                    images = append(images, image)
                }
            }
        }
    }

    // InitContainers 처리
    if initContainers, ok := spec["initContainers"].([]interface{}); ok {
        for _, container := range initContainers {
            if containerMap, ok := container.(map[string]interface{}); ok {
                if imageStr, ok := containerMap["image"].(string); ok {
                    image := e.parseImage(imageStr)
                    image.Source = source + " (init)"
                    images = append(images, image)
                }
            }
        }
    }

    return images
}

func (e *Extractor) findPodSpec(obj map[string]interface{}) map[string]interface{} {
    // 다양한 리소스 타입에서 Pod spec 찾기

    // Deployment, StatefulSet, DaemonSet
    if spec, ok := obj["spec"].(map[string]interface{}); ok {
        if template, ok := spec["template"].(map[string]interface{}); ok {
            if podSpec, ok := template["spec"].(map[string]interface{}); ok {
                return podSpec
            }
        }
    }

    // Job, CronJob
    if spec, ok := obj["spec"].(map[string]interface{}); ok {
        if jobTemplate, ok := spec["jobTemplate"].(map[string]interface{}); ok {
            if jobSpec, ok := jobTemplate["spec"].(map[string]interface{}); ok {
                if template, ok := jobSpec["template"].(map[string]interface{}); ok {
                    if podSpec, ok := template["spec"].(map[string]interface{}); ok {
                        return podSpec
                    }
                }
            }
        }
    }

    // Pod
    if kind, ok := obj["kind"].(string); ok && kind == "Pod" {
        if spec, ok := obj["spec"].(map[string]interface{}); ok {
            return spec
        }
    }

    return nil
}

func (e *Extractor) parseImage(imageStr string) *Image {
    image := &Image{Full: imageStr}

    // 태그 분리
    parts := strings.Split(imageStr, ":")
    if len(parts) == 2 {
        image.Tag = parts[1]
        imageStr = parts[0]
    } else if len(parts) == 3 {
        // 포트가 포함된 레지스트리 (e.g., localhost:5000/image:tag)
        image.Tag = parts[2]
        imageStr = strings.Join(parts[:2], ":")
    } else {
        image.Tag = "latest"
    }

    // 레지스트리와 리포지토리 분리
    if strings.Contains(imageStr, "/") {
        parts := strings.SplitN(imageStr, "/", 2)

        // 도메인 형식 확인 (점 또는 포트 포함)
        if strings.Contains(parts[0], ".") || strings.Contains(parts[0], ":") {
            image.Registry = parts[0]
            image.Repository = parts[1]
        } else {
            // Docker Hub 공식 이미지
            if len(parts) == 1 {
                image.Registry = "docker.io"
                image.Repository = "library/" + parts[0]
            } else {
                image.Registry = "docker.io"
                image.Repository = imageStr
            }
        }
    } else {
        // 단순 이미지명
        image.Registry = "docker.io"
        image.Repository = "library/" + imageStr
    }

    return image
}

func (e *Extractor) extractFromValues(chart *discovery.Chart) []*Image {
    images := make([]*Image, 0)

    // Pattern-based extraction
    extractor := patterns.New()

    // values.yaml에서 이미지 패턴 추출
    if results, err := extractor.ExtractFromValues(chart.Values); err == nil {
        for _, result := range results {
            image := &Image{
                Registry:   result.Registry,
                Repository: result.Repository,
                Tag:        result.Tag,
                Full:       result.Full(),
                Source:     fmt.Sprintf("%s (values)", chart.Name),
            }
            images = append(images, image)
        }
    }

    // 특별 처리: GPU Operator
    if strings.Contains(chart.Name, "gpu-operator") {
        images = append(images, e.extractGPUOperatorImages(chart)...)
    }

    // 특별 처리: Prometheus Stack
    if strings.Contains(chart.Name, "prometheus") {
        images = append(images, e.extractPrometheusImages(chart)...)
    }

    return images
}

func (e *Extractor) extractGPUOperatorImages(chart *discovery.Chart) []*Image {
    // GPU Operator 특수 이미지 패턴
    images := make([]*Image, 0)

    gpuImages := []string{
        "nvcr.io/nvidia/gpu-operator:v24.9.0",
        "nvcr.io/nvidia/driver:550.127.05",
        "nvcr.io/nvidia/cuda:12.6.2-base-ubi9",
        "nvcr.io/nvidia/k8s-device-plugin:v0.17.0-ubi9",
        "nvcr.io/nvidia/k8s/container-toolkit:v1.17.0-ubuntu20.04",
        "nvcr.io/nvidia/cloud-native/dcgm:3.3.8-1-ubuntu22.04",
        "nvcr.io/nvidia/k8s/dcgm-exporter:3.3.8-3.6.0-ubuntu22.04",
        "nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.0",
        "nvcr.io/nvidia/cloud-native/k8s-mig-manager:v0.10.0-ubuntu20.04",
        "nvcr.io/nvidia/cloud-native/nvidia-fs:2.20.5",
        "nvcr.io/nvidia/cloud-native/k8s-driver-manager:v0.7.0",
        "nvcr.io/nvidia/cloud-native/k8s-kata-manager:v0.2.2",
        "nvcr.io/nvidia/cloud-native/k8s-cc-manager:v0.1.1",
        "nvcr.io/nvidia/cloud-native/vgpu-device-manager:v0.2.8",
        "nvcr.io/nvidia/kubevirt-gpu-device-plugin:v1.2.10",
        "registry.k8s.io/nfd/node-feature-discovery:v0.16.4",
    }

    for _, img := range gpuImages {
        image := e.parseImage(img)
        image.Source = "gpu-operator (supplemental)"
        images = append(images, image)
    }

    return images
}

func (e *Extractor) extractPrometheusImages(chart *discovery.Chart) []*Image {
    // Prometheus Stack 관련 이미지
    images := make([]*Image, 0)

    promImages := []string{
        "quay.io/prometheus-operator/prometheus-operator:v0.68.0",
        "quay.io/prometheus-operator/prometheus-config-reloader:v0.68.0",
        "quay.io/prometheus-operator/admission-webhook:v0.68.0",
        "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0",
        "quay.io/prometheus/node-exporter:v1.8.2",
        "quay.io/prometheus/alertmanager:v0.27.0",
        "quay.io/prometheus/prometheus:v2.54.0",
        "quay.io/thanos/thanos:v0.36.0",
    }

    for _, img := range promImages {
        image := e.parseImage(img)
        image.Source = "prometheus-stack (supplemental)"
        images = append(images, image)
    }

    return images
}

func (e *Extractor) deduplicateImages(images []*Image) []*Image {
    seen := make(map[string]bool)
    unique := make([]*Image, 0)

    for _, img := range images {
        key := img.Full
        if !seen[key] {
            seen[key] = true
            unique = append(unique, img)
        }
    }

    return unique
}

func (e *Extractor) sortImages(images []*Image) []*Image {
    // 정렬: Registry → Repository → Tag
    // 실제 구현시 sort.Slice 사용
    return images
}
```

### 2.3 패턴 매칭 패키지

**`pkg/patterns/patterns.go`**
```go
package patterns

import (
    "fmt"
    "strings"
)

type PatternExtractor struct {
    patterns []Pattern
}

type Pattern interface {
    Extract(data map[string]interface{}) (*ImageResult, error)
    Name() string
}

type ImageResult struct {
    Registry   string
    Repository string
    Tag        string
}

func (i *ImageResult) Full() string {
    if i.Registry != "" {
        return fmt.Sprintf("%s/%s:%s", i.Registry, i.Repository, i.Tag)
    }
    return fmt.Sprintf("%s:%s", i.Repository, i.Tag)
}

func New() *PatternExtractor {
    return &PatternExtractor{
        patterns: []Pattern{
            &PatternA{}, // repository + image + tag
            &PatternB{}, // repository + tag
            &PatternC{}, // registry + image + tag
            &PatternD{}, // Bitnami 패턴
            &PatternE{}, // 중첩 구조 패턴
        },
    }
}

func (p *PatternExtractor) ExtractFromValues(values map[string]interface{}) ([]*ImageResult, error) {
    results := make([]*ImageResult, 0)

    // 모든 패턴 시도
    for _, pattern := range p.patterns {
        if result, err := pattern.Extract(values); err == nil && result != nil {
            results = append(results, result)
        }
    }

    // 재귀적으로 중첩된 맵 탐색
    for key, value := range values {
        if nestedMap, ok := value.(map[string]interface{}); ok {
            // image 관련 키 확인
            if strings.Contains(strings.ToLower(key), "image") {
                for _, pattern := range p.patterns {
                    if result, err := pattern.Extract(nestedMap); err == nil && result != nil {
                        results = append(results, result)
                    }
                }
            }

            // 재귀 탐색
            if nestedResults, err := p.ExtractFromValues(nestedMap); err == nil {
                results = append(results, nestedResults...)
            }
        }
    }

    return results, nil
}

// Pattern A: repository + image + tag
type PatternA struct{}

func (p *PatternA) Name() string { return "Pattern A" }

func (p *PatternA) Extract(data map[string]interface{}) (*ImageResult, error) {
    repo, repoOk := data["repository"].(string)
    image, imageOk := data["image"].(string)

    if !repoOk || !imageOk {
        return nil, fmt.Errorf("pattern A fields not found")
    }

    tag := "latest"
    if t, ok := data["tag"].(string); ok {
        tag = t
    } else if v, ok := data["version"].(string); ok {
        tag = v
    }

    return &ImageResult{
        Repository: fmt.Sprintf("%s/%s", repo, image),
        Tag:        tag,
    }, nil
}

// Pattern B: repository + tag
type PatternB struct{}

func (p *PatternB) Name() string { return "Pattern B" }

func (p *PatternB) Extract(data map[string]interface{}) (*ImageResult, error) {
    repo, repoOk := data["repository"].(string)
    if !repoOk {
        return nil, fmt.Errorf("repository not found")
    }

    // repository에 이미 전체 경로 포함
    if !strings.Contains(repo, "/") {
        return nil, fmt.Errorf("invalid repository format")
    }

    tag := "latest"
    if t, ok := data["tag"].(string); ok {
        tag = t
    } else if v, ok := data["version"].(string); ok {
        tag = v
    }

    // 레지스트리 분리
    parts := strings.SplitN(repo, "/", 2)
    registry := ""
    repository := repo

    if strings.Contains(parts[0], ".") || strings.Contains(parts[0], ":") {
        registry = parts[0]
        repository = parts[1]
    }

    return &ImageResult{
        Registry:   registry,
        Repository: repository,
        Tag:        tag,
    }, nil
}

// Pattern C: registry + image + tag
type PatternC struct{}

func (p *PatternC) Name() string { return "Pattern C" }

func (p *PatternC) Extract(data map[string]interface{}) (*ImageResult, error) {
    registry, regOk := data["registry"].(string)
    image, imgOk := data["image"].(string)

    if !regOk || !imgOk {
        return nil, fmt.Errorf("pattern C fields not found")
    }

    tag := "latest"
    if t, ok := data["tag"].(string); ok {
        tag = t
    } else if v, ok := data["version"].(string); ok {
        tag = v
    }

    return &ImageResult{
        Registry:   registry,
        Repository: image,
        Tag:        tag,
    }, nil
}

// Pattern D: Bitnami 스타일
type PatternD struct{}

func (p *PatternD) Name() string { return "Pattern D (Bitnami)" }

func (p *PatternD) Extract(data map[string]interface{}) (*ImageResult, error) {
    // Bitnami 차트는 보통 image.registry, image.repository, image.tag 구조
    imageMap, ok := data["image"].(map[string]interface{})
    if !ok {
        return nil, fmt.Errorf("image map not found")
    }

    registry, _ := imageMap["registry"].(string)
    repository, repoOk := imageMap["repository"].(string)
    if !repoOk {
        return nil, fmt.Errorf("repository not found in image map")
    }

    tag := "latest"
    if t, ok := imageMap["tag"].(string); ok {
        tag = t
    }

    if registry == "" {
        registry = "docker.io"
    }

    return &ImageResult{
        Registry:   registry,
        Repository: repository,
        Tag:        tag,
    }, nil
}

// Pattern E: 중첩 구조
type PatternE struct{}

func (p *PatternE) Name() string { return "Pattern E (Nested)" }

func (p *PatternE) Extract(data map[string]interface{}) (*ImageResult, error) {
    // 컨테이너별 이미지 설정 (e.g., containers.main.image)
    containers, ok := data["containers"].(map[string]interface{})
    if !ok {
        return nil, fmt.Errorf("containers not found")
    }

    for _, container := range containers {
        if containerMap, ok := container.(map[string]interface{}); ok {
            if imageStr, ok := containerMap["image"].(string); ok {
                // 전체 이미지 문자열 파싱
                parts := strings.Split(imageStr, ":")
                tag := "latest"
                repo := imageStr

                if len(parts) == 2 {
                    repo = parts[0]
                    tag = parts[1]
                }

                return &ImageResult{
                    Repository: repo,
                    Tag:        tag,
                }, nil
            }
        }
    }

    return nil, fmt.Errorf("no image found in containers")
}
```

### 📊 Phase 2 검증 체크리스트

- [ ] Helm SDK 통합 완료
- [ ] 차트 렌더링 기능 구현
- [ ] 이미지 추출 로직 구현
- [ ] 패턴 매칭 엔진 구현
- [ ] Operator 특수 처리 구현
- [ ] 병렬 처리 구현
- [ ] 통합 테스트 작성

---

## 📅 Phase 3: Enhancement (Week 3)
> **보완 기능 및 특수 케이스 처리**

### 3.1 Operator 보완 추출

**`internal/extractor/operator.go`**
```go
package extractor

import (
    "path/filepath"
    "strings"
    "os"

    "gopkg.in/yaml.v3"
)

type OperatorExtractor struct {
    knownOperators map[string]OperatorHandler
}

type OperatorHandler interface {
    Extract(chartPath string) ([]*Image, error)
    Name() string
}

func NewOperatorExtractor() *OperatorExtractor {
    return &OperatorExtractor{
        knownOperators: map[string]OperatorHandler{
            "gpu-operator":         &GPUOperatorHandler{},
            "prometheus-operator":  &PrometheusOperatorHandler{},
            "mpi-operator":         &MPIOperatorHandler{},
            "mariadb-operator":     &MariaDBOperatorHandler{},
        },
    }
}

// GPU Operator Handler
type GPUOperatorHandler struct{}

func (h *GPUOperatorHandler) Name() string { return "GPU Operator" }

func (h *GPUOperatorHandler) Extract(chartPath string) ([]*Image, error) {
    images := make([]*Image, 0)

    // values.yaml 읽기
    valuesPath := filepath.Join(chartPath, "values.yaml")
    data, err := os.ReadFile(valuesPath)
    if err != nil {
        return images, err
    }

    var values map[string]interface{}
    if err := yaml.Unmarshal(data, &values); err != nil {
        return images, err
    }

    // GPU Operator 특정 이미지 섹션들
    sections := []string{
        "operator",
        "driver",
        "toolkit",
        "devicePlugin",
        "dcgmExporter",
        "gfd",
        "migManager",
        "nodeStatusExporter",
        "validator",
    }

    for _, section := range sections {
        if sectionData, ok := values[section].(map[string]interface{}); ok {
            if img := extractImageFromSection(sectionData); img != nil {
                img.Source = fmt.Sprintf("gpu-operator/%s", section)
                images = append(images, img)
            }
        }
    }

    // NVIDIA 레지스트리 이미지 추가
    nvidiaImages := []string{
        "nvcr.io/nvidia/gpu-operator:v24.9.0",
        "nvcr.io/nvidia/driver:550.127.05-ubuntu22.04",
        "nvcr.io/nvidia/cuda:12.6.2-base-ubi9",
        "nvcr.io/nvidia/k8s-device-plugin:v0.17.0-ubi9",
        "nvcr.io/nvidia/k8s/container-toolkit:v1.17.0-ubuntu20.04",
        "nvcr.io/nvidia/cloud-native/dcgm:3.3.8-1-ubuntu22.04",
        "nvcr.io/nvidia/k8s/dcgm-exporter:3.3.8-3.6.0-ubuntu22.04",
        "nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.0",
        "nvcr.io/nvidia/cloud-native/k8s-mig-manager:v0.10.0-ubuntu20.04",
        "nvcr.io/nvidia/cloud-native/nvidia-fs:2.20.5",
        "nvcr.io/nvidia/cloud-native/gdrdrv:v2.4.1-2",
        "nvcr.io/nvidia/cloud-native/k8s-driver-manager:v0.7.0",
        "nvcr.io/nvidia/cloud-native/k8s-kata-manager:v0.2.2",
        "nvcr.io/nvidia/cloud-native/k8s-cc-manager:v0.1.1",
        "nvcr.io/nvidia/cloud-native/vgpu-device-manager:v0.2.8",
        "nvcr.io/nvidia/kubevirt-gpu-device-plugin:v1.2.10",
        "registry.k8s.io/nfd/node-feature-discovery:v0.16.4",
    }

    for _, imageStr := range nvidiaImages {
        img := parseImageString(imageStr)
        img.Source = "gpu-operator/nvidia"
        images = append(images, img)
    }

    return images, nil
}

// Prometheus Operator Handler
type PrometheusOperatorHandler struct{}

func (h *PrometheusOperatorHandler) Name() string { return "Prometheus Operator" }

func (h *PrometheusOperatorHandler) Extract(chartPath string) ([]*Image, error) {
    images := make([]*Image, 0)

    // kube-prometheus-stack의 서브차트들
    subcharts := []string{
        "kube-state-metrics",
        "prometheus-node-exporter",
        "prometheus-windows-exporter",
        "grafana",
    }

    for _, subchart := range subcharts {
        subchartPath := filepath.Join(chartPath, "charts", subchart)
        if _, err := os.Stat(subchartPath); err == nil {
            // 서브차트 values.yaml 파싱
            if subImages, err := extractFromSubchart(subchartPath); err == nil {
                images = append(images, subImages...)
            }
        }
    }

    // Operator 자체 이미지들
    operatorImages := []string{
        "quay.io/prometheus-operator/prometheus-operator:v0.68.0",
        "quay.io/prometheus-operator/prometheus-config-reloader:v0.68.0",
        "quay.io/prometheus-operator/admission-webhook:v0.68.0",
        "quay.io/prometheus/prometheus:v2.54.0",
        "quay.io/prometheus/alertmanager:v0.27.0",
        "quay.io/thanos/thanos:v0.36.0",
        "quay.io/brancz/kube-rbac-proxy:v0.18.0",
        "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0",
        "quay.io/prometheus/node-exporter:v1.8.2",
        "grafana/grafana:11.2.0",
        "quay.io/kiwigrid/k8s-sidecar:1.27.4",
        "docker.io/grafana/grafana-image-renderer:latest",
        "quay.io/prometheus-community/windows-exporter:0.27.2",
    }

    for _, imageStr := range operatorImages {
        img := parseImageString(imageStr)
        img.Source = "prometheus-operator"
        images = append(images, img)
    }

    return images, nil
}

// Helper functions
func extractImageFromSection(section map[string]interface{}) *Image {
    // 다양한 이미지 필드 확인
    imageFields := []string{"image", "repository", "imageName"}
    tagFields := []string{"tag", "version", "imageTag"}

    imageStr := ""
    tag := "latest"

    // 이미지 찾기
    for _, field := range imageFields {
        if val, ok := section[field].(string); ok {
            imageStr = val
            break
        }
    }

    // 태그 찾기
    for _, field := range tagFields {
        if val, ok := section[field].(string); ok {
            tag = val
            break
        }
    }

    if imageStr == "" {
        return nil
    }

    // 이미지가 이미 태그 포함하는 경우
    if strings.Contains(imageStr, ":") {
        return parseImageString(imageStr)
    }

    return &Image{
        Full:       fmt.Sprintf("%s:%s", imageStr, tag),
        Repository: imageStr,
        Tag:        tag,
    }
}

func extractFromSubchart(chartPath string) ([]*Image, error) {
    images := make([]*Image, 0)

    valuesPath := filepath.Join(chartPath, "values.yaml")
    data, err := os.ReadFile(valuesPath)
    if err != nil {
        return images, err
    }

    var values map[string]interface{}
    if err := yaml.Unmarshal(data, &values); err != nil {
        return images, err
    }

    // image 섹션 찾기
    if imageSection, ok := values["image"].(map[string]interface{}); ok {
        if img := extractImageFromSection(imageSection); img != nil {
            img.Source = filepath.Base(chartPath)
            images = append(images, img)
        }
    }

    return images, nil
}

func parseImageString(imageStr string) *Image {
    img := &Image{Full: imageStr}

    // 태그 분리
    if idx := strings.LastIndex(imageStr, ":"); idx != -1 {
        img.Repository = imageStr[:idx]
        img.Tag = imageStr[idx+1:]
    } else {
        img.Repository = imageStr
        img.Tag = "latest"
    }

    // 레지스트리 분리
    if strings.Count(img.Repository, "/") > 0 {
        parts := strings.SplitN(img.Repository, "/", 2)
        if strings.Contains(parts[0], ".") || strings.Contains(parts[0], ":") {
            img.Registry = parts[0]
            img.Repository = parts[1]
        }
    }

    return img
}
```

### 3.2 Output 모듈

**`internal/output/output.go`**
```go
package output

import (
    "encoding/json"
    "fmt"
    "os"
    "path/filepath"
    "sort"
    "strings"
    "text/tabwriter"
    "time"

    "gopkg.in/yaml.v3"

    "github.com/astrago/helm-image-extractor/internal/config"
    "github.com/astrago/helm-image-extractor/internal/extractor"
)

type Outputter struct {
    config *config.Config
}

type OutputReport struct {
    Metadata   Metadata               `json:"metadata" yaml:"metadata"`
    Summary    Summary                `json:"summary" yaml:"summary"`
    Images     []*extractor.Image     `json:"images" yaml:"images"`
    ByChart    map[string][]string    `json:"by_chart" yaml:"by_chart"`
    ByRegistry map[string][]string    `json:"by_registry" yaml:"by_registry"`
}

type Metadata struct {
    Timestamp   string `json:"timestamp" yaml:"timestamp"`
    Environment string `json:"environment" yaml:"environment"`
    Platform    string `json:"platform" yaml:"platform"`
    Version     string `json:"version" yaml:"version"`
}

type Summary struct {
    TotalImages    int    `json:"total_images" yaml:"total_images"`
    UniqueImages   int    `json:"unique_images" yaml:"unique_images"`
    TotalCharts    int    `json:"total_charts" yaml:"total_charts"`
    ExecutionTime  string `json:"execution_time" yaml:"execution_time"`
}

func New(cfg *config.Config) *Outputter {
    return &Outputter{config: cfg}
}

func (o *Outputter) Write(images []*extractor.Image) error {
    startTime := time.Now()

    // 출력 형식별 처리
    switch o.config.OutputFormat {
    case "json":
        return o.writeJSON(images, startTime)
    case "yaml":
        return o.writeYAML(images, startTime)
    case "table":
        return o.writeTable(images)
    default:
        return o.writeText(images)
    }
}

func (o *Outputter) writeText(images []*extractor.Image) error {
    // 정렬
    sort.Slice(images, func(i, j int) bool {
        return images[i].Full < images[j].Full
    })

    // 출력 파일 생성
    file, err := os.Create(o.config.OutputPath)
    if err != nil {
        return fmt.Errorf("출력 파일 생성 실패: %w", err)
    }
    defer file.Close()

    // 이미지 목록 작성
    for _, img := range images {
        fmt.Fprintln(file, img.Full)
    }

    // 콘솔 출력
    if o.config.Verbose {
        o.printSummary(images)
    }

    fmt.Printf("✅ %d개 이미지를 %s에 저장했습니다\n", len(images), o.config.OutputPath)

    return nil
}

func (o *Outputter) writeJSON(images []*extractor.Image, startTime time.Time) error {
    report := o.buildReport(images, startTime)

    // JSON 마샬링
    data, err := json.MarshalIndent(report, "", "  ")
    if err != nil {
        return fmt.Errorf("JSON 마샬링 실패: %w", err)
    }

    // 파일 저장
    if err := os.WriteFile(o.config.OutputPath, data, 0644); err != nil {
        return fmt.Errorf("파일 저장 실패: %w", err)
    }

    return nil
}

func (o *Outputter) writeYAML(images []*extractor.Image, startTime time.Time) error {
    report := o.buildReport(images, startTime)

    // YAML 마샬링
    data, err := yaml.Marshal(report)
    if err != nil {
        return fmt.Errorf("YAML 마샬링 실패: %w", err)
    }

    // 파일 저장
    if err := os.WriteFile(o.config.OutputPath, data, 0644); err != nil {
        return fmt.Errorf("파일 저장 실패: %w", err)
    }

    return nil
}

func (o *Outputter) writeTable(images []*extractor.Image) error {
    // 테이블 출력
    w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
    defer w.Flush()

    fmt.Fprintln(w, "REGISTRY\tREPOSITORY\tTAG\tSOURCE")
    fmt.Fprintln(w, "--------\t----------\t---\t------")

    for _, img := range images {
        fmt.Fprintf(w, "%s\t%s\t%s\t%s\n",
            img.Registry,
            img.Repository,
            img.Tag,
            img.Source,
        )
    }

    return nil
}

func (o *Outputter) buildReport(images []*extractor.Image, startTime time.Time) *OutputReport {
    report := &OutputReport{
        Metadata: Metadata{
            Timestamp:   time.Now().Format(time.RFC3339),
            Environment: o.config.Environment,
            Platform:    fmt.Sprintf("%s/%s", o.config.Platform.OS, o.config.Platform.Arch),
            Version:     "1.0.0",
        },
        Summary: Summary{
            TotalImages:   len(images),
            UniqueImages:  o.countUniqueImages(images),
            TotalCharts:   o.countCharts(images),
            ExecutionTime: time.Since(startTime).String(),
        },
        Images:     images,
        ByChart:    o.groupByChart(images),
        ByRegistry: o.groupByRegistry(images),
    }

    return report
}

func (o *Outputter) printSummary(images []*extractor.Image) {
    fmt.Println("\n📊 이미지 추출 요약")
    fmt.Println("=" + strings.Repeat("=", 50))

    // 통계
    fmt.Printf("총 이미지 수: %d\n", len(images))
    fmt.Printf("고유 이미지: %d\n", o.countUniqueImages(images))
    fmt.Printf("차트 수: %d\n", o.countCharts(images))

    // 레지스트리별 분류
    fmt.Println("\n📦 레지스트리별 분포:")
    byRegistry := o.groupByRegistry(images)
    for registry, imgs := range byRegistry {
        if registry == "" {
            registry = "docker.io"
        }
        fmt.Printf("  - %s: %d개\n", registry, len(imgs))
    }

    // 샘플 출력
    fmt.Println("\n📄 이미지 샘플 (처음 10개):")
    count := 10
    if len(images) < count {
        count = len(images)
    }

    for i := 0; i < count; i++ {
        fmt.Printf("  %s\n", images[i].Full)
    }

    if len(images) > 10 {
        fmt.Printf("  ... (나머지 %d개 생략)\n", len(images)-10)
    }
}

func (o *Outputter) countUniqueImages(images []*extractor.Image) int {
    unique := make(map[string]bool)
    for _, img := range images {
        key := fmt.Sprintf("%s/%s", img.Repository, img.Tag)
        unique[key] = true
    }
    return len(unique)
}

func (o *Outputter) countCharts(images []*extractor.Image) int {
    charts := make(map[string]bool)
    for _, img := range images {
        source := strings.Split(img.Source, " ")[0]
        charts[source] = true
    }
    return len(charts)
}

func (o *Outputter) groupByChart(images []*extractor.Image) map[string][]string {
    grouped := make(map[string][]string)
    for _, img := range images {
        source := strings.Split(img.Source, " ")[0]
        grouped[source] = append(grouped[source], img.Full)
    }
    return grouped
}

func (o *Outputter) groupByRegistry(images []*extractor.Image) map[string][]string {
    grouped := make(map[string][]string)
    for _, img := range images {
        registry := img.Registry
        if registry == "" {
            registry = "docker.io"
        }
        grouped[registry] = append(grouped[registry], img.Full)
    }
    return grouped
}

// 다운로드 스크립트 생성
func (o *Outputter) GenerateDownloadScript(images []*extractor.Image) error {
    scriptPath := strings.TrimSuffix(o.config.OutputPath, filepath.Ext(o.config.OutputPath)) + "-download.sh"

    file, err := os.Create(scriptPath)
    if err != nil {
        return err
    }
    defer file.Close()

    // 스크립트 헤더
    fmt.Fprintln(file, "#!/bin/bash")
    fmt.Fprintln(file, "# Astrago Image Download Script")
    fmt.Fprintln(file, "# Generated:", time.Now().Format(time.RFC3339))
    fmt.Fprintln(file, "# Total images:", len(images))
    fmt.Fprintln(file)
    fmt.Fprintln(file, "set -e")
    fmt.Fprintln(file)

    // 프로그레스 함수
    fmt.Fprintln(file, "COUNT=0")
    fmt.Fprintln(file, "TOTAL="+fmt.Sprint(len(images)))
    fmt.Fprintln(file)

    // 다운로드 명령
    for _, img := range images {
        fmt.Fprintf(file, "echo \"[$(( ++COUNT ))/$TOTAL] Pulling %s\"\n", img.Full)
        fmt.Fprintf(file, "docker pull %s || crane pull %s %s.tar\n", img.Full, img.Full,
            strings.ReplaceAll(img.Full, "/", "_"))
        fmt.Fprintln(file)
    }

    fmt.Fprintln(file, "echo \"✅ 모든 이미지 다운로드 완료\"")

    // 실행 권한 부여
    os.Chmod(scriptPath, 0755)

    return nil
}
```

### 📊 Phase 3 검증 체크리스트

- [ ] Operator 특수 처리 구현
- [ ] 다양한 출력 형식 지원
- [ ] 다운로드 스크립트 생성
- [ ] 보완 추출 메커니즘 구현
- [ ] 레포트 생성 기능
- [ ] 성능 측정 및 로깅

---

## 📅 Phase 4: Optimization (Week 4)
> **성능 최적화 및 안정화**

### 4.1 성능 최적화

#### 병렬 처리 최적화
```go
// Worker Pool 패턴 구현
type WorkerPool struct {
    workers   int
    jobs      chan Job
    results   chan Result
    wg        sync.WaitGroup
}

// 캐싱 메커니즘
type Cache struct {
    store sync.Map
    ttl   time.Duration
}

// 메모리 풀 사용
var bufferPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}
```

#### 벤치마크 테스트
```go
func BenchmarkImageExtraction(b *testing.B) {
    for i := 0; i < b.N; i++ {
        // 추출 로직 벤치마크
    }
}

func BenchmarkParallelVsSequential(b *testing.B) {
    b.Run("Sequential", func(b *testing.B) {
        // 순차 처리 벤치마크
    })

    b.Run("Parallel", func(b *testing.B) {
        // 병렬 처리 벤치마크
    })
}
```

### 4.2 에러 처리 및 복구

```go
type ErrorHandler struct {
    maxRetries int
    backoff    time.Duration
}

func (e *ErrorHandler) WithRetry(fn func() error) error {
    var lastErr error

    for i := 0; i < e.maxRetries; i++ {
        if err := fn(); err == nil {
            return nil
        } else {
            lastErr = err
            time.Sleep(e.backoff * time.Duration(i+1))
        }
    }

    return fmt.Errorf("max retries exceeded: %w", lastErr)
}
```

### 📊 Phase 4 검증 체크리스트

- [ ] 병렬 처리 성능 측정
- [ ] 메모리 사용량 최적화
- [ ] 캐싱 메커니즘 구현
- [ ] 에러 복구 전략 구현
- [ ] 벤치마크 테스트 작성
- [ ] 프로파일링 및 분석

---

## 📅 Phase 5: Deployment (Week 5-6)
> **배포 준비 및 문서화**

### 5.1 CI/CD 파이프라인

**`.github/workflows/ci.yml`**
```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Set up Go
      uses: actions/setup-go@v4
      with:
        go-version: '1.21'

    - name: Install dependencies
      run: make deps

    - name: Run tests
      run: make test

    - name: Run linter
      run: make lint

    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage.out

  build:
    needs: test
    runs-on: ubuntu-latest
    strategy:
      matrix:
        goos: [linux, darwin]
        goarch: [amd64, arm64]

    steps:
    - uses: actions/checkout@v3

    - name: Set up Go
      uses: actions/setup-go@v4
      with:
        go-version: '1.21'

    - name: Build
      env:
        GOOS: ${{ matrix.goos }}
        GOARCH: ${{ matrix.goarch }}
      run: |
        make build
        mv bin/extract-images bin/extract-images-${{ matrix.goos }}-${{ matrix.goarch }}

    - name: Upload artifact
      uses: actions/upload-artifact@v3
      with:
        name: binaries
        path: bin/
```

### 5.2 릴리즈 자동화

**`.goreleaser.yaml`**
```yaml
project_name: helm-image-extractor

before:
  hooks:
    - go mod tidy
    - go generate ./...

builds:
  - env:
      - CGO_ENABLED=0
    goos:
      - linux
      - darwin
    goarch:
      - amd64
      - arm64
    binary: extract-images
    ldflags:
      - -s -w
      - -X main.version={{.Version}}
      - -X main.commit={{.Commit}}
      - -X main.date={{.Date}}

archives:
  - format: tar.gz
    name_template: >-
      {{ .ProjectName }}_
      {{- title .Os }}_
      {{- if eq .Arch "amd64" }}x86_64
      {{- else if eq .Arch "386" }}i386
      {{- else }}{{ .Arch }}{{ end }}
    format_overrides:
      - goos: windows
        format: zip

checksum:
  name_template: 'checksums.txt'

snapshot:
  name_template: "{{ incpatch .Version }}-next"

changelog:
  sort: asc
  filters:
    exclude:
      - '^docs:'
      - '^test:'
```

### 5.3 문서화

**`docs/USER_GUIDE.md`**
```markdown
# 사용자 가이드

## 설치

### 바이너리 다운로드
```bash
# Linux
wget https://github.com/astrago/helm-image-extractor/releases/download/v1.0.0/extract-images-linux-amd64
chmod +x extract-images-linux-amd64
sudo mv extract-images-linux-amd64 /usr/local/bin/extract-images

# macOS
wget https://github.com/astrago/helm-image-extractor/releases/download/v1.0.0/extract-images-darwin-arm64
chmod +x extract-images-darwin-arm64
sudo mv extract-images-darwin-arm64 /usr/local/bin/extract-images
```

### 소스에서 빌드
```bash
git clone https://github.com/astrago/helm-image-extractor.git
cd helm-image-extractor
make build
sudo make install
```

## 사용법

### 기본 사용
```bash
# Helmfile에서 자동 감지
extract-images

# 특정 Helmfile 지정
extract-images -f /path/to/helmfile.yaml

# 특정 환경 지정
extract-images -e production

# JSON 출력
extract-images --json -o images.json
```

### 고급 옵션
```bash
# 병렬 처리 비활성화
extract-images --parallel=false

# Worker 수 조정
extract-images --workers=8

# 상세 출력
extract-images -v

# 캐시 활성화
extract-images --cache --cache-dir=/tmp/cache
```

## 설정 파일

`~/.extract-images.yaml`:
```yaml
helmfile_path: /path/to/helmfile.yaml
environment: default
output_format: text
parallel: true
workers: 4
cache:
  enabled: true
  dir: ~/.cache/extract-images
  ttl: 3600
supplemental:
  enabled: true
  patterns:
    - "**/values.yaml"
    - "**/config.yaml"
```

## 문제 해결

### 일반적인 문제

1. **Helmfile을 찾을 수 없음**
   - 현재 디렉토리 또는 상위 디렉토리에 helmfile이 있는지 확인
   - `-f` 플래그로 명시적 경로 지정

2. **이미지 누락**
   - Operator 차트의 경우 `--supplemental` 옵션 활성화
   - 상세 모드(`-v`)로 실행하여 로그 확인

3. **메모리 부족**
   - Worker 수 감소 (`--workers=2`)
   - 캐시 비활성화 (`--cache=false`)
```

### 📊 Phase 5 검증 체크리스트

- [ ] CI/CD 파이프라인 구성
- [ ] 자동화된 릴리즈 프로세스
- [ ] 포괄적인 문서화
- [ ] 도커 이미지 빌드
- [ ] 설치 스크립트 제공
- [ ] 예제 및 튜토리얼

---

## 🚀 마이그레이션 계획

### 기존 시스템에서 전환

#### Phase 1: 병렬 실행 (Week 1)
```bash
# 기존 스크립트와 새 도구 비교
./extract-images.sh > old.txt
extract-images -o new.txt
diff old.txt new.txt
```

#### Phase 2: 점진적 전환 (Week 2)
```bash
# 일부 환경에서 새 도구 사용
if [ "$ENVIRONMENT" = "dev" ]; then
    extract-images -e dev
else
    ./extract-images.sh
fi
```

#### Phase 3: 완전 전환 (Week 3)
```bash
# 모든 환경에서 새 도구 사용
extract-images -e $ENVIRONMENT
```

### 롤백 계획
```bash
# 이전 버전 유지
mv extract-images.sh extract-images.sh.backup

# 문제 발생시 롤백
mv extract-images.sh.backup extract-images.sh
```

---

## 📊 성공 지표 추적

### KPI 모니터링
```yaml
performance:
  execution_time: < 5s
  memory_usage: < 100MB
  cpu_usage: < 50%

reliability:
  success_rate: > 99.9%
  error_recovery: < 1s

coverage:
  chart_coverage: 100%
  image_extraction: 100%
  operator_support: 100%

adoption:
  user_satisfaction: > 90%
  migration_success: 100%
  documentation_completeness: 100%
```

### 모니터링 대시보드
```go
type Metrics struct {
    ExecutionTime   time.Duration
    MemoryUsage     uint64
    ImagesExtracted int
    ChartsProcessed int
    ErrorCount      int
    CacheHitRate    float64
}

func (m *Metrics) Report() {
    // Prometheus 메트릭 출력
    // Grafana 대시보드 연동
}
```

---

## 📅 타임라인 요약

| Phase | 기간 | 주요 산출물 | 완료 기준 |
|-------|------|------------|----------|
| **Phase 1** | Week 1 | 기반 구조, Config, Discovery | 프로젝트 구조 완성, 차트 발견 동작 |
| **Phase 2** | Week 2 | Renderer, Extractor, Patterns | 핵심 기능 구현, 이미지 추출 성공 |
| **Phase 3** | Week 3 | Operator 지원, Output, 보완 기능 | 모든 차트 타입 지원 |
| **Phase 4** | Week 4 | 성능 최적화, 에러 처리 | 성능 목표 달성 |
| **Phase 5** | Week 5-6 | CI/CD, 문서화, 배포 | 프로덕션 준비 완료 |

---

## 🎯 리스크 관리

### 식별된 리스크

| 리스크 | 발생 가능성 | 영향도 | 완화 전략 |
|--------|------------|--------|-----------|
| Helm SDK 호환성 | 중 | 높음 | 다중 버전 지원, Fallback 메커니즘 |
| Operator 패턴 변경 | 높음 | 중간 | 플러그인 아키텍처, 동적 로딩 |
| 성능 목표 미달성 | 낮음 | 중간 | 프로파일링, 최적화 반복 |
| 마이그레이션 실패 | 낮음 | 높음 | 점진적 전환, 롤백 계획 |

### 대응 계획
```go
type RiskMitigation struct {
    Risk        string
    Probability float64
    Impact      string
    Strategy    []string
    Triggers    []string
    Actions     []string
}

var risks = []RiskMitigation{
    {
        Risk:        "Helm SDK 버전 충돌",
        Probability: 0.4,
        Impact:      "HIGH",
        Strategy:    []string{"버전 감지", "동적 로딩"},
        Triggers:    []string{"컴파일 실패", "런타임 에러"},
        Actions:     []string{"Fallback 활성화", "helmfile 직접 실행"},
    },
}
```

---

## 📝 체크포인트

### Weekly Review
- [ ] Week 1: Foundation 완료
- [ ] Week 2: Core 구현 완료
- [ ] Week 3: Enhancement 완료
- [ ] Week 4: Optimization 완료
- [ ] Week 5: Deployment 준비
- [ ] Week 6: Production 배포

### Daily Standup Questions
1. 오늘 완료한 작업은?
2. 내일 계획된 작업은?
3. 블로커가 있는가?

---

## 🎉 프로젝트 완료 기준

### Definition of Done
- ✅ 모든 테스트 통과 (Coverage > 80%)
- ✅ 문서화 완료 (사용자/개발자/API)
- ✅ CI/CD 파이프라인 구성
- ✅ 성능 목표 달성
- ✅ 보안 검토 통과
- ✅ 마이그레이션 완료
- ✅ 사용자 교육 완료

### Success Celebration 🎊
- 팀 회고 미팅
- 성과 공유 세션
- 다음 단계 계획

---

## 📚 참고 자료

### 필수 문서
- [Helm SDK Documentation](https://helm.sh/docs/topics/advanced/)
- [Go Best Practices](https://go.dev/doc/effective_go)
- [Kubernetes API Reference](https://kubernetes.io/docs/reference/)

### 도구 및 라이브러리
- [Cobra CLI Framework](https://github.com/spf13/cobra)
- [Viper Configuration](https://github.com/spf13/viper)
- [GoReleaser](https://goreleaser.com/)

### 관련 프로젝트
- [Helm](https://github.com/helm/helm)
- [Helmfile](https://github.com/helmfile/helmfile)
- [Crane](https://github.com/google/go-containerregistry/tree/main/cmd/crane)

---

**문서 버전**: 1.0.0
**작성일**: 2024년 10월
**작성자**: Astrago Engineering Team
**검토자**: Technical Lead
**승인자**: Project Manager

---

이 구현 계획서는 실제 개발 진행에 따라 업데이트될 수 있습니다.
피드백과 개선 제안은 언제든지 환영합니다! 🚀