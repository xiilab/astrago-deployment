package chart

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"helm.sh/helm/v3/pkg/chart/loader"
	"sigs.k8s.io/yaml"
)

// Modifier handles chart modifications
type Modifier struct {
	chartPath string
}

// NewModifier creates a new chart modifier
func NewModifier(chartPath string) *Modifier {
	return &Modifier{
		chartPath: chartPath,
	}
}

// UpdateRepositoriesToLocal updates all dependency repositories to local file paths with exact versions
func (m *Modifier) UpdateRepositoriesToLocal() error {
	chartYamlPath := filepath.Join(m.chartPath, "Chart.yaml")
	
	// Load the chart
	chrt, err := loader.Load(m.chartPath)
	if err != nil {
		return fmt.Errorf("failed to load chart: %w", err)
	}

	// Update dependencies
	if chrt.Metadata.Dependencies != nil {
		for _, dep := range chrt.Metadata.Dependencies {
			// Update to local file path for external repos or empty repository
			if dep.Repository == "" ||
			   strings.HasPrefix(dep.Repository, "http://") || 
			   strings.HasPrefix(dep.Repository, "https://") || 
			   strings.HasPrefix(dep.Repository, "oci://") {
				// Update to local file path with dependency name
				dep.Repository = fmt.Sprintf("file://charts/%s", dep.Name)
			}
		}
	}

	// Marshal back to YAML
	data, err := yaml.Marshal(chrt.Metadata)
	if err != nil {
		return fmt.Errorf("failed to marshal chart metadata: %w", err)
	}

	// Write back to Chart.yaml
	if err := os.WriteFile(chartYamlPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write Chart.yaml: %w", err)
	}

	return nil
}

