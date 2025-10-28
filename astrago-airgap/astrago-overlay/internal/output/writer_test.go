package output

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/astrago/helm-image-extractor/internal/config"
	"gopkg.in/yaml.v3"
)

func TestIsValidImage(t *testing.T) {
	tests := []struct {
		name  string
		image string
		want  bool
	}{
		{
			name:  "유효한 이미지 - docker.io",
			image: "docker.io/library/nginx:1.19",
			want:  true,
		},
		{
			name:  "무효한 이미지 - 태그 없음 (오프라인 배포 불가)",
			image: "nginx",
			want:  false,
		},
		{
			name:  "유효한 이미지 - 프라이빗 레지스트리",
			image: "harbor.example.com/library/nginx:latest",
			want:  true,
		},
		{
			name:  "유효한 이미지 - SHA256 다이제스트",
			image: "nginx@sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
			want:  true,
		},
		{
			name:  "빈 문자열",
			image: "",
			want:  false,
		},
		{
			name:  "공백만",
			image: "   ",
			want:  false,
		},
		{
			name:  "슬래시로 시작",
			image: "/sig-storage/csi-provisioner",
			want:  false,
		},
		{
			name:  "콜론으로 끝남",
			image: "nginx:",
			want:  false,
		},
		{
			name:  "슬래시로 끝남",
			image: "docker.io/library/",
			want:  false,
		},
		{
			name:  "Kubernetes 레이블",
			image: "kubernetes.io/some-label",
			want:  false,
		},
		{
			name:  "메타데이터 라인",
			image: "description: some description",
			want:  false,
		},
		{
			name:  "유효한 이미지 - 언더스코어",
			image: "my_registry/my_image:v1.0.0",
			want:  true,
		},
		{
			name:  "유효한 이미지 - 하이픈",
			image: "my-registry.com/my-image:v1.0.0",
			want:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isValidImage(tt.image)
			if got != tt.want {
				t.Errorf("isValidImage(%q) = %v, want %v", tt.image, got, tt.want)
			}
		})
	}
}

func TestNormalizeImage(t *testing.T) {
	tests := []struct {
		name  string
		image string
		want  string
	}{
		{
			name:  "이미 정규화된 이미지",
			image: "docker.io/library/nginx:1.19",
			want:  "docker.io/library/nginx:1.19",
		},
		{
			name:  "docker.io 추가 필요",
			image: "bitnami/postgresql:15",
			want:  "docker.io/bitnami/postgresql:15",
		},
		{
			name:  "registry.k8s.io 추가",
			image: "/sig-storage/csi-provisioner:v5.0.2",
			want:  "registry.k8s.io/sig-storage/csi-provisioner:v5.0.2",
		},
		{
			name:  "공백 제거 및 레지스트리 추가",
			image: "  nginx:latest  ",
			want:  "docker.io/library/nginx:latest",
		},
		{
			name:  "프라이빗 레지스트리는 그대로",
			image: "harbor.example.com/library/nginx:1.19",
			want:  "harbor.example.com/library/nginx:1.19",
		},
		{
			name:  "태그 있는 단일 이름 (library 추가)",
			image: "nginx:latest",
			want:  "docker.io/library/nginx:latest",
		},
		{
			name:  "GCR 이미지",
			image: "gcr.io/project/image:tag",
			want:  "gcr.io/project/image:tag",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := normalizeImage(tt.image)
			if got != tt.want {
				t.Errorf("normalizeImage(%q) = %v, want %v", tt.image, got, tt.want)
			}
		})
	}
}

