#!/bin/bash

# Enhanced image synchronization with multiple sources
# Combines helmfile template + static lists for complete coverage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AIRGAP_DIR="$PROJECT_ROOT/astrago-airgap"
HELMFILE_DIR="$PROJECT_ROOT/helmfile"
KUBESPRAY_DIR="$PROJECT_ROOT/kubespray"
IMAGELISTS_DIR="$AIRGAP_DIR/astrago/imagelists"
TEMP_DIR=$(mktemp -d)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Update helm chart dependencies
update_chart_dependencies() {
    local chart_path="$1"
    if [[ -f "$chart_path/Chart.yaml" ]]; then
        log "Updating dependencies for $(basename "$chart_path")"
        helm dependency update "$chart_path" 2>/dev/null || warn "Failed to update dependencies for $chart_path"
    fi
}

# Extract images from helmfile template (existing function)
extract_helmfile_images() {
    log "Extracting images from helmfile template with dependencies..."
    
    cd "$HELMFILE_DIR"
    
    # Update dependencies for all charts
    find "$HELMFILE_DIR" -name "Chart.yaml" -type f | while read -r chart_file; do
        chart_dir=$(dirname "$chart_file")
        update_chart_dependencies "$chart_dir"
    done
    
    # Generate complete template without --skip-deps
    log "Generating complete helmfile template..."
    helmfile template --environment default > "$TEMP_DIR/complete_template.yaml" 2>/dev/null || {
        error "Failed to generate helmfile template"
        return 1
    }
    
    log "Extracting image references from template..."
    
    # Pattern 1: Standard image: "value" format
    grep -E 'image:[[:space:]]*"[^"]*"' "$TEMP_DIR/complete_template.yaml" | \
        sed 's/.*image:[[:space:]]*"\([^"]*\)".*/\1/' > "$TEMP_DIR/images_pattern1.txt"
    
    # Pattern 2: Image without quotes
    grep -E 'image:[[:space:]]*[^"[:space:]]+' "$TEMP_DIR/complete_template.yaml" | \
        grep -v 'image:[[:space:]]*"' | \
        sed 's/.*image:[[:space:]]*\([^[:space:]]*\).*/\1/' > "$TEMP_DIR/images_pattern2.txt"
    
    # Pattern 3: Repository + tag combinations
    awk 'BEGIN { repo=""; tag=""; registry="" }
    /repository:[[:space:]]*/ { 
        match($0, /repository:[[:space:]]*"?([^"[:space:]]*)"?/, arr)
        repo = arr[1]
    }
    /registry:[[:space:]]*/ {
        match($0, /registry:[[:space:]]*"?([^"[:space:]]*)"?/, arr) 
        registry = arr[1]
    }
    /tag:[[:space:]]*/ { 
        match($0, /tag:[[:space:]]*"?([^"[:space:]]*)"?/, arr)
        tag = arr[1]
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
    }' "$TEMP_DIR/complete_template.yaml" > "$TEMP_DIR/images_pattern3.txt"
    
    # Combine all patterns
    cat "$TEMP_DIR/images_pattern1.txt" \
        "$TEMP_DIR/images_pattern2.txt" \
        "$TEMP_DIR/images_pattern3.txt" | \
        grep -v '^$' | \
        sort -u > "$TEMP_DIR/helmfile_images.txt"
    
    local count=$(wc -l < "$TEMP_DIR/helmfile_images.txt")
    log "Extracted $count images from helmfile template"
}

# Add static Kubernetes system images
add_kubernetes_images() {
    log "Adding Kubernetes system images..."
    
    # Get K8s version from kubespray
    local k8s_version
    if [[ -f "$KUBESPRAY_DIR/inventory/sample/group_vars/k8s_cluster/k8s-cluster.yml" ]]; then
        k8s_version=$(grep "kube_version:" "$KUBESPRAY_DIR/inventory/sample/group_vars/k8s_cluster/k8s-cluster.yml" | cut -d'"' -f2 || echo "v1.28.10")
    else
        k8s_version="v1.28.10"
    fi
    
    cat > "$TEMP_DIR/k8s_images.txt" << EOF
registry.k8s.io/kube-apiserver:$k8s_version
registry.k8s.io/kube-controller-manager:$k8s_version
registry.k8s.io/kube-scheduler:$k8s_version
registry.k8s.io/kube-proxy:$k8s_version
registry.k8s.io/coredns/coredns:v1.10.1
registry.k8s.io/dns/k8s-dns-node-cache:1.22.28
registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.8.8
EOF
    
    log "Added $(wc -l < "$TEMP_DIR/k8s_images.txt") Kubernetes system images"
}

# Add Calico CNI images
add_calico_images() {
    log "Adding Calico CNI images..."
    
    # Try to extract from kubespray defaults
    local calico_version="v3.26.4"
    if [[ -f "$KUBESPRAY_DIR/roles/network_plugin/calico/defaults/main.yml" ]]; then
        calico_version=$(grep "calico_version:" "$KUBESPRAY_DIR/roles/network_plugin/calico/defaults/main.yml" | cut -d'"' -f2 || echo "v3.26.4")
    fi
    
    cat > "$TEMP_DIR/calico_images.txt" << EOF
quay.io/calico/node:$calico_version
quay.io/calico/kube-controllers:$calico_version
EOF
    
    log "Added $(wc -l < "$TEMP_DIR/calico_images.txt") Calico CNI images"
}

