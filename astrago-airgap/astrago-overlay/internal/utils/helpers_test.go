package utils

import (
	"reflect"
	"testing"
)

func TestDeepMerge(t *testing.T) {
	tests := []struct {
		name string
		dst  map[string]interface{}
		src  map[string]interface{}
		want map[string]interface{}
	}{
		{
			name: "nil dst",
			dst:  nil,
			src:  map[string]interface{}{"key": "value"},
			want: map[string]interface{}{"key": "value"},
		},
		{
			name: "nil src",
			dst:  map[string]interface{}{"key": "value"},
			src:  nil,
			want: map[string]interface{}{"key": "value"},
		},
		{
			name: "simple merge",
			dst:  map[string]interface{}{"a": "1"},
			src:  map[string]interface{}{"b": "2"},
			want: map[string]interface{}{"a": "1", "b": "2"},
		},
		{
			name: "override value",
			dst:  map[string]interface{}{"key": "old"},
			src:  map[string]interface{}{"key": "new"},
			want: map[string]interface{}{"key": "new"},
		},
		{
			name: "nested map merge",
			dst: map[string]interface{}{
				"parent": map[string]interface{}{
					"child1": "value1",
				},
			},
			src: map[string]interface{}{
				"parent": map[string]interface{}{
					"child2": "value2",
				},
			},
			want: map[string]interface{}{
				"parent": map[string]interface{}{
					"child1": "value1",
					"child2": "value2",
				},
			},
		},
		{
			name: "deep nested merge",
			dst: map[string]interface{}{
				"level1": map[string]interface{}{
					"level2": map[string]interface{}{
						"level3": "value1",
					},
				},
			},
			src: map[string]interface{}{
				"level1": map[string]interface{}{
					"level2": map[string]interface{}{
						"level3_new": "value2",
					},
				},
			},
			want: map[string]interface{}{
				"level1": map[string]interface{}{
					"level2": map[string]interface{}{
						"level3":     "value1",
						"level3_new": "value2",
					},
				},
			},
		},
		{
			name: "map overwritten by non-map",
			dst: map[string]interface{}{
				"key": map[string]interface{}{
					"nested": "value",
				},
			},
			src: map[string]interface{}{
				"key": "string_value",
			},
			want: map[string]interface{}{
				"key": "string_value",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := DeepMerge(tt.dst, tt.src)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("DeepMerge() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestGetNestedValue(t *testing.T) {
	tests := []struct {
		name string
		m    map[string]interface{}
		path string
		want string
	}{
		{
			name: "nil map",
			m:    nil,
			path: "key",
			want: "",
		},
		{
			name: "empty path",
			m:    map[string]interface{}{"key": "value"},
			path: "",
			want: "",
		},
		{
			name: "single level",
			m:    map[string]interface{}{"key": "value"},
			path: "key",
			want: "value",
		},
		{
			name: "nested path",
			m: map[string]interface{}{
				"parent": map[string]interface{}{
					"child": "value",
				},
			},
			path: "parent.child",
			want: "value",
		},
		{
			name: "deep nested path",
			m: map[string]interface{}{
				"level1": map[string]interface{}{
					"level2": map[string]interface{}{
						"level3": "deep_value",
					},
				},
			},
			path: "level1.level2.level3",
			want: "deep_value",
		},
		{
			name: "non-existent path",
			m:    map[string]interface{}{"key": "value"},
			path: "nonexistent",
			want: "",
		},
		{
			name: "non-existent nested path",
			m: map[string]interface{}{
				"parent": map[string]interface{}{
					"child": "value",
				},
			},
			path: "parent.nonexistent",
			want: "",
		},
		{
			name: "non-string value",
			m: map[string]interface{}{
				"key": 123,
			},
			path: "key",
			want: "",
		},
		{
			name: "path through non-map",
			m: map[string]interface{}{
				"parent": "string_value",
			},
			path: "parent.child",
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := GetNestedValue(tt.m, tt.path)
			if got != tt.want {
				t.Errorf("GetNestedValue() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestGetNestedValueWithDefault(t *testing.T) {
	tests := []struct {
		name       string
		m          map[string]interface{}
		path       string
		defaultVal string
		want       string
	}{
		{
			name:       "value exists",
			m:          map[string]interface{}{"key": "value"},
			path:       "key",
			defaultVal: "default",
			want:       "value",
		},
		{
			name:       "value doesn't exist - return default",
			m:          map[string]interface{}{"key": "value"},
			path:       "nonexistent",
			defaultVal: "default",
			want:       "default",
		},
		{
			name:       "nil map - return default",
			m:          nil,
			path:       "key",
			defaultVal: "default",
			want:       "default",
		},
		{
			name:       "nested value exists",
			m:          map[string]interface{}{"parent": map[string]interface{}{"child": "value"}},
			path:       "parent.child",
			defaultVal: "default",
			want:       "value",
		},
		{
			name:       "nested value doesn't exist - return default",
			m:          map[string]interface{}{"parent": map[string]interface{}{"child": "value"}},
			path:       "parent.nonexistent",
			defaultVal: "default",
			want:       "default",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := GetNestedValueWithDefault(tt.m, tt.path, tt.defaultVal)
			if got != tt.want {
				t.Errorf("GetNestedValueWithDefault() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestGetNestedMap(t *testing.T) {
	tests := []struct {
		name string
		m    map[string]interface{}
		path string
		want map[string]interface{}
	}{
		{
			name: "nil map",
			m:    nil,
			path: "key",
			want: nil,
		},
		{
			name: "empty path",
			m:    map[string]interface{}{"key": "value"},
			path: "",
			want: nil,
		},
		{
			name: "single level map",
			m:    map[string]interface{}{"key": map[string]interface{}{"nested": "value"}},
			path: "key",
			want: map[string]interface{}{"nested": "value"},
		},
		{
			name: "nested map",
			m: map[string]interface{}{
				"parent": map[string]interface{}{
					"child": map[string]interface{}{
						"value": "data",
					},
				},
			},
			path: "parent.child",
			want: map[string]interface{}{"value": "data"},
		},
		{
			name: "non-existent path",
			m:    map[string]interface{}{"key": "value"},
			path: "nonexistent",
			want: nil,
		},
		{
			name: "value is not a map",
			m:    map[string]interface{}{"key": "string_value"},
			path: "key",
			want: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := GetNestedMap(tt.m, tt.path)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("GetNestedMap() = %v, want %v", got, tt.want)
			}
		})
	}
}
