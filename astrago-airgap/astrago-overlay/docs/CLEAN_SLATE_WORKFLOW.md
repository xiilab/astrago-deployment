# 🚀 Clean Slate Workflow - Astrago Image Extractor 완전 재구축

> **Version 1.0.0 | 2024년 10월**
> **프로젝트 기간: 6-7주** (Phase 0: 3일 + Phase 1-5: 5-6주)
> **전략: 완전한 새 시작 (Clean Slate)**

## 📌 Executive Summary

본 워크플로우는 **astrago-overlay를 완전히 삭제하고 처음부터 재구축**하는 계획입니다.
기존 문서([TECHNICAL_SPECIFICATION_V2.md](./TECHNICAL_SPECIFICATION_V2.md), [EXECUTION_PLAN.md](./EXECUTION_PLAN.md))의 요구사항은 유지하되,
**Clean Architecture와 Go 모범 사례**를 적용하여 처음부터 올바르게 구축합니다.

### 왜 Clean Slate인가?

**기존 문제점**:
- 단일 파일 구조 (`extract-images.go`) - 유지보수 어려움
- 레이어 분리 없음 - 테스트 불가능
- 의존성 주입 없음 - 확장성 제한
- 문서와 구현 불일치

**새로운 접근**:
- ✅ 3-Layer 아키텍처 (`cmd/`, `internal/`, `pkg/`)
- ✅ 의존성 주입 (DI) 패턴
- ✅ 테스트 우선 개발 (TDD)
- ✅ 표준 Go 프로젝트 구조

---

## 🗂️ 새로운 프로젝트 구조

```
astrago-overlay/
├── cmd/
│   └── extractor/              # CLI 진입점
│       └── main.go
├── internal/                   # 비공개 패키지
│   ├── config/                 # 설정 관리
│   │   ├── config.go
│   │   └── config_test.go
│   ├── discovery/              # Helmfile 파싱 & 차트 발견
│   │   ├── discovery.go
│   │   ├── helmfile.go
│   │   ├── values.go
│   │   └── discovery_test.go
│   ├── renderer/               # Helm SDK 렌더링
│   │   ├── renderer.go
│   │   └── renderer_test.go
│   ├── extractor/              # 이미지 추출
│   │   ├── extractor.go
│   │   ├── patterns.go
│   │   └── extractor_test.go
│   ├── writer/                 # 출력 처리
│   │   ├── writer.go
│   │   ├── formats.go
│   │   └── writer_test.go
│   └── validator/              # 입력 검증
│       ├── validator.go
│       └── validator_test.go
├── pkg/                        # 공개 패키지 (추후 확장)
│   └── types/
│       └── image.go
├── test/                       # 테스트 데이터
│   ├── fixtures/
│   │   ├── helmfile.yaml
│   │   └── values/
│   └── e2e/
│       └── full_workflow_test.sh
├── docs/                       # 문서
│   ├── TECHNICAL_SPECIFICATION_V2.md
│   ├── ARCHITECTURE.md
│   ├── EXECUTION_PLAN.md
│   └── CLEAN_SLATE_WORKFLOW.md  (이 문서)
├── scripts/                    # 유틸리티 스크립트
│   ├── backup.sh
│   └── setup.sh
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── release.yml
├── .gitignore
├── go.mod
├── go.sum
├── Makefile
└── README.md
```

---

## 🚨 Phase 0: 프로젝트 초기화 (Day 1-3)

**목표**: 기존 삭제 → 새 프로젝트 생성 → 기본 구조 구축
**기간**: 3일
**우선순위**: P0 (최고)

### Day 1 Morning (09:00-12:00): 백업 및 초기화

#### Step 1: 기존 백업 (09:00-09:15) 🔄

```bash
cd astrago-airgap/

# 1. 현재 상태 확인
ls -la astrago-overlay/
git status

# 2. 타임스탬프 백업
BACKUP_DIR="astrago-overlay.backup.$(date +%Y%m%d-%H%M%S)"
mv astrago-overlay "$BACKUP_DIR"

echo "✅ 백업 완료: $BACKUP_DIR"
ls -la "$BACKUP_DIR"
```

