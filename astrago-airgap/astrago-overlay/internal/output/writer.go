package output

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"
)

// Writer handles output writing
type Writer struct {
	config *config.Config
}

// New creates a new Writer
func New(cfg *config.Config) *Writer {
	return &Writer{config: cfg}
}

// 이미지 검증 정규식 패턴
var (
	// 유효한 컨테이너 이미지 형식: [registry/]repository[:tag|@digest]
	validImagePattern = regexp.MustCompile(`^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?(/[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?)*(:[\w][\w.-]{0,127})?(@sha256:[a-fA-F0-9]{64})?$`)

	// 제외할 패턴들
	excludePatterns = []*regexp.Regexp{
		regexp.MustCompile(`^/`),                               // 슬래시로 시작 (registry 누락)
		regexp.MustCompile(`[:/]$`),                            // 콜론이나 슬래시로 끝남 (불완전)
		regexp.MustCompile(`^(description|metadata|labels?):`), // 메타데이터 라인
		regexp.MustCompile(`^(kubernetes\.io|k8s\.io|nvidia\.com|node\.kubernetes\.io|node-role\.kubernetes\.io)/`), // Kubernetes 레이블
		regexp.MustCompile(`^keda\.sh/`),                         // KEDA CRD
		regexp.MustCompile(`^[a-z0-9-]+\.[a-z]+/v\d+[a-z]+\d*$`), // CRD API 버전 (예: keda.sh/v1alpha1)
	}
)

// isValidImage checks if the string is a valid container image reference
func isValidImage(image string) bool {
	// 빈 문자열 제외
	if strings.TrimSpace(image) == "" {
		return false
	}

	// 제외 패턴 체크
	for _, pattern := range excludePatterns {
		if pattern.MatchString(image) {
			log.Debug().
				Str("image", image).
				Str("reason", "matches exclude pattern").
				Msg("이미지 제외")
			return false
		}
	}

	// 유효한 이미지 형식인지 체크
	if !validImagePattern.MatchString(image) {
		log.Debug().
			Str("image", image).
			Str("reason", "invalid format").
			Msg("이미지 제외")
		return false
	}

	// 태그나 digest가 없는 이미지는 오프라인 배포에서 사용 불가
	// (latest를 pull하게 되어 정확한 버전 관리 불가)
	if !strings.Contains(image, ":") && !strings.Contains(image, "@") {
		log.Debug().
			Str("image", image).
			Str("reason", "no tag or digest").
			Msg("태그 없는 이미지 제외 (오프라인 배포 불가)")
		return false
	}

	// NVCR 잘못된 루트/조직 레벨 참조 제거
	// 예: nvcr.io/nvidia:latest, nvcr.io/nvidia
	if strings.HasPrefix(image, "nvcr.io/nvidia") && !strings.Contains(image, "/") {
		return false
	}
	if strings.HasPrefix(image, "nvcr.io/nvidia:") {
		return false
	}

	return true
}

// removeDuplicatesWithoutTag removes images without tags if a tagged version exists
// Example: if both "nginx" and "nginx:1.19" exist, remove "nginx"
func removeDuplicatesWithoutTag(images map[string]bool) map[string]bool {
	result := make(map[string]bool)

	// 태그가 있는 이미지들의 repository 목록 생성
	taggedRepos := make(map[string]bool)
	for img := range images {
		if strings.Contains(img, ":") && !strings.Contains(img, "@") {
			// repository 부분만 추출 (마지막 :앞까지)
			lastColon := strings.LastIndex(img, ":")
			repo := img[:lastColon]
			taggedRepos[repo] = true
		}
	}

	// 필터링: 태그 없는 이미지는 태그 있는 버전이 없을 때만 포함
	for img := range images {
		// 태그가 없는 경우 (@도 없고 :도 없음)
		if !strings.Contains(img, ":") && !strings.Contains(img, "@") {
			// 태그 있는 버전이 존재하면 스킵
			if taggedRepos[img] {
				log.Debug().
					Str("image", img).
					Msg("태그 없는 버전 제외 (태그 있는 버전이 존재)")
				continue
			}
		}
		result[img] = true
	}

	return result
}

// removeLegacyReplacements removes bitnami images that have been replaced by bitnamilegacy
// Example: bitnami/postgresql → bitnamilegacy/postgresql
func removeLegacyReplacements(images map[string]bool) map[string]bool {
	result := make(map[string]bool)

	// bitnamilegacy로 대체된 이미지들의 원본(bitnami) 버전 찾기
	legacyImages := make(map[string]string) // bitnami → bitnamilegacy 매핑

	for img := range images {
		if strings.Contains(img, "bitnamilegacy/") {
			// bitnamilegacy/postgresql:16.1.0 → bitnami/postgresql:16.1.0
			bitnamiVersion := strings.Replace(img, "bitnamilegacy/", "bitnami/", 1)
			legacyImages[bitnamiVersion] = img
		}
	}

	// 필터링: bitnami 버전이 bitnamilegacy로 대체되었으면 제외
	for img := range images {
		if legacyReplacement, exists := legacyImages[img]; exists {
			// bitnami 버전이 bitnamilegacy로 대체됨 → 제외
			log.Debug().
				Str("bitnami_image", img).
				Str("replaced_by", legacyReplacement).
				Msg("Bitnami 이미지 제외 (bitnamilegacy로 대체됨)")
			continue
		}
		result[img] = true
	}

	return result
}

