#!/bin/bash

# Uyuni Theme Integration Test Script
# 사용법: ./scripts/test-uyuni-integration.sh [environment] [version]

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 기본값 설정
ENVIRONMENT=${1:-dev}
VERSION=${2:-latest}
UYUNI_REPO="https://github.com/xiilab/keycloak-theme-uyuni.git"

# 환경 검증
validate_environment() {
    local valid_envs=("dev" "dev2" "stage" "prod")
    if [[ ! " ${valid_envs[@]} " =~ " ${ENVIRONMENT} " ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log_info "Valid environments: ${valid_envs[*]}"
        exit 1
    fi
}

# uyuni 레포지토리 체크아웃
checkout_uyuni_repo() {
    log_info "Checking out uyuni theme repository..."
    
    if [ -d "uyuni-theme" ]; then
        rm -rf uyuni-theme
    fi
    
    git clone $UYUNI_REPO uyuni-theme
    cd uyuni-theme
    
    if [ "$VERSION" != "latest" ]; then
        git checkout $VERSION
    fi
    
    cd ..
    log_success "Uyuni theme repository checked out"
}

# 테마 버전 추출
extract_theme_version() {
    log_info "Extracting theme version..."
    
    cd uyuni-theme
    
    if [ "$VERSION" = "latest" ]; then
        # Get latest tag or commit hash
        THEME_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || git rev-parse --short HEAD)
    else
        THEME_VERSION="$VERSION"
    fi
    
    cd ..
    
    log_success "Theme version: $THEME_VERSION"
    echo $THEME_VERSION
}

# values.yaml 업데이트 테스트
test_values_update() {
    log_info "Testing values.yaml update..."
    
    local theme_version=$1
    
    # Backup original values file
    cp environments/$ENVIRONMENT/values.yaml environments/$ENVIRONMENT/values.yaml.backup
    
    # Update theme version
    yq eval ".keycloak.themeVersion = \"$theme_version\"" -i environments/$ENVIRONMENT/values.yaml
    
    # Verify update
    local updated_version=$(yq eval ".keycloak.themeVersion" environments/$ENVIRONMENT/values.yaml)
    
    if [ "$updated_version" = "$theme_version" ]; then
        log_success "Values.yaml updated successfully"
    else
        log_error "Values.yaml update failed"
        # Restore backup
        mv environments/$ENVIRONMENT/values.yaml.backup environments/$ENVIRONMENT/values.yaml
        exit 1
    fi
    
    # Restore backup
    mv environments/$ENVIRONMENT/values.yaml.backup environments/$ENVIRONMENT/values.yaml
}

# monochart 생성 테스트
test_monochart_generation() {
    log_info "Testing monochart generation..."
    
    # Check if Helmfile is available
    if ! command -v helmfile &> /dev/null; then
        log_info "Installing Helmfile..."
        wget https://github.com/helmfile/helmfile/releases/download/v0.159.0/helmfile_0.159.0_linux_amd64.tar.gz -P /tmp/
        tar -zxvf /tmp/helmfile_0.159.0_linux_amd64.tar.gz -C /tmp/
        chmod +x /tmp/helmfile
        sudo mv /tmp/helmfile /usr/local/bin
    fi
    
    # Backup original monochart file
    if [ -f "monochart/$ENVIRONMENT/keycloak/keycloak.yaml" ]; then
        cp monochart/$ENVIRONMENT/keycloak/keycloak.yaml monochart/$ENVIRONMENT/keycloak/keycloak.yaml.backup
    fi
    
    # Generate monochart
    helmfile -e $ENVIRONMENT -l app=keycloak template > monochart/$ENVIRONMENT/keycloak/keycloak.yaml
    
    # Verify generation
    if [ -s "monochart/$ENVIRONMENT/keycloak/keycloak.yaml" ]; then
        log_success "Monochart generated successfully"
        
        # Check if it contains Keycloak configuration
        if grep -q "kind: StatefulSet" monochart/$ENVIRONMENT/keycloak/keycloak.yaml; then
            log_success "Monochart contains valid Keycloak configuration"
        else
            log_warning "Monochart may not contain expected Keycloak configuration"
        fi
    else
        log_error "Monochart generation failed"
        # Restore backup
        if [ -f "monochart/$ENVIRONMENT/keycloak/keycloak.yaml.backup" ]; then
            mv monochart/$ENVIRONMENT/keycloak/keycloak.yaml.backup monochart/$ENVIRONMENT/keycloak/keycloak.yaml
        fi
        exit 1
    fi
    
    # Restore backup
    if [ -f "monochart/$ENVIRONMENT/keycloak/keycloak.yaml.backup" ]; then
        mv monochart/$ENVIRONMENT/keycloak/keycloak.yaml.backup monochart/$ENVIRONMENT/keycloak/keycloak.yaml
    fi
}

# 전체 통합 테스트
run_integration_test() {
    log_info "Running uyuni theme integration test"
    log_info "Environment: $ENVIRONMENT"
    log_info "Version: $VERSION"
    
    # 환경 검증
    validate_environment
    
    # uyuni 레포지토리 체크아웃
    checkout_uyuni_repo
    
    # 테마 버전 추출
    local theme_version=$(extract_theme_version)
    
    # values.yaml 업데이트 테스트
    test_values_update $theme_version
    
    # monochart 생성 테스트
    test_monochart_generation
    
    log_success "All integration tests passed!"
    log_info "Theme version: $theme_version"
    log_info "Environment: $ENVIRONMENT"
}

# 메인 실행
main() {
    run_integration_test
}

# 스크립트 실행
main "$@" 