**백업 확인**:
- [ ] 기존 `astrago-overlay` 디렉토리 백업 완료
- [ ] 백업 디렉토리에 모든 파일 존재 확인
- [ ] Git 히스토리 보존 확인

---

#### Step 2: 새 프로젝트 생성 (09:15-10:00) 🆕

```bash
# 1. 새 디렉토리 생성
mkdir -p astrago-overlay
cd astrago-overlay

# 2. Go 모듈 초기화
go mod init github.com/astrago/image-extractor

# 3. 기본 디렉토리 구조 생성
mkdir -p cmd/extractor
mkdir -p internal/{config,discovery,renderer,extractor,writer,validator}
mkdir -p pkg/types
mkdir -p test/{fixtures,e2e}
mkdir -p test/fixtures/values
mkdir -p docs
mkdir -p scripts
mkdir -p .github/workflows

# 4. 구조 확인
tree -L 3 -d
```

**생성 확인**:
- [ ] `go.mod` 파일 생성 확인
- [ ] 모든 디렉토리 생성 확인
- [ ] 구조가 설계대로 생성되었는지 확인

---

#### Step 3: 필수 의존성 설치 (10:00-11:00) 📦

```bash
# 1. Helm SDK v3.14.0 설치
go get helm.sh/helm/v3@v3.14.0

# 2. Cobra CLI 프레임워크
go get github.com/spf13/cobra@latest

# 3. 로깅 라이브러리 (zerolog)
go get github.com/rs/zerolog@v1.31.0

# 4. YAML 파싱
go get gopkg.in/yaml.v3@latest

# 5. 테스트 라이브러리
go get github.com/stretchr/testify@latest

# 6. 의존성 정리
go mod tidy

# 7. go.mod 확인
cat go.mod
```

**의존성 확인**:
- [ ] `helm.sh/helm/v3 v3.14.0` 존재
- [ ] `github.com/spf13/cobra` 존재
- [ ] `github.com/rs/zerolog v1.31.0` 존재
- [ ] `go mod tidy` 성공

---

#### Step 4: 기본 파일 생성 (11:00-12:00) 📝

##### .gitignore 생성

```bash
cat > .gitignore << 'EOF'
# Binaries
/bin/
*.exe
*.exe~
*.dll
*.so
*.dylib

# Test binary, built with `go test -c`
*.test

# Output of the go coverage tool
*.out
coverage.txt
coverage.html

# Go workspace file
go.work

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Output files
kubespray-offline/
imagelists/
*.txt
*.json
*.yaml
!test/fixtures/*.yaml
!test/fixtures/**/*.yaml

# Temp
/tmp/
EOF
```

##### Makefile 생성

```bash
cat > Makefile << 'EOF'
.PHONY: help build test lint clean deps install

# Variables
BINARY_NAME=extract-images
VERSION?=v1.0.0
BUILD_DIR=bin
GO=go
GOFLAGS=-v

# Help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Dependencies
deps: ## Install dependencies
	$(GO) mod download
	$(GO) mod tidy

# Build
build: ## Build binary for current platform
	mkdir -p $(BUILD_DIR)
	$(GO) build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/extractor

build-all: ## Build binaries for all platforms
	mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=amd64 $(GO) build -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 ./cmd/extractor
	GOOS=linux GOARCH=arm64 $(GO) build -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 ./cmd/extractor
	GOOS=darwin GOARCH=amd64 $(GO) build -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 ./cmd/extractor
	GOOS=darwin GOARCH=arm64 $(GO) build -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 ./cmd/extractor

# Test
test: ## Run unit tests
	$(GO) test -v -race -coverprofile=coverage.txt -covermode=atomic ./...

test-coverage: ## Generate coverage report
	$(GO) test -v -race -coverprofile=coverage.txt -covermode=atomic ./...
	$(GO) tool cover -html=coverage.txt -o coverage.html
	@echo "Coverage report: coverage.html"

test-integration: ## Run integration tests
	$(GO) test -v -tags=integration ./test/...

test-e2e: build ## Run E2E tests
	./test/e2e/full_workflow_test.sh

# Lint
lint: ## Run linter
	golangci-lint run ./...

fmt: ## Format code
	$(GO) fmt ./...
	gofmt -s -w .

# Clean
clean: ## Clean build artifacts
	rm -rf $(BUILD_DIR)
	rm -f coverage.txt coverage.html

# Install
install: build ## Install binary to $GOPATH/bin
	$(GO) install ./cmd/extractor

# Run
run: ## Run with default arguments
	$(GO) run ./cmd/extractor --help

.DEFAULT_GOAL := help
EOF
```

