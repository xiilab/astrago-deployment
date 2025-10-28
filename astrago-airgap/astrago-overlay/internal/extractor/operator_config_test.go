package extractor

import (
	"testing"
)

func TestExtractImagesFromSpec_ThreeFieldStructure(t *testing.T) {
	// GPU Operator 3필드 구조 테스트: repository + image + version
	spec := &OperatorSpec{
		Enabled: true,
		Images: []OperatorImage{
			{
				Path:      "validator.repository",
				ImagePath: "validator.image",
				TagPath:   "validator.version",
			},
			{
				Path:      "devicePlugin.repository",
				ImagePath: "devicePlugin.image",
				TagPath:   "devicePlugin.version",
			},
		},
	}

	values := map[string]interface{}{
		"validator": map[string]interface{}{
			"repository": "nvcr.io/nvidia/cloud-native",
			"image":      "gpu-operator-validator",
			"version":    "v25.3.4",
		},
		"devicePlugin": map[string]interface{}{
			"repository": "nvcr.io/nvidia",
			"image":      "k8s-device-plugin",
			"version":    "v0.17.4",
		},
	}

	images := ExtractImagesFromSpec(spec, values)

	expectedImages := []string{
		"nvcr.io/nvidia/cloud-native/gpu-operator-validator:v25.3.4",
		"nvcr.io/nvidia/k8s-device-plugin:v0.17.4",
	}

	if len(images) != len(expectedImages) {
		t.Fatalf("Expected %d images, got %d", len(expectedImages), len(images))
	}

	for i, expected := range expectedImages {
		if images[i] != expected {
			t.Errorf("Image %d: expected %s, got %s", i, expected, images[i])
		}
	}
}

func TestExtractImagesFromSpec_TwoFieldStructure(t *testing.T) {
	// 기존 2필드 구조 테스트 (하위 호환성): repository + version
	spec := &OperatorSpec{
		Enabled: true,
		Images: []OperatorImage{
			{
				Path:    "operator.repository",
				TagPath: "operator.version",
			},
		},
	}

	values := map[string]interface{}{
		"operator": map[string]interface{}{
			"repository": "nvcr.io/nvidia/gpu-operator",
			"version":    "v25.3.4",
		},
	}

	images := ExtractImagesFromSpec(spec, values)

	expected := "nvcr.io/nvidia/gpu-operator:v25.3.4"
	if len(images) != 1 {
		t.Fatalf("Expected 1 image, got %d", len(images))
	}

	if images[0] != expected {
		t.Errorf("Expected %s, got %s", expected, images[0])
	}
}

func TestExtractImagesFromSpec_MixedStructure(t *testing.T) {
	// 2필드와 3필드 혼합 테스트
	spec := &OperatorSpec{
		Enabled: true,
		Images: []OperatorImage{
			{
				Path:    "operator.repository",
				TagPath: "operator.version",
			},
			{
				Path:      "validator.repository",
				ImagePath: "validator.image",
				TagPath:   "validator.version",
			},
		},
	}

	values := map[string]interface{}{
		"operator": map[string]interface{}{
			"repository": "nvcr.io/nvidia/gpu-operator",
			"version":    "v25.3.4",
		},
		"validator": map[string]interface{}{
			"repository": "nvcr.io/nvidia/cloud-native",
			"image":      "gpu-operator-validator",
			"version":    "v25.3.4",
		},
	}

	images := ExtractImagesFromSpec(spec, values)

	expectedImages := []string{
		"nvcr.io/nvidia/gpu-operator:v25.3.4",
		"nvcr.io/nvidia/cloud-native/gpu-operator-validator:v25.3.4",
	}

	if len(images) != len(expectedImages) {
		t.Fatalf("Expected %d images, got %d", len(expectedImages), len(images))
	}

	for i, expected := range expectedImages {
		if images[i] != expected {
			t.Errorf("Image %d: expected %s, got %s", i, expected, images[i])
		}
	}
}

func TestExtractImagesFromSpec_MissingImageName(t *testing.T) {
	// ImagePath가 설정되었지만 실제 값이 없는 경우 (fallback)
	spec := &OperatorSpec{
		Enabled: true,
		Images: []OperatorImage{
			{
				Path:      "validator.repository",
				ImagePath: "validator.image",
				TagPath:   "validator.version",
			},
		},
	}

	values := map[string]interface{}{
		"validator": map[string]interface{}{
			"repository": "nvcr.io/nvidia/cloud-native",
			// image 필드 없음
			"version": "v25.3.4",
		},
	}

	images := ExtractImagesFromSpec(spec, values)

	// image가 없으면 기존 2필드 방식으로 fallback
	expected := "nvcr.io/nvidia/cloud-native:v25.3.4"
	if len(images) != 1 {
		t.Fatalf("Expected 1 image, got %d", len(images))
	}

	if images[0] != expected {
		t.Errorf("Expected %s, got %s", expected, images[0])
	}
}

func TestExtractImagesFromSpec_DefaultTag(t *testing.T) {
	// tag가 없을 때 latest 사용
	spec := &OperatorSpec{
		Enabled: true,
		Images: []OperatorImage{
			{
				Path:      "validator.repository",
				ImagePath: "validator.image",
				TagPath:   "validator.version",
			},
		},
	}

	values := map[string]interface{}{
		"validator": map[string]interface{}{
			"repository": "nvcr.io/nvidia/cloud-native",
			"image":      "gpu-operator-validator",
			// version 없음
		},
	}

	images := ExtractImagesFromSpec(spec, values)

	expected := "nvcr.io/nvidia/cloud-native/gpu-operator-validator:latest"
	if len(images) != 1 {
		t.Fatalf("Expected 1 image, got %d", len(images))
	}

	if images[0] != expected {
		t.Errorf("Expected %s, got %s", expected, images[0])
	}
}

func TestExtractImagesFromSpec_MissingRepository(t *testing.T) {
	// repository가 없으면 skip
	spec := &OperatorSpec{
		Enabled: true,
		Images: []OperatorImage{
			{
				Path:      "validator.repository",
				ImagePath: "validator.image",
				TagPath:   "validator.version",
			},
		},
	}

	values := map[string]interface{}{
		"validator": map[string]interface{}{
			// repository 없음
			"image":   "gpu-operator-validator",
			"version": "v25.3.4",
		},
	}

	images := ExtractImagesFromSpec(spec, values)

	if len(images) != 0 {
		t.Errorf("Expected 0 images, got %d", len(images))
	}
}

