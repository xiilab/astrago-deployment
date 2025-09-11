#!/bin/bash

# Fix 6 missing images by adding them to the image lists
# Based on values.yaml parsing for GPU Operator and prometheus-config-reloader

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGELISTS_DIR="$PROJECT_ROOT/astrago-airgap/astrago/imagelists"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Add missing images based on actual deployed versions
add_missing_images() {
    log "Adding 6 missing images..."
    
    # Missing GPU Operator images (from actual deployment)
    local gpu_missing=(
        "nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.0"
        "nvcr.io/nvidia/driver:550.127.05-ubuntu22.04"
        "nvcr.io/nvidia/k8s-device-plugin:v0.17.0-ubi9"
        "nvcr.io/nvidia/k8s/container-toolkit:v1.17.0-ubuntu20.04" 
        "nvcr.io/nvidia/k8s/dcgm-exporter:3.3.8-3.6.0-ubuntu22.04"
    )
    
    # Missing prometheus config reloader (from kube-prometheus-stack values)
    local prometheus_missing=(
        "quay.io/prometheus-operator/prometheus-config-reloader:v0.75.2"
    )
    
    # Add to main images.txt
    log "Updating main images.txt..."
    {
        # Remove trailing empty lines and add new images
        sed '/^$/d' "$IMAGELISTS_DIR/images.txt"
        printf "%s\n" "${gpu_missing[@]}"
        printf "%s\n" "${prometheus_missing[@]}"
        echo ""
        echo ""
    } > "$IMAGELISTS_DIR/images.txt.new"
    mv "$IMAGELISTS_DIR/images.txt.new" "$IMAGELISTS_DIR/images.txt"
    
    # Update GPU operator list
    if [[ -f "$IMAGELISTS_DIR/gpu-operator.txt" ]]; then
        log "Updating gpu-operator.txt..."
        {
            sed '/^$/d' "$IMAGELISTS_DIR/gpu-operator.txt"
            printf "%s\n" "${gpu_missing[@]}"
            echo ""
            echo ""
        } > "$IMAGELISTS_DIR/gpu-operator.txt.new"
        mv "$IMAGELISTS_DIR/gpu-operator.txt.new" "$IMAGELISTS_DIR/gpu-operator.txt"
    else
        log "Creating gpu-operator.txt..."
        {
            echo "# Auto-generated GPU Operator images on $(date '+%Y-%m-%d %H:%M:%S')"
            echo "# Source: values.yaml parsing + actual deployment"
            echo ""
            echo "nvcr.io/nvidia/gpu-operator:v24.9.0"
            printf "%s\n" "${gpu_missing[@]}"
            echo ""
            echo ""
        } > "$IMAGELISTS_DIR/gpu-operator.txt"
    fi
    
    # Update prometheus list
    if [[ -f "$IMAGELISTS_DIR/prometheus.txt" ]]; then
        log "Updating prometheus.txt..."
        {
            sed '/^$/d' "$IMAGELISTS_DIR/prometheus.txt"
            printf "%s\n" "${prometheus_missing[@]}"
            echo ""
            echo ""
        } > "$IMAGELISTS_DIR/prometheus.txt.new"
        mv "$IMAGELISTS_DIR/prometheus.txt.new" "$IMAGELISTS_DIR/prometheus.txt"
    fi
    
    log "Added ${#gpu_missing[@]} GPU Operator images"
    log "Added ${#prometheus_missing[@]} Prometheus images"
}

# Verify the fix
verify_fix() {
    log "Verifying the fix..."
    
    # Get current actual images (excluding kube-system)
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.spec.containers[*].image}{"\n"}{end}' | \
        grep -v "^kube-system" | \
        awk '{for(i=2;i<=NF;i++) print $i}' | \
        sort -u > /tmp/current_actual_images.txt
    
    # Get updated template images
    grep -v '^#' "$IMAGELISTS_DIR/images.txt" | grep -v '^$' | sort > /tmp/updated_template_images.txt
    
    local actual_count=$(wc -l < /tmp/current_actual_images.txt)
    local template_count=$(wc -l < /tmp/updated_template_images.txt) 
    
    # Check for missing images
    local missing_count=$(comm -23 /tmp/current_actual_images.txt /tmp/updated_template_images.txt | wc -l)
    
    echo -e "\n${BLUE}=== 수정 결과 검증 ===${NC}"
    echo "실제 배포된 이미지: $actual_count개"
    echo "Template 이미지: $template_count개"
    echo "누락된 이미지: $missing_count개"
    
    if [[ $missing_count -eq 0 ]]; then
        echo -e "\n${GREEN}✅ 성공: 모든 이미지가 일치합니다!${NC}"
    else
        echo -e "\n${YELLOW}⚠️  아직 누락된 이미지가 있습니다:${NC}"
        comm -23 /tmp/current_actual_images.txt /tmp/updated_template_images.txt
    fi
    
    # Show excess images (in template but not deployed)
    local excess_count=$(comm -13 /tmp/current_actual_images.txt /tmp/updated_template_images.txt | wc -l)
    if [[ $excess_count -gt 0 ]]; then
        echo -e "\n${YELLOW}ℹ️  Template에만 있는 이미지 (테스트/유틸리티): $excess_count개${NC}"
        comm -13 /tmp/current_actual_images.txt /tmp/updated_template_images.txt | head -5
    fi
}

# Show summary
show_summary() {
    echo -e "\n${BLUE}=== 최종 이미지 현황 ===${NC}"
    
    local total_images=$(grep -v '^#' "$IMAGELISTS_DIR/images.txt" | grep -v '^$' | wc -l)
    echo "전체 이미지: $total_images개"
    
    echo -e "\n카테고리별:"
    for file in "$IMAGELISTS_DIR"/*.txt; do
        [[ "$file" == "$IMAGELISTS_DIR/images.txt" ]] && continue
        local basename=$(basename "$file" .txt)
        local count=$(grep -v '^#' "$file" 2>/dev/null | grep -v '^$' | wc -l || echo 0)
        [[ $count -gt 0 ]] && echo "  $basename: $count개"
    done
    
    echo -e "\n${GREEN}🎯 폐쇄망을 위한 완전한 이미지 리스트가 준비되었습니다!${NC}"
}

# Main execution
main() {
    log "6개 누락 이미지 수정 시작..."
    
    add_missing_images
    verify_fix
    show_summary
    
    log "누락 이미지 수정 완료!"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi