#!/bin/bash

# Compare actual deployed images with current image lists
# Exclude kube-system namespace as requested

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGELISTS_DIR="$PROJECT_ROOT/astrago-airgap/astrago/imagelists"
TEMP_DIR=$(mktemp -d)

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Get actual deployed images (excluding kube-system)
get_actual_deployed_images() {
    log "Getting actual deployed images (excluding kube-system)..."
    
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.spec.containers[*].image}{"\n"}{end}' 2>/dev/null | \
        grep -v "^kube-system" | \
        awk '{for(i=2;i<=NF;i++) print $i}' | \
        sort -u > "$TEMP_DIR/actual_deployed.txt"
    
    # Also get init containers
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.spec.initContainers[*].image}{"\n"}{end}' 2>/dev/null | \
        grep -v "^kube-system" | \
        awk '{for(i=2;i<=NF;i++) if($i != "") print $i}' | \
        sort -u >> "$TEMP_DIR/actual_deployed.txt"
    
    # Remove duplicates and empty lines
    sort -u "$TEMP_DIR/actual_deployed.txt" | grep -v '^$' > "$TEMP_DIR/actual_deployed_clean.txt"
    mv "$TEMP_DIR/actual_deployed_clean.txt" "$TEMP_DIR/actual_deployed.txt"
    
    local count=$(wc -l < "$TEMP_DIR/actual_deployed.txt")
    log "Found $count actual deployed images (excluding kube-system)"
}

# Get current image list
get_current_image_list() {
    log "Getting current image list..."
    
    if [[ ! -f "$IMAGELISTS_DIR/images.txt" ]]; then
        error "Image list not found at $IMAGELISTS_DIR/images.txt"
        return 1
    fi
    
    # Extract images from current list (remove comments and empty lines)
    grep -v '^#' "$IMAGELISTS_DIR/images.txt" | \
        grep -v '^$' | \
        sort -u > "$TEMP_DIR/current_list.txt"
    
    local count=$(wc -l < "$TEMP_DIR/current_list.txt")
    log "Found $count images in current list"
}