// removeOverriddenImages removes vendor images when a custom replacement exists
// 현재 규칙:
// - xiilab/astrago-keycloak-theme 가 있으면 bitnami/keycloak 제거
func removeOverriddenImages(images map[string]bool) map[string]bool {
	result := make(map[string]bool)

	hasCustomKeycloak := false
	for img := range images {
		if strings.Contains(img, "xiilab/astrago-keycloak-theme:") {
			hasCustomKeycloak = true
			break
		}
	}

	for img := range images {
		// Keycloak: custom 이미지가 있으면 bitnami 기본 이미지는 제외
		if hasCustomKeycloak && (strings.Contains(img, "/bitnami/keycloak:") || strings.HasPrefix(img, "bitnami/keycloak:")) {
			log.Debug().
				Str("bitnami_image", img).
				Msg("Keycloak 기본 이미지 제외 (custom 이미지 존재)")
			continue
		}

		result[img] = true
	}

	return result
}

// removeWindowsExporter removes windows-exporter images which are Windows-only
// and should not be included when windowsMonitoring.enabled=false
func removeWindowsExporter(images map[string]bool) map[string]bool {
    result := make(map[string]bool)
    for img := range images {
        // 대표 레지스트리 경로들 필터링
        if strings.Contains(img, "/prometheus-community/windows-exporter:") {
            log.Debug().
                Str("image", img).
                Msg("Windows Exporter 이미지 제외 (windowsMonitoring.disabled)")
            continue
        }
        result[img] = true
    }
    return result
}

// normalizeImage normalizes the image reference
func normalizeImage(image string) string {
	// 트림
	image = strings.TrimSpace(image)

	// registry.k8s.io 프리픽스 추가 (K8s 공식 이미지)
	// 예: /sig-storage/csi-provisioner:v5.0.2 -> registry.k8s.io/sig-storage/csi-provisioner:v5.0.2
	if strings.HasPrefix(image, "/sig-storage/") ||
		strings.HasPrefix(image, "/sig-release/") ||
		strings.HasPrefix(image, "/metrics-server/") {
		image = "registry.k8s.io" + image
	}

	// K8s 공식 이미지 패턴 (defaultbackend 등)
	if strings.HasPrefix(image, "defaultbackend") ||
		strings.HasPrefix(image, "pause") ||
		strings.HasPrefix(image, "etcd") ||
		strings.HasPrefix(image, "coredns") {
		// 슬래시가 없으면 registry.k8s.io 추가
		if !strings.Contains(image, "/") {
			image = "registry.k8s.io/" + image
		}
	}

	// docker.io 프리픽스 추가 (registry가 없는 경우)
	if strings.Contains(image, "/") {
		firstPart := strings.Split(image, "/")[0]
		// 첫 번째 부분이 도메인이 아니면 docker.io 추가
		if !strings.Contains(firstPart, ".") && !strings.Contains(firstPart, ":") {
			image = "docker.io/" + image
		}
	} else {
		// 슬래시가 없는 이미지 (단일 이름)
		// K8s 이미지가 아니면 docker.io library 이미지로 간주
		if !strings.HasPrefix(image, "registry.k8s.io/") {
			image = "docker.io/library/" + image
		}
	}

	// 태그나 digest가 없는 이미지는 이미 isValidImage에서 필터링됨
	// 여기까지 온 이미지는 모두 유효함

	return image
}

// Write writes images to output file
func (w *Writer) Write(images map[string]bool) error {
	switch w.config.OutputFormat {
	case "json":
		return w.writeJSON(images)
	case "yaml":
		return w.writeYAML(images)
	default:
		return w.writeText(images)
	}
}

