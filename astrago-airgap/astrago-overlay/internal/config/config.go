package config

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/spf13/cobra"
)

// Config holds runtime configuration
type Config struct {
	// 경로 설정
	RootDir            string
	HelmfilePath       string
	ChartsPath         string
	OutputPath         string
	Environment        string
	OperatorConfigPath string // operators.yaml 경로 (Phase 4.3)

	// 실행 옵션
	Workers           int
	Verbose           bool
	Debug             bool
	MaxRecursionDepth int  // 재귀 탐색 최대 깊이 (Phase 4.3)
	EnableCache       bool // 차트 렌더링 결과 캐싱 (Phase 4.3)

	// 출력 형식
	OutputFormat string // text, json, yaml

	// 플랫폼 정보
	Platform struct {
		OS   string
		Arch string
	}
}

// Load creates a new Config from command flags
func Load(cmd *cobra.Command) (*Config, error) {
	cfg := &Config{
		Workers:           5,
		MaxRecursionDepth: 10,    // Phase 4.3: 기본값 10
		EnableCache:       false, // Phase 4.3: 기본값 false (추후 활성화)
	}

	// 플래그 값 읽기
	helmfilePath, _ := cmd.Flags().GetString("helmfile")
	environment, _ := cmd.Flags().GetString("environment")
	outputPath, _ := cmd.Flags().GetString("output")
	outputFormat, _ := cmd.Flags().GetString("format")
	workers, _ := cmd.Flags().GetInt("workers")
	verbose, _ := cmd.Flags().GetBool("verbose")
	debug, _ := cmd.Flags().GetBool("debug")

	cfg.Environment = environment
	cfg.OutputFormat = outputFormat
	cfg.Workers = workers
	cfg.Verbose = verbose
	cfg.Debug = debug

	// 플랫폼 정보
	cfg.Platform.OS = runtime.GOOS
	cfg.Platform.Arch = runtime.GOARCH

	// Helmfile 경로 설정
	if helmfilePath != "" {
		cfg.HelmfilePath = helmfilePath
	} else {
		// 자동 탐색
		found := findHelmfile()
		if found == "" {
			return nil, fmt.Errorf("Helmfile을 찾을 수 없습니다. --helmfile 플래그로 경로를 지정하세요")
		}
		cfg.HelmfilePath = found
	}

	// Charts 경로 설정
	cfg.ChartsPath = filepath.Join(filepath.Dir(cfg.HelmfilePath), "charts")

	// 출력 경로 설정
	if outputPath != "" {
		cfg.OutputPath = outputPath
	} else {
		// 기본 경로: kubespray-offline/imagelists/astrago.txt
		helmfileDir := filepath.Dir(cfg.HelmfilePath)
		deploymentRoot := filepath.Dir(helmfileDir)
		kubesprayPath := filepath.Join(deploymentRoot, "astrago-airgap", "kubespray-offline")
		cfg.OutputPath = filepath.Join(kubesprayPath, "imagelists", "astrago.txt")
	}

	// RootDir 설정
	cfg.RootDir = filepath.Dir(filepath.Dir(cfg.HelmfilePath))

	// 유효성 검증
	if err := cfg.validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

// validate checks if the configuration is valid
func (c *Config) validate() error {
	// Helmfile 존재 확인
	if _, err := os.Stat(c.HelmfilePath); err != nil {
		return fmt.Errorf("Helmfile이 존재하지 않음: %s", c.HelmfilePath)
	}

	// Charts 디렉토리 확인
	if _, err := os.Stat(c.ChartsPath); err != nil {
		return fmt.Errorf("Charts 디렉토리가 존재하지 않음: %s", c.ChartsPath)
	}

	// 출력 디렉토리 생성
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

	// 출력 형식 검증
	validFormats := map[string]bool{"text": true, "json": true, "yaml": true}
	if !validFormats[c.OutputFormat] {
		return fmt.Errorf("지원하지 않는 출력 형식: %s (text, json, yaml만 지원)", c.OutputFormat)
	}

	return nil
}

// findHelmfile searches for helmfile.yaml.gotmpl in current and parent directories
func findHelmfile() string {
	dir, err := os.Getwd()
	if err != nil {
		return ""
	}

	// 현재 디렉토리부터 상위로 탐색
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
