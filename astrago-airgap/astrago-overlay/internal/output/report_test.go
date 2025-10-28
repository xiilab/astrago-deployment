package output

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/astrago/helm-image-extractor/internal/discovery"
	"github.com/astrago/helm-image-extractor/internal/renderer"
)

func TestNewReportWriter(t *testing.T) {
	cfg := &config.Config{}
	rw := NewReportWriter(cfg)

	if rw == nil {
		t.Error("NewReportWriter() returned nil")
	}

	if rw.config != cfg {
		t.Error("Config not properly set")
	}
}

func TestGenerateReport(t *testing.T) {
	cfg := &config.Config{}
	rw := NewReportWriter(cfg)

	charts := []*discovery.Chart{
		{
			Name: "nginx",
			Type: discovery.ChartTypeLocal,
		},
		{
			Name: "redis",
			Type: discovery.ChartTypeLocal,
		},
	}

	results := []*renderer.RenderResult{
		{
			Chart:     charts[0],
			Manifests: "manifest1",
			Error:     nil,
		},
		{
			Chart:     charts[1],
			Manifests: "manifest2",
			Error:     nil,
		},
	}

	images := map[string]bool{
		"nginx:1.19":  true,
		"redis:6.2":   true,
		"postgres:13": true,
		"mysql:8.0":   true,
		"mongodb:5.0": true,
	}

	executionTime := 5 * time.Second

	report, err := rw.GenerateReport(charts, results, images, executionTime)
	if err != nil {
		t.Fatalf("GenerateReport() failed: %v", err)
	}

	// Check summary
	if report.Summary.TotalCharts != 2 {
		t.Errorf("Expected 2 charts, got %d", report.Summary.TotalCharts)
	}

	if report.Summary.SuccessfulRenders != 2 {
		t.Errorf("Expected 2 successful renders, got %d", report.Summary.SuccessfulRenders)
	}

	if report.Summary.FailedRenders != 0 {
		t.Errorf("Expected 0 failed renders, got %d", report.Summary.FailedRenders)
	}

	if report.Summary.TotalImages != 5 {
		t.Errorf("Expected 5 images, got %d", report.Summary.TotalImages)
	}

	// Check timestamp
	if report.Timestamp == "" {
		t.Error("Timestamp should not be empty")
	}

	// Check images
	if len(report.Images) != 5 {
		t.Errorf("Expected 5 images in report, got %d", len(report.Images))
	}

	// Check registries
	if report.Summary.UniqueRegistries == 0 {
		t.Error("Should have at least one registry")
	}

	// Check charts
	if len(report.Charts) != 2 {
		t.Errorf("Expected 2 chart reports, got %d", len(report.Charts))
	}
}

func TestGenerateReportWithFailures(t *testing.T) {
	cfg := &config.Config{}
	rw := NewReportWriter(cfg)

	charts := []*discovery.Chart{
		{
			Name: "nginx",
			Type: discovery.ChartTypeLocal,
		},
		{
			Name: "redis",
			Type: discovery.ChartTypeLocal,
		},
	}

	results := []*renderer.RenderResult{
		{
			Chart:     charts[0],
			Manifests: "manifest1",
			Error:     nil,
		},
		{
			Chart:     charts[1],
			Manifests: "",
			Error:     os.ErrNotExist,
		},
	}

	images := map[string]bool{
		"nginx:1.19": true,
	}

	executionTime := 3 * time.Second

	report, err := rw.GenerateReport(charts, results, images, executionTime)
	if err != nil {
		t.Fatalf("GenerateReport() failed: %v", err)
	}

	// Check summary with failures
	if report.Summary.TotalCharts != 2 {
		t.Errorf("Expected 2 charts, got %d", report.Summary.TotalCharts)
	}

	if report.Summary.SuccessfulRenders != 1 {
		t.Errorf("Expected 1 successful render, got %d", report.Summary.SuccessfulRenders)
	}

	if report.Summary.FailedRenders != 1 {
		t.Errorf("Expected 1 failed render, got %d", report.Summary.FailedRenders)
	}

	// Check failed chart has error
	failedChart := report.Charts[1]
	if failedChart.RenderSuccess {
		t.Error("Second chart should be marked as failed")
	}
	if failedChart.Error == "" {
		t.Error("Failed chart should have error message")
	}
}

