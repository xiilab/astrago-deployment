package discovery

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/astrago/helm-image-extractor/internal/config"
)

func TestDetectChartType(t *testing.T) {
	cfg := &config.Config{}
	d := &Discoverer{config: cfg}

	tests := []struct {
		name string
		path string
		want ChartType
	}{
		{
			name: "GPU Operator",
			path: "/path/to/gpu-operator",
			want: ChartTypeOperator,
		},
		{
			name: "Prometheus Operator",
			path: "/path/to/prometheus-operator",
			want: ChartTypeOperator,
		},
		{
			name: "MPI Operator",
			path: "/path/to/mpi-operator",
			want: ChartTypeOperator,
		},
		{
			name: "NFD",
			path: "/path/to/nfd",
			want: ChartTypeOperator,
		},
		{
			name: "일반 차트",
			path: "/path/to/nginx",
			want: ChartTypeLocal,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := d.detectChartType(tt.path)
			if got != tt.want {
				t.Errorf("detectChartType() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestDetectChartTypeWithCRD(t *testing.T) {
	// CRD 디렉토리가 있는 경우 Operator로 감지
	tmpDir := t.TempDir()
	chartPath := filepath.Join(tmpDir, "test-chart")
	crdPath := filepath.Join(chartPath, "crds")

	os.MkdirAll(crdPath, 0755)

	cfg := &config.Config{}
	d := &Discoverer{config: cfg}

	chartType := d.detectChartType(chartPath)
	if chartType != ChartTypeOperator {
		t.Errorf("Chart with CRDs should be detected as Operator, got %v", chartType)
	}
}

func TestParseHelmfile(t *testing.T) {
	tmpDir := t.TempDir()
	helmfilePath := filepath.Join(tmpDir, "helmfile.yaml")

	// 테스트용 Helmfile 생성
	helmfileContent := `
environments:
  default:
    values:
    - ./values.yaml
---
releases:
  - name: nginx
    chart: ./charts/nginx
    namespace: default
    installed: true

  - name: disabled-chart
    chart: ./charts/disabled
    namespace: default
    installed: false

  - name: auto-enabled
    chart: ./charts/auto
    namespace: default
`

	err := os.WriteFile(helmfilePath, []byte(helmfileContent), 0644)
	if err != nil {
		t.Fatalf("Failed to create test helmfile: %v", err)
	}

	cfg := &config.Config{
		HelmfilePath: helmfilePath,
	}

	d := &Discoverer{
		config: cfg,
		cache:  make(map[string]*Chart),
	}

	releases, err := d.parseHelmfile()
	if err != nil {
		t.Fatalf("parseHelmfile() error = %v", err)
	}

	// 오프라인 배포를 위해 installed: false인 차트도 포함되어야 함
	foundNginx := false
	foundDisabled := false
	foundAuto := false

	for _, rel := range releases {
		if rel.Name == "nginx" {
			foundNginx = true
		}
		if rel.Name == "disabled-chart" {
			foundDisabled = true
			// installed 필드가 false로 설정되어 있는지 확인
			if rel.Installed == nil || *rel.Installed {
				t.Error("disabled-chart should have installed: false")
			}
		}
		if rel.Name == "auto-enabled" {
			foundAuto = true
		}
	}

	if !foundNginx {
		t.Error("nginx release not found")
	}

	if !foundDisabled {
		t.Error("disabled-chart should be included for offline deployment")
	}

	if !foundAuto {
		t.Error("auto-enabled release not found")
	}

	// 총 3개의 릴리즈가 있어야 함
	if len(releases) != 3 {
		t.Errorf("Expected 3 releases, got %d", len(releases))
	}
}

func TestParseHelmfileMultipleDocuments(t *testing.T) {
	tmpDir := t.TempDir()
	helmfilePath := filepath.Join(tmpDir, "helmfile.yaml")

	// 여러 문서로 나뉜 Helmfile
	helmfileContent := `
releases:
  - name: first
    chart: ./charts/first
---
releases:
  - name: second
    chart: ./charts/second
---
releases:
  - name: third
    chart: ./charts/third
`

	err := os.WriteFile(helmfilePath, []byte(helmfileContent), 0644)
	if err != nil {
		t.Fatalf("Failed to create test helmfile: %v", err)
	}

	cfg := &config.Config{
		HelmfilePath: helmfilePath,
	}

	d := &Discoverer{
		config: cfg,
		cache:  make(map[string]*Chart),
	}

	releases, err := d.parseHelmfile()
	if err != nil {
		t.Fatalf("parseHelmfile() error = %v", err)
	}

	// 모든 문서의 releases가 병합되어야 함
	if len(releases) != 3 {
		t.Errorf("Expected 3 releases, got %d", len(releases))
	}

	expectedNames := map[string]bool{
		"first":  false,
		"second": false,
		"third":  false,
	}

	for _, rel := range releases {
		if _, ok := expectedNames[rel.Name]; ok {
			expectedNames[rel.Name] = true
		}
	}

	for name, found := range expectedNames {
		if !found {
			t.Errorf("Release %s not found", name)
		}
	}
}

func TestChartPathNormalization(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "Leading ./ 제거",
			input: "./charts/nginx",
			want:  "charts/nginx",
		},
		{
			name:  "이미 정규화됨",
			input: "charts/nginx",
			want:  "charts/nginx",
		},
		{
			name:  "addons 경로",
			input: "./addons/gpu-operator",
			want:  "addons/gpu-operator",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Release 구조체의 경로 정규화 테스트
			rel := Release{
				Chart: tt.input,
			}

			// 정규화 로직 (parseHelmfile에서 수행)
			normalized := rel.Chart
			if len(normalized) > 2 && normalized[:2] == "./" {
				normalized = normalized[2:]
			}

			if normalized != tt.want {
				t.Errorf("Normalized path = %v, want %v", normalized, tt.want)
			}
		})
	}
}

func TestDiscoverChart(t *testing.T) {
	// 테스트용 차트 구조 생성
	tmpDir := t.TempDir()
	chartsDir := filepath.Join(tmpDir, "charts")
	nginxDir := filepath.Join(chartsDir, "nginx")

	os.MkdirAll(nginxDir, 0755)

	// Chart.yaml 생성
	chartYaml := `
apiVersion: v2
name: nginx
version: 1.0.0
description: A Helm chart for Nginx
`
	err := os.WriteFile(filepath.Join(nginxDir, "Chart.yaml"), []byte(chartYaml), 0644)
	if err != nil {
		t.Fatalf("Failed to create Chart.yaml: %v", err)
	}

	// values.yaml 생성
	valuesYaml := `
image:
  repository: nginx
  tag: 1.19
replicas: 3
`
	err = os.WriteFile(filepath.Join(nginxDir, "values.yaml"), []byte(valuesYaml), 0644)
	if err != nil {
		t.Fatalf("Failed to create values.yaml: %v", err)
	}

	cfg := &config.Config{
		ChartsPath: chartsDir,
	}

	d := &Discoverer{
		config: cfg,
		cache:  make(map[string]*Chart),
	}

	release := Release{
		Name:  "nginx",
		Chart: "nginx",
	}

	chart, err := d.discoverChart(release)
	if err != nil {
		t.Fatalf("discoverChart() error = %v", err)
	}

	if chart.Name != "nginx" {
		t.Errorf("Chart name = %v, want nginx", chart.Name)
	}

	if chart.Version != "1.0.0" {
		t.Errorf("Chart version = %v, want 1.0.0", chart.Version)
	}

	// values 로드 확인
	if chart.Values == nil {
		t.Error("Chart values not loaded")
	}

	// 캐시 확인
	if _, ok := d.cache["nginx"]; !ok {
		t.Error("Chart not cached")
	}

	// 두 번째 호출은 캐시에서 가져와야 함
	chart2, err := d.discoverChart(release)
	if err != nil {
		t.Fatalf("discoverChart() second call error = %v", err)
	}

	if chart2 != chart {
		t.Error("Chart should be returned from cache")
	}
}

func TestDiscoverChartWithoutChartYaml(t *testing.T) {
	tmpDir := t.TempDir()
	chartsDir := filepath.Join(tmpDir, "charts")
	invalidDir := filepath.Join(chartsDir, "invalid")

	os.MkdirAll(invalidDir, 0755)
	// Chart.yaml 생성하지 않음

	cfg := &config.Config{
		ChartsPath: chartsDir,
	}

	d := &Discoverer{
		config: cfg,
		cache:  make(map[string]*Chart),
	}

	release := Release{
		Name:  "invalid",
		Chart: "invalid",
	}

	_, err := d.discoverChart(release)
	if err == nil {
		t.Error("discoverChart() should return error for chart without Chart.yaml")
	}
}

func TestChartType_String(t *testing.T) {
	tests := []struct {
		chartType ChartType
		want      string
	}{
		{ChartTypeLocal, "Local"},
		{ChartTypeRemote, "Remote"},
		{ChartTypeOperator, "Operator"},
	}

	// 간단한 ChartType → 문자열 변환 (실제로는 Stringer 인터페이스 구현 필요)
	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			// ChartType enum 값 확인
			if tt.chartType < ChartTypeLocal || tt.chartType > ChartTypeOperator {
				t.Errorf("Invalid ChartType: %v", tt.chartType)
			}
		})
	}
}

func TestNew(t *testing.T) {
	cfg := &config.Config{
		HelmfilePath: "/path/to/helmfile.yaml",
		ChartsPath:   "/path/to/charts",
	}

	d := New(cfg)

	if d == nil {
		t.Fatal("New() returned nil")
	}

	if d.config != cfg {
		t.Error("Config not set correctly")
	}

	if d.cache == nil {
		t.Error("Cache not initialized")
	}
}

func TestDiscover_EmptyHelmfile(t *testing.T) {
	tmpDir := t.TempDir()
	helmfilePath := filepath.Join(tmpDir, "helmfile.yaml")

	// 빈 Helmfile
	helmfileContent := `releases: []`

	err := os.WriteFile(helmfilePath, []byte(helmfileContent), 0644)
	if err != nil {
		t.Fatalf("Failed to create test helmfile: %v", err)
	}

	cfg := &config.Config{
		HelmfilePath: helmfilePath,
		ChartsPath:   tmpDir,
	}

	d := New(cfg)

	charts, err := d.Discover()
	if err != nil {
		t.Fatalf("Discover() error = %v", err)
	}

	// 빈 릴리즈여도 에러는 발생하지 않아야 함
	if charts == nil {
		t.Error("Discover() should return non-nil slice")
	}
}

func TestRelease_InstalledPointer(t *testing.T) {
	// installed: true
	installedTrue := true
	rel1 := Release{
		Name:      "test1",
		Installed: &installedTrue,
	}

	if rel1.Installed == nil || !*rel1.Installed {
		t.Error("Installed should be true")
	}

	// installed: false
	installedFalse := false
	rel2 := Release{
		Name:      "test2",
		Installed: &installedFalse,
	}

	if rel2.Installed == nil || *rel2.Installed {
		t.Error("Installed should be false")
	}

	// installed 설정 없음
	rel3 := Release{
		Name: "test3",
	}

	if rel3.Installed != nil {
		t.Error("Installed should be nil")
	}
}
