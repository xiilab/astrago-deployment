package output

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/astrago/helm-image-extractor/internal/discovery"
	"github.com/astrago/helm-image-extractor/internal/renderer"
	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// Report represents extraction report
type Report struct {
	Summary    Summary        `json:"summary" yaml:"summary"`
	Charts     []ChartReport  `json:"charts" yaml:"charts"`
	Images     []string       `json:"images" yaml:"images"`
	Registries map[string]int `json:"registries" yaml:"registries"`
	Timestamp  string         `json:"timestamp" yaml:"timestamp"`
}

// Summary contains overall statistics
type Summary struct {
	TotalCharts       int    `json:"total_charts" yaml:"total_charts"`
	SuccessfulRenders int    `json:"successful_renders" yaml:"successful_renders"`
	FailedRenders     int    `json:"failed_renders" yaml:"failed_renders"`
	TotalImages       int    `json:"total_images" yaml:"total_images"`
	UniqueRegistries  int    `json:"unique_registries" yaml:"unique_registries"`
	ExecutionTime     string `json:"execution_time" yaml:"execution_time"`
}

// ChartReport contains per-chart statistics
type ChartReport struct {
	Name          string   `json:"name" yaml:"name"`
	Type          string   `json:"type" yaml:"type"`
	RenderSuccess bool     `json:"render_success" yaml:"render_success"`
	ImageCount    int      `json:"image_count" yaml:"image_count"`
	Images        []string `json:"images" yaml:"images"`
	Error         string   `json:"error,omitempty" yaml:"error,omitempty"`
}

// ReportWriter generates extraction reports
type ReportWriter struct {
	config *config.Config
}

// NewReportWriter creates a new ReportWriter
func NewReportWriter(cfg *config.Config) *ReportWriter {
	return &ReportWriter{config: cfg}
}

// GenerateReport generates a comprehensive extraction report
func (r *ReportWriter) GenerateReport(
	charts []*discovery.Chart,
	results []*renderer.RenderResult,
	images map[string]bool,
	executionTime time.Duration,
) (*Report, error) {
	report := &Report{
		Timestamp:  time.Now().Format(time.RFC3339),
		Registries: make(map[string]int),
	}

	// Build summary
	successCount := 0
	for _, result := range results {
		if result.Error == nil {
			successCount++
		}
	}

	report.Summary = Summary{
		TotalCharts:       len(charts),
		SuccessfulRenders: successCount,
		FailedRenders:     len(charts) - successCount,
		TotalImages:       len(images),
		ExecutionTime:     executionTime.String(),
	}

	// Build chart reports
	chartReports := make([]ChartReport, 0, len(charts))
	for i, chart := range charts {
		cr := ChartReport{
			Name:   chart.Name,
			Type:   getChartTypeString(chart.Type),
			Images: make([]string, 0),
		}

		if i < len(results) {
			result := results[i]
			cr.RenderSuccess = result.Error == nil
			if result.Error != nil {
				cr.Error = result.Error.Error()
			}
		}

		// Count images for this chart
		chartImages := r.getChartImages(chart, images)
		cr.ImageCount = len(chartImages)
		cr.Images = chartImages

		chartReports = append(chartReports, cr)
	}
	report.Charts = chartReports

	// Build image list
	imageList := make([]string, 0, len(images))
	for img := range images {
		imageList = append(imageList, img)
	}
	sort.Strings(imageList)
	report.Images = imageList

	// Analyze registries
	for _, img := range imageList {
		registry := extractRegistry(img)
		report.Registries[registry]++
	}
	report.Summary.UniqueRegistries = len(report.Registries)

	return report, nil
}

// WriteReport writes the report to file
func (r *ReportWriter) WriteReport(report *Report) error {
	reportDir := filepath.Join(filepath.Dir(r.config.OutputPath), "reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		return fmt.Errorf("failed to create report directory: %w", err)
	}

	timestamp := time.Now().Format("20060102-150405")

	// Write JSON report
	jsonPath := filepath.Join(reportDir, fmt.Sprintf("report-%s.json", timestamp))
	jsonData, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %w", err)
	}
	if err := os.WriteFile(jsonPath, jsonData, 0644); err != nil {
		return fmt.Errorf("failed to write JSON report: %w", err)
	}
	log.Info().Str("path", jsonPath).Msg("JSON 리포트 생성 완료")

	// Write YAML report
	yamlPath := filepath.Join(reportDir, fmt.Sprintf("report-%s.yaml", timestamp))
	yamlData, err := yaml.Marshal(report)
	if err != nil {
		return fmt.Errorf("failed to marshal YAML: %w", err)
	}
	if err := os.WriteFile(yamlPath, yamlData, 0644); err != nil {
		return fmt.Errorf("failed to write YAML report: %w", err)
	}
	log.Info().Str("path", yamlPath).Msg("YAML 리포트 생성 완료")

	// Write text summary
	textPath := filepath.Join(reportDir, fmt.Sprintf("summary-%s.txt", timestamp))
	textData := r.generateTextSummary(report)
	if err := os.WriteFile(textPath, []byte(textData), 0644); err != nil {
		return fmt.Errorf("failed to write text summary: %w", err)
	}
	log.Info().Str("path", textPath).Msg("텍스트 요약 생성 완료")

	return nil
}

