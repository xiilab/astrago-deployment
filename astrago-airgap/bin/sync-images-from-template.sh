#!/bin/bash
# Astrago Airgap - Auto Sync Images from Helmfile Template
# helmfile template에서 실제 필요한 모든 이미지를 추출하여 imagelists를 업데이트

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

echo -e "${BLUE}🔄 Auto-syncing images from helmfile template...${NC}"

# Change to helmfile directory
cd "$HELMFILE_DIR"

# Function to extract images from a specific release
extract_release_images() {
    local release="$1"
    local output_file="$2"
    local description="$3"
    
    echo -e "${YELLOW}  📦 Processing $description ($release)...${NC}"
    
    # Generate template for specific release with timeout
    local temp_file="/tmp/${release}_template.yaml"
    
    if timeout 60 helmfile -e default template --selector name="$release" --skip-deps > "$temp_file" 2>/dev/null; then
        {
            # Extract standard image: patterns
            sed -n 's/.*image:[[:space:]]*"\([^"]*\)".*/\1/p' "$temp_file" 2>/dev/null || true
            
            # Extract repository + tag patterns for charts that use separate fields
            awk '
            BEGIN { repo=""; tag="" }
            /repository:/ { 
                if (match($0, /repository:[[:space:]]*"([^"]*)"/, arr)) {
                    repo = arr[1]
                } else if (match($0, /repository:[[:space:]]*([^[:space:]]+)/, arr)) {
                    repo = arr[1]
                }
            }
            /tag:/ { 
                if (match($0, /tag:[[:space:]]*"([^"]*)"/, arr)) {
                    tag = arr[1]
                } else if (match($0, /tag:[[:space:]]*([^[:space:]]+)/, arr)) {
                    tag = arr[1]
                }
                if (repo != "" && tag != "" && repo !~ /:/) {
                    print repo ":" tag
                    repo = ""
                    tag = ""
                }
            }
            ' "$temp_file" 2>/dev/null || true
            
        } | grep -E '^[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*:[a-zA-Z0-9._-]+$' | sort -u > "$output_file" || true
        
        local count=$(wc -l < "$output_file" 2>/dev/null || echo "0")
        echo -e "${GREEN}    ✅ Extracted $count images${NC}"
        
        # Show first few images for debugging
        if [[ $count -gt 0 ]]; then
            echo -e "${BLUE}    📋 Sample images:${NC}"
            head -3 "$output_file" | sed 's/^/      /'
        fi
    else
        echo -e "${RED}    ❌ Timeout or error processing $release${NC}"
        touch "$output_file"
    fi
    
    rm -f "$temp_file"
}

# Create temporary directory
TEMP_DIR="/tmp/astrago_images"
mkdir -p "$TEMP_DIR"

echo -e "${YELLOW}📂 Extracting images by release...${NC}"

# Extract images by release
extract_release_images "astrago" "$TEMP_DIR/astrago.txt" "Astrago applications"
extract_release_images "flux" "$TEMP_DIR/flux.txt" "Flux2 GitOps"
extract_release_images "harbor" "$TEMP_DIR/harbor.txt" "Harbor registry"
extract_release_images "gpu-operator" "$TEMP_DIR/gpu-operator.txt" "NVIDIA GPU Operator"
extract_release_images "keycloak" "$TEMP_DIR/keycloak.txt" "Keycloak auth"
extract_release_images "prometheus" "$TEMP_DIR/prometheus.txt" "Prometheus monitoring"
extract_release_images "mpi-operator" "$TEMP_DIR/mpi-operator.txt" "MPI Operator"
extract_release_images "nfs-provisioner" "$TEMP_DIR/nfs-provisioner.txt" "NFS CSI Driver"

# Update individual imagelists with header
update_imagelist() {
    local category="$1"
    local temp_file="$TEMP_DIR/${category}.txt"
    local target_file="$IMAGELISTS_DIR/${category}.txt"
    
    if [[ -f "$temp_file" && -s "$temp_file" ]]; then
        echo -e "${YELLOW}  ✏️  Updating ${category}.txt...${NC}"
        
        # Create header with timestamp
        cat > "$target_file" << EOF
# Auto-generated from helmfile template on $(date '+%Y-%m-%d %H:%M:%S')
# Source: helmfile template --environment default

EOF
        
        # Add images
        cat "$temp_file" >> "$target_file"
        echo "" >> "$target_file"
        
        local count=$(wc -l < "$temp_file")
        echo -e "${GREEN}    ✅ Updated with $count images${NC}"
    else
        echo -e "${YELLOW}    ⚠️  No images found for $category${NC}"
    fi
}

# Update all category-specific imagelists
echo -e "${YELLOW}📝 Updating imagelists...${NC}"
update_imagelist "astrago"
update_imagelist "flux"
update_imagelist "harbor"
update_imagelist "gpu-operator"
update_imagelist "keycloak" 
update_imagelist "prometheus"
update_imagelist "mpi-operator"
update_imagelist "nfs-provisioner"

# Create comprehensive images.txt by combining all
echo -e "${YELLOW}📋 Creating comprehensive images.txt...${NC}"
cat > "$IMAGELISTS_DIR/images.txt" << EOF
# Auto-generated from helmfile template on $(date '+%Y-%m-%d %H:%M:%S')
# Source: helmfile template --environment default

EOF

# Combine all category files
for file in "$TEMP_DIR"/*.txt; do
    if [[ -f "$file" && -s "$file" ]]; then
        cat "$file" >> "$IMAGELISTS_DIR/images.txt"
    fi
done

# Remove duplicates and sort
if [[ -s "$IMAGELISTS_DIR/images.txt" ]]; then
    sort -u "$IMAGELISTS_DIR/images.txt" | grep -v '^#' | grep -v '^$' > "${IMAGELISTS_DIR}/images_temp.txt"
    head -3 "$IMAGELISTS_DIR/images.txt" > "${IMAGELISTS_DIR}/images_new.txt"
    cat "${IMAGELISTS_DIR}/images_temp.txt" >> "${IMAGELISTS_DIR}/images_new.txt"
    echo "" >> "${IMAGELISTS_DIR}/images_new.txt"
    mv "${IMAGELISTS_DIR}/images_new.txt" "$IMAGELISTS_DIR/images.txt"
    rm -f "${IMAGELISTS_DIR}/images_temp.txt"
fi

TOTAL_COUNT=$(grep -v '^#' "$IMAGELISTS_DIR/images.txt" 2>/dev/null | grep -v '^$' | wc -l)

# Display summary
echo -e "${GREEN}🎉 Image sync completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  Total unique images: ${GREEN}$TOTAL_COUNT${NC}"
echo -e "  Updated imagelists in: ${BLUE}$IMAGELISTS_DIR${NC}"

# Show final result preview
if [[ $TOTAL_COUNT -gt 0 ]]; then
    echo -e "${BLUE}📋 Final image list preview:${NC}"
    head -10 "$IMAGELISTS_DIR/images.txt" | grep -v '^#' | sed 's/^/  /'
fi

# Clean up
rm -rf "$TEMP_DIR"

echo -e "${YELLOW}💡 Next steps:${NC}"
echo -e "  1. Review updated imagelists: ${BLUE}ls -la $IMAGELISTS_DIR/${NC}"
echo -e "  2. Run image download: ${BLUE}./bin/download-images.sh${NC}"
echo -e "  3. Create delivery package: ${BLUE}./bin/create_delivery_package.sh${NC}"