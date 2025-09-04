package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/astrago/chart-sync/internal/chart"
	"github.com/astrago/chart-sync/internal/config"
	"github.com/astrago/chart-sync/internal/helm"
	"github.com/spf13/cobra"
)

const (
	chartsJSON  = "charts.json"
)

var (
	chartsDir = getChartsDir()
)

func getChartsDir() string {
	dir, _ := filepath.Abs("../charts/external")
	return dir
}

// SyncCmd creates the sync command
func SyncCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "sync",
		Short: "Sync all external charts",
		Long:  "Downloads and synchronizes all external Helm charts for offline deployment",
		RunE:  runSync,
	}
}

func runSync(cmd *cobra.Command, args []string) error {
	fmt.Println("🚀 Starting external charts sync...")

	// Load charts configuration
	chartsConfig, err := config.LoadChartsConfig(chartsJSON)
	if err != nil {
		return fmt.Errorf("failed to load charts config: %w", err)
	}

	// Create Helm client
	helmClient, err := helm.NewClient()
	if err != nil {
		return fmt.Errorf("failed to create Helm client: %w", err)
	}

	// Add repositories
	fmt.Println("📦 Adding Helm repositories...")
	for name, url := range chartsConfig.Repositories {
		fmt.Printf("  • Adding %s: %s\n", name, url)
		if err := helmClient.AddRepository(name, url); err != nil {
			return fmt.Errorf("failed to add repository %s: %w", name, err)
		}
	}

	// Update repositories
	fmt.Println("🔄 Updating repositories...")
	if err := helmClient.UpdateRepositories(); err != nil {
		return fmt.Errorf("failed to update repositories: %w", err)
	}

	// Create charts directory
	if err := os.MkdirAll(chartsDir, 0755); err != nil {
		return fmt.Errorf("failed to create charts directory: %w", err)
	}

	successCount := 0
	totalCount := len(chartsConfig.Charts)

	// Process each chart with simplified 4-step approach
	for chartName, chartInfo := range chartsConfig.Charts {
		version := chartInfo.Version
		repoName := chartInfo.Repository
		
		fmt.Printf("\n📥 Processing %s/%s:%s\n", repoName, chartName, version)
		
		if err := processChart(helmClient, repoName, chartName, version); err != nil {
			fmt.Printf("  ❌ Failed: %v\n", err)
			continue
		}
		
		fmt.Printf("  ✅ Completed\n")
		successCount++
	}

	// Summary
	fmt.Printf("\n📊 Sync completed: %d/%d\n", successCount, totalCount)
	if successCount == totalCount {
		fmt.Println("✅ All charts synced successfully!")
	} else {
		fmt.Printf("⚠️  Some charts failed to sync\n")
	}

	return nil
}

func hasDependencies(chartYamlPath string) bool {
	data, err := os.ReadFile(chartYamlPath)
	if err != nil {
		return false
	}
	return strings.Contains(string(data), "dependencies:")
}

func getExistingChartVersion(chartYamlPath string) string {
	data, err := os.ReadFile(chartYamlPath)
	if err != nil {
		return ""
	}
	
	lines := strings.Split(string(data), "\n")
	inDependencies := false
	
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		
		// dependencies 섹션 진입
		if trimmed == "dependencies:" {
			inDependencies = true
			continue
		}
		
		// dependencies 섹션에서 나감 (들여쓰기가 없는 새 섹션)
		if inDependencies && trimmed != "" && !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "-") {
			inDependencies = false
		}
		
		// dependencies 섹션이 아닌 곳에서 version: 찾기
		if !inDependencies && strings.HasPrefix(trimmed, "version:") {
			parts := strings.Split(trimmed, ":")
			if len(parts) >= 2 {
				return strings.TrimSpace(strings.Trim(parts[1], `"`))
			}
		}
	}
	return ""
}


// processChart implements the simplified 4-step process for each chart
func processChart(helmClient *helm.Client, repoName, chartName, version string) error {
	actualTargetDir := filepath.Join(chartsDir, chartName)
	
	// Check if chart already exists and compare version
	if _, err := os.Stat(actualTargetDir); err == nil {
		// Check existing version in Chart.yaml
		chartYamlPath := filepath.Join(actualTargetDir, "Chart.yaml")
		if existingVersion := getExistingChartVersion(chartYamlPath); existingVersion != "" {
			if existingVersion == version {
				fmt.Printf("  ⏭️ Already exists with same version (%s), skipping\n", version)
				return nil
			} else {
				fmt.Printf("  🔄 Version changed (%s → %s), updating...\n", existingVersion, version)
				// Remove existing directory for update
				if err := os.RemoveAll(actualTargetDir); err != nil {
					return fmt.Errorf("failed to remove existing chart: %w", err)
				}
			}
		}
	}
	
	// Step 1: Download chart using helm pull
	fmt.Printf("  1️⃣ Downloading chart...\n")
	chartRef := fmt.Sprintf("%s/%s", repoName, chartName)
	pullCmd := fmt.Sprintf("helm pull %s --version %s --untar --untardir %s", chartRef, version, chartsDir)
	
	if err := runCommand(pullCmd); err != nil {
		return fmt.Errorf("download failed: %w", err)
	}
	
	// Step 2: Update Chart.yaml to file:// repositories
	fmt.Printf("  2️⃣ Updating Chart.yaml...\n")
	modifier := chart.NewModifier(actualTargetDir)
	if err := modifier.UpdateRepositoriesToLocal(); err != nil {
		return fmt.Errorf("Chart.yaml update failed: %w", err)
	}

	// Step 3: Remove Chart.lock
	fmt.Printf("  3️⃣ Removing Chart.lock...\n")
	lockPath := filepath.Join(actualTargetDir, "Chart.lock")
	if err := os.RemoveAll(lockPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove Chart.lock: %w", err)
	}

	// Step 4: Run helm dependency build
	fmt.Printf("  4️⃣ Running helm dependency build...\n")
	if hasDependencies(filepath.Join(actualTargetDir, "Chart.yaml")) {
		buildCmd := fmt.Sprintf("helm dependency build %s", actualTargetDir)
		if err := runCommand(buildCmd); err != nil {
			return fmt.Errorf("dependency build failed: %w", err)
		}
	}

	return nil
}


// runCommand executes a shell command
func runCommand(cmdStr string) error {
	parts := strings.Fields(cmdStr)
	if len(parts) == 0 {
		return fmt.Errorf("empty command")
	}
	
	cmd := exec.Command(parts[0], parts[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	
	return cmd.Run()
}