##### README.md 초기 버전

```bash
cat > README.md << 'EOF'
# Astrago Helm Chart Image Extractor

> **Status**: 🚧 Under Development (Clean Slate Rebuild)

Helmfile 기반 Helm 차트에서 컨테이너 이미지를 자동으로 추출하는 도구입니다.
오프라인/에어갭 Kubernetes 환경 배포를 위한 이미지 리스트를 생성합니다.

## 🎯 프로젝트 목표

- **핵심 기능**: Helmfile 자동 파싱 및 이미지 추출 (95%+ 커버리지)
- **성능 목표**: 50개 차트 < 1초 (병렬 처리)
- **품질 목표**: 테스트 커버리지 80%+, 보안 검증 통과

## 🚀 빠른 시작

### 빌드

```bash
make build
```

### 실행

```bash
./bin/extract-images --helmfile helmfile.yaml --environment default
```

## 📖 문서

- [기술 명세서](docs/TECHNICAL_SPECIFICATION_V2.md)
- [아키텍처 가이드](docs/ARCHITECTURE.md)
- [실행 계획](docs/EXECUTION_PLAN.md)
- [Clean Slate 워크플로우](docs/CLEAN_SLATE_WORKFLOW.md)

## 🏗️ 아키텍처

3-Layer 아키텍처:
- **Application Layer**: CLI Interface (Cobra)
- **Core Layer**: Discovery, Renderer, Extractor
- **Data Layer**: Parser, Validator, Writer

## 🤝 기여하기

TBD

## 📄 라이선스

Apache License 2.0
EOF
```

**파일 확인**:
- [ ] `.gitignore` 생성 확인
- [ ] `Makefile` 생성 및 `make help` 동작 확인
- [ ] `README.md` 생성 확인

---

### Day 1 Afternoon (13:00-17:00): 기본 구조 구현

#### Step 5: Config 패키지 구현 (13:00-14:30) ⚙️

