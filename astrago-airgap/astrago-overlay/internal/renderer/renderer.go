package renderer

import (
	"bytes"
	"fmt"
	"os"
	"runtime"
	"sync"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/astrago/helm-image-extractor/internal/discovery"
	"github.com/astrago/helm-image-extractor/internal/utils"
	"github.com/rs/zerolog/log"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/chartutil"
	"helm.sh/helm/v3/pkg/cli"
)

// Renderer handles Helm chart rendering
type Renderer struct {
	config   *config.Config
	settings *cli.EnvSettings
	cache    map[string]*RenderResult // Phase 5.2: 차트 렌더링 결과 캐싱
	cacheMu  sync.RWMutex             // Phase 5.2: 캐시 동시성 제어
}

// RenderResult holds the result of rendering a chart
type RenderResult struct {
	Chart     *discovery.Chart
	Manifests string
	Error     error
}

// New creates a new Renderer
func New(cfg *config.Config) *Renderer {
	return &Renderer{
		config:   cfg,
		settings: cli.New(),
		cache:    make(map[string]*RenderResult), // Phase 5.2: 캐시 초기화
	}
}

// RenderAll renders all charts
func (r *Renderer) RenderAll(charts []*discovery.Chart) ([]*RenderResult, error) {
	if r.config.Workers > 1 {
		return r.renderParallel(charts)
	}
	return r.renderSequential(charts)
}

// renderParallel renders charts in parallel
func (r *Renderer) renderParallel(charts []*discovery.Chart) ([]*RenderResult, error) {
	var wg sync.WaitGroup
	results := make([]*RenderResult, len(charts))
	jobs := make(chan int, len(charts))

	// Phase 5.1: 동적 워커 수 조정
	workers := r.config.Workers
	if workers <= 0 {
		workers = runtime.NumCPU()
	}
	if workers > 32 {
		workers = 32
	}

	log.Debug().Int("workers", workers).Msg("병렬 렌더링 시작")

	// Start workers
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for idx := range jobs {
				results[idx] = r.renderChart(charts[idx])
			}
		}()
	}

	// Send jobs
	for i := range charts {
		jobs <- i
	}
	close(jobs)

	wg.Wait()
	return results, nil
}

// renderSequential renders charts sequentially
func (r *Renderer) renderSequential(charts []*discovery.Chart) ([]*RenderResult, error) {
	results := make([]*RenderResult, 0, len(charts))

	log.Debug().Msg("순차 렌더링 시작")

	for _, chart := range charts {
		result := r.renderChart(chart)
		results = append(results, result)
	}

	return results, nil
}

// renderChart renders a single chart
func (r *Renderer) renderChart(chart *discovery.Chart) *RenderResult {
	// Phase 5.2: 캐시 확인
	if r.config.EnableCache {
		cacheKey := chart.Path
		r.cacheMu.RLock()
		if cached, ok := r.cache[cacheKey]; ok {
			r.cacheMu.RUnlock()
			log.Debug().
				Str("name", chart.Name).
				Msg("캐시에서 렌더링 결과 가져옴")
			return cached
		}
		r.cacheMu.RUnlock()
	}

	result := &RenderResult{Chart: chart}

	log.Debug().
		Str("name", chart.Name).
		Str("path", chart.Path).
		Msg("차트 렌더링 시작")

	// Load chart
	chartObj, err := loader.Load(chart.Path)
	if err != nil {
		result.Error = fmt.Errorf("차트 로드 실패: %w", err)
		log.Warn().
			Str("chart", chart.Name).
			Err(err).
			Msg("차트 로드 실패, fallback 사용")
		return result
	}

	// Setup action configuration
	actionConfig := new(action.Configuration)
	namespace := "default"

	// Initialize with no-op logger (DryRun mode, no cluster needed)
	if err := actionConfig.Init(
		r.settings.RESTClientGetter(),
		namespace,
		os.Getenv("HELM_DRIVER"),
		func(format string, v ...interface{}) {
			// No-op logger
		},
	); err != nil {
		result.Error = fmt.Errorf("action config 초기화 실패: %w", err)
		log.Warn().
			Str("chart", chart.Name).
			Err(err).
			Msg("Action config 초기화 실패")
		return result
	}

	// Create install action (dry-run for template)
	client := action.NewInstall(actionConfig)
	client.DryRun = true
	client.ReleaseName = chart.Name
	client.Replace = true
	client.ClientOnly = true

	// Set Kubernetes version for compatibility check
	// Use k8s 1.28 to support most modern charts
	client.KubeVersion = &chartutil.KubeVersion{
		Version: "v1.28.0",
		Major:   "1",
		Minor:   "28",
	}
	client.Namespace = namespace

	// Merge values with Go template rendering support
	vals := make(map[string]interface{})
	if chartObj.Values != nil {
		for k, v := range chartObj.Values {
			vals[k] = v
		}
	}
	if chart.Values != nil {
		// Use utils.DeepMerge for proper nested value handling (Gap #2 fix)
		vals = utils.DeepMerge(vals, chart.Values)
	}

	// Render chart
	release, err := client.Run(chartObj, vals)
	if err != nil {
		result.Error = fmt.Errorf("렌더링 실패: %w", err)
		log.Warn().
			Str("chart", chart.Name).
			Err(err).
			Msg("렌더링 실패, fallback 사용")
		return result
	}

	// Collect manifests
	var buf bytes.Buffer
	fmt.Fprintln(&buf, release.Manifest)

	// Include hooks
	for _, hook := range release.Hooks {
		fmt.Fprintln(&buf, "---")
		fmt.Fprintln(&buf, hook.Manifest)
	}

	result.Manifests = buf.String()

	log.Debug().
		Str("chart", chart.Name).
		Int("manifest_size", len(result.Manifests)).
		Msg("차트 렌더링 완료")

	// Phase 5.2: 캐시 저장
	if r.config.EnableCache {
		cacheKey := chart.Path
		r.cacheMu.Lock()
		r.cache[cacheKey] = result
		r.cacheMu.Unlock()
	}

	return result
}
