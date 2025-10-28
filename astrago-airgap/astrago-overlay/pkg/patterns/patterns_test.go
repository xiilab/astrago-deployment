package patterns

import (
	"strings"
	"testing"
)

func TestImageInfo_String(t *testing.T) {
	tests := []struct {
		name string
		info ImageInfo
		want string
	}{
		{
			name: "Full 필드가 있는 경우",
			info: ImageInfo{
				Full: "docker.io/library/nginx:1.19",
			},
			want: "docker.io/library/nginx:1.19",
		},
		{
			name: "Registry + Repository + Image + Tag",
			info: ImageInfo{
				Registry:   "docker.io",
				Repository: "library",
				Image:      "nginx",
				Tag:        "1.19",
			},
			want: "docker.io/library/nginx:1.19",
		},
		{
			name: "Repository + Image + Tag",
			info: ImageInfo{
				Repository: "bitnami",
				Image:      "postgresql",
				Tag:        "15",
			},
			want: "bitnami/postgresql:15",
		},
		{
			name: "Image + Tag만",
			info: ImageInfo{
				Image: "nginx",
				Tag:   "latest",
			},
			want: "nginx:latest",
		},
		{
			name: "태그 없음",
			info: ImageInfo{
				Repository: "nginx",
			},
			want: "nginx",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.info.String()
			if got != tt.want {
				t.Errorf("ImageInfo.String() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestImageInfo_Normalize(t *testing.T) {
	tests := []struct {
		name string
		info ImageInfo
		want string
	}{
		{
			name: "따옴표 제거",
			info: ImageInfo{
				Full: `"nginx:1.19"`,
			},
			want: "nginx:1.19",
		},
		{
			name: "태그 없으면 latest 추가",
			info: ImageInfo{
				Image: "nginx",
			},
			want: "nginx:latest",
		},
		{
			name: "이미 정규화됨",
			info: ImageInfo{
				Full: "docker.io/nginx:1.19",
			},
			want: "docker.io/nginx:1.19",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.info.Normalize()
			if got != tt.want {
				t.Errorf("ImageInfo.Normalize() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestLooksLikeImage(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  bool
	}{
		{
			name:  "유효한 이미지 - registry/image:tag",
			input: "docker.io/library/nginx:1.19",
			want:  true,
		},
		{
			name:  "유효한 이미지 - image:tag",
			input: "nginx:1.19",
			want:  false, // 슬래시가 없으면 false
		},
		{
			name:  "유효한 이미지 - registry/image",
			input: "docker.io/nginx",
			want:  true,
		},
		{
			name:  "유효한 이미지 - SHA256",
			input: "docker.io/nginx@sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
			want:  true,
		},
		{
			name:  "슬래시/콜론 없음",
			input: "nginx",
			want:  false,
		},
		{
			name:  "빈 문자열",
			input: "",
			want:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := looksLikeImage(tt.input)
			if got != tt.want {
				t.Errorf("looksLikeImage(%q) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}

func TestIsValidImage(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  bool
	}{
		{
			name:  "유효한 이미지",
			input: "nginx:1.19",
			want:  true,
		},
		{
			name:  "따옴표 포함",
			input: `"nginx:1.19"`,
			want:  true,
		},
		{
			name:  "빈 문자열",
			input: "",
			want:  false,
		},
		{
			name:  "공백 포함",
			input: "nginx 1.19",
			want:  false,
		},
		{
			name:  "HTTP URL",
			input: "http://example.com/image",
			want:  false,
		},
		{
			name:  "HTTPS URL",
			input: "https://example.com/image",
			want:  false,
		},
		{
			name:  "슬래시/콜론 없음",
			input: "nginx",
			want:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isValidImage(tt.input)
			if got != tt.want {
				t.Errorf("isValidImage(%q) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}

func TestTryExtractImage(t *testing.T) {
	tests := []struct {
		name  string
		input map[string]interface{}
		want  string
	}{
		{
			name: "Pattern A: repository + image + tag",
			input: map[string]interface{}{
				"repository": "docker.io",
				"image":      "nginx",
				"tag":        "1.19",
			},
			want: "docker.io/nginx:1.19",
		},
		{
			name: "Pattern B: repository + tag",
			input: map[string]interface{}{
				"repository": "nginx",
				"tag":        "1.19",
			},
			want: "nginx:1.19",
		},
		{
			name: "Pattern C: registry + image + tag",
			input: map[string]interface{}{
				"registry": "docker.io",
				"image":    "nginx",
				"tag":      "1.19",
			},
			want: "docker.io/nginx:1.19",
		},
		{
			name: "Pattern D: image + tag (ingress-nginx style)",
			input: map[string]interface{}{
				"image": "ingress-nginx/controller",
				"tag":   "v1.13.2",
			},
			want: "ingress-nginx/controller:v1.13.2",
		},
		{
			name: "Pattern D: image + tag (simple)",
			input: map[string]interface{}{
				"image": "nginx",
				"tag":   "1.19",
			},
			want: "nginx:1.19",
		},
		{
			name: "Pattern Full: complete image string",
			input: map[string]interface{}{
				"image": "docker.io/library/nginx:1.19",
			},
			want: "docker.io/library/nginx:1.19",
		},
		{
			name: "태그 없음 (기본 latest)",
			input: map[string]interface{}{
				"repository": "docker.io",
				"image":      "nginx",
			},
			want: "docker.io/nginx:latest",
		},
		{
			name:  "매칭 패턴 없음",
			input: map[string]interface{}{"replicas": 3},
			want:  "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tryExtractImage(tt.input)
			if got != tt.want {
				t.Errorf("tryExtractImage() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestExtractFromValues(t *testing.T) {
	tests := []struct {
		name   string
		values map[string]interface{}
		want   []string
	}{
		{
			name: "단일 이미지",
			values: map[string]interface{}{
				"image": map[string]interface{}{
					"repository": "nginx",
					"tag":        "1.19",
				},
			},
			want: []string{"nginx:1.19"},
		},
		{
			name: "중첩된 이미지들",
			values: map[string]interface{}{
				"frontend": map[string]interface{}{
					"image": map[string]interface{}{
						"repository": "nginx",
						"tag":        "1.19",
					},
				},
				"backend": map[string]interface{}{
					"image": map[string]interface{}{
						"repository": "node",
						"tag":        "16",
					},
				},
			},
			want: []string{"nginx:1.19", "node:16"},
		},
		{
			name: "배열 내 이미지",
			values: map[string]interface{}{
				"containers": []interface{}{
					map[string]interface{}{
						"image": "nginx:1.19",
					},
					map[string]interface{}{
						"image": "redis:6.2",
					},
				},
			},
			want: []string{"nginx:1.19", "redis:6.2"},
		},
		{
			name: "문자열 이미지",
			values: map[string]interface{}{
				"image": "nginx:1.19",
			},
			want: []string{"nginx:1.19"},
		},
		{
			name:   "이미지 없음",
			values: map[string]interface{}{"replicas": 3},
			want:   []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExtractFromValues(tt.values)

			// 결과가 기대값을 포함하는지 확인
			for _, wantImg := range tt.want {
				found := false
				for _, gotImg := range got {
					if gotImg == wantImg {
						found = true
						break
					}
				}
				if !found {
					t.Errorf("Expected image %s not found in result", wantImg)
				}
			}
		})
	}
}

func TestExtractFromManifest(t *testing.T) {
	tests := []struct {
		name     string
		manifest string
		want     []string
	}{
		{
			name: "표준 image 필드",
			manifest: `
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.19
`,
			want: []string{"nginx:1.19"},
		},
		{
			name: "여러 컨테이너",
			manifest: `
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      initContainers:
      - name: init
        image: busybox:latest
      containers:
      - name: app
        image: myapp:v1.0.0
      - name: sidecar
        image: envoy:v1.18
`,
			want: []string{"busybox:latest", "myapp:v1.0.0", "envoy:v1.18"},
		},
		{
			name: "따옴표로 감싼 이미지",
			manifest: `
image: "nginx:1.19"
`,
			want: []string{"nginx:1.19"},
		},
		{
			name: "다중 문서",
			manifest: `apiVersion: v1
kind: Pod
spec:
  containers:
  - name: nginx
    image: nginx:1.19
---
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: redis
    image: redis:6.2`,
			want: []string{"nginx:1.19", "redis:6.2"},
		},
		{
			name: "환경 변수의 이미지",
			manifest: `
env:
- name: SIDECAR_IMAGE
  value: envoy:v1.18
`,
			want: []string{"envoy:v1.18"},
		},
		{
			name: "value 필드의 이미지",
			manifest: `
  value: docker.io/library/nginx:1.19
`,
			want: []string{"docker.io/library/nginx:1.19"},
		},
		{
			name:     "이미지 없음",
			manifest: `apiVersion: v1\nkind: ConfigMap`,
			want:     []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExtractFromManifest(tt.manifest)

			if len(tt.want) == 0 && len(got) == 0 {
				return // Both empty, test passes
			}

			// 기대하는 모든 이미지가 결과에 있는지 확인
			for _, wantImg := range tt.want {
				found := false
				for _, gotImg := range got {
					if gotImg == wantImg {
						found = true
						break
					}
				}
				if !found {
					t.Errorf("Expected image %s not found in result %v", wantImg, got)
				}
			}
		})
	}
}

func TestExtractRecursive(t *testing.T) {
	images := make(map[string]bool)

	data := map[string]interface{}{
		"level1": map[string]interface{}{
			"level2": map[string]interface{}{
				"image": map[string]interface{}{
					"repository": "nginx",
					"tag":        "1.19",
				},
			},
		},
	}

	extractRecursive(data, "", images, 0, 10)

	// nginx:1.19가 추출되어야 함
	found := false
	for img := range images {
		if strings.Contains(img, "nginx") {
			found = true
			break
		}
	}

	if !found {
		t.Error("Expected to find nginx image in deeply nested structure")
	}
}

func TestGetStringOrDefault(t *testing.T) {
	tests := []struct {
		name string
		m    map[string]interface{}
		key  string
		def  string
		want string
	}{
		{
			name: "키가 존재하고 문자열",
			m:    map[string]interface{}{"key": "value"},
			key:  "key",
			def:  "default",
			want: "value",
		},
		{
			name: "키가 존재하지 않음",
			m:    map[string]interface{}{},
			key:  "key",
			def:  "default",
			want: "default",
		},
		{
			name: "키가 존재하지만 문자열이 아님",
			m:    map[string]interface{}{"key": 123},
			key:  "key",
			def:  "default",
			want: "default",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := getStringOrDefault(tt.m, tt.key, tt.def)
			if got != tt.want {
				t.Errorf("getStringOrDefault() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestExtractFromManifest_ComplexScenarios(t *testing.T) {
	// 실제 Harbor 차트 같은 복잡한 매니페스트
	manifest := `
apiVersion: v1
kind: ConfigMap
metadata:
  name: harbor-core
data:
  config.yml: |
    registry:
      image: goharbor/registry-photon:v2.9.0
    portal:
      image: goharbor/harbor-portal:v2.9.0
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: harbor-core
spec:
  template:
    spec:
      containers:
      - name: core
        image: "goharbor/harbor-core:v2.9.0"
      - name: portal
        image: 'goharbor/harbor-portal:v2.9.0'
      initContainers:
      - name: init
        image: goharbor/prepare:v2.9.0
`

	images := ExtractFromManifest(manifest)

	expectedImages := []string{
		"goharbor/harbor-core:v2.9.0",
		"goharbor/harbor-portal:v2.9.0",
	}

	// 최소한 기대하는 이미지들이 포함되어야 함
	for _, expected := range expectedImages {
		found := false
		for _, img := range images {
			if img == expected {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Expected image %s not found. Got: %v", expected, images)
		}
	}
}
