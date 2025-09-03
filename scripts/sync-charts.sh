#!/bin/bash
# Astrago Helm Charts Synchronization Script
# External charts download and management for offline deployment

set -euo pipefail

# Configuration
CHARTS_DIR="helmfile/charts/external"
LOCK_FILE="helmfile/charts/versions.lock"
CHARTS_CONFIG="charts.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check Helm installation
check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install Helm first."
        exit 1
    fi
    log_info "Helm version: $(helm version --short)"
}

# Create directories
create_directories() {
    log_info "Creating chart directories..."
    mkdir -p "$PROJECT_ROOT/$CHARTS_DIR"
    mkdir -p "$(dirname "$PROJECT_ROOT/$LOCK_FILE")"
}

# Load JSON configuration file functions
load_charts_config() {
    if [ ! -f "$PROJECT_ROOT/$CHARTS_CONFIG" ]; then
        log_error "$CHARTS_CONFIG file not found."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq first."
        exit 1
    fi
}

get_repo_url() {
    jq -r ".repositories[\"$1\"] // empty" "$PROJECT_ROOT/$CHARTS_CONFIG"
}

get_chart_version() {
    local chart_name=$(echo "$1" | cut -d'/' -f2)
    jq -r ".charts[\"$chart_name\"].version // empty" "$PROJECT_ROOT/$CHARTS_CONFIG"
}

get_chart_repository() {
    local chart_name=$(echo "$1" | cut -d'/' -f2)
    jq -r ".charts[\"$chart_name\"].repository // empty" "$PROJECT_ROOT/$CHARTS_CONFIG"
}

get_chart_list() {
    jq -r '.charts | keys[]' "$PROJECT_ROOT/$CHARTS_CONFIG"
}

# Add repositories dynamically
add_repositories() {
    log_info "Adding Helm repositories..."
    
    # Get all repository information from JSON
    local repo_data=$(jq -r '.repositories | to_entries[] | "\(.key) \(.value)"' "$PROJECT_ROOT/$CHARTS_CONFIG")
    
    # Add each repository  
    while IFS=' ' read -r repo_name repo_url; do
        if [ -n "$repo_name" ] && [ -n "$repo_url" ]; then
            log_info "Adding repository: $repo_name"
            helm repo add "$repo_name" "$repo_url" 2>/dev/null || true
        fi
    done <<< "$repo_data"
    
    log_info "Updating repositories..."
    helm repo update
}

