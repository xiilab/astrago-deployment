package errors

import (
	"fmt"
)

// ErrorType represents the type of error
type ErrorType string

const (
	// ErrorTypeConfig represents configuration errors
	ErrorTypeConfig ErrorType = "CONFIG"
	// ErrorTypeDiscovery represents chart discovery errors
	ErrorTypeDiscovery ErrorType = "DISCOVERY"
	// ErrorTypeRenderer represents rendering errors
	ErrorTypeRenderer ErrorType = "RENDERER"
	// ErrorTypeExtractor represents image extraction errors
	ErrorTypeExtractor ErrorType = "EXTRACTOR"
	// ErrorTypeOutput represents output writing errors
	ErrorTypeOutput ErrorType = "OUTPUT"
)

// ExtractorError represents a structured error with context
type ExtractorError struct {
	Type    ErrorType
	Message string
	Cause   error
	Context map[string]interface{}
}

// Error implements the error interface
func (e *ExtractorError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("[%s] %s: %v", e.Type, e.Message, e.Cause)
	}
	return fmt.Sprintf("[%s] %s", e.Type, e.Message)
}

// Unwrap returns the underlying error
func (e *ExtractorError) Unwrap() error {
	return e.Cause
}

// New creates a new ExtractorError
func New(errType ErrorType, message string) *ExtractorError {
	return &ExtractorError{
		Type:    errType,
		Message: message,
		Context: make(map[string]interface{}),
	}
}

// Wrap wraps an existing error with context
func Wrap(err error, errType ErrorType, message string) *ExtractorError {
	return &ExtractorError{
		Type:    errType,
		Message: message,
		Cause:   err,
		Context: make(map[string]interface{}),
	}
}

// WithContext adds context to the error
func (e *ExtractorError) WithContext(key string, value interface{}) *ExtractorError {
	e.Context[key] = value
	return e
}
