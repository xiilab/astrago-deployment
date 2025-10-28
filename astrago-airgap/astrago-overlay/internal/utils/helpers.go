package utils

import "strings"

// DeepMerge performs a deep merge of two maps.
// Values from src override values in dst.
// Nested maps are merged recursively.
func DeepMerge(dst, src map[string]interface{}) map[string]interface{} {
	if dst == nil {
		dst = make(map[string]interface{})
	}
	if src == nil {
		return dst
	}

	for key, srcVal := range src {
		if dstVal, ok := dst[key]; ok {
			// Both values exist, check if they're both maps
			srcMap, srcIsMap := srcVal.(map[string]interface{})
			dstMap, dstIsMap := dstVal.(map[string]interface{})

			if srcIsMap && dstIsMap {
				// Recursively merge maps
				dst[key] = DeepMerge(dstMap, srcMap)
				continue
			}
		}
		// Override or add new key
		dst[key] = srcVal
	}

	return dst
}

// GetNestedValue retrieves a nested value from a map using dot notation path.
// Example: GetNestedValue(m, "parent.child.value") retrieves m["parent"]["child"]["value"]
// Returns empty string if path doesn't exist or value is not a string.
func GetNestedValue(m map[string]interface{}, path string) string {
	if m == nil || path == "" {
		return ""
	}

	parts := strings.Split(path, ".")
	current := m

	for i, part := range parts {
		if part == "" {
			return ""
		}

		if i == len(parts)-1 {
			// Last part - return the value
			if val, ok := current[part].(string); ok {
				return val
			}
			return ""
		}

		// Navigate deeper
		if next, ok := current[part].(map[string]interface{}); ok {
			current = next
		} else {
			return ""
		}
	}

	return ""
}

// GetNestedValueWithDefault retrieves a nested value with a default fallback.
// If the path doesn't exist or the value is empty, returns defaultVal.
func GetNestedValueWithDefault(m map[string]interface{}, path, defaultVal string) string {
	val := GetNestedValue(m, path)
	if val == "" {
		return defaultVal
	}
	return val
}

// GetNestedMap retrieves a nested map from a map using dot notation path.
// Returns nil if path doesn't exist or value is not a map.
func GetNestedMap(m map[string]interface{}, path string) map[string]interface{} {
	if m == nil || path == "" {
		return nil
	}

	parts := strings.Split(path, ".")
	current := m

	for i, part := range parts {
		if part == "" {
			return nil
		}

		if i == len(parts)-1 {
			// Last part - return the map
			if val, ok := current[part].(map[string]interface{}); ok {
				return val
			}
			return nil
		}

		// Navigate deeper
		if next, ok := current[part].(map[string]interface{}); ok {
			current = next
		} else {
			return nil
		}
	}

	return current
}