# Enhanced GPU Operator image extraction
add_gpu_operator_images() {
    log "Adding comprehensive GPU Operator images..."
    
    # Static list of common NVIDIA images based on gpu-operator v24.9.0
    cat > "$TEMP_DIR/gpu_operator_images.txt" << EOF
nvcr.io/nvidia/gpu-operator:v24.9.0
nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.0
nvcr.io/nvidia/driver:550.127.05-ubuntu22.04
nvcr.io/nvidia/k8s-device-plugin:v0.17.0-ubi9
nvcr.io/nvidia/k8s/container-toolkit:v1.17.0-ubuntu20.04
nvcr.io/nvidia/k8s/dcgm-exporter:3.3.8-3.6.0-ubuntu22.04
EOF
    
    log "Added $(wc -l < "$TEMP_DIR/gpu_operator_images.txt") GPU Operator images"
}

# Add missing prometheus components
add_prometheus_missing() {
    log "Adding missing Prometheus components..."
    
    cat > "$TEMP_DIR/prometheus_missing.txt" << EOF
quay.io/prometheus-operator/prometheus-config-reloader:v0.75.2
EOF
    
    log "Added $(wc -l < "$TEMP_DIR/prometheus_missing.txt") missing Prometheus images"
}

# Categorize and save images
categorize_and_save_images() {
    log "Categorizing and saving images..."
    
    # Combine all sources
    cat "$TEMP_DIR/helmfile_images.txt" \
        "$TEMP_DIR/k8s_images.txt" \
        "$TEMP_DIR/calico_images.txt" \
        "$TEMP_DIR/gpu_operator_images.txt" \
        "$TEMP_DIR/prometheus_missing.txt" | \
        sort -u > "$TEMP_DIR/all_images.txt"
    
    local total_count=$(wc -l < "$TEMP_DIR/all_images.txt")
    log "Total unique images: $total_count"
    
    # Create categorized lists
    mkdir -p "$IMAGELISTS_DIR"
    
    # Generate master list
    {
        echo "# Auto-generated with dependencies on $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Source: helmfile template + static K8s/Calico/GPU images"
        echo ""
        cat "$TEMP_DIR/all_images.txt"
        echo ""
        echo ""
    } > "$IMAGELISTS_DIR/images.txt"
    
    # Individual service lists
    grep "astrago" "$TEMP_DIR/all_images.txt" > "$TEMP_DIR/astrago_images.txt" || true
    grep "harbor" "$TEMP_DIR/all_images.txt" > "$TEMP_DIR/harbor_images.txt" || true  
    grep "flux" "$TEMP_DIR/all_images.txt" > "$TEMP_DIR/flux_images.txt" || true
    grep "keycloak\|postgresql" "$TEMP_DIR/all_images.txt" > "$TEMP_DIR/keycloak_images.txt" || true
    grep "prometheus\|grafana\|alertmanager" "$TEMP_DIR/all_images.txt" > "$TEMP_DIR/prometheus_images.txt" || true
    grep "nvidia\|gpu" "$TEMP_DIR/all_images.txt" > "$TEMP_DIR/gpu_images.txt" || true
    grep "registry.k8s.io\|calico" "$TEMP_DIR/all_images.txt" > "$TEMP_DIR/system_images.txt" || true
    
    # Save individual lists with headers
    for category in astrago harbor flux keycloak prometheus gpu system; do
        local file="$IMAGELISTS_DIR/${category}.txt"
        local temp_file="$TEMP_DIR/${category}_images.txt"
        
        if [[ -s "$temp_file" ]]; then
            {
                echo "# Auto-generated with dependencies on $(date '+%Y-%m-%d %H:%M:%S')"
                echo "# Source: helmfile template + static images"
                echo ""
                cat "$temp_file"
                echo ""
                echo ""
            } > "$file"
            log "Saved $(wc -l < "$temp_file") images to $category.txt"
        fi
    done
    
    log "Image categorization complete!"
}

# Main execution
main() {
    log "Starting complete image synchronization..."
    
    extract_helmfile_images
    add_kubernetes_images
    add_calico_images  
    add_gpu_operator_images
    add_prometheus_missing
    categorize_and_save_images
    
    log "Complete image synchronization finished!"
    log "Check $IMAGELISTS_DIR for updated image lists"
    
    # Show summary
    echo -e "\n${BLUE}=== IMAGE SUMMARY ===${NC}"
    echo "Total images: $(grep -v '^#' "$IMAGELISTS_DIR/images.txt" | grep -v '^$' | wc -l)"
    echo "By category:"
    for file in "$IMAGELISTS_DIR"/*.txt; do
        [[ "$file" == "$IMAGELISTS_DIR/images.txt" ]] && continue
        local basename=$(basename "$file" .txt)
        local count=$(grep -v '^#' "$file" 2>/dev/null | grep -v '^$' | wc -l || echo 0)
        echo "  $basename: $count images"
    done
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi