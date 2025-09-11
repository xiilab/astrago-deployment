#!/bin/bash
# Astrago Airgap - Complete Image Sync with Dependencies
# helmfile template with dependencies로 완전한 이미지 목록 생성

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HELMFILE_DIR="$(dirname "$ROOT_DIR")/helmfile"
IMAGELISTS_DIR="$ROOT_DIR/astrago/imagelists"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Complete image sync with dependencies...${NC}"

# Change to helmfile directory
cd "$HELMFILE_DIR"

# Create temporary directory
TEMP_DIR="/tmp/astrago_images_deps"
mkdir -p "$TEMP_DIR"

# Step 1: Update dependencies for all local charts
echo -e "${YELLOW}📦 Step 1: Updating chart dependencies...${NC}"

update_chart_dependencies() {
    local chart_path="$1"
    local chart_name=$(basename "$chart_path")
    
    if [[ -f "$chart_path/Chart.yaml" ]]; then
        echo -e "${YELLOW}  ⏳ Updating dependencies for $chart_name...${NC}"
        if helm dependency update "$chart_path" 2>/dev/null; then
            echo -e "${GREEN}    ✅ Dependencies updated for $chart_name${NC}"
        else
            echo -e "${YELLOW}    ⚠️  No dependencies or update failed for $chart_name${NC}"
        fi
    fi
}

# Update dependencies for local charts
if [[ -d "charts/external" ]]; then
    for chart in charts/external/*; do
        if [[ -d "$chart" ]]; then
            update_chart_dependencies "$chart"
        fi
    done
fi

if [[ -d "charts/astrago" ]]; then
    update_chart_dependencies "charts/astrago"
fi

# Step 2: Generate complete template with dependencies
echo -e "${YELLOW}📋 Step 2: Generating complete helmfile template (may take several minutes)...${NC}"

# Try full template first
if timeout 600 helmfile -e default template > "$TEMP_DIR/complete_template.yaml" 2>/dev/null; then
    echo -e "${GREEN}  ✅ Complete template generated successfully${NC}"
    TEMPLATE_SUCCESS=true
else
    echo -e "${RED}  ❌ Complete template generation failed or timed out${NC}"
    echo -e "${YELLOW}  🔄 Trying individual release templates...${NC}"
    TEMPLATE_SUCCESS=false
    > "$TEMP_DIR/complete_template.yaml"  # Create empty file
fi

# If full template failed, generate individual release templates
if [[ "$TEMPLATE_SUCCESS" == "false" ]]; then
    RELEASES=(
        "astrago"
        "flux" 
        "harbor"
        "gpu-operator"
        "keycloak"
        "prometheus"
        "mpi-operator"
        "nfs-provisioner"
    )
    
    for release in "${RELEASES[@]}"; do
        echo -e "${YELLOW}    📦 Generating template for $release...${NC}"
        if timeout 120 helmfile -e default template --selector name="$release" >> "$TEMP_DIR/complete_template.yaml" 2>/dev/null; then
            echo -e "${GREEN}      ✅ Template generated for $release${NC}"
        else
            echo -e "${RED}      ❌ Template generation failed for $release${NC}"
        fi
    done
fi

# Step 3: Extract all images from the template
echo -e "${YELLOW}🔍 Step 3: Extracting images from template...${NC}"

# Enhanced image extraction with multiple patterns
{
    # Pattern 1: Standard image: "value" format
    grep -E 'image:[[:space:]]*"[^"]*"' "$TEMP_DIR/complete_template.yaml" 2>/dev/null | \
        sed 's/.*image:[[:space:]]*"\([^"]*\)".*/\1/' || true
    
    # Pattern 2: image: value format (without quotes)
    grep -E 'image:[[:space:]]*[^[:space:]"]+' "$TEMP_DIR/complete_template.yaml" 2>/dev/null | \
        grep -v 'image:[[:space:]]*"' | \
        sed 's/.*image:[[:space:]]*\([^[:space:]]*\).*/\1/' || true
    
    # Pattern 3: Repository + tag combinations
    awk '
    BEGIN { repo=""; tag=""; registry="" }
    
    # Capture registry field
    /registry:[[:space:]]*/ {
        if (match($0, /registry:[[:space:]]*"?([^"[:space:]]*)"?/, arr)) {
            registry = arr[1]
            if (registry !~ /\/$/) registry = registry "/"
        }
    }
    
    # Capture repository field  
    /repository:[[:space:]]*/ {
        if (match($0, /repository:[[:space:]]*"?([^"[:space:]]*)"?/, arr)) {
            repo = arr[1]
            # If repository already contains registry, use as-is
            if (repo !~ /^[a-z0-9.-]+\//) {
                if (registry != "") {
                    repo = registry repo
                } else {
                    # Default to docker.io if no registry specified
                    repo = "docker.io/" repo
                }
            }
        }
    }
    
    # Capture tag field and output complete image
    /tag:[[:space:]]*/ {
        if (match($0, /tag:[[:space:]]*"?([^"[:space:]]*)"?/, arr)) {
            tag = arr[1]
            if (repo != "" && tag != "" && repo !~ /:/) {
                print repo ":" tag
            }
            # Reset for next image
            repo = ""
            tag = ""
            registry = ""
        }
    }
    
    # Special handling for NVIDIA images with complex structure
    /nvidia/ {
        if (/repository:[[:space:]]*nvcr\.io/) {
            nvidia_repo = $0
            getline
            if (/tag:/) {
                if (match(nvidia_repo, /repository:[[:space:]]*"?([^"[:space:]]*)"?/, repo_arr) && 
                    match($0, /tag:[[:space:]]*"?([^"[:space:]]*)"?/, tag_arr)) {
                    print repo_arr[1] ":" tag_arr[1]
                }
            }
        }
    }
    
    ' "$TEMP_DIR/complete_template.yaml" 2>/dev/null || true
    
    # Pattern 4: Flux specific image extraction
    grep -A1 -B1 'ghcr.io/fluxcd' "$TEMP_DIR/complete_template.yaml" 2>/dev/null | \
        grep -E 'image:|ghcr.io/fluxcd' | \
        sed 's/.*"\(ghcr\.io\/fluxcd\/[^"]*\)".*/\1/' | \
        grep 'ghcr.io/fluxcd' || true
        
} | grep -E '^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$' | sort -u > "$TEMP_DIR/all_images.txt"

