package extractor

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/astrago/helm-image-extractor/internal/utils"
	"gopkg.in/yaml.v3"
)

// Embedded config is not used for now - will load from filesystem

// OperatorConfig represents the operator configuration
type OperatorConfig struct {
	Operators map[string]OperatorSpec `yaml:"operators"`
}

// OperatorSpec represents a single operator specification
type OperatorSpec struct {
	Enabled bool            `yaml:"enabled"`
	Aliases []string        `yaml:"aliases"`
	Images  []OperatorImage `yaml:"images"`
}

// OperatorImage represents an image path configuration
type OperatorImage struct {
	Path      string `yaml:"path"`       // repository 경로 (예: validator.repository)
	ImagePath string `yaml:"image_path"` // image 이름 경로 (예: validator.image) - GPU Operator용
	TagPath   string `yaml:"tag_path"`   // tag/version 경로 (예: validator.version)
}

// LoadOperatorConfig loads operator configuration from file
func LoadOperatorConfig(configPath string) (*OperatorConfig, error) {
	var data []byte
	var err error

	// Try to load from file
	if configPath != "" {
		data, err = os.ReadFile(configPath)
		if err != nil {
			return nil, fmt.Errorf("failed to read config file: %w", err)
		}
	} else {
		// Try to find config file
		execPath, _ := os.Executable()
		execDir := filepath.Dir(execPath)

		// Try multiple locations
		possiblePaths := []string{
			filepath.Join(execDir, "..", "configs", "operators.yaml"),
			filepath.Join(execDir, "configs", "operators.yaml"),
			"configs/operators.yaml",
		}

		for _, path := range possiblePaths {
			data, err = os.ReadFile(path)
			if err == nil {
				break
			}
		}

		if err != nil {
			return nil, fmt.Errorf("failed to find operator config: %w", err)
		}
	}

	var config OperatorConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	return &config, nil
}

// GetOperatorSpec returns the operator spec for a given chart name
func (c *OperatorConfig) GetOperatorSpec(chartName string) *OperatorSpec {
	// Direct match
	if spec, ok := c.Operators[chartName]; ok && spec.Enabled {
		specCopy := spec
		return &specCopy
	}

	// Check aliases
	for _, spec := range c.Operators {
		if !spec.Enabled {
			continue
		}
		for _, alias := range spec.Aliases {
			if alias == chartName {
				specCopy := spec
				return &specCopy
			}
		}
	}

	return nil
}

// ExtractImagesFromSpec extracts images based on operator spec
func ExtractImagesFromSpec(spec *OperatorSpec, values map[string]interface{}) []string {
	images := make([]string, 0)

	for _, imgSpec := range spec.Images {
		repo := utils.GetNestedValue(values, imgSpec.Path)
		if repo == "" {
			continue
		}

		tag := utils.GetNestedValue(values, imgSpec.TagPath)
		if tag == "" {
			tag = "latest"
		}

		// GPU Operator 3필드 구조 지원: repository + image + version
		// 예: nvcr.io/nvidia/cloud-native + gpu-operator-validator + v25.3.4
		var fullImage string
		if imgSpec.ImagePath != "" {
			imageName := utils.GetNestedValue(values, imgSpec.ImagePath)
			if imageName != "" {
				// repository/imageName:tag 형식
				fullImage = fmt.Sprintf("%s/%s:%s", repo, imageName, tag)
			} else {
				// imageName이 없으면 기존 방식 사용
				fullImage = fmt.Sprintf("%s:%s", repo, tag)
			}
		} else {
			// ImagePath가 없으면 기존 2필드 방식 (하위 호환성)
			fullImage = fmt.Sprintf("%s:%s", repo, tag)
		}

		images = append(images, fullImage)
	}

	return images
}