```bash
# internal/config/config.go
cat > internal/config/config.go << 'EOF'
package config

import (
	"fmt"
	"os"
	"path/filepath"
)

// Config holds application configuration
type Config struct {
	// Helmfile settings
	HelmfilePath string
	Environment  string

	// Output settings
	OutputPath string
	Format     string // text, json, yaml

	// Execution settings
	Verbose  bool
	Parallel bool
	Workers  int

	// Deprecated flags (for backward compatibility)
	JSONOutput bool
}

// Validate checks if configuration is valid
func (c *Config) Validate() error {
	// Helmfile path must exist
	if c.HelmfilePath == "" {
		return fmt.Errorf("helmfile path is required")
	}

	absPath, err := filepath.Abs(c.HelmfilePath)
	if err != nil {
		return fmt.Errorf("invalid helmfile path: %w", err)
	}

	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		return fmt.Errorf("helmfile not found: %s", absPath)
	}

	c.HelmfilePath = absPath

	// Format validation
	validFormats := map[string]bool{"text": true, "json": true, "yaml": true}
	if !validFormats[c.Format] {
		return fmt.Errorf("unsupported format: %s (valid: text, json, yaml)", c.Format)
	}

	// Handle deprecated JSON flag
	if c.JSONOutput {
		c.Format = "json"
	}

	// Workers must be > 0
	if c.Workers <= 0 {
		c.Workers = 5 // default
	}

	return nil
}

// EnsureOutputDir creates output directory if it doesn't exist
func (c *Config) EnsureOutputDir() error {
	dir := filepath.Dir(c.OutputPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}
	return nil
}
EOF

# internal/config/config_test.go
cat > internal/config/config_test.go << 'EOF'
package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConfig_Validate(t *testing.T) {
	// Create temp helmfile for testing
	tmpDir := t.TempDir()
	helmfilePath := filepath.Join(tmpDir, "helmfile.yaml")
	err := os.WriteFile(helmfilePath, []byte("releases: []"), 0644)
	require.NoError(t, err)

	tests := []struct {
		name    string
		config  Config
		wantErr bool
		errMsg  string
	}{
		{
			name: "valid config",
			config: Config{
				HelmfilePath: helmfilePath,
				Environment:  "default",
				Format:       "text",
				Workers:      5,
			},
			wantErr: false,
		},
		{
			name: "missing helmfile path",
			config: Config{
				Environment: "default",
				Format:      "text",
			},
			wantErr: true,
			errMsg:  "helmfile path is required",
		},
		{
			name: "helmfile not found",
			config: Config{
				HelmfilePath: "/nonexistent/helmfile.yaml",
				Format:       "text",
			},
			wantErr: true,
			errMsg:  "helmfile not found",
		},
		{
			name: "invalid format",
			config: Config{
				HelmfilePath: helmfilePath,
				Format:       "invalid",
			},
			wantErr: true,
			errMsg:  "unsupported format",
		},
		{
			name: "deprecated json flag",
			config: Config{
				HelmfilePath: helmfilePath,
				Format:       "text",
				JSONOutput:   true,
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.Validate()

			if tt.wantErr {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tt.errMsg)
			} else {
				assert.NoError(t, err)

				// Check deprecated flag handling
				if tt.config.JSONOutput {
					assert.Equal(t, "json", tt.config.Format)
				}

				// Check default workers
				if tt.config.Workers == 0 {
					assert.Equal(t, 5, tt.config.Workers)
				}
			}
		})
	}
}

func TestConfig_EnsureOutputDir(t *testing.T) {
	tmpDir := t.TempDir()

	tests := []struct {
		name       string
		outputPath string
		wantErr    bool
	}{
		{
			name:       "create nested directory",
			outputPath: filepath.Join(tmpDir, "nested", "dir", "output.txt"),
			wantErr:    false,
		},
		{
			name:       "existing directory",
			outputPath: filepath.Join(tmpDir, "output.txt"),
			wantErr:    false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := &Config{OutputPath: tt.outputPath}
			err := cfg.EnsureOutputDir()

			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)

				// Verify directory was created
				dir := filepath.Dir(tt.outputPath)
				_, err := os.Stat(dir)
				assert.NoError(t, err)
			}
		})
	}
}
EOF
```

**테스트 실행**:
```bash
go test -v ./internal/config/...
```

---

#### Step 6: CLI 진입점 구현 (14:30-17:00) 🖥️

```bash
# cmd/extractor/main.go
cat > cmd/extractor/main.go << 'EOF'
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/astrago/image-extractor/internal/config"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"
)

var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

var rootCmd = &cobra.Command{
	Use:   "extract-images",
	Short: "Helm 차트에서 컨테이너 이미지 추출",
	Long: `Helmfile 기반 Helm 차트에서 컨테이너 이미지를 자동으로 추출합니다.