// writeText writes images as plain text (one per line)
func (w *Writer) writeText(images map[string]bool) error {
	// 검증, 정규화 및 중복 제거
	imageSet := make(map[string]bool) // 중복 제거를 위한 set
	filteredCount := 0

	for img := range images {
		// 유효성 검증
		if !isValidImage(img) {
			filteredCount++
			continue
		}

		// 정규화
		normalized := normalizeImage(img)
		imageSet[normalized] = true // set에 추가 (자동 중복 제거)
	}

	// 태그 없는 중복 제거: repository:tag와 repository가 둘 다 있으면 repository만 제거
	imageSet = removeDuplicatesWithoutTag(imageSet)

	// bitnami → bitnamilegacy 대체 처리
	imageSet = removeLegacyReplacements(imageSet)

	// 커스텀 이미지가 존재할 경우 벤더 기본 이미지 제거
	imageSet = removeOverriddenImages(imageSet)

    // Windows Exporter 제거 (비활성화된 경우 텍스트/주석에서 감지된 참조 방지)
    imageSet = removeWindowsExporter(imageSet)

	// set을 slice로 변환
	imageList := make([]string, 0, len(imageSet))
	for img := range imageSet {
		imageList = append(imageList, img)
	}

	// 로그 출력
	if filteredCount > 0 {
		log.Info().
			Int("filtered", filteredCount).
			Msg("무효한 이미지 항목 제외됨")
	}

	sort.Strings(imageList)

	// Write to file
	content := strings.Join(imageList, "\n")
	if content != "" {
		content += "\n"
	}

	if err := os.WriteFile(w.config.OutputPath, []byte(content), 0644); err != nil {
		return fmt.Errorf("파일 쓰기 실패: %w", err)
	}

	log.Info().
		Str("path", w.config.OutputPath).
		Int("count", len(imageList)).
		Msg("이미지 목록 저장 완료")

	return nil
}

// writeJSON writes images as JSON
func (w *Writer) writeJSON(images map[string]bool) error {
	// 검증, 정규화 및 중복 제거
	imageSet := make(map[string]bool) // 중복 제거를 위한 set
	filteredCount := 0

	for img := range images {
		// 유효성 검증
		if !isValidImage(img) {
			filteredCount++
			continue
		}

		// 정규화
		normalized := normalizeImage(img)
		imageSet[normalized] = true // set에 추가 (자동 중복 제거)
	}

	// 태그 없는 중복 제거
	imageSet = removeDuplicatesWithoutTag(imageSet)

	// bitnami → bitnamilegacy 대체 처리
	imageSet = removeLegacyReplacements(imageSet)

	// 커스텀 이미지가 존재할 경우 벤더 기본 이미지 제거
	imageSet = removeOverriddenImages(imageSet)

    // Windows Exporter 제거
    imageSet = removeWindowsExporter(imageSet)

	// set을 slice로 변환
	imageList := make([]string, 0, len(imageSet))
	for img := range imageSet {
		imageList = append(imageList, img)
	}

	// 로그 출력
	if filteredCount > 0 {
		log.Info().
			Int("filtered", filteredCount).
			Msg("무효한 이미지 항목 제외됨")
	}

	sort.Strings(imageList)

	output := map[string]interface{}{
		"images": imageList,
		"count":  len(imageList),
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return fmt.Errorf("JSON 마샬링 실패: %w", err)
	}

	if err := os.WriteFile(w.config.OutputPath, data, 0644); err != nil {
		return fmt.Errorf("파일 쓰기 실패: %w", err)
	}

	log.Info().
		Str("path", w.config.OutputPath).
		Int("count", len(imageList)).
		Msg("이미지 목록 저장 완료 (JSON)")

	return nil
}

// writeYAML writes images as YAML
func (w *Writer) writeYAML(images map[string]bool) error {
	// 검증, 정규화 및 중복 제거
	imageSet := make(map[string]bool) // 중복 제거를 위한 set
	filteredCount := 0

	for img := range images {
		// 유효성 검증
		if !isValidImage(img) {
			filteredCount++
			continue
		}

		// 정규화
		normalized := normalizeImage(img)
		imageSet[normalized] = true // set에 추가 (자동 중복 제거)
	}

	// bitnami → bitnamilegacy 대체 처리
	imageSet = removeLegacyReplacements(imageSet)
	// 태그 없는 중복 제거
	imageSet = removeDuplicatesWithoutTag(imageSet)

	// 커스텀 이미지가 존재할 경우 벤더 기본 이미지 제거
	imageSet = removeOverriddenImages(imageSet)

    // Windows Exporter 제거
    imageSet = removeWindowsExporter(imageSet)

	// set을 slice로 변환
	imageList := make([]string, 0, len(imageSet))
	for img := range imageSet {
		imageList = append(imageList, img)
	}

	// 로그 출력
	if filteredCount > 0 {
		log.Info().
			Int("filtered", filteredCount).
			Msg("무효한 이미지 항목 제외됨")
	}

	sort.Strings(imageList)

	output := map[string]interface{}{
		"images": imageList,
		"count":  len(imageList),
	}

	data, err := yaml.Marshal(output)
	if err != nil {
		return fmt.Errorf("YAML 마샬링 실패: %w", err)
	}

	if err := os.WriteFile(w.config.OutputPath, data, 0644); err != nil {
		return fmt.Errorf("파일 쓰기 실패: %w", err)
	}

	log.Info().
		Str("path", w.config.OutputPath).
		Int("count", len(imageList)).
		Msg("이미지 목록 저장 완료 (YAML)")

	return nil
}