func TestWriter_WriteText(t *testing.T) {
	tmpDir := t.TempDir()
	outputPath := filepath.Join(tmpDir, "images.txt")

	cfg := &config.Config{
		OutputPath:   outputPath,
		OutputFormat: "text",
	}

	w := New(cfg)

	images := map[string]bool{
		"nginx:1.19":               true,
		"postgres:13":              true,
		"redis:6.2":                true,
		"invalid/":                 true, // 무효한 이미지
		"/sig-storage/provisioner": true, // 정규화 필요
	}
	// 중복 테스트를 위해 같은 키 추가 (이미 존재하므로 덮어씀)
	images["nginx:1.19"] = true

	err := w.writeText(images)
	if err != nil {
		t.Fatalf("writeText() error = %v", err)
	}

	// 파일 읽기
	content, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("Failed to read output file: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(string(content)), "\n")

	// 중복 제거 확인
	uniqueLines := make(map[string]bool)
	for _, line := range lines {
		if line != "" {
			if uniqueLines[line] {
				t.Errorf("Duplicate line found: %s", line)
			}
			uniqueLines[line] = true
		}
	}

	// 정렬 확인
	for i := 1; i < len(lines); i++ {
		if lines[i] != "" && lines[i-1] > lines[i] {
			t.Errorf("Lines not sorted: %s > %s", lines[i-1], lines[i])
		}
	}

	// 유효한 이미지만 포함되어야 함
	for _, line := range lines {
		if line != "" && !isValidImage(line) {
			t.Errorf("Invalid image in output: %s", line)
		}
	}
}

func TestWriter_WriteJSON(t *testing.T) {
	tmpDir := t.TempDir()
	outputPath := filepath.Join(tmpDir, "images.json")

	cfg := &config.Config{
		OutputPath:   outputPath,
		OutputFormat: "json",
	}

	w := New(cfg)

	images := map[string]bool{
		"nginx:1.19":  true,
		"postgres:13": true,
		"redis:6.2":   true,
		"invalid/":    true, // 무효한 이미지
	}
	// 중복 테스트 (맵에서 중복은 자동으로 하나만 유지됨)
	images["nginx:1.19"] = true

	err := w.writeJSON(images)
	if err != nil {
		t.Fatalf("writeJSON() error = %v", err)
	}

	// 파일 읽기 및 파싱
	content, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("Failed to read output file: %v", err)
	}

	var output map[string]interface{}
	err = json.Unmarshal(content, &output)
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	// images 배열 확인
	imageList, ok := output["images"].([]interface{})
	if !ok {
		t.Fatal("images field is not an array")
	}

	if len(imageList) == 0 {
		t.Error("No images in output")
	}

	// count 필드 확인
	count, ok := output["count"].(float64)
	if !ok {
		t.Fatal("count field is not a number")
	}

	if int(count) != len(imageList) {
		t.Errorf("count = %d, but images length = %d", int(count), len(imageList))
	}

	// 중복 확인
	seen := make(map[string]bool)
	for _, img := range imageList {
		imgStr, ok := img.(string)
		if !ok {
			t.Errorf("Image is not a string: %v", img)
			continue
		}
		if seen[imgStr] {
			t.Errorf("Duplicate image found: %s", imgStr)
		}
		seen[imgStr] = true
	}
}

func TestWriter_WriteYAML(t *testing.T) {
	tmpDir := t.TempDir()
	outputPath := filepath.Join(tmpDir, "images.yaml")

	cfg := &config.Config{
		OutputPath:   outputPath,
		OutputFormat: "yaml",
	}

	w := New(cfg)

	images := map[string]bool{
		"nginx:1.19":  true,
		"postgres:13": true,
		"redis:6.2":   true,
	}

	err := w.writeYAML(images)
	if err != nil {
		t.Fatalf("writeYAML() error = %v", err)
	}

	// 파일 읽기 및 파싱
	content, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("Failed to read output file: %v", err)
	}

	var output map[string]interface{}
	err = yaml.Unmarshal(content, &output)
	if err != nil {
		t.Fatalf("Failed to unmarshal YAML: %v", err)
	}

	// images 배열 확인
	imageList, ok := output["images"].([]interface{})
	if !ok {
		t.Fatal("images field is not an array")
	}

	if len(imageList) == 0 {
		t.Error("No images in output")
	}

	// count 필드 확인
	count, ok := output["count"].(int)
	if !ok {
		t.Fatal("count field is not a number")
	}

	if count != len(imageList) {
		t.Errorf("count = %d, but images length = %d", count, len(imageList))
	}
}

func TestWriter_Write(t *testing.T) {
	tests := []struct {
		name   string
		format string
		images map[string]bool
	}{
		{
			name:   "text 형식",
			format: "text",
			images: map[string]bool{
				"nginx:1.19": true,
			},
		},
		{
			name:   "json 형식",
			format: "json",
			images: map[string]bool{
				"nginx:1.19": true,
			},
		},
		{
			name:   "yaml 형식",
			format: "yaml",
			images: map[string]bool{
				"nginx:1.19": true,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			outputPath := filepath.Join(tmpDir, "images."+tt.format)

			cfg := &config.Config{
				OutputPath:   outputPath,
				OutputFormat: tt.format,
			}

			w := New(cfg)

			err := w.Write(tt.images)
			if err != nil {
				t.Fatalf("Write() error = %v", err)
			}

			// 파일 생성 확인
			if _, err := os.Stat(outputPath); os.IsNotExist(err) {
				t.Errorf("Output file not created: %s", outputPath)
			}

			// 파일이 비어있지 않은지 확인
			info, err := os.Stat(outputPath)
			if err != nil {
				t.Fatalf("Failed to stat output file: %v", err)
			}

			if info.Size() == 0 {
				t.Error("Output file is empty")
			}
		})
	}
}

