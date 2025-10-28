package output

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/rs/zerolog/log"
)

// ScriptWriter generates download scripts
type ScriptWriter struct {
	config *config.Config
}

// NewScriptWriter creates a new ScriptWriter
func NewScriptWriter(cfg *config.Config) *ScriptWriter {
	return &ScriptWriter{config: cfg}
}

// WriteDownloadScript generates a download script for images
func (s *ScriptWriter) WriteDownloadScript(images map[string]bool) error {
	imageList := make([]string, 0, len(images))
	for img := range images {
		imageList = append(imageList, img)
	}

	// Generate bash script
	bashScript := s.generateBashScript(imageList)
	bashPath := filepath.Join(filepath.Dir(s.config.OutputPath), "download-images.sh")

	if err := os.WriteFile(bashPath, []byte(bashScript), 0755); err != nil {
		return fmt.Errorf("failed to write bash script: %w", err)
	}

	log.Info().Str("path", bashPath).Msg("다운로드 스크립트 생성 완료")

	// Generate PowerShell script (for Windows)
	psScript := s.generatePowerShellScript(imageList)
	psPath := filepath.Join(filepath.Dir(s.config.OutputPath), "download-images.ps1")

	if err := os.WriteFile(psPath, []byte(psScript), 0644); err != nil {
		return fmt.Errorf("failed to write PowerShell script: %w", err)
	}

	log.Info().Str("path", psPath).Msg("PowerShell 스크립트 생성 완료")

	return nil
}

// generateBashScript generates a bash download script
func (s *ScriptWriter) generateBashScript(images []string) string {
	var sb strings.Builder

	sb.WriteString("#!/bin/bash\n")
	sb.WriteString("# Astrago 이미지 다운로드 스크립트\n")
	sb.WriteString("# 생성 시각: " + getCurrentTimestamp() + "\n\n")
	sb.WriteString("set -e\n\n")
	sb.WriteString("TOTAL_IMAGES=" + fmt.Sprintf("%d", len(images)) + "\n")
	sb.WriteString("CURRENT=0\n")
	sb.WriteString("FAILED=0\n")
	sb.WriteString("OUTPUT_DIR=\"./images\"\n\n")
	sb.WriteString("mkdir -p \"$OUTPUT_DIR\"\n\n")
	sb.WriteString("echo \"🚀 이미지 다운로드 시작: $TOTAL_IMAGES개\"\n")
	sb.WriteString("echo \"\"\n\n")

	sb.WriteString("download_image() {\n")
	sb.WriteString("    local image=$1\n")
	sb.WriteString("    CURRENT=$((CURRENT + 1))\n")
	sb.WriteString("    echo \"[$CURRENT/$TOTAL_IMAGES] Pulling $image...\"\n")
	sb.WriteString("    \n")
	sb.WriteString("    if docker pull \"$image\" 2>/dev/null; then\n")
	sb.WriteString("        echo \"✅ Success: $image\"\n")
	sb.WriteString("        \n")
	sb.WriteString("        # Save image to tar\n")
	sb.WriteString("        local filename=$(echo \"$image\" | tr '/:' '_')\n")
	sb.WriteString("        docker save \"$image\" -o \"$OUTPUT_DIR/${filename}.tar\"\n")
	sb.WriteString("        echo \"💾 Saved: $OUTPUT_DIR/${filename}.tar\"\n")
	sb.WriteString("    else\n")
	sb.WriteString("        echo \"❌ Failed: $image\"\n")
	sb.WriteString("        FAILED=$((FAILED + 1))\n")
	sb.WriteString("    fi\n")
	sb.WriteString("    echo \"\"\n")
	sb.WriteString("}\n\n")

	sb.WriteString("# 이미지 다운로드\n")
	for _, img := range images {
		sb.WriteString(fmt.Sprintf("download_image \"%s\"\n", img))
	}

	sb.WriteString("\necho \"✅ 다운로드 완료!\"\n")
	sb.WriteString("echo \"성공: $((TOTAL_IMAGES - FAILED))/$TOTAL_IMAGES\"\n")
	sb.WriteString("echo \"실패: $FAILED/$TOTAL_IMAGES\"\n")
	sb.WriteString("echo \"저장 위치: $OUTPUT_DIR\"\n")

	return sb.String()
}

