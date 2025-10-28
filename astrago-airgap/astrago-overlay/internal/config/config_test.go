package config

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/spf13/cobra"
)

func TestConfig_Validate(t *testing.T) {
	// 임시 디렉토리 생성
	tmpDir := t.TempDir()
	helmfileDir := filepath.Join(tmpDir, "helmfile")
	chartsDir := filepath.Join(helmfileDir, "charts")
	outputDir := filepath.Join(tmpDir, "output")

	os.MkdirAll(chartsDir, 0755)
	os.MkdirAll(outputDir, 0755)

	// 더미 Helmfile 생성
	helmfilePath := filepath.Join(helmfileDir, "helmfile.yaml.gotmpl")
	os.WriteFile(helmfilePath, []byte("releases: []"), 0644)

	tests := []struct {
		name    string
		config  *Config
		wantErr bool
		errMsg  string
	}{
		{
			name: "유효한 설정",
			config: &Config{
				HelmfilePath: helmfilePath,
				ChartsPath:   chartsDir,
				OutputPath:   filepath.Join(outputDir, "images.txt"),
				Workers:      5,
				OutputFormat: "text",
			},
			wantErr: false,
		},
		{
			name: "Helmfile 없음",
			config: &Config{
				HelmfilePath: filepath.Join(tmpDir, "nonexistent.yaml"),
				ChartsPath:   chartsDir,
				OutputPath:   filepath.Join(outputDir, "images.txt"),
				Workers:      5,
				OutputFormat: "text",
			},
			wantErr: true,
			errMsg:  "Helmfile이 존재하지 않음",
		},
		{
			name: "Charts 디렉토리 없음",
			config: &Config{
				HelmfilePath: helmfilePath,
				ChartsPath:   filepath.Join(tmpDir, "nonexistent-charts"),
				OutputPath:   filepath.Join(outputDir, "images.txt"),
				Workers:      5,
				OutputFormat: "text",
			},
			wantErr: true,
			errMsg:  "Charts 디렉토리가 존재하지 않음",
		},
		{
			name: "Workers 범위 초과 (자동 조정)",
			config: &Config{
				HelmfilePath: helmfilePath,
				ChartsPath:   chartsDir,
				OutputPath:   filepath.Join(outputDir, "images.txt"),
				Workers:      100, // 최대 32로 조정됨
				OutputFormat: "text",
			},
			wantErr: false,
		},
		{
			name: "Workers 0 (자동 조정)",
			config: &Config{
				HelmfilePath: helmfilePath,
				ChartsPath:   chartsDir,
				OutputPath:   filepath.Join(outputDir, "images.txt"),
				Workers:      0, // 최소 1로 조정됨
				OutputFormat: "text",
			},
			wantErr: false,
		},
		{
			name: "지원하지 않는 출력 형식",
			config: &Config{
				HelmfilePath: helmfilePath,
				ChartsPath:   chartsDir,
				OutputPath:   filepath.Join(outputDir, "images.txt"),
				Workers:      5,
				OutputFormat: "xml",
			},
			wantErr: true,
			errMsg:  "지원하지 않는 출력 형식",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.validate()

			if tt.wantErr {
				if err == nil {
					t.Errorf("validate()에서 에러가 발생해야 하지만 nil을 반환함")
					return
				}
				if tt.errMsg != "" && !contains(err.Error(), tt.errMsg) {
					t.Errorf("에러 메시지 = %v, 기대값에 포함되어야 함 = %v", err.Error(), tt.errMsg)
				}
			} else {
				if err != nil {
					t.Errorf("validate()에서 예상치 못한 에러 발생 = %v", err)
				}
			}

			// Workers 범위 검증
			if !tt.wantErr {
				if tt.config.Workers < 1 || tt.config.Workers > 32 {
					t.Errorf("Workers = %v, 범위는 1-32여야 함", tt.config.Workers)
				}
			}
		})
	}
}