# Show detailed comparison
show_detailed_comparison() {
    log "Performing detailed comparison..."
    
    local actual_count
    actual_count=$(wc -l < "$TEMP_DIR/actual_deployed.txt")
    local list_count
    list_count=$(wc -l < "$TEMP_DIR/current_list.txt")
    
    # Find missing images (in deployment but not in list)
    comm -23 "$TEMP_DIR/actual_deployed.txt" "$TEMP_DIR/current_list.txt" > "$TEMP_DIR/missing_images.txt"
    local missing_count
    missing_count=$(wc -l < "$TEMP_DIR/missing_images.txt")
    
    # Find extra images (in list but not deployed)
    comm -13 "$TEMP_DIR/actual_deployed.txt" "$TEMP_DIR/current_list.txt" > "$TEMP_DIR/extra_images.txt"
    local extra_count
    extra_count=$(wc -l < "$TEMP_DIR/extra_images.txt")
    
    # Find common images
    comm -12 "$TEMP_DIR/actual_deployed.txt" "$TEMP_DIR/current_list.txt" > "$TEMP_DIR/common_images.txt"
    local common_count
    common_count=$(wc -l < "$TEMP_DIR/common_images.txt")
    
    echo -e "\n${BLUE}=== 이미지 비교 결과 (kube-system 제외) ===${NC}"
    echo "실제 배포된 이미지: $actual_count개"
    echo "현재 리스트 이미지: $list_count개"
    echo "공통 이미지: $common_count개"
    echo ""
    
    if [[ $missing_count -gt 0 ]]; then
        echo -e "${RED}❌ 누락된 이미지 ($missing_count개):${NC}"
        echo "   (실제 배포되었지만 리스트에 없음)"
        cat "$TEMP_DIR/missing_images.txt" | sed 's/^/   /'
        echo ""
    else
        echo -e "${GREEN}✅ 누락된 이미지: 없음${NC}"
        echo ""
    fi
    
    if [[ $extra_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  추가 이미지 ($extra_count개):${NC}"
        echo "   (리스트에는 있지만 현재 배포되지 않음)"
        cat "$TEMP_DIR/extra_images.txt" | sed 's/^/   /'
        echo ""
    fi
    
    # Accuracy calculation
    if [[ $actual_count -gt 0 ]]; then
        local accuracy=$((common_count * 100 / actual_count))
        echo -e "📊 정확도: ${accuracy}% ($common_count/$actual_count 매치)"
        echo ""
    fi
}

# Show namespace breakdown
show_namespace_breakdown() {
    log "Showing namespace breakdown..."
    
    echo -e "${BLUE}=== 네임스페이스별 배포 현황 ===${NC}"
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | \
        grep -v "^kube-system" | \
        sort | uniq -c | sort -nr | \
        awk '{printf "  %-20s: %s pods\n", $2, $1}'
    echo ""
}

# Analyze missing images by category
analyze_missing_by_category() {
    if [[ ! -s "$TEMP_DIR/missing_images.txt" ]]; then
        return 0
    fi
    
    log "Analyzing missing images by category..."
    
    echo -e "${RED}=== 누락 이미지 분석 ===${NC}"
    
    # GPU/NVIDIA images
    local gpu_missing=$(grep -E "(nvidia|gpu)" "$TEMP_DIR/missing_images.txt" | wc -l)
    if [[ $gpu_missing -gt 0 ]]; then
        echo "🎯 GPU/NVIDIA 관련: $gpu_missing개"
        grep -E "(nvidia|gpu)" "$TEMP_DIR/missing_images.txt" | sed 's/^/   /'
        echo ""
    fi
    
    # Prometheus/Monitoring images
    local monitoring_missing=$(grep -E "(prometheus|grafana|alert)" "$TEMP_DIR/missing_images.txt" | wc -l)
    if [[ $monitoring_missing -gt 0 ]]; then
        echo "📊 모니터링 관련: $monitoring_missing개"
        grep -E "(prometheus|grafana|alert)" "$TEMP_DIR/missing_images.txt" | sed 's/^/   /'
        echo ""
    fi
    
    # Kubernetes registry images
    local k8s_missing=$(grep -E "^registry\.k8s\.io" "$TEMP_DIR/missing_images.txt" | wc -l)
    if [[ $k8s_missing -gt 0 ]]; then
        echo "☸️  Kubernetes 관련: $k8s_missing개"
        grep -E "^registry\.k8s\.io" "$TEMP_DIR/missing_images.txt" | sed 's/^/   /'
        echo ""
    fi
    
    # Network/CNI images
    local network_missing=$(grep -E "(calico|flannel|cilium|weave)" "$TEMP_DIR/missing_images.txt" | wc -l)
    if [[ $network_missing -gt 0 ]]; then
        echo "🌐 네트워킹 관련: $network_missing개"
        grep -E "(calico|flannel|cilium|weave)" "$TEMP_DIR/missing_images.txt" | sed 's/^/   /'
        echo ""
    fi
    
    # Other images
    local other_missing=$(wc -l < "$TEMP_DIR/missing_images.txt")
    local categorized=$((gpu_missing + monitoring_missing + k8s_missing + network_missing))
    local other=$((other_missing - categorized))
    if [[ $other -gt 0 ]]; then
        echo "🔧 기타: $other개"
        grep -v -E "(nvidia|gpu|prometheus|grafana|alert|registry\.k8s\.io|calico|flannel|cilium|weave)" "$TEMP_DIR/missing_images.txt" | sed 's/^/   /'
        echo ""
    fi
}

# Generate recommendations
generate_recommendations() {
    echo -e "${BLUE}=== 권장사항 ===${NC}"
    
    local missing_count=$(wc -l < "$TEMP_DIR/missing_images.txt" 2>/dev/null || echo 0)
    local extra_count=$(wc -l < "$TEMP_DIR/extra_images.txt" 2>/dev/null || echo 0)
    
    if [[ $missing_count -eq 0 ]]; then
        echo "✅ 완벽함: 모든 배포된 이미지가 리스트에 포함되어 있습니다"
        echo "🎯 폐쇄망 배포를 위한 준비가 완료되었습니다"
    else
        echo "🔧 $missing_count개 이미지를 리스트에 추가해야 합니다"
        echo "💡 대부분 GPU Operator나 동적 생성되는 이미지들일 가능성이 높습니다"
    fi
    
    if [[ $extra_count -gt 0 ]]; then
        echo "ℹ️  $extra_count개 추가 이미지가 포함되어 있습니다 (테스트/유틸리티 용도 가능)"
    fi
    
    echo ""
}

# Save results for further analysis
save_results() {
    log "Saving comparison results..."
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local results_dir="$PROJECT_ROOT/astrago-airgap/comparison_results_$timestamp"
    mkdir -p "$results_dir"
    
    cp "$TEMP_DIR/actual_deployed.txt" "$results_dir/"
    cp "$TEMP_DIR/current_list.txt" "$results_dir/"
    cp "$TEMP_DIR/missing_images.txt" "$results_dir/" 2>/dev/null || touch "$results_dir/missing_images.txt"
    cp "$TEMP_DIR/extra_images.txt" "$results_dir/" 2>/dev/null || touch "$results_dir/extra_images.txt"
    cp "$TEMP_DIR/common_images.txt" "$results_dir/" 2>/dev/null || touch "$results_dir/common_images.txt"
    
    log "Results saved to $results_dir/"
}

# Main execution
main() {
    echo -e "${GREEN}🔍 이미지 비교 분석 시작...${NC}\n"
    
    get_actual_deployed_images
    get_current_image_list
    show_namespace_breakdown
    show_detailed_comparison
    analyze_missing_by_category
    generate_recommendations
    save_results
    
    echo -e "${GREEN}✨ 이미지 비교 분석 완료!${NC}"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi