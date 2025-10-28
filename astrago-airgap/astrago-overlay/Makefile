.PHONY: all build build-all clean install test lint fmt deps help release-prep release-upload download-binaries install-from-release

# 변수 정의
BINARY_NAME := extract-images
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME := $(shell date -u '+%Y-%m-%d_%H:%M:%S')
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
LDFLAGS := -ldflags "-X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(BUILD_TIME)"
REPO := xiilab/astrago-deployment
RELEASE_VERSION ?= $(VERSION)

# Go 환경 변수
GO := go
GOFLAGS := -v
GOTEST := $(GO) test -v -race -coverprofile=coverage.out

# 기본 타겟
all: test build

# 현재 플랫폼용 빌드
build:
	@echo "🔨 Building for $(shell go env GOOS)/$(shell go env GOARCH)..."
	$(GO) build $(GOFLAGS) $(LDFLAGS) -o bin/$(BINARY_NAME)-$(shell go env GOOS)-$(shell go env GOARCH) ./cmd/extractor
	@echo "✅ Build complete: bin/$(BINARY_NAME)-$(shell go env GOOS)-$(shell go env GOARCH)"

# 크로스 컴파일 (모든 플랫폼)
build-all:
	@echo "🔨 Building for multiple platforms..."
	@mkdir -p bin
	GOOS=linux GOARCH=amd64 $(GO) build $(LDFLAGS) -o bin/$(BINARY_NAME)-linux-amd64 ./cmd/extractor
	GOOS=linux GOARCH=arm64 $(GO) build $(LDFLAGS) -o bin/$(BINARY_NAME)-linux-arm64 ./cmd/extractor
	GOOS=darwin GOARCH=amd64 $(GO) build $(LDFLAGS) -o bin/$(BINARY_NAME)-darwin-amd64 ./cmd/extractor
	GOOS=darwin GOARCH=arm64 $(GO) build $(LDFLAGS) -o bin/$(BINARY_NAME)-darwin-arm64 ./cmd/extractor
	@echo "✅ All platforms built successfully:"
	@ls -lh bin/

# 테스트
test:
	@echo "🧪 Running tests..."
	$(GOTEST) ./...

# 테스트 커버리지 (HTML 리포트)
test-coverage:
	@echo "📊 Generating coverage report..."
	$(GO) test -v -race -coverprofile=coverage.out -covermode=atomic ./...
	$(GO) tool cover -html=coverage.out -o coverage.html
	@echo "✅ Coverage report generated: coverage.html"
	@$(GO) tool cover -func=coverage.out | grep total | awk '{print "Total coverage: " $$3}'

# 통합 테스트
test-integration:
	@echo "🧪 Running integration tests..."
	$(GOTEST) ./test/integration/... -tags=integration

# 벤치마크
bench:
	@echo "📊 Running benchmarks..."
	$(GO) test -bench=. -benchmem ./...

# 정적 분석 (golangci-lint 필요)
lint:
	@echo "🔍 Running linter..."
	@which golangci-lint > /dev/null || (echo "golangci-lint not installed. Run: brew install golangci-lint" && exit 1)
	golangci-lint run

# 포맷팅
fmt:
	@echo "✨ Formatting code..."
	$(GO) fmt ./...
	@which goimports > /dev/null && goimports -w . || echo "goimports not installed, skipping"

# 의존성 업데이트
deps:
	@echo "📦 Updating dependencies..."
	$(GO) mod download
	$(GO) mod tidy
	$(GO) mod verify
	@echo "✅ Dependencies updated"

# 설치 (로컬 시스템에)
install: build
	@echo "📦 Installing $(BINARY_NAME)..."
	@mkdir -p ../../tools/$(shell go env GOOS)
	cp bin/$(BINARY_NAME)-$(shell go env GOOS)-$(shell go env GOARCH) ../../tools/$(shell go env GOOS)/$(BINARY_NAME)
	chmod +x ../../tools/$(shell go env GOOS)/$(BINARY_NAME)
	@echo "✅ Installed to ../../tools/$(shell go env GOOS)/$(BINARY_NAME)"