func TestLoad(t *testing.T) {
	// 임시 디렉토리 생성
	tmpDir := t.TempDir()
	helmfileDir := filepath.Join(tmpDir, "helmfile")
	chartsDir := filepath.Join(helmfileDir, "charts")

	os.MkdirAll(chartsDir, 0755)

	// 더미 Helmfile 생성
	helmfilePath := filepath.Join(helmfileDir, "helmfile.yaml.gotmpl")
	os.WriteFile(helmfilePath, []byte("releases: []"), 0644)

	tests := []struct {
		name      string
		flags     map[string]interface{}
		wantErr   bool
		checkFunc func(*testing.T, *Config)
	}{
		{
			name: "기본 설정 로드",
			flags: map[string]interface{}{
				"helmfile":    helmfilePath,
				"environment": "default",
				"format":      "text",
				"workers":     5,
				"verbose":     false,
				"debug":       false,
			},
			wantErr: false,
			checkFunc: func(t *testing.T, cfg *Config) {
				if cfg.HelmfilePath != helmfilePath {
					t.Errorf("HelmfilePath = %v, 기대값 = %v", cfg.HelmfilePath, helmfilePath)
				}
				if cfg.Environment != "default" {
					t.Errorf("Environment = %v, 기대값 = default", cfg.Environment)
				}
				if cfg.Workers != 5 {
					t.Errorf("Workers = %v, 기대값 = 5", cfg.Workers)
				}
				if cfg.OutputFormat != "text" {
					t.Errorf("OutputFormat = %v, 기대값 = text", cfg.OutputFormat)
				}
			},
		},
		{
			name: "JSON 출력 형식",
			flags: map[string]interface{}{
				"helmfile":    helmfilePath,
				"environment": "production",
				"format":      "json",
				"workers":     10,
				"verbose":     true,
				"debug":       false,
			},
			wantErr: false,
			checkFunc: func(t *testing.T, cfg *Config) {
				if cfg.OutputFormat != "json" {
					t.Errorf("OutputFormat = %v, 기대값 = json", cfg.OutputFormat)
				}
				if cfg.Workers != 10 {
					t.Errorf("Workers = %v, 기대값 = 10", cfg.Workers)
				}
				if !cfg.Verbose {
					t.Error("Verbose가 true여야 함")
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// 더미 Cobra 명령 생성
			cmd := &cobra.Command{}
			cmd.Flags().String("helmfile", "", "")
			cmd.Flags().String("environment", "default", "")
			cmd.Flags().String("output", "", "")
			cmd.Flags().String("format", "text", "")
			cmd.Flags().Int("workers", 5, "")
			cmd.Flags().Bool("verbose", false, "")
			cmd.Flags().Bool("debug", false, "")

			// 플래그 설정
			for key, val := range tt.flags {
				switch v := val.(type) {
				case string:
					cmd.Flags().Set(key, v)
				case int:
					cmd.Flags().Set(key, fmt.Sprintf("%d", v))
				case bool:
					if v {
						cmd.Flags().Set(key, "true")
					}
				}
			}

			cfg, err := Load(cmd)

			if tt.wantErr {
				if err == nil {
					t.Errorf("Load()에서 에러가 발생해야 하지만 nil을 반환함")
				}
				return
			}

			if err != nil {
				t.Errorf("Load()에서 예상치 못한 에러 발생 = %v", err)
				return
			}

			if tt.checkFunc != nil {
				tt.checkFunc(t, cfg)
			}
		})
	}
}

func TestFindHelmfile(t *testing.T) {
	// 임시 디렉토리 구조 생성
	tmpDir := t.TempDir()
	helmfileDir := filepath.Join(tmpDir, "helmfile")
	os.MkdirAll(helmfileDir, 0755)

	helmfilePath := filepath.Join(helmfileDir, "helmfile.yaml.gotmpl")
	os.WriteFile(helmfilePath, []byte("releases: []"), 0644)

	// 작업 디렉토리 변경
	originalWd, _ := os.Getwd()
	defer os.Chdir(originalWd)

	tests := []struct {
		name    string
		workDir string
		want    string
	}{
		{
			name:    "프로젝트 루트에서 찾기",
			workDir: tmpDir,
			want:    helmfilePath,
		},
		{
			name:    "Helmfile이 없는 디렉토리",
			workDir: t.TempDir(),
			want:    "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			os.Chdir(tt.workDir)
			got := findHelmfile()

			if tt.want == "" {
				if got != "" {
					t.Errorf("findHelmfile() = %v, 기대값 = \"\"", got)
				}
			} else {
				// macOS에서 /var와 /private/var를 처리하기 위해 EvalSymlinks 사용
				wantResolved, _ := filepath.EvalSymlinks(tt.want)
				gotResolved, _ := filepath.EvalSymlinks(got)
				if wantResolved == "" {
					wantResolved = tt.want
				}
				if gotResolved == "" {
					gotResolved = got
				}

				if gotResolved != wantResolved {
					t.Errorf("findHelmfile() = %v, 기대값 = %v", got, tt.want)
				}
			}
		})
	}
}

// Helper function
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(substr) == 0 ||
		(len(s) > 0 && len(substr) > 0 && s[:len(substr)] == substr) ||
		(len(s) > len(substr) && containsSubstring(s, substr)))
}

func containsSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
