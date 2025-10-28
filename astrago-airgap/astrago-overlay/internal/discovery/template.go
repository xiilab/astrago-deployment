package discovery

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/astrago/helm-image-extractor/internal/utils"
	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// renderGoTemplate renders Go template variables in the content
func (d *Discoverer) renderGoTemplate(content string, envValues map[string]interface{}) (string, error) {
	// Create template with custom functions (Helmfile template functions)
	funcMap := template.FuncMap{
		"default": func(defaultVal, val interface{}) interface{} {
			if val == nil || val == "" {
				return defaultVal
			}
			return val
		},
		"required": func(msg string, val interface{}) (interface{}, error) {
			if val == nil || val == "" {
				return nil, fmt.Errorf("required value missing: %s", msg)
			}
			return val, nil
		},
		"env": func(key string) string {
			return os.Getenv(key)
		},
		"getenv": func(key string, defaultVal ...string) string {
			if val := os.Getenv(key); val != "" {
				return val
			}
			if len(defaultVal) > 0 {
				return defaultVal[0]
			}
			return ""
		},
		// Additional Helmfile/Sprig template functions
		"hasKey": func(m map[string]interface{}, key string) bool {
			_, exists := m[key]
			return exists
		},
		"get": func(m map[string]interface{}, key string) interface{} {
			return m[key]
		},
		"set": func(m map[string]interface{}, key string, val interface{}) map[string]interface{} {
			m[key] = val
			return m
		},
		"empty": func(v interface{}) bool {
			if v == nil {
				return true
			}
			switch val := v.(type) {
			case string:
				return val == ""
			case []interface{}:
				return len(val) == 0
			case map[string]interface{}:
				return len(val) == 0
			default:
				return false
			}
		},
		"coalesce": func(vals ...interface{}) interface{} {
			for _, val := range vals {
				if val != nil && val != "" {
					return val
				}
			}
			return nil
		},
		"ternary": func(condition bool, trueVal, falseVal interface{}) interface{} {
			if condition {
				return trueVal
			}
			return falseVal
		},
		"toYaml": func(v interface{}) string {
			// Simple YAML-like string representation
			data, err := yaml.Marshal(v)
			if err != nil {
				return fmt.Sprintf("%v", v)
			}
			return string(data)
		},
		"nindent": func(n int, v string) string {
			// Add indentation to each line
			indent := strings.Repeat(" ", n)
			lines := strings.Split(v, "\n")
			indented := make([]string, len(lines))
			for i, line := range lines {
				if line != "" {
					indented[i] = indent + line
				} else {
					indented[i] = ""
				}
			}
			return strings.Join(indented, "\n")
		},
		"quote": func(v interface{}) string {
			// Quote a string value
			return fmt.Sprintf("\"%v\"", v)
		},
	}

	tmpl, err := template.New("values").
		Funcs(funcMap).
		Option("missingkey=zero"). // Don't error on missing keys, use zero value
		Parse(content)
	if err != nil {
		return "", fmt.Errorf("template parse failed: %w", err)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, envValues); err != nil {
		return "", fmt.Errorf("template execute failed: %w", err)
	}

	return buf.String(), nil
}

