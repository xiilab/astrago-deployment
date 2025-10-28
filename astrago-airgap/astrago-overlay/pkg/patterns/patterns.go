package patterns

import (
	"fmt"
	"regexp"
	"strings"
)

// ImagePattern represents different patterns for image extraction
type ImagePattern int

const (
	// PatternA: repository + image + tag
	PatternA ImagePattern = iota
	// PatternB: repository + tag
	PatternB
	// PatternC: registry + image + tag
	PatternC
	// PatternFull: complete image string
	PatternFull
)

// ImageInfo holds extracted image information
type ImageInfo struct {
	Registry   string
	Repository string
	Image      string
	Tag        string
	Full       string
}

// String returns the full image string
func (i *ImageInfo) String() string {
	if i.Full != "" {
		return i.Full
	}

	parts := []string{}
	if i.Registry != "" {
		parts = append(parts, i.Registry)
	}
	if i.Repository != "" {
		parts = append(parts, i.Repository)
	}
	if i.Image != "" {
		parts = append(parts, i.Image)
	}

	imagePath := strings.Join(parts, "/")
	if i.Tag != "" {
		return fmt.Sprintf("%s:%s", imagePath, i.Tag)
	}
	return imagePath
}

// Normalize normalizes the image string
func (i *ImageInfo) Normalize() string {
	img := i.String()

	// Remove quotes
	img = strings.Trim(img, `"'`)

	// Add default tag if missing
	if !strings.Contains(img, ":") {
		img += ":latest"
	}

	return img
}

// ExtractFromValues extracts images from values map
func ExtractFromValues(values map[string]interface{}) []string {
	return ExtractFromValuesWithDepth(values, 10) // Default maxDepth: 10
}

// ExtractFromValuesWithDepth extracts images from values map with depth limit
func ExtractFromValuesWithDepth(values map[string]interface{}, maxDepth int) []string {
	images := make(map[string]bool)
	extractRecursive(values, "", images, 0, maxDepth)

	result := make([]string, 0, len(images))
	for img := range images {
		if isValidImage(img) {
			result = append(result, img)
		}
	}
	return result
}

// extractRecursive recursively extracts images from nested maps with depth limit
func extractRecursive(data interface{}, path string, images map[string]bool, depth int, maxDepth int) {
	// Stop if max depth reached
	if depth >= maxDepth {
		return
	}

	switch v := data.(type) {
	case map[string]interface{}:
		// Check for image patterns
		if img := tryExtractImage(v); img != "" {
			images[img] = true
		}

		// Recurse into nested maps
		for key, val := range v {
			newPath := key
			if path != "" {
				newPath = path + "." + key
			}
			extractRecursive(val, newPath, images, depth+1, maxDepth)
		}

	case []interface{}:
		// Recurse into arrays
		for _, item := range v {
			extractRecursive(item, path, images, depth+1, maxDepth)
		}

	case string:
		// Check if string looks like an image
		if looksLikeImage(v) {
			images[v] = true
		}
	}
}

// tryExtractImage tries to extract image from a map using known patterns
func tryExtractImage(m map[string]interface{}) string {
	// Pattern A: repository + image + tag
	if repo, ok := m["repository"].(string); ok {
		if image, ok := m["image"].(string); ok {
			tag := getStringOrDefault(m, "tag", "latest")
			return fmt.Sprintf("%s/%s:%s", repo, image, tag)
		}
	}

	// Pattern B: repository + tag
	if repo, ok := m["repository"].(string); ok {
		if tag, ok := m["tag"].(string); ok {
			return fmt.Sprintf("%s:%s", repo, tag)
		}
	}

	// Pattern C: registry + image + tag
	if registry, ok := m["registry"].(string); ok {
		if image, ok := m["image"].(string); ok {
			tag := getStringOrDefault(m, "tag", "latest")
			return fmt.Sprintf("%s/%s:%s", registry, image, tag)
		}
	}

	// Pattern D: image + tag (common pattern where "image" is actually the repository)
	// Example: image: "nginx", tag: "1.19" OR image: "ingress-nginx/controller", tag: "v1.13.2"
	if image, ok := m["image"].(string); ok {
		if tag, ok := m["tag"].(string); ok {
			// If image contains ":" it's already complete, just return it
			if strings.Contains(image, ":") {
				return image
			}
			// Otherwise combine image + tag
			return fmt.Sprintf("%s:%s", image, tag)
		}
	}

	// Pattern Full: complete image string (fallback)
	if image, ok := m["image"].(string); ok {
		if strings.Contains(image, ":") || strings.Contains(image, "@") {
			return image
		}
	}

	return ""
}

// getStringOrDefault gets string value or returns default
func getStringOrDefault(m map[string]interface{}, key, defaultVal string) string {
	if val, ok := m[key].(string); ok {
		return val
	}
	return defaultVal
}

// looksLikeImage checks if a string looks like a container image
func looksLikeImage(s string) bool {
	// Must contain at least one slash or colon
	if !strings.Contains(s, "/") && !strings.Contains(s, ":") {
		return false
	}

	// Common image patterns
	patterns := []string{
		`^[a-z0-9\-\.]+/[a-z0-9\-\./_]+:[a-z0-9\-\.]+$`,       // registry/image:tag
		`^[a-z0-9\-\.]+/[a-z0-9\-\./_]+@sha256:[a-f0-9]{64}$`, // registry/image@sha256
		`^[a-z0-9\-\.]+/[a-z0-9\-\./_]+$`,                     // registry/image
	}

	for _, pattern := range patterns {
		if matched, _ := regexp.MatchString(pattern, strings.ToLower(s)); matched {
			return true
		}
	}

	return false
}