오프라인/에어갭 Kubernetes 환경 배포를 위한 이미지 리스트를 생성합니다.`,
	Version: fmt.Sprintf("%s (commit: %s, built: %s)", version, commit, date),
	RunE:    run,
}

func init() {
	// Required flags
	rootCmd.Flags().StringP("helmfile", "f", "", "Helmfile 경로 (필수)")
	rootCmd.MarkFlagRequired("helmfile")

	// Optional flags
	rootCmd.Flags().StringP("environment", "e", "default", "Helmfile 환경")
	rootCmd.Flags().StringP("output", "o", "kubespray-offline/imagelists/astrago.txt", "출력 파일")
	rootCmd.Flags().StringP("format", "F", "text", "출력 형식 (text|json|yaml)")
	rootCmd.Flags().BoolP("verbose", "v", false, "상세 로그 출력")
	rootCmd.Flags().BoolP("parallel", "p", true, "병렬 처리 활성화")
	rootCmd.Flags().IntP("workers", "w", 5, "병렬 워커 수")

	// Deprecated flags (backward compatibility)
	rootCmd.Flags().Bool("json", false, "JSON 형식 출력 (deprecated: use --format json)")
}

func run(cmd *cobra.Command, args []string) error {
	// Setup logging
	setupLogging(cmd)

	// Build configuration
	cfg, err := buildConfig(cmd)
	if err != nil {
		return fmt.Errorf("configuration error: %w", err)
	}

	// Validate configuration
	if err := cfg.Validate(); err != nil {
		return fmt.Errorf("validation error: %w", err)
	}

	// Ensure output directory exists
	if err := cfg.EnsureOutputDir(); err != nil {
		return err
	}

	log.Info().
		Str("helmfile", cfg.HelmfilePath).
		Str("environment", cfg.Environment).
		Str("output", cfg.OutputPath).
		Str("format", cfg.Format).
		Msg("Starting image extraction")

	// TODO: Implement extraction pipeline
	// 1. Discovery: Parse Helmfile and discover releases
	// 2. Renderer: Render charts using Helm SDK
	// 3. Extractor: Extract images from manifests
	// 4. Writer: Write images to output file

	log.Info().Msg("🚧 Image extraction pipeline not yet implemented")
	log.Info().Msg("This is Phase 0 - basic structure only")

	return nil
}

func buildConfig(cmd *cobra.Command) (*config.Config, error) {
	helmfile, _ := cmd.Flags().GetString("helmfile")
	environment, _ := cmd.Flags().GetString("environment")
	output, _ := cmd.Flags().GetString("output")
	format, _ := cmd.Flags().GetString("format")
	verbose, _ := cmd.Flags().GetBool("verbose")
	parallel, _ := cmd.Flags().GetBool("parallel")
	workers, _ := cmd.Flags().GetInt("workers")
	jsonFlag, _ := cmd.Flags().GetBool("json")

	// Handle deprecated --json flag
	if jsonFlag {
		fmt.Fprintln(os.Stderr, "Warning: --json is deprecated, use --format json instead")
	}

	return &config.Config{
		HelmfilePath: helmfile,
		Environment:  environment,
		OutputPath:   output,
		Format:       format,
		Verbose:      verbose,
		Parallel:     parallel,
		Workers:      workers,
		JSONOutput:   jsonFlag,
	}, nil
}

func setupLogging(cmd *cobra.Command) {
	verbose, _ := cmd.Flags().GetBool("verbose")

	// Configure zerolog
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})

	if !verbose {
		zerolog.SetGlobalLevel(zerolog.InfoLevel)
	} else {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	}
}
EOF
```

**빌드 및 테스트**:
```bash
# 빌드
make build

# 기본 실행 (도움말)
./bin/extract-images --help

# 버전 확인
./bin/extract-images --version

# 간단한 테스트 (아직 구현 안 됨, 에러 확인용)
./bin/extract-images --helmfile /nonexistent.yaml
```

**Day 1 완료 기준**:
- [ ] 기존 백업 완료
- [ ] 새 프로젝트 구조 생성
- [ ] 기본 의존성 설치
- [ ] Config 패키지 구현 및 테스트 통과
- [ ] CLI 진입점 구현 및 빌드 성공

---

### Day 2: 핵심 패키지 스켈레톤 구현 (09:00-17:00)

#### Morning (09:00-12:00): Discovery 패키지 스켈레톤

