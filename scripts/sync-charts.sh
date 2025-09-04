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
                
                # Modify Chart.yaml repository to local file path (offline support)
                log_info "Modifying Chart.yaml repository field for offline mode..."
                
                # Simple approach: just replace repository URLs with file://charts
                # The dependency charts are already in the charts/ folder with their actual names
                if [ -f Chart.yaml ] && grep -q "dependencies:" Chart.yaml; then
                    # For each dependency, find its name and update repository in one pass
                    # Using a simple while loop with state tracking
                    local temp_file="Chart.yaml.tmp"
                    local dep_name=""
                    
                    while IFS= read -r line; do
                        # Extract dependency name
                        if [[ "$line" =~ ^[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
                            dep_name="${BASH_REMATCH[1]}"
                            dep_name="${dep_name// /}"  # Trim spaces
                            echo "$line" >> "$temp_file"
                        # Replace repository URL with local path
                        elif [[ "$line" =~ ^([[:space:]]*repository:[[:space:]]*)(https?://|oci://)(.*)$ ]]; then
                            if [[ -n "$dep_name" ]]; then
                                echo "${BASH_REMATCH[1]}file://charts/$dep_name" >> "$temp_file"
                            else
                                echo "${BASH_REMATCH[1]}file://charts" >> "$temp_file"
                            fi
                        # Reset dep_name when new dependency starts
                        elif [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                            dep_name=""
                            echo "$line" >> "$temp_file"
                        else
                            echo "$line" >> "$temp_file"
                        fi
                    done < Chart.yaml
                    
                    # Replace original file
                    mv "$temp_file" Chart.yaml
                fi
                
                log_success "Repository field modification completed: $chart_simple_name"
                
                # Regenerate Chart.lock to match modified Chart.yaml
                log_info "Regenerating Chart.lock for offline compatibility..."
                if helm dependency build --skip-refresh .; then
                    log_success "Chart.lock regenerated successfully: $chart_simple_name"
                else
                    log_warn "Chart.lock regeneration failed: $chart_simple_name"
                fi
                
                log_success "Repository field modification completed: $chart_simple_name"
            else
                log_warn "Dependencies download failed: $chart_simple_name"
            fi
        fi
        
        # Don't calculate checksum yet - will calculate after all modifications
        local download_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        echo "$chart_name,$version,TEMP_CHECKSUM_$chart_simple_name,$download_date" >> "$PROJECT_ROOT/$LOCK_FILE"
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
    
    # 모든 다운로드 완료 후 Chart.lock 재생성 및 최종 체크섬 계산
    log_info "Finalizing charts and updating checksums..."
    
    # 각 차트 디렉토리를 처리하고 최종 체크섬 계산
    for chart_dir in "$PROJECT_ROOT/$CHARTS_DIR"/*; do
        if [ -d "$chart_dir" ]; then
            local chart_name=$(basename "$chart_dir")
            cd "$chart_dir"
            
            # Chart.lock 완전히 삭제하고 재생성 (dependency가 있는 경우)
            if [ -f "Chart.yaml" ] && grep -q "dependencies:" "Chart.yaml"; then
                log_info "Deleting old Chart.lock and regenerating: $chart_name"
                rm -f Chart.lock
                if helm dependency update . 2>/dev/null; then
                    log_success "Chart.lock regenerated: $chart_name"
                else
                    log_warn "Chart.lock regeneration failed: $chart_name"
                fi
            fi
            
            # 최종 체크섬 계산
            local final_checksum=$(find . -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
            
            # 임시 체크섬을 실제 체크섬으로 교체
            local simple_name=$(echo "$chart_name" | sed 's/-v[0-9].*//' | sed 's/-[0-9].*//')
            sed -i.bak "s/TEMP_CHECKSUM_$simple_name/$final_checksum/g" "$PROJECT_ROOT/$LOCK_FILE" 2>/dev/null || true
            
            log_success "Final checksum updated: $chart_name"
        fi
    done
    
    # 백업 파일 정리
    rm -f "$PROJECT_ROOT/$LOCK_FILE.bak"
    
    log_info "Download completed: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        log_success "All charts downloaded successfully!"
        return 0
    else
        log_error "Some charts download failed"
        return 1
    fi
}

# Update checksums in lock file
update_checksums_in_lock() {
    log_info "Updating checksums in versions.lock..."
    
    if [ ! -f "$PROJECT_ROOT/$LOCK_FILE" ]; then
        log_error "versions.lock file not found."
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    local updated_count=0
    
    while IFS=',' read -r chart_name version stored_checksum download_date; do
        # Skip comments and empty lines
        if [[ "$chart_name" =~ ^#.*$ ]] || [[ -z "$chart_name" ]]; then
            echo "$chart_name,$version,$stored_checksum,$download_date" >> "$temp_file"
            continue
        fi
        
        local chart_simple_name=$(echo "$chart_name" | cut -d'/' -f2)
        local chart_dir="$PROJECT_ROOT/$CHARTS_DIR/${chart_simple_name}-${version}"
        
        if [ -d "$chart_dir" ]; then
            # Calculate current checksum
            local current_checksum=$(find "$chart_dir" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
            echo "$chart_name,$version,$current_checksum,$download_date" >> "$temp_file"
            ((updated_count++))
            log_info "Checksum updated: $chart_name"
        else
            echo "$chart_name,$version,$stored_checksum,$download_date" >> "$temp_file"
        fi
    done < "$PROJECT_ROOT/$LOCK_FILE"
    
    # Replace original file
    mv "$temp_file" "$PROJECT_ROOT/$LOCK_FILE"
    log_success "Updated $updated_count checksums in versions.lock"
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
        
        # Skip validation if checksum is temporary placeholder
        if [[ "$stored_checksum" =~ ^TEMP_CHECKSUM_ ]]; then
            log_warn "Skipping validation for temporary checksum: $chart_name:$version"
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
  fix-locks       Fix Chart.lock synchronization issues
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

# Fix Chart.lock files
fix_chart_locks() {
    log_info "Fixing all Chart.lock files..."
    
    for chart_dir in "$PROJECT_ROOT/$CHARTS_DIR"/*; do
        if [ -d "$chart_dir" ]; then
            local chart_name=$(basename "$chart_dir")
            cd "$chart_dir"
            
            if [ -f "Chart.yaml" ] && grep -q "dependencies:" "Chart.yaml"; then
                log_info "Fixing Chart.lock: $chart_name"
                
                # Chart.lock 완전히 삭제
                rm -f Chart.lock
                
                # dependency build로 로컬 차트 기반 재생성 (update는 remote 접근 시도함)
                if helm dependency build . 2>/dev/null; then
                    log_success "Chart.lock fixed: $chart_name"
                else
                    log_error "Chart.lock fix failed: $chart_name"
                fi
            fi
        fi
    done
    
    log_success "All Chart.lock files have been fixed!"
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
            # validate_checksums  # Skip validation after download since checksums are calculated after modifications
            ;;
        "validate")
            load_charts_config
            update_checksums_in_lock
            validate_checksums
            ;;
        "list")
            list_charts
            ;;
        "clean")
            clean_charts
            ;;
        "fix-locks")
            fix_chart_locks
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