package main

import (
	"context"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"
)

const (
	metricsFile = "/tmp/metrics/gpu_metrics.prom"
	defaultPort = 8080
)

type Server struct {
	port        int
	metricsFile string
	logger      *log.Logger
}

func NewServer() *Server {
	port := defaultPort
	if p := os.Getenv("METRICS_PORT"); p != "" {
		if parsed, err := strconv.Atoi(p); err == nil {
			port = parsed
		}
	}

	return &Server{
		port:        port,
		metricsFile: metricsFile,
		logger:      log.New(os.Stdout, "[HTTP-SERVER] ", log.LstdFlags),
	}
}

func (s *Server) metricsHandler(w http.ResponseWriter, r *http.Request) {
	s.logger.Printf("GET %s from %s", r.URL.Path, r.RemoteAddr)

	// Check if metrics file exists
	if _, err := os.Stat(s.metricsFile); os.IsNotExist(err) {
		s.logger.Printf("WARNING: Metrics file not found: %s", s.metricsFile)
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "# Metrics file not ready yet\n")
		return
	}

	// Read metrics file
	content, err := ioutil.ReadFile(s.metricsFile)
	if err != nil {
		s.logger.Printf("ERROR: Failed to read metrics file: %v", err)
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "# Error reading metrics: %v\n", err)
		return
	}

	// Return metrics content
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	w.Header().Set("Content-Length", strconv.Itoa(len(content)))
	w.WriteHeader(http.StatusOK)
	w.Write(content)

	s.logger.Printf("Metrics served successfully (%d bytes)", len(content))
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	s.logger.Printf("GET %s from %s", r.URL.Path, r.RemoteAddr)

	var status string
	var code int

	// Check if metrics file exists and is recent (within 2 minutes)
	if stat, err := os.Stat(s.metricsFile); err == nil {
		fileAge := time.Since(stat.ModTime())
		if fileAge < 2*time.Minute {
			status = "OK"
			code = http.StatusOK
		} else {
			status = fmt.Sprintf("STALE - metrics file too old (%.0f seconds)", fileAge.Seconds())
			code = http.StatusServiceUnavailable
		}
	} else {
		status = "ERROR - metrics file not found"
		code = http.StatusServiceUnavailable
	}

	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Length", strconv.Itoa(len(status)))
	w.WriteHeader(code)
	fmt.Fprint(w, status)

	s.logger.Printf("Health check: %s (code: %d)", status, code)
}

func (s *Server) rootHandler(w http.ResponseWriter, r *http.Request) {
	// Root path redirects to /metrics
	if r.URL.Path == "/" {
		s.metricsHandler(w, r)
		return
	}

	// 404 for unknown paths
	s.logger.Printf("404 - GET %s from %s", r.URL.Path, r.RemoteAddr)
	w.WriteHeader(http.StatusNotFound)
	fmt.Fprintf(w, "Not Found")
}

func (s *Server) loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		duration := time.Since(start)
		s.logger.Printf("Request completed in %v", duration)
	})
}

func (s *Server) Run() error {
	// Create metrics directory if it doesn't exist
	if err := os.MkdirAll("/tmp/metrics", 0755); err != nil {
		return fmt.Errorf("failed to create metrics directory: %v", err)
	}

	// Setup HTTP routes
	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", s.metricsHandler)
	mux.HandleFunc("/health", s.healthHandler)
	mux.HandleFunc("/", s.rootHandler)

	// Create HTTP server
	server := &http.Server{
		Addr:           fmt.Sprintf(":%d", s.port),
		Handler:        s.loggingMiddleware(mux),
		ReadTimeout:    10 * time.Second,
		WriteTimeout:   10 * time.Second,
		IdleTimeout:    30 * time.Second,
		MaxHeaderBytes: 1 << 20, // 1MB
	}

	// Start server in goroutine
	go func() {
		s.logger.Printf("GPU Process Exporter HTTP Server starting on port %d", s.port)
		s.logger.Printf("Metrics endpoint: http://0.0.0.0:%d/metrics", s.port)
		s.logger.Printf("Health endpoint: http://0.0.0.0:%d/health", s.port)

		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			s.logger.Fatalf("Failed to start HTTP server: %v", err)
		}
	}()

	// Wait for interrupt signal for graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	s.logger.Println("Received termination signal, shutting down gracefully...")

	// Graceful shutdown with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		s.logger.Printf("Server forced to shutdown: %v", err)
		return err
	}

	s.logger.Println("Server shutdown completed")
	return nil
}

func main() {
	// Set up logger
	log.SetFlags(log.LstdFlags)
	log.SetPrefix("[MAIN] ")

	// Print startup info
	nodeName := os.Getenv("NODE_NAME")
	if nodeName == "" {
		nodeName = "unknown"
	}
	
	log.Printf("=== GPU Process Exporter HTTP Server (Go) ===")
	log.Printf("Node: %s", nodeName)
	log.Printf("Go version: %s", "1.19+")

	// Create and run server
	server := NewServer()
	if err := server.Run(); err != nil {
		log.Fatalf("Server error: %v", err)
	}
} 