```bash
# internal/discovery/discovery.go
cat > internal/discovery/discovery.go << 'EOF'
package discovery

import (
	"context"
	"fmt"

	"github.com/astrago/image-extractor/internal/config"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// Release represents a Helm release
type Release struct {
	Name         string
	Chart        string
	Namespace    string
	Version      string
	Values       []string
	MergedValues map[string]interface{}
}

// Discoverer discovers Helm releases from Helmfile
type Discoverer struct {
	config *config.Config
	logger zerolog.Logger
}

// New creates a new Discoverer
func New(cfg *config.Config) *Discoverer {
	logger := log.With().Str("component", "discovery").Logger()
	if !cfg.Verbose {
		logger = logger.Level(zerolog.InfoLevel)
	}

	return &Discoverer{
		config: cfg,
		logger: logger,
	}
}

// Discover finds all releases from Helmfile
func (d *Discoverer) Discover(ctx context.Context) ([]*Release, error) {
	d.logger.Info().Msg("Starting Helmfile discovery")

	// TODO: Implement helmfile parsing
	// - Execute `helmfile list --output json`
	// - Parse JSON response
	// - Load and merge values for each release

	return nil, fmt.Errorf("discovery not yet implemented")
}
EOF

# internal/discovery/discovery_test.go
cat > internal/discovery/discovery_test.go << 'EOF'
package discovery

import (
	"context"
	"testing"

	"github.com/astrago/image-extractor/internal/config"
	"github.com/stretchr/testify/assert"
)

func TestNew(t *testing.T) {
	cfg := &config.Config{Verbose: true}
	d := New(cfg)

	assert.NotNil(t, d)
	assert.NotNil(t, d.config)
}

func TestDiscover_NotImplemented(t *testing.T) {
	cfg := &config.Config{Verbose: false}
	d := New(cfg)

	releases, err := d.Discover(context.Background())

	assert.Error(t, err)
	assert.Nil(t, releases)
	assert.Contains(t, err.Error(), "not yet implemented")
}
EOF
```

#### Afternoon (13:00-17:00): Renderer, Extractor, Writer 스켈레톤

```bash
# Renderer 스켈레톤
cat > internal/renderer/renderer.go << 'EOF'
package renderer

import (
	"context"
	"fmt"

	"github.com/astrago/image-extractor/internal/config"
	"github.com/astrago/image-extractor/internal/discovery"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

type Renderer struct {
	config *config.Config
	logger zerolog.Logger
}

func New(cfg *config.Config) *Renderer {
	logger := log.With().Str("component", "renderer").Logger()
	return &Renderer{
		config: cfg,
		logger: logger,
	}
}

func (r *Renderer) Render(ctx context.Context, release *discovery.Release) (string, error) {
	r.logger.Debug().Str("release", release.Name).Msg("Rendering chart")
	// TODO: Implement Helm SDK rendering
	return "", fmt.Errorf("renderer not yet implemented")
}
EOF

# Extractor 스켈레톤
cat > internal/extractor/extractor.go << 'EOF'
package extractor

import (
	"context"
	"fmt"

	"github.com/astrago/image-extractor/internal/config"
	"github.com/astrago/image-extractor/internal/discovery"
	"github.com/astrago/image-extractor/internal/renderer"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

type Extractor struct {
	config *config.Config
	logger zerolog.Logger
}

func New(cfg *config.Config) *Extractor {
	logger := log.With().Str("component", "extractor").Logger()
	return &Extractor{
		config: cfg,
		logger: logger,
	}
}

func (e *Extractor) Extract(ctx context.Context, releases []*discovery.Release, renderer *renderer.Renderer) ([]string, error) {
	e.logger.Info().Msg("Starting image extraction")
	// TODO: Implement image extraction
	return nil, fmt.Errorf("extractor not yet implemented")
}
EOF

# Writer 스켈레톤
cat > internal/writer/writer.go << 'EOF'
package writer

import (
	"fmt"

	"github.com/astrago/image-extractor/internal/config"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

type Writer struct {
	config *config.Config
	logger zerolog.Logger
}

func New(cfg *config.Config) *Writer {
	logger := log.With().Str("component", "writer").Logger()
	return &Writer{
		config: cfg,
		logger: logger,
	}
}

func (w *Writer) Write(images []string) error {
	w.logger.Info().Msg("Writing images to output")
	// TODO: Implement output writing
	return fmt.Errorf("writer not yet implemented")
}
EOF
```

