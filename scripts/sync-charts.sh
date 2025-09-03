#!/bin/bash
# Astrago Helm Charts Synchronization Script
# 오프라인 배포를 위한 외부 차트 다운로드 및 관리

set -euo pipefail

# 설정
CHARTS_DIR="helmfile/charts/external"
LOCK_FILE="helmfile/charts/versions.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 색상 출력
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

# Helm 설치 확인
check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "Helm이 설치되지 않았습니다. 먼저 Helm을 설치해주세요."
        exit 1
    fi
    log_info "Helm version: $(helm version --short)"
}

# 디렉토리 생성
create_directories() {
    log_info "차트 디렉토리 생성 중..."
    mkdir -p "$PROJECT_ROOT/$CHARTS_DIR"
    mkdir -p "$(dirname "$PROJECT_ROOT/$LOCK_FILE")"
}

# 차트 정의 (실제 사용 중인 외부 차트)
get_chart_version() {
    case "$1" in
        "prometheus-community/kube-prometheus-stack") echo "61.9.0" ;;
        "fluxcd-community/flux2") echo "2.12.4" ;;
        "harbor/harbor") echo "1.14.2" ;;
        "nvidia/gpu-operator") echo "v24.9.0" ;;
        "bitnami/keycloak") echo "21.4.4" ;;
        *) echo "" ;;
    esac
}

CHART_LIST=(
    "prometheus-community/kube-prometheus-stack"
    "fluxcd-community/flux2"
    "harbor/harbor"
    "nvidia/gpu-operator"
    "bitnami/keycloak"
)

# Repository 추가
add_repositories() {
    log_info "Helm 리포지토리 추가 중..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts || true
    helm repo add harbor https://helm.goharbor.io || true
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
    helm repo add bitnami https://charts.bitnami.com/bitnami || true
    
    log_info "리포지토리 업데이트 중..."
    helm repo update
}

