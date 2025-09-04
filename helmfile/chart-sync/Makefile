# Astrago Chart Sync Tool Makefile

BINARY_NAME=chart-sync
GO=go
GOFLAGS=-v
MAIN_PATH=cmd/chart-sync/main.go

.PHONY: all build clean deps run-download run-validate run-list run-clean run-fix-locks help

all: deps build

## help: Show this help message
help:
	@echo "Available targets:"
	@grep -E '^## ' Makefile | sed 's/## /  /'

## deps: Download Go module dependencies
deps:
	$(GO) mod download
	$(GO) mod tidy

## build: Build the binary
build:
	$(GO) build $(GOFLAGS) -o $(BINARY_NAME) $(MAIN_PATH)

## clean: Remove build artifacts
clean:
	rm -f $(BINARY_NAME)
	rm -rf ../charts/external/*
	rm -f ../charts/versions.lock

## run-download: Download all charts
run-download: build
	./$(BINARY_NAME) download

## run-validate: Validate chart checksums
run-validate: build
	./$(BINARY_NAME) validate

## run-list: List downloaded charts
run-list: build
	./$(BINARY_NAME) list

## run-clean: Clean downloaded charts
run-clean: build
	./$(BINARY_NAME) clean

## run-fix-locks: Fix Chart.lock files
run-fix-locks: build
	./$(BINARY_NAME) fix-locks

## install: Install the binary to /usr/local/bin
install: build
	sudo cp $(BINARY_NAME) /usr/local/bin/

## test: Run tests
test:
	$(GO) test -v ./...