**Day 2 완료 기준**:
- [ ] 모든 핵심 패키지 스켈레톤 생성
- [ ] 각 패키지 컴파일 성공
- [ ] 기본 테스트 작성 및 통과
- [ ] `make build` 성공

---

### Day 3: 테스트 인프라 및 문서 정리 (09:00-17:00)

#### Morning (09:00-12:00): 테스트 픽스처 생성

```bash
# 테스트용 Helmfile
cat > test/fixtures/helmfile.yaml << 'EOF'
releases:
  - name: test-nginx
    namespace: default
    chart: nginx
    version: 1.21.0
    values:
      - ./values/nginx-values.yaml

  - name: test-redis
    namespace: default
    chart: redis
    version: 6.2.0
    values:
      - ./values/redis-values.yaml
EOF

# nginx values
mkdir -p test/fixtures/values
cat > test/fixtures/values/nginx-values.yaml << 'EOF'
image:
  repository: nginx
  tag: "1.21"
EOF

# redis values
cat > test/fixtures/values/redis-values.yaml << 'EOF'
image:
  repository: redis
  tag: "6.2"
EOF
```

#### Afternoon (13:00-17:00): 문서 이동 및 정리

```bash
# 기존 백업에서 문서 복사
BACKUP_DIR=$(ls -td astrago-overlay.backup.* | head -1)

cp "$BACKUP_DIR/docs/TECHNICAL_SPECIFICATION_V2.md" docs/
cp "$BACKUP_DIR/docs/ARCHITECTURE.md" docs/
cp "$BACKUP_DIR/docs/IMPLEMENTATION_PLAN.md" docs/
cp "$BACKUP_DIR/docs/EXECUTION_PLAN.md" docs/
cp "$BACKUP_DIR/docs/PHASE_0_CRITICAL_FIXES.md" docs/

# 현재 워크플로우 문서는 이미 생성됨
# docs/CLEAN_SLATE_WORKFLOW.md
```

**Phase 0 완료 기준**:
- [ ] 프로젝트 구조 완성
- [ ] 모든 패키지 스켈레톤 생성
- [ ] 기본 테스트 인프라 구축
- [ ] `make build` 성공
- [ ] `make test` 성공 (스켈레톤 테스트)
- [ ] 문서 정리 완료

---

## 🏗️ Phase 1: 핵심 기능 구현 (Week 1-2)

**Phase 1부터는 기존 [EXECUTION_PLAN.md](./EXECUTION_PLAN.md)의 내용을 그대로 따릅니다.**

**단, 차이점**:
- ✅ 이미 올바른 구조가 구축되어 있음
- ✅ 패키지 분리가 완료되어 있음
- ✅ 테스트 인프라가 준비되어 있음

### Week 1: Discovery & Renderer 구현

**Day 4-5**: Discovery 패키지 완성 (Helmfile 파싱, Values 병합)
**Day 6-7**: Renderer 패키지 완성 (Helm SDK 통합, action.Configuration 초기화)
**Day 8**: 통합 테스트

