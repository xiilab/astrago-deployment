#!/bin/bash

CURRENT_DIR=$(dirname "$(realpath "$0")")
ADDITIONAL_IMAGE_ORIGINAL_FILE=$CURRENT_DIR/kubespray-offline/imagelists/images.txt.original
ADDITIONAL_IMAGE_FILE=$CURRENT_DIR/kubespray-offline/imagelists/images.txt

# Note: Image extraction is now handled by predefined image list files
# This approach is more reliable and maintainable than dynamic helm template parsing

# Function to process Helm charts and prepare the images list
prepare_images_list() {
  echo "Start Extract Image List"
  cp $ADDITIONAL_IMAGE_ORIGINAL_FILE $ADDITIONAL_IMAGE_FILE
  
  # Combine all image list files
  echo "Adding images from predefined lists..."
  cat $CURRENT_DIR/kubespray-offline/imagelists/*.txt | grep -v "^#" | grep -v "^$" | tr ' ' '\n' | sort | uniq | grep -v "^$" >> $ADDITIONAL_IMAGE_FILE
  
  # Add additional required images
  echo "jacobcarlborg/docker-alpine-wget:latest" >> "$ADDITIONAL_IMAGE_FILE"
  echo "busybox:latest" >> "$ADDITIONAL_IMAGE_FILE"
  
  # Remove duplicates and empty lines, fix formatting
  sort $ADDITIONAL_IMAGE_FILE | uniq | grep -v "^$" > $ADDITIONAL_IMAGE_FILE.tmp
  mv $ADDITIONAL_IMAGE_FILE.tmp $ADDITIONAL_IMAGE_FILE
  
  echo "Finished Extract Image List"
  echo "Total images: $(wc -l < $ADDITIONAL_IMAGE_FILE)"
  echo ""
  echo "=== New Components Added ==="
  echo "✅ Loki Stack (Logging): $(grep -c -E "loki|promtail" $ADDITIONAL_IMAGE_FILE) images"
  echo "✅ GPU Process Exporter: $(grep -c "dcgm-exporter" $ADDITIONAL_IMAGE_FILE) images"  
  echo "✅ MPI Operator: $(grep -c "mpioperator" $ADDITIONAL_IMAGE_FILE) images"
  echo "✅ Updated GPU Operator: $(grep -c "nvidia" $ADDITIONAL_IMAGE_FILE) images"
}

prepare_images_list