# 단일 차트 다운로드
download_chart() {
    local chart_name="$1"
    local version="$2"
    local chart_dir="$PROJECT_ROOT/$CHARTS_DIR"
    
    log_info "다운로드 중: $chart_name:$version"
    
    # 차트명에서 리포지토리 분리
    local repo_name=$(echo "$chart_name" | cut -d'/' -f1)
    local chart_simple_name=$(echo "$chart_name" | cut -d'/' -f2)
    
    # 버전별 디렉토리 생성
    local target_dir="$chart_dir/${chart_simple_name}-${version}"
    
    if [ -d "$target_dir" ]; then
        log_warn "$chart_simple_name:$version 이미 존재합니다. 건너뛰기..."
        return 0
    fi
    
    # 임시 디렉토리에서 다운로드
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    if helm pull "$chart_name" --version "$version" --untar; then
        # 다운로드된 차트를 목표 디렉토리로 이동
        mv "$chart_simple_name" "$target_dir"
        log_success "다운로드 완료: $chart_name:$version → $target_dir"
        
        # 체크섬 계산
        local checksum=$(find "$target_dir" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
        echo "$chart_name,$version,$checksum,$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PROJECT_ROOT/$LOCK_FILE"
    else
        log_error "$chart_name:$version 다운로드 실패"
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
}

# 모든 차트 다운로드
download_all_charts() {
    log_info "외부 차트 다운로드 시작..."
    
    # versions.lock 파일 초기화
    echo "# Astrago Helm Charts Versions Lock File" > "$PROJECT_ROOT/$LOCK_FILE"
    echo "# Format: chart_name,version,checksum,download_date" >> "$PROJECT_ROOT/$LOCK_FILE"
    echo "# Generated at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PROJECT_ROOT/$LOCK_FILE"
    echo "" >> "$PROJECT_ROOT/$LOCK_FILE"
    
    local success_count=0
    local total_count=${#CHART_LIST[@]}
    
    for chart_name in "${CHART_LIST[@]}"; do
        local version=$(get_chart_version "$chart_name")
        if [ -n "$version" ] && download_chart "$chart_name" "$version"; then
            ((success_count++))
        fi
    done
    
    log_info "다운로드 완료: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        log_success "모든 차트 다운로드 성공!"
        return 0
    else
        log_error "일부 차트 다운로드 실패"
        return 1
    fi
}

# 체크섬 검증
validate_checksums() {
    log_info "차트 무결성 검증 중..."
    
    if [ ! -f "$PROJECT_ROOT/$LOCK_FILE" ]; then
        log_error "versions.lock 파일이 없습니다."
        return 1
    fi
    
    local validation_failed=0
    
    while IFS=',' read -r chart_name version stored_checksum download_date; do
        # 주석과 빈 줄 건너뛰기
        [[ "$chart_name" =~ ^#.*$ ]] || [[ -z "$chart_name" ]] && continue
        
        local chart_simple_name=$(echo "$chart_name" | cut -d'/' -f2)
        local chart_dir="$PROJECT_ROOT/$CHARTS_DIR/${chart_simple_name}-${version}"
        
        if [ ! -d "$chart_dir" ]; then
            log_error "차트 디렉토리가 없습니다: $chart_dir"
            ((validation_failed++))
            continue
        fi
        
        # 현재 체크섬 계산
        local current_checksum=$(find "$chart_dir" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
        
        if [ "$current_checksum" != "$stored_checksum" ]; then
            log_error "체크섬 불일치: $chart_name:$version"
            log_error "  예상: $stored_checksum"
            log_error "  실제: $current_checksum"
            ((validation_failed++))
        else
            log_success "체크섬 검증 통과: $chart_name:$version"
        fi
    done < "$PROJECT_ROOT/$LOCK_FILE"
    
    if [ $validation_failed -eq 0 ]; then
        log_success "모든 차트 무결성 검증 통과!"
        return 0
    else
        log_error "$validation_failed개 차트에서 무결성 검증 실패"
        return 1
    fi
}

# 정리 함수
cleanup() {
    log_info "임시 파일 정리 중..."
    # 임시 디렉토리가 있다면 정리
}

# 도움말 표시
show_help() {
    cat << EOF
Astrago Helm Charts Synchronization Script

사용법:
  $0 [옵션]

옵션:
  download, sync    모든 외부 차트 다운로드
  validate         차트 무결성 검증
  clean           다운로드된 차트 제거
  list            다운로드된 차트 목록 표시
  help, -h        이 도움말 표시

예제:
  $0 download      # 모든 차트 다운로드
  $0 validate      # 차트 검증
  $0 list          # 차트 목록 표시

차트 저장 위치: $CHARTS_DIR/
Lock 파일 위치: $LOCK_FILE
EOF
}

# 차트 목록 표시
list_charts() {
    log_info "다운로드된 차트 목록:"
    
    if [ ! -d "$PROJECT_ROOT/$CHARTS_DIR" ]; then
        log_warn "차트 디렉토리가 없습니다."
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
    
    log_info "총 ${count}개 차트가 저장되어 있습니다."
}

# 정리 함수
clean_charts() {
    log_warn "모든 다운로드된 차트를 제거합니다."
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$PROJECT_ROOT/$CHARTS_DIR"/*
        rm -f "$PROJECT_ROOT/$LOCK_FILE"
        log_success "모든 차트가 제거되었습니다."
    else
        log_info "취소되었습니다."
    fi
}

# 메인 함수
main() {
    cd "$PROJECT_ROOT"
    
    case "${1:-download}" in
        "download"|"sync")
            check_helm
            create_directories
            add_repositories
            download_all_charts
            validate_checksums
            ;;
        "validate")
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
            log_error "알 수 없는 명령어: $1"
            show_help
            exit 1
            ;;
    esac
}

# 시그널 핸들러
trap cleanup EXIT

# 스크립트 실행
main "$@"