func TestWriter_EmptyImages(t *testing.T) {
	tmpDir := t.TempDir()
	outputPath := filepath.Join(tmpDir, "images.txt")

	cfg := &config.Config{
		OutputPath:   outputPath,
		OutputFormat: "text",
	}

	w := New(cfg)

	// 빈 이미지 맵
	images := map[string]bool{}

	err := w.Write(images)
	if err != nil {
		t.Fatalf("Write() with empty images error = %v", err)
	}

	// 파일이 생성되어야 함
	if _, err := os.Stat(outputPath); os.IsNotExist(err) {
		t.Errorf("Output file not created: %s", outputPath)
	}
}

func TestRemoveDuplicatesWithoutTag(t *testing.T) {
	tests := []struct {
		name    string
		input   map[string]bool
		want    []string
		notWant []string
	}{
		{
			name: "태그 있는 버전이 있으면 태그 없는 버전 제거",
			input: map[string]bool{
				"docker.io/bats/bats":        true,
				"docker.io/bats/bats:v1.4.1": true,
			},
			want: []string{
				"docker.io/bats/bats:v1.4.1",
			},
			notWant: []string{
				"docker.io/bats/bats",
			},
		},
		{
			name: "태그 있는 버전만 있으면 그대로 유지",
			input: map[string]bool{
				"nginx:1.19": true,
				"redis:6.2":  true,
			},
			want: []string{
				"nginx:1.19",
				"redis:6.2",
			},
			notWant: []string{},
		},
		{
			name: "태그 없는 버전만 있으면 그대로 유지",
			input: map[string]bool{
				"nginx": true,
				"redis": true,
			},
			want: []string{
				"nginx",
				"redis",
			},
			notWant: []string{},
		},
		{
			name: "여러 이미지 혼합",
			input: map[string]bool{
				"nginx":      true, // 태그 없음
				"nginx:1.19": true, // 태그 있음 → nginx 제거
				"redis:6.2":  true, // 태그만 있음
				"postgres":   true, // 태그 없음만
			},
			want: []string{
				"nginx:1.19",
				"redis:6.2",
				"postgres",
			},
			notWant: []string{
				"nginx",
			},
		},
		{
			name: "digest 형식도 처리",
			input: map[string]bool{
				"nginx@sha256:abc123": true,
			},
			want: []string{
				"nginx@sha256:abc123",
			},
			notWant: []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := removeDuplicatesWithoutTag(tt.input)

			// want 항목들이 있는지 확인
			for _, wantImg := range tt.want {
				if !result[wantImg] {
					t.Errorf("Expected image %s not found in result", wantImg)
				}
			}

			// notWant 항목들이 없는지 확인
			for _, notWantImg := range tt.notWant {
				if result[notWantImg] {
					t.Errorf("Unexpected image %s found in result", notWantImg)
				}
			}
		})
	}
}

func TestWriter_InvalidImagesFiltered(t *testing.T) {
	tmpDir := t.TempDir()
	outputPath := filepath.Join(tmpDir, "images.txt")

	cfg := &config.Config{
		OutputPath:   outputPath,
		OutputFormat: "text",
	}

	w := New(cfg)

	images := map[string]bool{
		"":                         true, // 빈 문자열
		"   ":                      true, // 공백
		"kubernetes.io/some-label": true, // K8s 레이블
		"/invalid-start":           true, // 슬래시로 시작
		"nginx:":                   true, // 콜론으로 끝남
		"valid-image:v1.0.0":       true, // 유효한 이미지
	}

	err := w.Write(images)
	if err != nil {
		t.Fatalf("Write() error = %v", err)
	}

	// 파일 읽기
	content, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("Failed to read output file: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(string(content)), "\n")

	// 유효한 이미지만 포함되어야 함
	validCount := 0
	for _, line := range lines {
		if line != "" {
			validCount++
			if !isValidImage(line) {
				t.Errorf("Invalid image in output: %s", line)
			}
		}
	}

	// 최소 하나의 유효한 이미지가 있어야 함
	if validCount == 0 {
		t.Error("No valid images in output")
	}

	// 무효한 이미지들은 필터링되어야 함
	contentStr := string(content)
	if strings.Contains(contentStr, "kubernetes.io") {
		t.Error("Kubernetes label found in output")
	}
	if strings.Contains(contentStr, "/invalid-start") {
		t.Error("Invalid image starting with / found in output")
	}
}
