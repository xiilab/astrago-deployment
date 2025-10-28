package extractor

import (
	"testing"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/astrago/helm-image-extractor/internal/discovery"
	"github.com/astrago/helm-image-extractor/internal/renderer"
	"github.com/astrago/helm-image-extractor/internal/utils"
)

func TestGetNestedValue(t *testing.T) {
	tests := []struct {
		name string
		data map[string]interface{}
		path string
		want string
	}{
		{
			name: "단일 레벨 값",
			data: map[string]interface{}{
				"image": "nginx:latest",
			},
			path: "image",
			want: "nginx:latest",
		},
		{
			name: "중첩된 값",
			data: map[string]interface{}{
				"image": map[string]interface{}{
					"repository": "nginx",
					"tag":        "1.19",
				},
			},
			path: "image.repository",
			want: "nginx",
		},
		{
			name: "깊게 중첩된 값",
			data: map[string]interface{}{
				"spec": map[string]interface{}{
					"template": map[string]interface{}{
						"spec": map[string]interface{}{
							"containers": map[string]interface{}{
								"image": "busybox:latest",
							},
						},
					},
				},
			},
			path: "spec.template.spec.containers.image",
			want: "busybox:latest",
		},
		{
			name: "존재하지 않는 경로",
			data: map[string]interface{}{
				"image": "nginx:latest",
			},
			path: "nonexistent.path",
			want: "",
		},
		{
			name: "잘못된 타입",
			data: map[string]interface{}{
				"replicas": 3,
			},
			path: "replicas",
			want: "",
		},
		{
			name: "중간에 잘못된 타입",
			data: map[string]interface{}{
				"config": "string-value",
			},
			path: "config.nested.value",
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := utils.GetNestedValue(tt.data, tt.path)
			if got != tt.want {
				t.Errorf("utils.GetNestedValue() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestExtract(t *testing.T) {
	cfg := &config.Config{
		Workers: 2,
	}
	e := New(cfg)

	// 테스트 데이터 준비
	charts := []*discovery.Chart{
		{
			Name: "test-chart",
			Type: discovery.ChartTypeLocal,
			Values: map[string]interface{}{
				"image": map[string]interface{}{
					"repository": "nginx",
					"tag":        "1.19",
				},
			},
		},
	}

	results := []*renderer.RenderResult{
		{
			Chart: charts[0],
			Manifests: `
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.19
`,
			Error: nil,
		},
	}

	images := e.Extract(results, charts)

	if len(images) == 0 {
		t.Error("Expected at least one image to be extracted")
	}

	// nginx 이미지 확인
	nginxFound := false
	for img := range images {
		if contains(img, "nginx") {
			nginxFound = true
			break
		}
	}

	if !nginxFound {
		t.Error("Expected nginx image not found")
	}
}

func TestExtractWithErrors(t *testing.T) {
	cfg := &config.Config{
		Workers: 2,
	}
	e := New(cfg)

	// 렌더링 실패한 차트
	charts := []*discovery.Chart{
		{
			Name: "failed-chart",
			Type: discovery.ChartTypeLocal,
			Values: map[string]interface{}{
				"image": "fallback-image:latest",
			},
		},
	}

	results := []*renderer.RenderResult{
		{
			Chart:     charts[0],
			Manifests: "",
			Error:     &testError{msg: "rendering failed"},
		},
	}

	// Fallback으로 values에서 이미지 추출해야 함
	images := e.Extract(results, charts)

	if len(images) == 0 {
		t.Error("Expected fallback image extraction from values")
	}
}

func TestExtractOperatorImages(t *testing.T) {
	cfg := &config.Config{}

	// Mock operator config with test specs
	mockOperatorConfig := &OperatorConfig{
		Operators: map[string]OperatorSpec{
			"gpu-operator": {
				Enabled: true,
				Images: []OperatorImage{
					{Path: "operator.repository", TagPath: "operator.version"},
				},
			},
			"harbor": {
				Enabled: true,
				Images: []OperatorImage{
					{Path: "portal.image.repository", TagPath: "portal.image.tag"},
				},
			},
		},
	}

	e := &Extractor{
		config:         cfg,
		operatorConfig: mockOperatorConfig,
	}

	tests := []struct {
		name      string
		chart     *discovery.Chart
		wantCount int
	}{
		{
			name: "GPU Operator",
			chart: &discovery.Chart{
				Name: "gpu-operator",
				Type: discovery.ChartTypeOperator,
				Values: map[string]interface{}{
					"operator": map[string]interface{}{
						"repository": "nvcr.io/nvidia/gpu-operator",
						"version":    "v23.9.0",
					},
				},
			},
			wantCount: 1, // 최소 1개
		},
		{
			name: "Harbor",
			chart: &discovery.Chart{
				Name: "harbor",
				Type: discovery.ChartTypeLocal,
				Values: map[string]interface{}{
					"portal": map[string]interface{}{
						"image": map[string]interface{}{
							"repository": "goharbor/harbor-portal",
							"tag":        "v2.9.0",
						},
					},
				},
			},
			wantCount: 1, // 최소 1개
		},
		{
			name: "일반 차트 (Operator 로직 미적용)",
			chart: &discovery.Chart{
				Name:   "nginx",
				Type:   discovery.ChartTypeLocal,
				Values: map[string]interface{}{},
			},
			wantCount: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			images := e.extractOperatorImages(tt.chart)
			if len(images) < tt.wantCount {
				t.Errorf("extractOperatorImages() returned %d images, want at least %d", len(images), tt.wantCount)
			}
		})
	}
}

// Helper types and functions

type testError struct {
	msg string
}

func (e *testError) Error() string {
	return e.msg
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && substringExists(s, substr)
}

func substringExists(s, substr string) bool {
	if len(substr) == 0 {
		return true
	}
	if len(s) < len(substr) {
		return false
	}
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
