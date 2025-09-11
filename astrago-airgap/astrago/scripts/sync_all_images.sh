#!/bin/bash
# Astrago Airgap - 모든 차트 이미지를 helmfile에서 동기화하는 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load configuration
source "$ROOT_DIR/astrago-airgap/airgap.conf"

HELMFILE_PATH="$ROOT_DIR/helmfile"
OUTPUT_DIR="$ROOT_DIR/astrago-airgap/astrago/imagelists"
TEMP_IMAGES_FILE="/tmp/helmfile_images.txt"

echo "🔄 Syncing all chart images from helmfile..."
echo "Helmfile path: $HELMFILE_PATH"
echo "Output directory: $OUTPUT_DIR"

# helmfile template으로 모든 이미지 추출
extract_all_images() {
    echo "📋 Extracting all images from helmfile template..."
    
    cd "$HELMFILE_PATH"
    
    # helmfile template 실행하고 이미지만 추출
    timeout 300 helmfile template --environment default 2>/dev/null | \
    grep -oE 'image:.*["|'"'"'].*["|'"'"']' | \
    sed -E 's/image:[[:space:]]*["|'"'"']([^"|'"'"']*)["|'"'"'].*/\1/' | \
    grep -v '^[[:space:]]*$' | \
    sort -u > "$TEMP_IMAGES_FILE"
    
    # 추가로 values에서 직접 이미지 추출
    find . -name "values*.yaml*" -exec grep -oE '(registry|repository|image|tag):[[:space:]]*["|'"'"']?[^"|'"'"'\s]+["|'"'"']?' {} \; | \
    grep -E '\.(io|com|org|net)/|docker\.io|registry\.k8s\.io|ghcr\.io|nvcr\.io' >> "$TEMP_IMAGES_FILE" || true
    
    echo "✅ Found $(wc -l < "$TEMP_IMAGES_FILE") unique images"
}

# 컴포넌트별로 이미지 분류
categorize_images() {
    echo "🏷️ Categorizing images by component..."
    
    # GPU Operator 이미지들
    grep -i 'nvidia\|gpu\|cuda' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/gpu-operator.txt.new" || touch "$OUTPUT_DIR/gpu-operator.txt.new"
    
    # Harbor 이미지들  
    grep -i 'harbor\|goharbor' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/harbor.txt.new" || touch "$OUTPUT_DIR/harbor.txt.new"
    
    # Prometheus 이미지들
    grep -i 'prometheus\|grafana\|alertmanager' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/prometheus.txt.new" || touch "$OUTPUT_DIR/prometheus.txt.new"
    
    # Keycloak 이미지들
    grep -i 'keycloak\|bitnami.*keycloak' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/keycloak.txt.new" || touch "$OUTPUT_DIR/keycloak.txt.new"
    
    # Flux 이미지들
    grep -i 'flux\|ghcr.io/fluxcd' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/flux.txt.new" || touch "$OUTPUT_DIR/flux.txt.new"
    
    # MPI Operator 이미지들
    grep -i 'mpi.*operator\|mpioperator' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/mpi-operator.txt.new" || touch "$OUTPUT_DIR/mpi-operator.txt.new"
    
    # NFS/CSI 이미지들
    grep -i 'csi.*nfs\|nfs.*plugin\|sig-storage' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/nfs-provisioner.txt.new" || touch "$OUTPUT_DIR/nfs-provisioner.txt.new"
    
    # Astrago 이미지들 (xiilab)
    grep -i 'xiilab\|astrago' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/astrago.txt.new" || touch "$OUTPUT_DIR/astrago.txt.new"
    
    # Loki Stack 이미지들
    grep -i 'loki\|logstash' "$TEMP_IMAGES_FILE" > "$OUTPUT_DIR/loki-stack.txt.new" || touch "$OUTPUT_DIR/loki-stack.txt.new"
    
    # 기타 모든 이미지
    cp "$TEMP_IMAGES_FILE" "$OUTPUT_DIR/images.txt.new"
}

# 기존 파일들과 비교하고 업데이트
update_image_lists() {
    echo "🔄 Updating image lists..."
    
    for file in "$OUTPUT_DIR"/*.txt.new; do
        if [ -f "$file" ]; then
            base_name=$(basename "$file" .new)
            old_file="$OUTPUT_DIR/$base_name"
            
            if [ -f "$old_file" ]; then
                if ! diff -q "$old_file" "$file" >/dev/null 2>&1; then
                    echo "📝 Updating $base_name (found changes)"
                    # 헤더 추가
                    echo "# Auto-generated from helmfile template on $(date)" > "$old_file.tmp"
                    echo "# Source: helmfile template --environment default" >> "$old_file.tmp"
                    echo "" >> "$old_file.tmp"
                    cat "$file" >> "$old_file.tmp"
                    mv "$old_file.tmp" "$old_file"
                else
                    echo "✅ $base_name is up to date"
                fi
            else
                echo "📝 Creating new $base_name"
                # 헤더 추가
                echo "# Auto-generated from helmfile template on $(date)" > "$old_file"
                echo "# Source: helmfile template --environment default" >> "$old_file"
                echo "" >> "$old_file"
                cat "$file" >> "$old_file"
            fi
            
            rm "$file"
        fi
    done
}

# 실행
main() {
    extract_all_images
    categorize_images
    update_image_lists
    
    # 임시 파일 정리
    rm -f "$TEMP_IMAGES_FILE"
    
    echo ""
    echo "🎉 Image synchronization completed!"
    echo "📊 Updated image lists:"
    ls -la "$OUTPUT_DIR"/*.txt | while read -r line; do
        echo "   $line"
    done
}

main "$@"