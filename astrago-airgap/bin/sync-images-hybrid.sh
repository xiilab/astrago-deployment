#!/bin/bash

# Hybrid approach: Template for most charts + Values for GPU Operator
# Excludes kube-system images, focuses on pure helmfile applications

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AIRGAP_DIR="$PROJECT_ROOT/astrago-airgap"
HELMFILE_DIR="$PROJECT_ROOT/helmfile"
IMAGELISTS_DIR="$AIRGAP_DIR/astrago/imagelists"
TEMP_DIR=$(mktemp -d)

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Extract images from helmfile template (existing dependency-aware method)
extract_template_images() {
    log "Extracting images from helmfile template..."
    
    cd "$HELMFILE_DIR"
    
    # Update dependencies for all charts
    find "$HELMFILE_DIR" -name "Chart.yaml" -type f | while read -r chart_file; do
        chart_dir=$(dirname "$chart_file")
        if [[ -f "$chart_dir/Chart.yaml" ]]; then
            helm dependency update "$chart_dir" 2>/dev/null || true
        fi
    done
    
    # Generate complete template without --skip-deps
    log "Generating complete helmfile template..."
    helmfile template --environment default > "$TEMP_DIR/complete_template.yaml" 2>/dev/null || {
        error "Failed to generate helmfile template"
        return 1
    }
    
    # Extract image references using proven patterns
    {
        # Pattern 1: Standard image: "value" format
        grep -E 'image:[[:space:]]*"[^"]*"' "$TEMP_DIR/complete_template.yaml" | \
            sed 's/.*image:[[:space:]]*"\([^"]*\)".*/\1/'
        
        # Pattern 2: Image without quotes
        grep -E 'image:[[:space:]]*[^"[:space:]]+' "$TEMP_DIR/complete_template.yaml" | \
            grep -v 'image:[[:space:]]*"' | \
            sed 's/.*image:[[:space:]]*\([^[:space:]]*\).*/\1/'
        
        # Pattern 3: Repository + tag combinations
        awk 'BEGIN { repo=""; tag=""; registry="" }
        /repository:[[:space:]]*/ { 
            gsub(/.*repository:[[:space:]]*"?/, "")
            gsub(/"?[[:space:]]*$/, "")
            repo = $0
        }
        /registry:[[:space:]]*/ {
            gsub(/.*registry:[[:space:]]*"?/, "")
            gsub(/"?[[:space:]]*$/, "")
            registry = $0
        }
        /tag:[[:space:]]*/ { 
            gsub(/.*tag:[[:space:]]*"?/, "")
            gsub(/"?[[:space:]]*$/, "")
            tag = $0
            if (repo != "" && tag != "") {
                if (registry != "" && repo !~ /^[^\/]*\./) {
                    print registry "/" repo ":" tag
                } else if (repo ~ /^[^\/]*\./) {
                    print repo ":" tag  
                } else {
                    print "docker.io/" repo ":" tag
                }
                repo=""; tag=""; registry=""
            }
        }' "$TEMP_DIR/complete_template.yaml"
    } | sort -u > "$TEMP_DIR/template_images.txt"
    
    local count=$(wc -l < "$TEMP_DIR/template_images.txt")
    log "Extracted $count images from template"
}

# Extract missing GPU Operator images from values
extract_gpu_operator_images() {
    log "Extracting GPU Operator images from values..."
    
    # GPU Operator specific images with actual versions
    cat > "$TEMP_DIR/gpu_operator_images.txt" << 'EOF'
nvcr.io/nvidia/gpu-operator:v24.9.0
nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.0
nvcr.io/nvidia/driver:550.127.05-ubuntu22.04
nvcr.io/nvidia/k8s-device-plugin:v0.17.0-ubi9
nvcr.io/nvidia/k8s/container-toolkit:v1.17.0-ubuntu20.04
nvcr.io/nvidia/k8s/dcgm-exporter:3.3.8-3.6.0-ubuntu22.04
EOF
    
    local count=$(wc -l < "$TEMP_DIR/gpu_operator_images.txt")
    log "Added $count GPU Operator images"
}

# Filter out kube-system images
filter_kube_system_images() {
    log "Filtering out kube-system images..."
    
    # Remove Kubernetes system images that kubespray manages
    grep -v -E '^registry\.k8s\.io/(kube-apiserver|kube-controller-manager|kube-scheduler|kube-proxy|coredns|dns|cpa)' \
        "$TEMP_DIR/template_images.txt" > "$TEMP_DIR/template_filtered.txt" || true
    
    # Remove Calico CNI (managed by kubespray)
    grep -v -E '^quay\.io/calico/' \
        "$TEMP_DIR/template_filtered.txt" > "$TEMP_DIR/template_clean.txt" || true
    
    local original_count=$(wc -l < "$TEMP_DIR/template_images.txt")
    local filtered_count=$(wc -l < "$TEMP_DIR/template_clean.txt")
    local removed_count=$((original_count - filtered_count))
    
    log "Filtered out $removed_count kube-system images ($filtered_count remaining)"
}

# Combine and categorize
combine_and_categorize() {
    log "Combining template and GPU Operator images..."
    
    # Combine all sources
    cat "$TEMP_DIR/template_clean.txt" \
        "$TEMP_DIR/gpu_operator_images.txt" | \
        sort -u > "$TEMP_DIR/final_images.txt"
    
    local total_count=$(wc -l < "$TEMP_DIR/final_images.txt")
    log "Total hybrid images: $total_count"
    
    # Create output directory
    mkdir -p "$IMAGELISTS_DIR"
    
    # Generate master list
    {
        echo "# Auto-generated hybrid approach on $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Source: helmfile template (filtered) + GPU operator values"
        echo ""
        cat "$TEMP_DIR/final_images.txt"
        echo ""
        echo ""
    } > "$IMAGELISTS_DIR/images.txt"
    
    # Individual service lists
    grep "astrago" "$TEMP_DIR/final_images.txt" | grep -v "harbor\|keycloak" > "$TEMP_DIR/astrago_images.txt" || true
    grep "harbor" "$TEMP_DIR/final_images.txt" > "$TEMP_DIR/harbor_images.txt" || true  
    grep "flux" "$TEMP_DIR/final_images.txt" > "$TEMP_DIR/flux_images.txt" || true
    grep "keycloak\|postgresql" "$TEMP_DIR/final_images.txt" > "$TEMP_DIR/keycloak_images.txt" || true
    grep "prometheus\|grafana\|alertmanager" "$TEMP_DIR/final_images.txt" > "$TEMP_DIR/prometheus_images.txt" || true
    grep "nvidia\|gpu" "$TEMP_DIR/final_images.txt" > "$TEMP_DIR/gpu_images.txt" || true
    
    # Save individual lists with headers
    for category in astrago harbor flux keycloak prometheus gpu-operator; do
        local file="$IMAGELISTS_DIR/${category}.txt"
        local temp_file="$TEMP_DIR/${category/gpu-operator/gpu}_images.txt"
        
        if [[ -s "$temp_file" ]]; then
            {
                echo "# Auto-generated hybrid approach on $(date '+%Y-%m-%d %H:%M:%S')"
                echo "# Source: helmfile template + values (GPU operator)"
                echo ""
                cat "$temp_file"
                echo ""
                echo ""
            } > "$file"
            log "Saved $(wc -l < "$temp_file") images to $category.txt"
        fi
    done
}

# Show summary
show_summary() {
    echo -e "\n${BLUE}=== HYBRID APPROACH SUMMARY ===${NC}"
    echo "✅ Template approach: All standard charts (astrago, flux, harbor, etc.)"
    echo "✅ Values approach: GPU Operator only"
    echo "✅ Filtered out: kube-system images (managed by kubespray)"
    echo ""
    echo "Total images: $(grep -v '^#' "$IMAGELISTS_DIR/images.txt" | grep -v '^$' | wc -l)"
    echo ""
    echo "By category:"
    for file in "$IMAGELISTS_DIR"/*.txt; do
        [[ "$file" == "$IMAGELISTS_DIR/images.txt" ]] && continue
        local basename=$(basename "$file" .txt)
        local count=$(grep -v '^#' "$file" 2>/dev/null | grep -v '^$' | wc -l || echo 0)
        [[ $count -gt 0 ]] && echo "  $basename: $count images"
    done
    echo ""
    echo "🎯 Pure helmfile applications only, no kube-system dependencies"
}

# Main execution
main() {
    log "Starting hybrid image synchronization..."
    
    extract_template_images
    filter_kube_system_images
    extract_gpu_operator_images
    combine_and_categorize
    show_summary
    
    log "Hybrid image synchronization complete!"
    log "Check $IMAGELISTS_DIR for updated image lists"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi