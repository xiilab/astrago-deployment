#!/bin/bash

# Extract images from helmfile values.yaml files
# This approach reads values directly without rendering templates

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELMFILE_DIR="$PROJECT_ROOT/helmfile"
IMAGELISTS_DIR="$PROJECT_ROOT/astrago-airgap/astrago/imagelists"
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

# Parse template variables and resolve values
resolve_template_vars() {
    local input_file="$1"
    local output_file="$2"
    
    # Simple template variable resolution
    # This is a basic implementation - may need enhancement for complex templates
    
    # First pass: resolve basic .Values references
    sed -e 's/{{ \.Values\.offline\.registry | default "\([^"]*\)" }}/\1/g' \
        -e 's/{{ \.Values\.offline\.registry | default "" }}/docker.io/g' \
        -e 's/{{ \.Values\.astrago\.core\.registry }}/docker.io/g' \
        -e 's/{{ \.Values\.astrago\.core\.repository }}/xiilab\/astrago-posco/g' \
        -e 's/{{ \.Values\.astrago\.core\.imageTag }}/core-stage-c5ad/g' \
        -e 's/{{ \.Values\.astrago\.batch\.registry }}/docker.io/g' \
        -e 's/{{ \.Values\.astrago\.batch\.repository }}/xiilab\/astrago-posco/g' \
        -e 's/{{ \.Values\.astrago\.batch\.imageTag }}/batch-stage-c5ad/g' \
        -e 's/{{ \.Values\.astrago\.monitor\.registry }}/docker.io/g' \
        -e 's/{{ \.Values\.astrago\.monitor\.repository }}/xiilab\/astrago-posco/g' \
        -e 's/{{ \.Values\.astrago\.monitor\.imageTag }}/monitor-stage-c5ad/g' \
        -e 's/{{ \.Values\.astrago\.frontend\.registry }}/docker.io/g' \
        -e 's/{{ \.Values\.astrago\.frontend\.repository }}/xiilab\/astrago-posco/g' \
        -e 's/{{ \.Values\.astrago\.frontend\.imageTag }}/frontend-stage-3770/g' \
        "$input_file" > "$output_file"
}

# Extract images from values files
extract_images_from_values() {
    log "Extracting images from values.yaml files..."
    
    > "$TEMP_DIR/all_values_images.txt"
    
    # Process each values file
    for values_file in "$HELMFILE_DIR"/values/*.yaml.gotmpl; do
        if [[ -f "$values_file" ]]; then
            local basename=$(basename "$values_file" .yaml.gotmpl)
            log "Processing $basename values..."
            
            local resolved_file="$TEMP_DIR/${basename}_resolved.yaml"
            resolve_template_vars "$values_file" "$resolved_file"
            
            # Extract images based on different patterns
            extract_images_from_resolved_values "$resolved_file" "$basename"
        fi
    done
    
    # Sort and deduplicate
    sort -u "$TEMP_DIR/all_values_images.txt" > "$TEMP_DIR/unique_values_images.txt"
    
    local count=$(wc -l < "$TEMP_DIR/unique_values_images.txt")
    log "Extracted $count unique images from values files"
}

extract_images_from_resolved_values() {
    local file="$1"
    local chart_name="$2"
    local chart_images="$TEMP_DIR/${chart_name}_images.txt"
    
    > "$chart_images"
    
    case "$chart_name" in
        "astrago")
            # Astrago custom format: registry/repository:tag
            extract_astrago_images "$file" "$chart_images"
            ;;
        "flux")
            # Flux format: direct image references
            extract_flux_images "$file" "$chart_images"
            ;;
        "harbor")
            # Harbor uses standard helm chart - need to check values for image references
            extract_standard_images "$file" "$chart_images"
            ;;
        "keycloak")
            extract_standard_images "$file" "$chart_images"
            ;;
        "prometheus")
            extract_standard_images "$file" "$chart_images"
            ;;
        "gpu-operator")
            extract_standard_images "$file" "$chart_images"
            ;;
        *)
            extract_standard_images "$file" "$chart_images"
            ;;
    esac
    
    # Add to master list
    cat "$chart_images" >> "$TEMP_DIR/all_values_images.txt"
    
    local count=$(wc -l < "$chart_images" 2>/dev/null || echo 0)
    if [[ $count -gt 0 ]]; then
        log "  Found $count images in $chart_name"
    fi
}

extract_astrago_images() {
    local file="$1" 
    local output="$2"
    
    # Extract Astrago component images
    awk '
    BEGIN { registry=""; repository=""; tag="" }
    /^[[:space:]]*registry:[[:space:]]*/ { 
        gsub(/[[:space:]]*registry:[[:space:]]*["]*/, "")
        gsub(/["]*[[:space:]]*$/, "")
        registry = $0
    }
    /^[[:space:]]*repository:[[:space:]]*/ { 
        gsub(/[[:space:]]*repository:[[:space:]]*["]*/, "")
        gsub(/["]*[[:space:]]*$/, "")
        repository = $0
    }
    /^[[:space:]]*tag:[[:space:]]*/ { 
        gsub(/[[:space:]]*tag:[[:space:]]*["]*/, "")
        gsub(/["]*[[:space:]]*$/, "")
        tag = $0
        if (registry != "" && repository != "" && tag != "") {
            print registry "/" repository ":" tag
            registry=""; repository=""; tag=""
        }
    }' "$file" >> "$output"
    
    # Also extract MariaDB dependency (bitnami/mariadb is used)
    echo "docker.io/bitnami/mariadb:10.11.4-debian-11-r46" >> "$output"
    echo "docker.io/library/nginx:1.27.0-alpine3.19" >> "$output"
}

extract_flux_images() {
    local file="$1"
    local output="$2"
    
    # Flux2 images from values
    grep -E 'image:[[:space:]]*"[^"]*"' "$file" | \
        sed 's/.*image:[[:space:]]*"\([^"]*\)".*/\1/' | \
        while read -r image_base; do
            # Add version tag - flux2 2.14.0 versions
            case "$image_base" in
                *flux-cli) echo "${image_base}:v2.4.0" ;;
                *helm-controller) echo "${image_base}:v1.1.0" ;;
                *image-automation-controller) echo "${image_base}:v0.39.0" ;;
                *image-reflector-controller) echo "${image_base}:v0.33.0" ;;
                *kustomize-controller) echo "${image_base}:v1.4.0" ;;
                *notification-controller) echo "${image_base}:v1.4.0" ;;
                *source-controller) echo "${image_base}:v1.4.1" ;;
            esac
        done >> "$output"
}

extract_standard_images() {
    local file="$1"
    local output="$2"
    
    # Standard helm image patterns
    
    # Pattern 1: image: "registry/repo:tag"
    grep -E 'image:[[:space:]]*"[^"]*"' "$file" | \
        sed 's/.*image:[[:space:]]*"\([^"]*\)".*/\1/' >> "$output"
    
    # Pattern 2: repository + tag combination
    awk 'BEGIN { repo=""; tag="" }
    /repository:[[:space:]]*/ { 
        match($0, /repository:[[:space:]]*"?([^"[:space:]]*)"?/, arr)
        repo = arr[1]
    }
    /tag:[[:space:]]*/ { 
        match($0, /tag:[[:space:]]*"?([^"[:space:]]*)"?/, arr)
        tag = arr[1]
        if (repo != "" && tag != "") {
            if (repo ~ /^[^\/]*\./) {
                print repo ":" tag
            } else {
                print "docker.io/" repo ":" tag  
            }
            repo=""; tag=""
        }
    }' "$file" >> "$output"
}

# Add static dependencies not captured in values
add_known_dependencies() {
    log "Adding known dependencies..."
    
    # Dependencies that are hard to extract from values but are used
    cat >> "$TEMP_DIR/static_deps.txt" << EOF
docker.io/bitnami/postgresql:16.1.0-debian-11-r9
quay.io/kiwigrid/k8s-sidecar:1.27.4
quay.io/prometheus-operator/prometheus-operator:v0.75.2
quay.io/prometheus-operator/prometheus-config-reloader:v0.75.2
quay.io/prometheus/alertmanager:v0.27.0
quay.io/prometheus/node-exporter:v1.8.2
quay.io/prometheus/prometheus:v2.54.0
docker.io/grafana/grafana:11.1.3
docker.io/bats/bats:v1.4.1
ghcr.io/cowboysysop/pytest:1.0.35
docker.io/mpioperator/mpi-operator:0.3.0
registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20221220-controller-v1.5.1-58-g787ea74b6
registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0
registry.k8s.io/metrics-server/metrics-server:v0.7.0
registry.k8s.io/nfd/node-feature-discovery:v0.16.6
registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.11.1
registry.k8s.io/sig-storage/csi-provisioner:v5.0.2
registry.k8s.io/sig-storage/csi-snapshotter:v8.0.1
registry.k8s.io/sig-storage/livenessprobe:v2.13.1
registry.k8s.io/sig-storage/nfsplugin:v4.9.0
docker.io/xiilab/astrago:time-prediction-v0.2
nvcr.io/nvidia/gpu-operator:v24.9.0
EOF
    
    cat "$TEMP_DIR/static_deps.txt" >> "$TEMP_DIR/all_values_images.txt"
    
    log "Added $(wc -l < "$TEMP_DIR/static_deps.txt") static dependencies"
}

# Categorize and save images
categorize_and_save_images() {
    log "Categorizing and saving images from values..."
    
    # Combine values images with static deps
    add_known_dependencies
    
    sort -u "$TEMP_DIR/all_values_images.txt" > "$TEMP_DIR/final_values_images.txt"
    
    local total_count=$(wc -l < "$TEMP_DIR/final_values_images.txt")
    log "Total unique images from values: $total_count"
    
    # Create output directory
    mkdir -p "$IMAGELISTS_DIR"
    
    # Generate master list
    {
        echo "# Auto-generated from values.yaml files on $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Source: helmfile values + known dependencies"
        echo ""
        cat "$TEMP_DIR/final_values_images.txt"
        echo ""
        echo ""
    } > "$IMAGELISTS_DIR/images-from-values.txt"
    
    # Individual service lists
    grep "astrago" "$TEMP_DIR/final_values_images.txt" > "$TEMP_DIR/astrago_values.txt" || true
    grep "harbor" "$TEMP_DIR/final_values_images.txt" > "$TEMP_DIR/harbor_values.txt" || true
    grep "flux" "$TEMP_DIR/final_values_images.txt" > "$TEMP_DIR/flux_values.txt" || true
    grep "keycloak\|postgresql" "$TEMP_DIR/final_values_images.txt" > "$TEMP_DIR/keycloak_values.txt" || true
    grep "prometheus\|grafana\|alertmanager" "$TEMP_DIR/final_values_images.txt" > "$TEMP_DIR/prometheus_values.txt" || true
    grep "nvidia\|gpu" "$TEMP_DIR/final_values_images.txt" > "$TEMP_DIR/gpu_values.txt" || true
    
    # Save categorized lists
    for category in astrago harbor flux keycloak prometheus gpu; do
        local file="$IMAGELISTS_DIR/${category}-from-values.txt"
        local temp_file="$TEMP_DIR/${category}_values.txt"
        
        if [[ -s "$temp_file" ]]; then
            {
                echo "# Auto-generated from values.yaml on $(date '+%Y-%m-%d %H:%M:%S')"
                echo "# Source: values files + static dependencies"
                echo ""
                cat "$temp_file"
                echo ""
                echo ""
            } > "$file"
            log "Saved $(wc -l < "$temp_file") images to ${category}-from-values.txt"
        fi
    done
}

# Compare with template results
compare_with_template() {
    log "Comparing values approach with template approach..."
    
    if [[ -f "$IMAGELISTS_DIR/images.txt" ]]; then
        local template_images="$TEMP_DIR/template_images_clean.txt"
        local values_images="$TEMP_DIR/final_values_images.txt"
        
        # Clean template results (remove comments and empty lines)
        grep -v '^#' "$IMAGELISTS_DIR/images.txt" | grep -v '^$' | sort > "$template_images"
        
        echo -e "\n${BLUE}=== COMPARISON RESULTS ===${NC}"
        echo "Template approach: $(wc -l < "$template_images") images"
        echo "Values approach: $(wc -l < "$values_images") images"
        
        # Find differences
        echo -e "\n${YELLOW}Images only in Template:${NC}"
        comm -23 "$template_images" "$values_images" | head -10
        
        echo -e "\n${YELLOW}Images only in Values:${NC}"  
        comm -13 "$template_images" "$values_images" | head -10
        
        echo -e "\n${GREEN}Common images:${NC} $(comm -12 "$template_images" "$values_images" | wc -l)"
    else
        warn "No template results found for comparison"
    fi
}

# Main execution
main() {
    log "Starting values-based image extraction..."
    
    extract_images_from_values
    categorize_and_save_images
    compare_with_template
    
    log "Values-based image extraction complete!"
    log "Results saved to $IMAGELISTS_DIR/*-from-values.txt"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi