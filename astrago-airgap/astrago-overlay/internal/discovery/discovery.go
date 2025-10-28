package discovery

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/astrago/helm-image-extractor/internal/utils"
	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// Chart represents a Helm chart
type Chart struct {
	Name         string
	Path         string
	Version      string
	Type         ChartType
	Dependencies []Chart
	Values       map[string]interface{}
}

// ChartType represents the type of chart
type ChartType int

const (
	ChartTypeLocal ChartType = iota
	ChartTypeRemote
	ChartTypeOperator
)

// Release represents a Helmfile release
type Release struct {
	Name      string   `yaml:"name"`
	Chart     string   `yaml:"chart"`
	Namespace string   `yaml:"namespace"`
	Values    []string `yaml:"values"`
	Installed *bool    `yaml:"installed"`
}

// Helmfile represents the helmfile.yaml structure
type Helmfile struct {
	Releases []Release `yaml:"releases"`
}

// Discoverer discovers charts from helmfile
type Discoverer struct {
	config *config.Config
	cache  map[string]*Chart
}

// New creates a new Discoverer
func New(cfg *config.Config) *Discoverer {
	return &Discoverer{
		config: cfg,
		cache:  make(map[string]*Chart),
	}
}

// Discover finds all charts from helmfile
func (d *Discoverer) Discover() ([]*Chart, error) {
	// 1. Helmfile 파싱
	releases, err := d.parseHelmfile()
	if err != nil {
		return nil, fmt.Errorf("Helmfile 파싱 실패: %w", err)
	}

	log.Debug().Int("releases", len(releases)).Msg("Helmfile 릴리즈 파싱 완료")

	// 2. 차트 수집
	charts := make([]*Chart, 0)
	for _, release := range releases {
		chart, err := d.discoverChart(release)
		if err != nil {
			log.Warn().
				Str("release", release.Name).
				Err(err).
				Msg("차트 발견 실패")
			continue
		}
		charts = append(charts, chart)
		log.Debug().
			Str("name", chart.Name).
			Str("path", chart.Path).
			Msg("차트 발견")
	}

	// 3. 추가 차트 스캔 (charts/ 디렉토리)
	additionalCharts, err := d.scanChartsDirectory()
	if err != nil {
		log.Warn().Err(err).Msg("추가 차트 스캔 실패")
	} else {
		charts = append(charts, additionalCharts...)
	}

	return charts, nil
}

// parseHelmfile parses helmfile.yaml.gotmpl
func (d *Discoverer) parseHelmfile() ([]Release, error) {
	data, err := os.ReadFile(d.config.HelmfilePath)
	if err != nil {
		return nil, err
	}

	// Parse multi-document YAML (separated by ---)
	decoder := yaml.NewDecoder(strings.NewReader(string(data)))
	var helmfile Helmfile

	for {
		var doc map[string]interface{}
		if err := decoder.Decode(&doc); err != nil {
			if err.Error() == "EOF" {
				break
			}
			return nil, err
		}

		// Check if this document contains releases
		if releases, ok := doc["releases"]; ok {
			// Re-parse just the releases part
			releasesData, _ := yaml.Marshal(map[string]interface{}{"releases": releases})
			var tempHelmfile Helmfile
			if err := yaml.Unmarshal(releasesData, &tempHelmfile); err == nil {
				helmfile.Releases = append(helmfile.Releases, tempHelmfile.Releases...)
			}
		}
	}

	// Normalize paths (include all releases for offline deployment)
	// Note: We don't filter out installed: false releases here because
	// for offline deployments, all images must be available even if
	// some charts are not installed by default. The actual installation
	// decision is made during Helmfile deployment, not during image extraction.
	var allReleases []Release
	for _, rel := range helmfile.Releases {
		// Normalize chart path: remove leading "./" if present
		rel.Chart = strings.TrimPrefix(rel.Chart, "./")

		allReleases = append(allReleases, rel)

		if rel.Installed != nil && !*rel.Installed {
			log.Debug().
				Str("release", rel.Name).
				Msg("릴리즈가 기본적으로 비활성화되어 있지만 오프라인 배포를 위해 이미지는 추출됨")
		}
	}

	return allReleases, nil
}

// discoverChart discovers a single chart
func (d *Discoverer) discoverChart(release Release) (*Chart, error) {
	// 캐시 확인
	if cached, ok := d.cache[release.Chart]; ok {
		return cached, nil
	}

	// Normalize chart path
	// Helmfile paths can be:
	// 1. "./charts/external/harbor" → "charts/external/harbor"
	// 2. "./addons/gpu-operator" → "addons/gpu-operator"
	// 3. "charts/external/harbor" → "charts/external/harbor"
	chartPath := release.Chart

	// If path starts with "charts/", it's already relative to helmfile dir
	// ChartsPath is already pointing to the charts directory, so we need to go up one level
	if strings.HasPrefix(chartPath, "charts/") {
		// Use helmfile directory instead of charts directory
		helmfileDir := filepath.Dir(d.config.HelmfilePath)
		chartPath = filepath.Join(helmfileDir, chartPath)
	} else if strings.HasPrefix(chartPath, "addons/") {
		// Path like "addons/gpu-operator" → use helmfile directory
		helmfileDir := filepath.Dir(d.config.HelmfilePath)
		chartPath = filepath.Join(helmfileDir, chartPath)
	} else {
		// Path like "external/harbor" → use charts directory
		chartPath = filepath.Join(d.config.ChartsPath, chartPath)
	}

	// Chart.yaml 확인
	chartYaml := filepath.Join(chartPath, "Chart.yaml")
	if _, err := os.Stat(chartYaml); err != nil {
		return nil, fmt.Errorf("chart.yaml 없음: %s", chartYaml)
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

	// values.yaml 로드 (기본 차트 values)
	valuesPath := filepath.Join(chartPath, "values.yaml")
	if data, err := os.ReadFile(valuesPath); err == nil {
		yaml.Unmarshal(data, &chart.Values)
	}

	// Helmfile release values 로드 및 병합 (Gap #1 & #2 해결)
	// Always load values (includes environment base values even if no release-specific values)
	releaseValues, err := d.LoadReleaseValues(release)
	if err != nil {
		log.Warn().
			Err(err).
			Str("release", release.Name).
			Msg("Release values 로드 실패, 차트 기본값 사용")
	} else if len(releaseValues) > 0 {
		// Deep merge release values into chart values
		if chart.Values == nil {
			chart.Values = releaseValues
		} else {
			chart.Values = utils.DeepMerge(chart.Values, releaseValues)
		}
		log.Debug().
			Str("release", release.Name).
			Int("values_count", len(chart.Values)).
			Msg("Release values 병합 완료")
	}

	// 캐시 저장
	d.cache[release.Chart] = chart

	return chart, nil
}

// detectChartType detects the type of chart
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

// scanChartsDirectory scans the charts directory for additional charts
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