// isValidImage validates if a string is a valid container image
func isValidImage(s string) bool {
	// Remove quotes
	s = strings.Trim(s, `"'`)

	// Must not be empty
	if s == "" {
		return false
	}

	// Must not contain spaces
	if strings.Contains(s, " ") {
		return false
	}

	// Must not be a URL
	if strings.HasPrefix(s, "http://") || strings.HasPrefix(s, "https://") {
		return false
	}

	// Must contain at least one slash or colon
	if !strings.Contains(s, "/") && !strings.Contains(s, ":") {
		return false
	}

	return true
}

// ExtractFromManifest extracts images from Kubernetes manifest YAML (Gap #5 개선)
func ExtractFromManifest(manifest string) []string {
	images := make(map[string]bool)

	// Split by document separator
	docs := strings.Split(manifest, "---")

	for _, doc := range docs {
		// Skip non-Kubernetes resource documents (e.g., Chart.yaml metadata)
		// Only process documents with 'kind:' field (actual K8s resources)
		// Chart.yaml has 'apiVersion: v2' but no 'kind:' field
		if !strings.Contains(doc, "kind:") {
			continue
		}

		// Gap #5: 확장된 regex 패턴들
		patterns := []struct {
			name    string
			regex   *regexp.Regexp
			extract func([]string) string
		}{
			{
				// Pattern 1: 표준 image: 필드
				name:  "standard_image",
				regex: regexp.MustCompile(`(?m)^\s*image:\s*["']?([^\s"']+)["']?`),
				extract: func(match []string) string {
					if len(match) > 1 {
						return match[1]
					}
					return ""
				},
			},
			{
				// Pattern 1-2: 비표준 *Image 필드 (themeImage, configReloaderImage 등)
				name:  "custom_image_fields",
				regex: regexp.MustCompile(`(?m)^\s*[a-zA-Z]+[Ii]mage:\s*["']?([^\s"']+)["']?`),
				extract: func(match []string) string {
					if len(match) > 1 {
						candidate := match[1]
						// 이미지 형태인지 검증 (최소한 / 또는 : 포함)
						if strings.Contains(candidate, "/") || strings.Contains(candidate, ":") {
							return candidate
						}
					}
					return ""
				},
			},
			{
				// Pattern 1-3: repository 필드 (단독으로 나타나는 경우)
				name:  "repository_field",
				regex: regexp.MustCompile(`(?m)^\s*repository:\s*["']?([a-z0-9\-\.]+/[^\s"':]+)["']?`),
				extract: func(match []string) string {
					if len(match) > 1 {
						return match[1]
					}
					return ""
				},
			},
			{
				// Pattern 2: value 또는 defaultValue 필드의 이미지
				name:  "value_field",
				regex: regexp.MustCompile(`(?m)^\s*(?:value|defaultValue):\s*["']?([a-z0-9\-\.]+/[^\s"']+)["']?`),
				extract: func(match []string) string {
					if len(match) > 1 {
						return match[1]
					}
					return ""
				},
			},
			{
				// Pattern 3: - image 형태 (리스트 아이템)
				name:  "list_image",
				regex: regexp.MustCompile(`(?m)^\s*-\s+["']?([a-z0-9\-\.]+/[^\s"':]+:[^\s"']+)["']?`),
				extract: func(match []string) string {
					if len(match) > 1 {
						candidate := match[1]
						// 이미지 형태인지 검증
						if strings.Contains(candidate, "/") && !strings.HasPrefix(candidate, "http") {
							return candidate
						}
					}
					return ""
				},
			},
			{
				// Pattern 4: 환경 변수의 이미지 참조
				name:  "env_var_image",
				regex: regexp.MustCompile(`(?m)^\s*-\s+name:\s+[A-Z_]+IMAGE[A-Z_]*\s+value:\s*["']?([^\s"']+)["']?`),
				extract: func(match []string) string {
					if len(match) > 1 {
						return match[1]
					}
					return ""
				},
			},
			{
				// Pattern 4-1: 컨테이너 args 내 reloader 이미지 플래그
				// 예: --prometheus-config-reloader=quay.io/prometheus-operator/prometheus-config-reloader:v0.75.2
				name:  "arg_reloader_image",
				regex: regexp.MustCompile(`(?m)--prometheus-config-reloader=([^\s"']+)`),
				extract: func(match []string) string {
					if len(match) > 1 {
						return match[1]
					}
					return ""
				},
			},
			{
				// Pattern 5: ConfigMap/Secret 데이터 내 이미지
				name:  "configmap_image",
				regex: regexp.MustCompile(`(?m)^\s*[a-z0-9\-\.]+:\s*\|\s*\n\s+([a-z0-9\-\.]+/[^\s]+:[^\s]+)`),
				extract: func(match []string) string {
					if len(match) > 1 {
						return match[1]
					}
					return ""
				},
			},
		}

		// 모든 패턴으로 이미지 추출
		for _, p := range patterns {
			// Chart.yaml 등 메타데이터에 있는 안내용 repository 문자열을 피하기 위해
			// 표준 image: 패턴 외에는 tag 또는 digest가 반드시 포함된 경우만 허용한다
			matches := p.regex.FindAllStringSubmatch(doc, -1)
			for _, match := range matches {
				img := p.extract(match)
				if img == "" {
					continue
				}
				img = strings.Trim(img, `"'`)

				// 표준 image: 필드가 아닌 경우는 안전장치로 tag/digest 필수
				if p.name != "standard_image" {
					if !strings.Contains(img, ":") && !strings.Contains(img, "@") {
						// 태그/다이제스트 없는 repository 문자열은 스킵
						continue
					}
				}

				if isValidImage(img) {
					images[img] = true
				}
			}
		}
	}

	result := make([]string, 0, len(images))
	for img := range images {
		result = append(result, img)
	}
	return result
}
