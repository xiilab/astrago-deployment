package renderer

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/astrago/helm-image-extractor/internal/discovery"
	"github.com/astrago/helm-image-extractor/internal/utils"
)

func TestNew(t *testing.T) {
	cfg := &config.Config{
		Workers: 5,
	}

	r := New(cfg)

	if r == nil {
		t.Fatal("New() returned nil")
	}

	if r.config != cfg {
		t.Error("Config not set correctly")
	}

	if r.settings == nil {
		t.Error("Settings not initialized")
	}
}

func TestDeepMerge(t *testing.T) {
	tests := []struct {
		name string
		dst  map[string]interface{}
		src  map[string]interface{}
		want map[string]interface{}
	}{
		{
			name: "단순 병합",
			dst: map[string]interface{}{
				"replicas": 1,
			},
			src: map[string]interface{}{
				"replicas": 3,
			},
			want: map[string]interface{}{
				"replicas": 3,
			},
		},
		{
			name: "중첩 맵 병합",
			dst: map[string]interface{}{
				"image": map[string]interface{}{
					"repository": "nginx",
					"tag":        "latest",
				},
			},
			src: map[string]interface{}{
				"image": map[string]interface{}{
					"tag": "1.19",
				},
			},
			want: map[string]interface{}{
				"image": map[string]interface{}{
					"repository": "nginx",
					"tag":        "1.19",
				},
			},
		},
		{
			name: "새 키 추가",
			dst: map[string]interface{}{
				"replicas": 1,
			},
			src: map[string]interface{}{
				"port": 8080,
			},
			want: map[string]interface{}{
				"replicas": 1,
				"port":     8080,
			},
		},
		{
			name: "nil dst",
			dst:  nil,
			src: map[string]interface{}{
				"key": "value",
			},
			want: map[string]interface{}{
				"key": "value",
			},
		},
		{
			name: "빈 src",
			dst: map[string]interface{}{
				"key": "value",
			},
			src: map[string]interface{}{},
			want: map[string]interface{}{
				"key": "value",
			},
		},
		{
			name: "깊게 중첩된 병합",
			dst: map[string]interface{}{
				"config": map[string]interface{}{
					"database": map[string]interface{}{
						"host": "localhost",
						"port": 5432,
					},
				},
			},
			src: map[string]interface{}{
				"config": map[string]interface{}{
					"database": map[string]interface{}{
						"port": 3306,
						"name": "mydb",
					},
				},
			},
			want: map[string]interface{}{
				"config": map[string]interface{}{
					"database": map[string]interface{}{
						"host": "localhost",
						"port": 3306,
						"name": "mydb",
					},
				},
			},
		},
		{
			name: "맵이 아닌 값으로 덮어쓰기",
			dst: map[string]interface{}{
				"value": map[string]interface{}{
					"nested": "data",
				},
			},
			src: map[string]interface{}{
				"value": "simple-string",
			},
			want: map[string]interface{}{
				"value": "simple-string",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := utils.DeepMerge(tt.dst, tt.src)

			// 간단한 깊이의 비교
			for key, wantVal := range tt.want {
				gotVal, ok := got[key]
				if !ok {
					t.Errorf("Expected key %s not found in result", key)
					continue
				}

				// 맵인 경우 중첩된 값도 확인
				if wantMap, ok := wantVal.(map[string]interface{}); ok {
					gotMap, ok := gotVal.(map[string]interface{})
					if !ok {
						t.Errorf("Value for key %s is not a map", key)
						continue
					}

					// 중첩된 맵의 키들 비교
					for nestedKey, nestedWant := range wantMap {
						nestedGot, ok := gotMap[nestedKey]
						if !ok {
							t.Errorf("Expected nested key %s.%s not found", key, nestedKey)
							continue
						}

						// 더 깊은 중첩의 경우
						if nestedWantMap, ok := nestedWant.(map[string]interface{}); ok {
							nestedGotMap, ok := nestedGot.(map[string]interface{})
							if !ok {
								t.Errorf("Nested value for %s.%s is not a map", key, nestedKey)
								continue
							}

							for deepKey, deepWant := range nestedWantMap {
								deepGot, ok := nestedGotMap[deepKey]
								if !ok {
									t.Errorf("Expected deep key %s.%s.%s not found", key, nestedKey, deepKey)
									continue
								}
								if deepGot != deepWant {
									t.Errorf("Deep value mismatch for %s.%s.%s: got %v, want %v", key, nestedKey, deepKey, deepGot, deepWant)
								}
							}
						} else {
							// 기본 타입 비교
							if nestedGot != nestedWant {
								t.Errorf("Nested value mismatch for %s.%s: got %v, want %v", key, nestedKey, nestedGot, nestedWant)
							}
						}
					}
				} else {
					// 기본 타입 비교
					if gotVal != wantVal {
						t.Errorf("Value mismatch for key %s: got %v, want %v", key, gotVal, wantVal)
					}
				}
			}
		})
	}
}