**상세 구현 내용은 [EXECUTION_PLAN.md의 Phase 1](./EXECUTION_PLAN.md#phase-1-핵심-기능-구현-week-1-2) 참조**

### Week 2: Extractor & Writer 구현

**Day 9-10**: Extractor 패키지 완성 (정규식 패턴, 병렬 처리)
**Day 11-12**: Writer 패키지 완성 (Text/JSON/YAML 출력)
**Day 13**: 통합 테스트 및 Week 2 마무리

---

## 🧪 Phase 2: 테스트 및 검증 (Week 3)

**상세 내용은 [EXECUTION_PLAN.md의 Phase 2](./EXECUTION_PLAN.md#phase-2-테스트-및-검증-week-3) 참조**

---

## ⚡ Phase 3: 최적화 (Week 4)

**상세 내용은 [EXECUTION_PLAN.md의 Phase 3](./EXECUTION_PLAN.md#phase-3-최적화-week-4) 참조**

---

## 📚 Phase 4: 문서화 및 배포 (Week 5)

**상세 내용은 [EXECUTION_PLAN.md의 Phase 4](./EXECUTION_PLAN.md#phase-4-문서화-및-배포-준비-week-5) 참조**

---

## 🔄 Phase 5: 예비 기간 (Week 6)

**상세 내용은 [EXECUTION_PLAN.md의 Phase 5](./EXECUTION_PLAN.md#phase-5-예비-기간-및-리팩토링-week-6) 참조**

---

## 🎯 Clean Slate의 장점

### ✅ 기술적 장점

1. **Clean Architecture**
   - 명확한 레이어 분리
   - 의존성 주입 패턴
   - 테스트 가능한 설계

2. **표준 Go 프로젝트 구조**
   - `cmd/`, `internal/`, `pkg/` 분리
   - 패키지별 책임 명확화
   - 확장 가능한 구조

3. **테스트 우선 개발**
   - 각 패키지별 테스트
   - 통합 테스트 인프라
   - CI/CD 파이프라인 준비

### ✅ 유지보수 장점

1. **가독성**
   - 패키지별 기능 분리
   - 명확한 인터페이스
   - 문서화된 구조

2. **확장성**
   - 새 기능 추가 용이
   - 패키지 독립적 개발
   - 팀 협업 용이

3. **디버깅**
   - 문제 발생 지점 명확
   - 단위 테스트로 격리
   - 구조화된 로깅

---

## 📊 타임라인 요약

```
Phase 0 (3일)   : 프로젝트 초기화 및 기본 구조 ✅
├─ Day 1: 백업 → 새 프로젝트 생성 → Config 구현
├─ Day 2: 핵심 패키지 스켈레톤 생성
└─ Day 3: 테스트 인프라 및 문서 정리

Phase 1 (2주)   : 핵심 기능 구현 (MVP)
Phase 2 (1주)   : 테스트 및 검증
Phase 3 (1주)   : 최적화
Phase 4 (1주)   : 문서화 및 배포
Phase 5 (1주)   : 예비 기간

총 기간: 6-7주
```

---

## 🚀 시작하기

### 즉시 실행 가능한 스크립트

```bash
# 1. 백업 및 초기화
cd astrago-airgap/
BACKUP_DIR="astrago-overlay.backup.$(date +%Y%m%d-%H%M%S)"
mv astrago-overlay "$BACKUP_DIR"

# 2. 새 프로젝트 생성
mkdir -p astrago-overlay
cd astrago-overlay

# 3. 구조 생성 스크립트 실행
# (위의 Day 1 Step 2-6 명령어들을 순서대로 실행)

# 4. 빌드 및 테스트
make deps
make build
make test

# 5. 실행
./bin/extract-images --help
```

---

## 📝 변경 이력

| 버전 | 날짜 | 작성자 | 변경 내용 |
|------|------|--------|----------|
| 1.0.0 | 2024-10-24 | System Architect | Clean Slate 워크플로우 초기 작성 |

---

## 📚 참고 문서

- [EXECUTION_PLAN.md](./EXECUTION_PLAN.md) - 기본 실행 계획 (Phase 1-5 상세)
- [TECHNICAL_SPECIFICATION_V2.md](./TECHNICAL_SPECIFICATION_V2.md) - 기술 명세서
- [ARCHITECTURE.md](./ARCHITECTURE.md) - 아키텍처 가이드
- [PHASE_0_CRITICAL_FIXES.md](./PHASE_0_CRITICAL_FIXES.md) - Critical 이슈 목록

---

**질문이나 이슈**: Astrago 개발팀
**라이선스**: Apache License 2.0