// generateTextSummary generates a human-readable text summary
func (r *ReportWriter) generateTextSummary(report *Report) string {
	var sb strings.Builder

	sb.WriteString("=" + strings.Repeat("=", 70) + "\n")
	sb.WriteString("  Astrago Helm Chart Image Extraction Report\n")
	sb.WriteString("=" + strings.Repeat("=", 70) + "\n\n")

	sb.WriteString(fmt.Sprintf("생성 시각: %s\n\n", report.Timestamp))

	sb.WriteString("📊 요약\n")
	sb.WriteString(strings.Repeat("-", 72) + "\n")
	sb.WriteString(fmt.Sprintf("총 차트 수:        %d\n", report.Summary.TotalCharts))
	sb.WriteString(fmt.Sprintf("렌더링 성공:       %d\n", report.Summary.SuccessfulRenders))
	sb.WriteString(fmt.Sprintf("렌더링 실패:       %d\n", report.Summary.FailedRenders))
	sb.WriteString(fmt.Sprintf("총 이미지 수:      %d\n", report.Summary.TotalImages))
	sb.WriteString(fmt.Sprintf("레지스트리 수:     %d\n", report.Summary.UniqueRegistries))
	sb.WriteString(fmt.Sprintf("실행 시간:         %s\n\n", report.Summary.ExecutionTime))

	sb.WriteString("📦 레지스트리별 이미지 분포\n")
	sb.WriteString(strings.Repeat("-", 72) + "\n")

	// Sort registries by count
	type regCount struct {
		registry string
		count    int
	}
	regCounts := make([]regCount, 0, len(report.Registries))
	for reg, count := range report.Registries {
		regCounts = append(regCounts, regCount{reg, count})
	}
	sort.Slice(regCounts, func(i, j int) bool {
		return regCounts[i].count > regCounts[j].count
	})

	for _, rc := range regCounts {
		percentage := float64(rc.count) / float64(report.Summary.TotalImages) * 100
		sb.WriteString(fmt.Sprintf("%-40s %3d (%.1f%%)\n", rc.registry, rc.count, percentage))
	}
	sb.WriteString("\n")

	sb.WriteString("📋 차트별 상세\n")
	sb.WriteString(strings.Repeat("-", 72) + "\n")
	for _, chart := range report.Charts {
		status := "✅"
		if !chart.RenderSuccess {
			status = "❌"
		}
		sb.WriteString(fmt.Sprintf("%s %-30s [%s] %d images\n",
			status, chart.Name, chart.Type, chart.ImageCount))
		if chart.Error != "" {
			sb.WriteString(fmt.Sprintf("   Error: %s\n", chart.Error))
		}
	}

	sb.WriteString("\n" + strings.Repeat("=", 72) + "\n")

	return sb.String()
}

// getChartImages gets images belonging to a specific chart
func (r *ReportWriter) getChartImages(chart *discovery.Chart, allImages map[string]bool) []string {
	// This is a simplified version - in reality, we'd need to track which images came from which chart
	// For now, return empty slice
	return []string{}
}

// getChartTypeString converts ChartType to string
func getChartTypeString(t discovery.ChartType) string {
	switch t {
	case discovery.ChartTypeLocal:
		return "Local"
	case discovery.ChartTypeRemote:
		return "Remote"
	case discovery.ChartTypeOperator:
		return "Operator"
	default:
		return "Unknown"
	}
}

// extractRegistry extracts registry from image string
func extractRegistry(image string) string {
	parts := strings.Split(image, "/")
	if len(parts) >= 2 && strings.Contains(parts[0], ".") {
		return parts[0]
	}
	return "docker.io"
}