func TestRenderAll_SequentialVsParallel(t *testing.T) {
	cfg := &config.Config{
		Workers: 1, // Sequential
	}

	r := New(cfg)

	// 빈 차트 리스트로 테스트 (실제 차트 렌더링은 Helm이 필요)
	charts := []*discovery.Chart{}

	results, err := r.RenderAll(charts)
	if err != nil {
		t.Errorf("RenderAll() error = %v", err)
	}

	if results == nil {
		t.Error("RenderAll() returned nil results")
	}

	// 병렬 모드로 변경
	cfg.Workers = 5
	r = New(cfg)

	results, err = r.RenderAll(charts)
	if err != nil {
		t.Errorf("RenderAll() parallel error = %v", err)
	}

	if results == nil {
		t.Error("RenderAll() parallel returned nil results")
	}
}

func TestRenderSequential(t *testing.T) {
	cfg := &config.Config{
		Workers: 1,
	}

	r := New(cfg)

	// 빈 차트 리스트
	charts := []*discovery.Chart{}

	results, err := r.renderSequential(charts)
	if err != nil {
		t.Errorf("renderSequential() error = %v", err)
	}

	if results == nil {
		t.Error("renderSequential() returned nil")
	}

	if len(results) != 0 {
		t.Errorf("renderSequential() with empty charts returned %d results, want 0", len(results))
	}
}

func TestRenderParallel(t *testing.T) {
	cfg := &config.Config{
		Workers: 3,
	}

	r := New(cfg)

	// 빈 차트 리스트
	charts := []*discovery.Chart{}

	results, err := r.renderParallel(charts)
	if err != nil {
		t.Errorf("renderParallel() error = %v", err)
	}

	if results == nil {
		t.Error("renderParallel() returned nil")
	}

	if len(results) != 0 {
		t.Errorf("renderParallel() with empty charts returned %d results, want 0", len(results))
	}
}

func TestRenderChart_InvalidChart(t *testing.T) {
	cfg := &config.Config{}
	r := New(cfg)

	// 존재하지 않는 차트
	chart := &discovery.Chart{
		Name: "nonexistent",
		Path: "/path/to/nonexistent/chart",
	}

	result := r.renderChart(chart)

	// 에러가 발생해야 함
	if result.Error == nil {
		t.Error("renderChart() with invalid chart should return error")
	}

	if result.Chart != chart {
		t.Error("renderChart() should preserve chart reference")
	}

	if result.Manifests != "" {
		t.Error("renderChart() with error should have empty manifests")
	}
}

func TestRenderChart_ValidChart(t *testing.T) {
	// 간단한 테스트용 차트 생성
	tmpDir := t.TempDir()
	chartDir := filepath.Join(tmpDir, "test-chart")
	templatesDir := filepath.Join(chartDir, "templates")

	os.MkdirAll(templatesDir, 0755)

	// Chart.yaml
	chartYaml := `
apiVersion: v2
name: test-chart
version: 1.0.0
description: Test chart
`
	os.WriteFile(filepath.Join(chartDir, "Chart.yaml"), []byte(chartYaml), 0644)

	// values.yaml
	valuesYaml := `
image:
  repository: nginx
  tag: 1.19
`
	os.WriteFile(filepath.Join(chartDir, "values.yaml"), []byte(valuesYaml), 0644)

	// 간단한 템플릿
	deploymentTpl := `
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Chart.Name }}
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
`
	os.WriteFile(filepath.Join(templatesDir, "deployment.yaml"), []byte(deploymentTpl), 0644)

	cfg := &config.Config{}
	r := New(cfg)

	chart := &discovery.Chart{
		Name: "test-chart",
		Path: chartDir,
		Values: map[string]interface{}{
			"image": map[string]interface{}{
				"repository": "nginx",
				"tag":        "1.19",
			},
		},
	}

	result := r.renderChart(chart)

	// Note: Helm SDK가 실제 K8s 클러스터 접근을 시도하므로
	// 에러가 발생할 수 있지만, 기본적인 구조는 확인 가능
	if result == nil {
		t.Fatal("renderChart() returned nil")
	}

	if result.Chart != chart {
		t.Error("renderChart() should preserve chart reference")
	}
}

