package config

import (
	"encoding/json"
	"fmt"
	"os"
)

// ChartsConfig represents the charts.json configuration
type ChartsConfig struct {
	Repositories map[string]string      `json:"repositories"`
	Charts       map[string]ChartInfo   `json:"charts"`
}

// ChartInfo represents information about a single chart
type ChartInfo struct {
	Repository string `json:"repository"`
	Version    string `json:"version"`
}

// LoadChartsConfig loads the charts configuration from charts.json
func LoadChartsConfig(path string) (*ChartsConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read charts config: %w", err)
	}

	var config ChartsConfig
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse charts config: %w", err)
	}

	return &config, nil
}

// GetChartList returns a list of all chart names
func (c *ChartsConfig) GetChartList() []string {
	charts := make([]string, 0, len(c.Charts))
	for name := range c.Charts {
		charts = append(charts, name)
	}
	return charts
}

// GetChartVersion returns the version for a specific chart
func (c *ChartsConfig) GetChartVersion(name string) string {
	if info, ok := c.Charts[name]; ok {
		return info.Version
	}
	return ""
}

// GetChartRepository returns the repository name for a specific chart
func (c *ChartsConfig) GetChartRepository(name string) string {
	if info, ok := c.Charts[name]; ok {
		return info.Repository
	}
	return ""
}

// GetRepositoryURL returns the URL for a repository
func (c *ChartsConfig) GetRepositoryURL(name string) string {
	if url, ok := c.Repositories[name]; ok {
		return url
	}
	return ""
}