TOTAL_COUNT=$(wc -l < "$TEMP_DIR/all_images.txt")
echo -e "${GREEN}🎉 Extracted $TOTAL_COUNT total images${NC}"

# Step 4: Show sample of extracted images for verification
echo -e "${BLUE}📋 Sample extracted images:${NC}"
head -10 "$TEMP_DIR/all_images.txt" | sed 's/^/  /'

# Step 5: Categorize and update imagelists  
echo -e "${YELLOW}📂 Step 4: Categorizing images...${NC}"

categorize_images() {
    local category="$1"
    local pattern="$2" 
    local description="$3"
    
    grep -E "$pattern" "$TEMP_DIR/all_images.txt" > "$TEMP_DIR/${category}.txt" 2>/dev/null || touch "$TEMP_DIR/${category}.txt"
    local count=$(wc -l < "$TEMP_DIR/${category}.txt")
    
    if [[ $count -gt 0 ]]; then
        echo -e "${BLUE}  📦 $description: $count images${NC}"
        # Show first few images as sample
        head -3 "$TEMP_DIR/${category}.txt" | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠️  $description: $count images${NC}"
    fi
}

categorize_images "astrago" "docker.io/xiilab/astrago|docker.io/(bitnami/mariadb|library/nginx)" "Astrago applications"
categorize_images "flux" "ghcr.io/fluxcd/" "Flux2 GitOps"
categorize_images "harbor" "docker.io/goharbor/" "Harbor registry"  
categorize_images "gpu-operator" "nvcr.io/nvidia/" "NVIDIA GPU Operator"
categorize_images "keycloak" "docker.io/bitnami/(keycloak|postgresql)" "Keycloak auth"
categorize_images "prometheus" "quay.io/prometheus|quay.io/kiwigrid|registry.k8s.io/kube-state-metrics|docker.io/grafana|quay.io/prometheus-operator" "Prometheus monitoring"
categorize_images "mpi-operator" "docker.io/mpioperator/|ghcr.io/cowboysysop/" "MPI Operator"
categorize_images "nfs-provisioner" "registry.k8s.io/sig-storage/" "NFS CSI Driver"

# Step 6: Update individual imagelists
echo -e "${YELLOW}📝 Step 5: Updating imagelists...${NC}"

update_imagelist() {
    local category="$1"
    local temp_file="$TEMP_DIR/${category}.txt"
    local target_file="$IMAGELISTS_DIR/${category}.txt"
    
    if [[ -f "$temp_file" && -s "$temp_file" ]]; then
        echo -e "${YELLOW}  ✏️  Updating ${category}.txt...${NC}"
        
        cat > "$target_file" << EOF
# Auto-generated with dependencies on $(date '+%Y-%m-%d %H:%M:%S')
# Source: helmfile template --environment default (with dependencies)

EOF
        cat "$temp_file" >> "$target_file"
        echo "" >> "$target_file"
        
        local count=$(wc -l < "$temp_file")
        echo -e "${GREEN}    ✅ Updated with $count images${NC}"
    else
        echo -e "${YELLOW}    ⚠️  No images found for $category${NC}"
    fi
}

update_imagelist "astrago"
update_imagelist "flux"
update_imagelist "harbor"
update_imagelist "gpu-operator"
update_imagelist "keycloak"
update_imagelist "prometheus" 
update_imagelist "mpi-operator"
update_imagelist "nfs-provisioner"

# Step 7: Create comprehensive images.txt
echo -e "${YELLOW}📋 Creating comprehensive images.txt...${NC}"

cat > "$IMAGELISTS_DIR/images.txt" << EOF
# Auto-generated with dependencies on $(date '+%Y-%m-%d %H:%M:%S')
# Source: helmfile template --environment default (with dependencies)

EOF

cat "$TEMP_DIR/all_images.txt" >> "$IMAGELISTS_DIR/images.txt"
echo "" >> "$IMAGELISTS_DIR/images.txt"

# Final summary
echo -e "${GREEN}🎉 Complete dependency-based image sync finished!${NC}"
echo -e "${BLUE}📊 Final Summary:${NC}"
echo -e "  Total unique images: ${GREEN}$TOTAL_COUNT${NC}"
echo -e "  Updated imagelists in: ${BLUE}$IMAGELISTS_DIR${NC}"

# Show template file size for verification
TEMPLATE_SIZE=$(wc -l < "$TEMP_DIR/complete_template.yaml" 2>/dev/null || echo "0")
echo -e "  Generated template size: ${YELLOW}$TEMPLATE_SIZE lines${NC}"

# Clean up
rm -rf "$TEMP_DIR"

echo -e "${YELLOW}💡 Next steps:${NC}"
echo -e "  1. Review updated imagelists: ${BLUE}ls -la $IMAGELISTS_DIR/${NC}"  
echo -e "  2. Compare with previous version to see improvements"
echo -e "  3. Run image download: ${BLUE}./bin/download-images.sh${NC}"
echo -e "  4. Create delivery package: ${BLUE}./bin/create_delivery_package.sh${NC}"