# 정리
clean:
	@echo "🧹 Cleaning..."
	rm -rf bin/ coverage.out dist/
	@echo "✅ Clean complete"

# 도움말
help:
	@echo "Available targets:"
	@echo "  make build               - Build for current platform"
	@echo "  make build-all           - Build for all platforms"
	@echo "  make test                - Run unit tests"
	@echo "  make test-coverage       - Generate test coverage report (HTML)"
	@echo "  make test-integration    - Run integration tests"
	@echo "  make bench               - Run benchmarks"
	@echo "  make lint                - Run linter"
	@echo "  make fmt                 - Format code"
	@echo "  make deps                - Update dependencies"
	@echo "  make install             - Install binary to tools directory"
	@echo "  make clean               - Clean build artifacts"
	@echo ""
	@echo "Release targets:"
	@echo "  make release-prep        - Prepare release artifacts (tar.gz)"
	@echo "  make release-upload      - Upload to GitHub Release (requires gh CLI)"
	@echo "  make download-binaries   - Download from GitHub Release (no build needed)"
	@echo "  make install-from-release - Download and install to /usr/local/bin"

# GitHub Release 관련 명령어
release-prep: build-all ## GitHub Release용 바이너리 압축
	@echo "📦 Compressing binaries for release..."
	@cd bin && \
	tar -czf astrago-image-extractor-$(RELEASE_VERSION)-linux-amd64.tar.gz $(BINARY_NAME)-linux-amd64 && \
	tar -czf astrago-image-extractor-$(RELEASE_VERSION)-linux-arm64.tar.gz $(BINARY_NAME)-linux-arm64 && \
	tar -czf astrago-image-extractor-$(RELEASE_VERSION)-darwin-amd64.tar.gz $(BINARY_NAME)-darwin-amd64 && \
	tar -czf astrago-image-extractor-$(RELEASE_VERSION)-darwin-arm64.tar.gz $(BINARY_NAME)-darwin-arm64
	@echo "✅ Release artifacts ready in bin/"
	@ls -lh bin/*.tar.gz

release-upload: release-prep ## GitHub Release 업로드 (gh CLI 필요)
	@echo "🚀 Uploading to GitHub Release..."
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "❌ GitHub CLI (gh) not installed"; \
		echo "   Install: https://cli.github.com/"; \
		exit 1; \
	fi
	gh release create $(RELEASE_VERSION) bin/*.tar.gz \
		--repo $(REPO) \
		--title "Astrago Image Extractor $(RELEASE_VERSION)" \
		--notes "Automated release for $(RELEASE_VERSION)"

download-binaries: ## GitHub Release에서 바이너리 다운로드 (원격 서버용)
	@echo "📥 Downloading binaries from GitHub Release..."
	@PLATFORM=$$(go env GOOS)-$$(go env GOARCH) && \
	mkdir -p bin && \
	cd bin && \
	curl -L "https://github.com/$(REPO)/releases/latest/download/astrago-image-extractor-$$PLATFORM.tar.gz" -o temp.tar.gz && \
	tar -xzf temp.tar.gz && \
	rm -f temp.tar.gz && \
	chmod +x $(BINARY_NAME)-* && \
	echo "✅ Downloaded: $(BINARY_NAME)-$$PLATFORM"

install-from-release: download-binaries ## 다운로드 후 PATH에 설치
	@echo "📍 Installing to /usr/local/bin..."
	@PLATFORM=$$(go env GOOS)-$$(go env GOARCH) && \
	sudo cp bin/$(BINARY_NAME)-$$PLATFORM /usr/local/bin/$(BINARY_NAME) && \
	echo "✅ Installed: /usr/local/bin/$(BINARY_NAME)"
	@$(BINARY_NAME) --version