// loadEnvironmentValues loads environment-specific values
func (d *Discoverer) loadEnvironmentValues() (map[string]interface{}, error) {
	helmfileDir := filepath.Dir(d.config.HelmfilePath)

	// Load order:
	// 1. environments/common/values.yaml
	// 2. environments/base/values.yaml
	// 3. environments/customers/{customer}/values.yaml (if customer mode)

	envValues := make(map[string]interface{})

	// Common values
	commonPath := filepath.Join(helmfileDir, "environments", "common", "values.yaml")
	if data, err := os.ReadFile(commonPath); err == nil {
		var common map[string]interface{}
		if err := yaml.Unmarshal(data, &common); err == nil {
			envValues = utils.DeepMerge(envValues, common)
			log.Debug().Str("path", commonPath).Msg("Loaded common values")
		}
	}

	// Base values
	basePath := filepath.Join(helmfileDir, "environments", "base", "values.yaml")
	if data, err := os.ReadFile(basePath); err == nil {
		var base map[string]interface{}
		if err := yaml.Unmarshal(data, &base); err == nil {
			envValues = utils.DeepMerge(envValues, base)
			log.Debug().Str("path", basePath).Msg("Loaded base values")
		}
	}

	// Customer-specific values (if environment variable is set OR environment flag is used)
	customer := os.Getenv("CUSTOMER_NAME")

	// Check if environment flag is set and not "default"
	if customer == "" && d.config.Environment != "default" && d.config.Environment != "" {
		// Check if environment is a valid customer directory
		customerPath := filepath.Join(helmfileDir, "environments", "customers", d.config.Environment, "values.yaml")
		if _, err := os.Stat(customerPath); err == nil {
			customer = d.config.Environment
			log.Debug().
				Str("environment", d.config.Environment).
				Msg("Using environment as customer name")
		}
	}

	if customer != "" {
		customerPath := filepath.Join(helmfileDir, "environments", "customers", customer, "values.yaml")
		if data, err := os.ReadFile(customerPath); err == nil {
			var customerVals map[string]interface{}
			if err := yaml.Unmarshal(data, &customerVals); err == nil {
				envValues = utils.DeepMerge(envValues, customerVals)
				log.Debug().
					Str("customer", customer).
					Str("path", customerPath).
					Msg("Loaded customer values")
			}
		} else {
			log.Debug().
				Str("customer", customer).
				Str("path", customerPath).
				Msg("Customer values file not found")
		}
	}

	// Wrap in .Values structure for template compatibility
	return map[string]interface{}{
		"Values": envValues,
	}, nil
}

// loadAndRenderValues loads values file and renders Go templates if needed
func (d *Discoverer) loadAndRenderValues(valuesPath string) (map[string]interface{}, error) {
	// 1. Read values file
	data, err := os.ReadFile(valuesPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read values file %s: %w", valuesPath, err)
	}

	// 2. If .gotmpl file, render Go template
	if strings.HasSuffix(valuesPath, ".gotmpl") || strings.HasSuffix(valuesPath, ".yaml.gotmpl") {
		log.Debug().Str("path", valuesPath).Msg("Rendering Go template")

		// Load environment values
		envValues, err := d.loadEnvironmentValues()
		if err != nil {
			log.Warn().Err(err).Msg("Failed to load environment values, using empty context")
			envValues = map[string]interface{}{
				"Values": make(map[string]interface{}),
			}
		}

		// Render template
		rendered, err := d.renderGoTemplate(string(data), envValues)
		if err != nil {
			log.Warn().
				Err(err).
				Str("path", valuesPath).
				Msg("Template rendering failed, using original content")
			// Fall back to original content if template rendering fails
		} else {
			data = []byte(rendered)
			log.Debug().
				Str("path", valuesPath).
				Int("size", len(rendered)).
				Msg("Template rendered successfully")
		}
	}

	// 3. Parse YAML
	var values map[string]interface{}
	if err := yaml.Unmarshal(data, &values); err != nil {
		return nil, fmt.Errorf("failed to parse YAML from %s: %w", valuesPath, err)
	}

	return values, nil
}

// LoadReleaseValues loads all values files for a release and merges them
func (d *Discoverer) LoadReleaseValues(release Release) (map[string]interface{}, error) {
	// Start with environment values (base + customer-specific)
	envContext, err := d.loadEnvironmentValues()
	if err != nil {
		log.Warn().Err(err).Msg("Failed to load environment values, starting with empty")
		envContext = map[string]interface{}{"Values": make(map[string]interface{})}
	}

	// Extract actual values from { "Values": {...} } structure
	mergedValues := make(map[string]interface{})
	if vals, ok := envContext["Values"].(map[string]interface{}); ok {
		mergedValues = vals
	}

	helmfileDir := filepath.Dir(d.config.HelmfilePath)

	// Load each values file in order (release-specific values override environment)
	for _, valuesFile := range release.Values {
		// Resolve path relative to helmfile directory
		valuesPath := valuesFile
		if !filepath.IsAbs(valuesPath) {
			valuesPath = filepath.Join(helmfileDir, valuesFile)
		}

		log.Debug().
			Str("release", release.Name).
			Str("values", valuesPath).
			Msg("Loading values file")

		values, err := d.loadAndRenderValues(valuesPath)
		if err != nil {
			log.Warn().
				Err(err).
				Str("release", release.Name).
				Str("values", valuesPath).
				Msg("Failed to load values file, skipping")
			continue
		}

		// Merge values
		mergedValues = utils.DeepMerge(mergedValues, values)
	}

	log.Debug().
		Str("release", release.Name).
		Int("keys", len(mergedValues)).
		Msg("Merged values")

	return mergedValues, nil
}
