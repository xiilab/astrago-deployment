package extractor

import (
	"sync"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/astrago/helm-image-extractor/internal/discovery"
	"github.com/astrago/helm-image-extractor/internal/renderer"
	"github.com/astrago/helm-image-extractor/pkg/patterns"
	"github.com/rs/zerolog/log"
)

// Extractor extracts images from charts
type Extractor struct {
	config         *config.Config
	operatorConfig *OperatorConfig
}

// New creates a new Extractor
func New(cfg *config.Config) *Extractor {
	// Load operator config
	opConfig, err := LoadOperatorConfig("")
	if err != nil {
		log.Warn().Err(err).Msg("Failed to load operator config, using fallback")
		opConfig = &OperatorConfig{Operators: make(map[string]OperatorSpec)}
	}

	return &Extractor{
		config:         cfg,
		operatorConfig: opConfig,
	}
}

// Extract extracts images from render results
func (e *Extractor) Extract(results []*renderer.RenderResult, charts []*discovery.Chart) map[string]bool {
	images := make(map[string]bool)
	mu := sync.Mutex{}

	log.Info().Msg("이미지 추출 시작")

	// Track successfully rendered charts
	successfulCharts := make(map[string]bool)

	// Extract from manifests
	for _, result := range results {
		if result.Error != nil {
			log.Debug().
				Str("chart", result.Chart.Name).
				Msg("렌더링 실패, fallback 사용")

			// Fallback to values.yaml extraction
			if result.Chart.Values != nil {
				fallbackImages := patterns.ExtractFromValues(result.Chart.Values)
				mu.Lock()
				for _, img := range fallbackImages {
					images[img] = true
				}
				mu.Unlock()

				log.Debug().
					Str("chart", result.Chart.Name).
					Int("count", len(fallbackImages)).
					Msg("Fallback에서 이미지 추출")
			}
			continue
		}

		// Mark as successfully rendered
		successfulCharts[result.Chart.Name] = true

		// Extract from manifests
		manifestImages := patterns.ExtractFromManifest(result.Manifests)
		mu.Lock()
		for _, img := range manifestImages {
			images[img] = true
		}
		mu.Unlock()

		log.Debug().
			Str("chart", result.Chart.Name).
			Int("count", len(manifestImages)).
			Msg("Manifest에서 이미지 추출")
	}

	// Supplement with values.yaml extraction (only for charts without successful manifest rendering)
	for _, chart := range charts {
		// Skip if chart was successfully rendered
		if successfulCharts[chart.Name] {
			log.Debug().
				Str("chart", chart.Name).
				Msg("Manifest 렌더링 성공, Values 보조 추출 skip")
			continue
		}

		if chart.Values != nil {
			valuesImages := patterns.ExtractFromValues(chart.Values)
			mu.Lock()
			for _, img := range valuesImages {
				images[img] = true
			}
			mu.Unlock()

			log.Debug().
				Str("chart", chart.Name).
				Int("count", len(valuesImages)).
				Msg("Values에서 보조 이미지 추출")
		}
	}

	// Operator-specific supplementation
	for _, chart := range charts {
		if chart.Type == discovery.ChartTypeOperator {
			operatorImages := e.extractOperatorImages(chart)
			mu.Lock()
			for _, img := range operatorImages {
				images[img] = true
			}
			mu.Unlock()

			log.Debug().
				Str("chart", chart.Name).
				Int("count", len(operatorImages)).
				Msg("Operator 특화 이미지 추출")
		}
	}

	log.Info().Int("total", len(images)).Msg("이미지 추출 완료")

	return images
}

// extractOperatorImages extracts images specific to operator charts
// Uses operators.yaml configuration for dynamic image extraction
func (e *Extractor) extractOperatorImages(chart *discovery.Chart) []string {
	images := make([]string, 0)

	if chart.Values == nil {
		return images
	}

	// Get operator spec from config
	spec := e.operatorConfig.GetOperatorSpec(chart.Name)
	if spec != nil {
		configImages := ExtractImagesFromSpec(spec, chart.Values)
		images = append(images, configImages...)

		log.Debug().
			Str("chart", chart.Name).
			Int("count", len(configImages)).
			Msg("Operator 설정 기반 이미지 추출")
	} else {
		log.Debug().
			Str("chart", chart.Name).
			Msg("Operator 설정 없음, 기본 추출 메커니즘 사용")
	}

	return images
}
