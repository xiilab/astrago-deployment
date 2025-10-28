package discovery

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/astrago/helm-image-extractor/internal/config"
)

func TestRenderGoTemplateBasic(t *testing.T) {
	cfg := &config.Config{
		Environment: "production",
	}

	d := New(cfg)

	template := `environment: {{ .Environment }}`
	data := map[string]interface{}{
		"Environment": "production",
	}

	result, err := d.renderGoTemplate(template, data)
	if err != nil {
		t.Fatalf("renderGoTemplate() failed: %v", err)
	}

	if !strings.Contains(result, "environment: production") {
		t.Error("Template should render Environment")
	}
}

func TestRenderGoTemplateWithDefaults(t *testing.T) {
	cfg := &config.Config{}
	d := New(cfg)

	template := `replicas: {{ .Values.replicas | default 3 }}`
	result, err := d.renderGoTemplate(template, map[string]interface{}{
		"Values": map[string]interface{}{},
	})

	if err != nil {
		t.Fatalf("renderGoTemplate() with default failed: %v", err)
	}

	if !strings.Contains(result, "3") {
		t.Error("Template should use default value")
	}
}

func TestLoadReleaseValuesSimple(t *testing.T) {
	tmpDir := t.TempDir()
	helmfileDir := filepath.Join(tmpDir, "helmfile")
	valuesDir := filepath.Join(helmfileDir, "values")
	if err := os.MkdirAll(valuesDir, 0755); err != nil {
		t.Fatal(err)
	}

	// Create a simple values file
	values1 := `
replicas: 3
image:
  repository: nginx
  tag: "1.19"
`
	if err := os.WriteFile(filepath.Join(valuesDir, "base.yaml"), []byte(values1), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		HelmfilePath: filepath.Join(helmfileDir, "helmfile.yaml.gotmpl"),
		Environment:  "production",
	}

	d := New(cfg)

	release := Release{
		Name: "test",
		Values: []string{
			"values/base.yaml",
		},
	}

	mergedValues, err := d.LoadReleaseValues(release)
	if err != nil {
		t.Fatalf("LoadReleaseValues() failed: %v", err)
	}

	if mergedValues == nil {
		t.Error("Merged values should not be nil")
	}

	// Check replicas
	if replicas, ok := mergedValues["replicas"].(int); !ok || replicas != 3 {
		t.Errorf("Replicas should be 3, got %v", mergedValues["replicas"])
	}
}

func TestLoadReleaseValuesNonExistent(t *testing.T) {
	tmpDir := t.TempDir()
	helmfileDir := filepath.Join(tmpDir, "helmfile")
	if err := os.MkdirAll(helmfileDir, 0755); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		HelmfilePath: filepath.Join(helmfileDir, "helmfile.yaml.gotmpl"),
		Environment:  "production",
	}

	d := New(cfg)

	release := Release{
		Name: "test",
		Values: []string{
			"values/nonexistent.yaml",
		},
	}

	// Should not fail, just skip non-existent files
	mergedValues, err := d.LoadReleaseValues(release)
	if err != nil {
		t.Fatalf("LoadReleaseValues() should not fail: %v", err)
	}

	// Should return empty or minimal map
	if mergedValues == nil {
		t.Error("Should return non-nil map")
	}
}

func TestRenderGoTemplateInvalidSyntax(t *testing.T) {
	cfg := &config.Config{}
	d := New(cfg)

	// Invalid template syntax
	template := `{{ .Invalid `

	_, err := d.renderGoTemplate(template, map[string]interface{}{})
	if err == nil {
		t.Error("renderGoTemplate() should fail with invalid syntax")
	}
}