func TestWriteReport(t *testing.T) {
	// Create temp directory
	tmpDir := t.TempDir()
	outputPath := filepath.Join(tmpDir, "images.txt")

	cfg := &config.Config{
		OutputPath: outputPath,
	}
	rw := NewReportWriter(cfg)

	report := &Report{
		Summary: Summary{
			TotalCharts:       3,
			SuccessfulRenders: 3,
			FailedRenders:     0,
			TotalImages:       10,
			UniqueRegistries:  2,
			ExecutionTime:     "5s",
		},
		Charts: []ChartReport{
			{
				Name:          "nginx",
				Type:          "Local",
				RenderSuccess: true,
				ImageCount:    3,
			},
		},
		Images: []string{"nginx:1.19", "redis:6.2"},
		Registries: map[string]int{
			"docker.io": 8,
			"quay.io":   2,
		},
		Timestamp: time.Now().Format(time.RFC3339),
	}

	err := rw.WriteReport(report)
	if err != nil {
		t.Fatalf("WriteReport() failed: %v", err)
	}

	// Check reports directory was created
	reportDir := filepath.Join(tmpDir, "reports")
	if _, err := os.Stat(reportDir); os.IsNotExist(err) {
		t.Error("Reports directory was not created")
	}

	// Check files exist (we can't check exact names due to timestamp)
	entries, err := os.ReadDir(reportDir)
	if err != nil {
		t.Fatalf("Failed to read report directory: %v", err)
	}

	foundJSON := false
	foundYAML := false
	foundText := false

	for _, entry := range entries {
		name := entry.Name()
		if strings.HasPrefix(name, "report-") && strings.HasSuffix(name, ".json") {
			foundJSON = true
		}
		if strings.HasPrefix(name, "report-") && strings.HasSuffix(name, ".yaml") {
			foundYAML = true
		}
		if strings.HasPrefix(name, "summary-") && strings.HasSuffix(name, ".txt") {
			foundText = true
		}
	}

	if !foundJSON {
		t.Error("JSON report was not created")
	}
	if !foundYAML {
		t.Error("YAML report was not created")
	}
	if !foundText {
		t.Error("Text summary was not created")
	}
}

func TestGenerateTextSummary(t *testing.T) {
	cfg := &config.Config{}
	rw := NewReportWriter(cfg)

	report := &Report{
		Summary: Summary{
			TotalCharts:       5,
			SuccessfulRenders: 4,
			FailedRenders:     1,
			TotalImages:       20,
			UniqueRegistries:  3,
			ExecutionTime:     "10s",
		},
		Charts: []ChartReport{
			{
				Name:          "nginx",
				Type:          "Local",
				RenderSuccess: true,
				ImageCount:    5,
			},
			{
				Name:          "redis",
				Type:          "Local",
				RenderSuccess: false,
				ImageCount:    0,
				Error:         "chart not found",
			},
		},
		Registries: map[string]int{
			"docker.io": 15,
			"quay.io":   3,
			"gcr.io":    2,
		},
		Timestamp: "2025-10-28T00:00:00Z",
	}

	summary := rw.generateTextSummary(report)

	// Check essential sections
	essentials := []string{
		"Astrago Helm Chart Image Extraction Report",
		"요약",
		"총 차트 수:",
		"렌더링 성공:",
		"렌더링 실패:",
		"총 이미지 수:",
		"레지스트리 수:",
		"실행 시간:",
		"레지스트리별 이미지 분포",
		"차트별 상세",
		"nginx",
		"redis",
	}

	for _, essential := range essentials {
		if !strings.Contains(summary, essential) {
			t.Errorf("Summary should contain: %s", essential)
		}
	}

	// Check numbers
	if !strings.Contains(summary, "5") { // Total charts
		t.Error("Summary should contain total charts count")
	}
	if !strings.Contains(summary, "20") { // Total images
		t.Error("Summary should contain total images count")
	}

	// Check success/failure indicators
	if !strings.Contains(summary, "✅") {
		t.Error("Summary should contain success indicator")
	}
	if !strings.Contains(summary, "❌") {
		t.Error("Summary should contain failure indicator")
	}

	// Check error message for failed chart
	if !strings.Contains(summary, "chart not found") {
		t.Error("Summary should contain error message")
	}
}

func TestGetChartTypeString(t *testing.T) {
	tests := []struct {
		chartType discovery.ChartType
		expected  string
	}{
		{discovery.ChartTypeLocal, "Local"},
		{discovery.ChartTypeRemote, "Remote"},
		{discovery.ChartTypeOperator, "Operator"},
		{discovery.ChartType(999), "Unknown"},
	}

	for _, tt := range tests {
		result := getChartTypeString(tt.chartType)
		if result != tt.expected {
			t.Errorf("getChartTypeString(%v) = %s, want %s", tt.chartType, result, tt.expected)
		}
	}
}

func TestExtractRegistry(t *testing.T) {
	tests := []struct {
		image    string
		expected string
	}{
		{"nginx:1.19", "docker.io"},
		{"redis", "docker.io"},
		{"quay.io/prometheus/prometheus:v2.45.0", "quay.io"},
		{"gcr.io/google_containers/pause:3.9", "gcr.io"},
		{"registry.k8s.io/kube-apiserver:v1.28.0", "registry.k8s.io"},
		{"nvcr.io/nvidia/cuda:11.8.0", "nvcr.io"},
		{"library/nginx:latest", "docker.io"},
	}

	for _, tt := range tests {
		result := extractRegistry(tt.image)
		if result != tt.expected {
			t.Errorf("extractRegistry(%s) = %s, want %s", tt.image, result, tt.expected)
		}
	}
}

func TestGetChartImages(t *testing.T) {
	cfg := &config.Config{}
	rw := NewReportWriter(cfg)

	chart := &discovery.Chart{
		Name: "nginx",
		Type: discovery.ChartTypeLocal,
	}

	allImages := map[string]bool{
		"nginx:1.19": true,
		"redis:6.2":  true,
	}

	// Currently returns empty slice (simplified implementation)
	images := rw.getChartImages(chart, allImages)
	if images == nil {
		t.Error("getChartImages should return non-nil slice")
	}
}