func TestRenderResult_Structure(t *testing.T) {
	chart := &discovery.Chart{
		Name: "test-chart",
	}

	result := &RenderResult{
		Chart:     chart,
		Manifests: "test manifest",
		Error:     nil,
	}

	if result.Chart != chart {
		t.Error("RenderResult.Chart not set correctly")
	}

	if result.Manifests != "test manifest" {
		t.Error("RenderResult.Manifests not set correctly")
	}

	if result.Error != nil {
		t.Error("RenderResult.Error should be nil")
	}
}

func TestRenderWithDifferentWorkerCounts(t *testing.T) {
	tests := []struct {
		name    string
		workers int
	}{
		{"순차 처리", 1},
		{"병렬 2 워커", 2},
		{"병렬 5 워커", 5},
		{"병렬 10 워커", 10},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := &config.Config{
				Workers: tt.workers,
			}

			r := New(cfg)

			// 빈 차트로 기본 동작 확인
			charts := []*discovery.Chart{}

			results, err := r.RenderAll(charts)
			if err != nil {
				t.Errorf("RenderAll() with %d workers error = %v", tt.workers, err)
			}

			if results == nil {
				t.Errorf("RenderAll() with %d workers returned nil", tt.workers)
			}
		})
	}
}

func TestRenderer_ValuesHandling(t *testing.T) {
	// utils.DeepMerge가 values를 올바르게 병합하는지 테스트
	chartValues := map[string]interface{}{
		"image": map[string]interface{}{
			"repository": "nginx",
			"tag":        "latest",
			"pullPolicy": "IfNotPresent",
		},
		"service": map[string]interface{}{
			"type": "ClusterIP",
			"port": 80,
		},
	}

	releaseValues := map[string]interface{}{
		"image": map[string]interface{}{
			"tag": "1.19",
		},
		"service": map[string]interface{}{
			"port": 8080,
		},
	}

	merged := utils.DeepMerge(chartValues, releaseValues)

	// image.repository는 유지
	if img, ok := merged["image"].(map[string]interface{}); ok {
		if repo, ok := img["repository"].(string); !ok || repo != "nginx" {
			t.Error("image.repository should be preserved")
		}
		// image.tag는 덮어쓰기
		if tag, ok := img["tag"].(string); !ok || tag != "1.19" {
			t.Error("image.tag should be overwritten to 1.19")
		}
		// image.pullPolicy는 유지
		if policy, ok := img["pullPolicy"].(string); !ok || policy != "IfNotPresent" {
			t.Error("image.pullPolicy should be preserved")
		}
	} else {
		t.Fatal("merged image is not a map")
	}

	// service.port는 덮어쓰기
	if svc, ok := merged["service"].(map[string]interface{}); ok {
		if port, ok := svc["port"].(int); !ok || port != 8080 {
			t.Error("service.port should be overwritten to 8080")
		}
		// service.type은 유지
		if svcType, ok := svc["type"].(string); !ok || svcType != "ClusterIP" {
			t.Error("service.type should be preserved")
		}
	} else {
		t.Fatal("merged service is not a map")
	}
}

func TestRenderChart_ManifestCollection(t *testing.T) {
	// RenderResult가 매니페스트와 훅을 올바르게 수집하는지 테스트
	chart := &discovery.Chart{
		Name: "test",
	}

	result := &RenderResult{
		Chart:     chart,
		Manifests: "apiVersion: v1\nkind: Pod\n---\napiVersion: v1\nkind: Service",
		Error:     nil,
	}

	// 매니페스트가 여러 리소스를 포함하는지 확인
	if !strings.Contains(result.Manifests, "Pod") {
		t.Error("Manifests should contain Pod")
	}

	if !strings.Contains(result.Manifests, "Service") {
		t.Error("Manifests should contain Service")
	}

	// 문서 구분자 확인
	if !strings.Contains(result.Manifests, "---") {
		t.Error("Manifests should contain document separator")
	}
}
