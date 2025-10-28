package errors

import (
	"errors"
	"strings"
	"testing"
)

func TestNew(t *testing.T) {
	err := New(ErrorTypeConfig, "test error")

	if err.Type != ErrorTypeConfig {
		t.Errorf("Expected type %s, got %s", ErrorTypeConfig, err.Type)
	}

	if err.Message != "test error" {
		t.Errorf("Expected message 'test error', got '%s'", err.Message)
	}

	if !strings.Contains(err.Error(), "CONFIG") {
		t.Errorf("Error string should contain type: %s", err.Error())
	}
}

func TestWrap(t *testing.T) {
	cause := errors.New("original error")
	err := Wrap(cause, ErrorTypeDiscovery, "wrapped error")

	if err.Cause != cause {
		t.Error("Cause not properly set")
	}

	if err.Unwrap() != cause {
		t.Error("Unwrap() should return the cause")
	}

	errStr := err.Error()
	if !strings.Contains(errStr, "DISCOVERY") {
		t.Errorf("Error string should contain type: %s", errStr)
	}
	if !strings.Contains(errStr, "wrapped error") {
		t.Errorf("Error string should contain message: %s", errStr)
	}
	if !strings.Contains(errStr, "original error") {
		t.Errorf("Error string should contain cause: %s", errStr)
	}
}

func TestWithContext(t *testing.T) {
	err := New(ErrorTypeExtractor, "test error").
		WithContext("chart", "test-chart").
		WithContext("count", 5)

	if err.Context["chart"] != "test-chart" {
		t.Error("Context not properly set")
	}

	if err.Context["count"] != 5 {
		t.Error("Context count not properly set")
	}
}

func TestErrorTypes(t *testing.T) {
	types := []ErrorType{
		ErrorTypeConfig,
		ErrorTypeDiscovery,
		ErrorTypeRenderer,
		ErrorTypeExtractor,
		ErrorTypeOutput,
	}

	for _, errType := range types {
		err := New(errType, "test")
		if err.Type != errType {
			t.Errorf("Expected type %s, got %s", errType, err.Type)
		}
	}
}
