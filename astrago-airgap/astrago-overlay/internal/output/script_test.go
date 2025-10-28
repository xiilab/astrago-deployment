package output

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/astrago/helm-image-extractor/internal/config"
)

func TestNewScriptWriter(t *testing.T) {
	cfg := &config.Config{}
	sw := NewScriptWriter(cfg)

	if sw == nil {
		t.Error("NewScriptWriter() returned nil")
	}

	if sw.config != cfg {
		t.Error("Config not properly set")
	}
}

func TestGenerateBashScript(t *testing.T) {
	cfg := &config.Config{}
	sw := NewScriptWriter(cfg)

	images := []string{
		"nginx:1.19",
		"redis:6.2",
		"postgres:13",
	}

	script := sw.generateBashScript(images)

	// Check shebang
	if !strings.HasPrefix(script, "#!/bin/bash") {
		t.Error("Script should start with shebang")
	}

	// Check all images are included
	for _, img := range images {
		if !strings.Contains(script, img) {
			t.Errorf("Script should contain image: %s", img)
		}
	}

	// Check essential bash commands
	essentials := []string{
		"set -e",
		"TOTAL_IMAGES=",
		"docker pull",
		"docker save",
		"download_image",
	}

	for _, essential := range essentials {
		if !strings.Contains(script, essential) {
			t.Errorf("Script should contain: %s", essential)
		}
	}

	// Check image count
	if !strings.Contains(script, "TOTAL_IMAGES=3") {
		t.Error("Script should have correct image count")
	}
}

func TestGeneratePowerShellScript(t *testing.T) {
	cfg := &config.Config{}
	sw := NewScriptWriter(cfg)

	images := []string{
		"nginx:1.19",
		"redis:6.2",
	}

	script := sw.generatePowerShellScript(images)

	// Check PowerShell header
	if !strings.Contains(script, "PowerShell") {
		t.Error("Script should be identified as PowerShell")
	}

	// Check all images are included
	for _, img := range images {
		if !strings.Contains(script, img) {
			t.Errorf("Script should contain image: %s", img)
		}
	}

	// Check essential PowerShell commands
	essentials := []string{
		"$ErrorActionPreference",
		"$TOTAL_IMAGES",
		"docker pull",
		"docker save",
		"Download-Image",
		"Write-Host",
	}

	for _, essential := range essentials {
		if !strings.Contains(script, essential) {
			t.Errorf("Script should contain: %s", essential)
		}
	}

	// Check image count
	if !strings.Contains(script, "$TOTAL_IMAGES = 2") {
		t.Error("Script should have correct image count")
	}
}

func TestWriteDownloadScript(t *testing.T) {
	// Create temp directory
	tmpDir := t.TempDir()
	outputPath := filepath.Join(tmpDir, "images.txt")

	cfg := &config.Config{
		OutputPath: outputPath,
	}
	sw := NewScriptWriter(cfg)

	images := map[string]bool{
		"nginx:1.19": true,
		"redis:6.2":  true,
	}

	err := sw.WriteDownloadScript(images)
	if err != nil {
		t.Fatalf("WriteDownloadScript() failed: %v", err)
	}

	// Check bash script was created
	bashPath := filepath.Join(tmpDir, "download-images.sh")
	if _, err := os.Stat(bashPath); os.IsNotExist(err) {
		t.Error("Bash script file was not created")
	}

	// Check PowerShell script was created
	psPath := filepath.Join(tmpDir, "download-images.ps1")
	if _, err := os.Stat(psPath); os.IsNotExist(err) {
		t.Error("PowerShell script file was not created")
	}

	// Check bash script content
	bashContent, err := os.ReadFile(bashPath)
	if err != nil {
		t.Fatalf("Failed to read bash script: %v", err)
	}

	if !strings.Contains(string(bashContent), "#!/bin/bash") {
		t.Error("Bash script should have shebang")
	}

	// Check bash script is executable
	info, err := os.Stat(bashPath)
	if err != nil {
		t.Fatalf("Failed to stat bash script: %v", err)
	}
	if info.Mode().Perm()&0100 == 0 {
		t.Error("Bash script should be executable")
	}

	// Check PowerShell script content
	psContent, err := os.ReadFile(psPath)
	if err != nil {
		t.Fatalf("Failed to read PowerShell script: %v", err)
	}

	if !strings.Contains(string(psContent), "PowerShell") {
		t.Error("PowerShell script should be identified")
	}
}

func TestGenerateScriptWithEmptyImages(t *testing.T) {
	cfg := &config.Config{}
	sw := NewScriptWriter(cfg)

	// Empty image list
	images := []string{}

	bashScript := sw.generateBashScript(images)
	if !strings.Contains(bashScript, "TOTAL_IMAGES=0") {
		t.Error("Script should handle empty image list")
	}

	psScript := sw.generatePowerShellScript(images)
	if !strings.Contains(psScript, "$TOTAL_IMAGES = 0") {
		t.Error("PowerShell script should handle empty image list")
	}
}

func TestGenerateScriptWithSpecialCharacters(t *testing.T) {
	cfg := &config.Config{}
	sw := NewScriptWriter(cfg)

	// Images with special characters
	images := []string{
		"registry.k8s.io/kube-apiserver:v1.28.0",
		"quay.io/prometheus/node-exporter:v1.5.0",
		"gcr.io/google_containers/pause:3.9",
	}

	bashScript := sw.generateBashScript(images)
	psScript := sw.generatePowerShellScript(images)

	// All images should be properly quoted in bash
	for _, img := range images {
		if !strings.Contains(bashScript, "\""+img+"\"") {
			t.Errorf("Bash script should properly quote image: %s", img)
		}
		if !strings.Contains(psScript, "\""+img+"\"") {
			t.Errorf("PowerShell script should properly quote image: %s", img)
		}
	}
}

func TestGetCurrentTimestamp(t *testing.T) {
	timestamp := getCurrentTimestamp()

	if timestamp == "" {
		t.Error("Timestamp should not be empty")
	}

	// Should be a valid timestamp string
	if !strings.Contains(timestamp, "2025") {
		t.Error("Timestamp should contain year")
	}
}