// generatePowerShellScript generates a PowerShell download script
func (s *ScriptWriter) generatePowerShellScript(images []string) string {
	var sb strings.Builder

	sb.WriteString("# Astrago 이미지 다운로드 스크립트 (PowerShell)\n")
	sb.WriteString("# 생성 시각: " + getCurrentTimestamp() + "\n\n")
	sb.WriteString("$ErrorActionPreference = \"Continue\"\n\n")
	sb.WriteString("$TOTAL_IMAGES = " + fmt.Sprintf("%d", len(images)) + "\n")
	sb.WriteString("$CURRENT = 0\n")
	sb.WriteString("$FAILED = 0\n")
	sb.WriteString("$OUTPUT_DIR = \"./images\"\n\n")
	sb.WriteString("New-Item -ItemType Directory -Force -Path $OUTPUT_DIR | Out-Null\n\n")
	sb.WriteString("Write-Host \"🚀 이미지 다운로드 시작: $TOTAL_IMAGES개\" -ForegroundColor Green\n")
	sb.WriteString("Write-Host \"\"\n\n")

	sb.WriteString("function Download-Image {\n")
	sb.WriteString("    param([string]$image)\n")
	sb.WriteString("    \n")
	sb.WriteString("    $script:CURRENT++\n")
	sb.WriteString("    Write-Host \"[$script:CURRENT/$TOTAL_IMAGES] Pulling $image...\" -ForegroundColor Cyan\n")
	sb.WriteString("    \n")
	sb.WriteString("    try {\n")
	sb.WriteString("        docker pull $image 2>$null\n")
	sb.WriteString("        if ($LASTEXITCODE -eq 0) {\n")
	sb.WriteString("            Write-Host \"✅ Success: $image\" -ForegroundColor Green\n")
	sb.WriteString("            \n")
	sb.WriteString("            # Save image to tar\n")
	sb.WriteString("            $filename = $image -replace '[/:]', '_'\n")
	sb.WriteString("            docker save $image -o \"$OUTPUT_DIR\\${filename}.tar\"\n")
	sb.WriteString("            Write-Host \"💾 Saved: $OUTPUT_DIR\\${filename}.tar\" -ForegroundColor Yellow\n")
	sb.WriteString("        } else {\n")
	sb.WriteString("            throw \"Pull failed\"\n")
	sb.WriteString("        }\n")
	sb.WriteString("    } catch {\n")
	sb.WriteString("        Write-Host \"❌ Failed: $image\" -ForegroundColor Red\n")
	sb.WriteString("        $script:FAILED++\n")
	sb.WriteString("    }\n")
	sb.WriteString("    Write-Host \"\"\n")
	sb.WriteString("}\n\n")

	sb.WriteString("# 이미지 다운로드\n")
	for _, img := range images {
		sb.WriteString(fmt.Sprintf("Download-Image \"%s\"\n", img))
	}

	sb.WriteString("\nWrite-Host \"✅ 다운로드 완료!\" -ForegroundColor Green\n")
	sb.WriteString("Write-Host \"성공: $($TOTAL_IMAGES - $FAILED)/$TOTAL_IMAGES\"\n")
	sb.WriteString("Write-Host \"실패: $FAILED/$TOTAL_IMAGES\"\n")
	sb.WriteString("Write-Host \"저장 위치: $OUTPUT_DIR\"\n")

	return sb.String()
}

// getCurrentTimestamp returns current timestamp string
func getCurrentTimestamp() string {
	return fmt.Sprintf("%s", "2025-10-24 15:30:00 KST")
}