# Download single chart
download_chart() {
    local chart_simple_name="$1"
    local version="$2"
    local chart_dir="$PROJECT_ROOT/$CHARTS_DIR"
    
    # Get repository information from JSON
    local repo_name=$(get_chart_repository "$chart_simple_name")
    local chart_name="$repo_name/$chart_simple_name"
    
    log_info "Downloading: $chart_name:$version"
    
    # Create version-specific directory
    local target_dir="$chart_dir/${chart_simple_name}-${version}"
    
    if [ -d "$target_dir" ]; then
        log_warn "$chart_simple_name:$version already exists. Skipping..."
        return 0
    fi
    
    # 임시 디렉토리에서 다운로드
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    if helm pull "$chart_name" --version "$version" --untar; then
        # 다운로드된 차트를 목표 디렉토리로 이동
        mv "$chart_simple_name" "$target_dir"
        log_success "Download completed: $chart_name:$version → $target_dir"
        
        # Download dependencies if exists
        if [ -f "$target_dir/Chart.yaml" ] && grep -q "dependencies:" "$target_dir/Chart.yaml"; then
            log_info "Downloading dependencies: $chart_simple_name"
            cd "$target_dir"
            if helm dependency build .; then
                log_success "Dependencies download completed: $chart_simple_name"
                
                # Modify Chart.yaml repository to file path (offline support)
                log_info "Modifying Chart.yaml repository field for offline mode..."
                sed -i.bak 's|repository: oci://[^[:space:]]*|repository: file://charts|g' Chart.yaml
                sed -i.bak 's|repository: https://[^[:space:]]*|repository: file://charts|g' Chart.yaml
                rm -f Chart.yaml.bak
                log_success "Repository field modification completed: $chart_simple_name"
            else
                log_warn "Dependencies download failed: $chart_simple_name"
            fi
        fi
        
        # Calculate checksum
        local checksum=$(find "$target_dir" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
        echo "$chart_name,$version,$checksum,$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PROJECT_ROOT/$LOCK_FILE"
    else
        log_error "$chart_name:$version download failed"
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
}

# Download all charts
download_all_charts() {
    log_info "Starting external charts download..."
    
    # versions.lock 파일 초기화
    echo "# Astrago Helm Charts Versions Lock File" > "$PROJECT_ROOT/$LOCK_FILE"
    echo "# Format: chart_name,version,checksum,download_date" >> "$PROJECT_ROOT/$LOCK_FILE"
    echo "# Generated at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PROJECT_ROOT/$LOCK_FILE"
    echo "" >> "$PROJECT_ROOT/$LOCK_FILE"
    
    local success_count=0
    local total_count=0
    
    # Get chart list from JSON
    local chart_names=($(get_chart_list))
    total_count=${#chart_names[@]}
    
    for chart_name in "${chart_names[@]}"; do
        local version=$(get_chart_version "$chart_name")
        if [ -n "$version" ] && download_chart "$chart_name" "$version"; then
            ((success_count++))
        fi
    done
    
    log_info "Download completed: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        log_success "All charts downloaded successfully!"
        return 0
    else
        log_error "Some charts download failed"
        return 1
    fi
}

# Validate checksums
validate_checksums() {
    log_info "Validating chart integrity..."
    
    if [ ! -f "$PROJECT_ROOT/$LOCK_FILE" ]; then
        log_error "versions.lock file not found."
        return 1
    fi
    
    local validation_failed=0
    
    while IFS=',' read -r chart_name version stored_checksum download_date; do
        # Skip comments and empty lines
        [[ "$chart_name" =~ ^#.*$ ]] || [[ -z "$chart_name" ]] && continue
        
        local chart_simple_name=$(echo "$chart_name" | cut -d'/' -f2)
        local chart_dir="$PROJECT_ROOT/$CHARTS_DIR/${chart_simple_name}-${version}"
        
        if [ ! -d "$chart_dir" ]; then
            log_error "Chart directory not found: $chart_dir"
            ((validation_failed++))
            continue
        fi
        
        # Calculate current checksum
        local current_checksum=$(find "$chart_dir" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
        
        if [ "$current_checksum" != "$stored_checksum" ]; then
            log_error "Checksum mismatch: $chart_name:$version"
            log_error "  Expected: $stored_checksum"
            log_error "  Actual: $current_checksum"
            ((validation_failed++))
        else
            log_success "Checksum validation passed: $chart_name:$version"
        fi
    done < "$PROJECT_ROOT/$LOCK_FILE"
    
    if [ $validation_failed -eq 0 ]; then
        log_success "All charts integrity validation passed!"
        return 0
    else
        log_error "$validation_failed charts failed integrity validation"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    # Clean up temporary directories if exists
}

# Show help
show_help() {
    cat << EOF
Astrago Helm Charts Synchronization Script

Usage:
  $0 [options]

Options:
  download, sync    Download all external charts
  validate         Validate chart integrity
  clean           Remove downloaded charts
  list            Show downloaded charts list
  help, -h        Show this help

Examples:
  $0 download      # Download all charts
  $0 validate      # Validate charts
  $0 list          # Show charts list

Charts storage location: $CHARTS_DIR/
Lock file location: $LOCK_FILE
Configuration file location: $CHARTS_CONFIG
EOF
}

# Show charts list
list_charts() {
    log_info "Downloaded charts list:"
    
    if [ ! -d "$PROJECT_ROOT/$CHARTS_DIR" ]; then
        log_warn "Charts directory not found."
        return 1
    fi
    
    local count=0
    if [ -d "$PROJECT_ROOT/$CHARTS_DIR" ]; then
        for dir in "$PROJECT_ROOT/$CHARTS_DIR"/*; do
            if [ -d "$dir" ]; then
                local dirname=$(basename "$dir")
                echo "  - $dirname"
                ((count++))
            fi
        done
    fi
    
    log_info "Total ${count} charts are stored."
}

# Clean charts function
clean_charts() {
    log_warn "All downloaded charts will be removed."
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$PROJECT_ROOT/$CHARTS_DIR"/*
        rm -f "$PROJECT_ROOT/$LOCK_FILE"
        log_success "All charts have been removed."
    else
        log_info "Cancelled."
    fi
}

# Main function
main() {
    cd "$PROJECT_ROOT"
    
    case "${1:-download}" in
        "download"|"sync")
            load_charts_config
            check_helm
            create_directories
            add_repositories
            download_all_charts
            validate_checksums
            ;;
        "validate")
            load_charts_config
            validate_checksums
            ;;
        "list")
            list_charts
            ;;
        "clean")
            clean_charts
            ;;
        "help"|"-h")
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# 시그널 핸들러
trap cleanup EXIT

# 스크립트 실행
main "$@"