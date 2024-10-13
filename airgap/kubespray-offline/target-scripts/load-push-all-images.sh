#!/bin/bash

source ./config.sh

LOCAL_REGISTRY=${LOCAL_REGISTRY:-"localhost:${REGISTRY_PORT}"}
NERDCTL=/usr/local/bin/nerdctl

BASEDIR="."
if [ ! -d images ] && [ -d ../outputs ]; then
    BASEDIR="../outputs"  # for tests
fi

# Function to check if image exists in private registry
check_image_exists() {
    local image_name="$1"
    local tag="$2"

    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
               "http://${LOCAL_REGISTRY}/v2/${image_name}/manifests/${tag}")

    if [ "$response" = "200" ]; then
        return 0
    else
        return 1
    fi
}

process_image() {
    local tar_file="$1"
    local filename=$(basename "$tar_file")
    
    # Remove .tar.gz extension
    local name_without_extension=${filename%.tar.gz}
    
    # Split the filename into parts
    IFS='_' read -ra parts <<< "$name_without_extension"
    
    local registry="${parts[0]}"
    local tag="${parts[-1]}"
    
    if [ ${#parts[@]} -eq 3 ]; then
        # Case: registry_image_tag
        local image_name="${parts[1]}"
        local full_image_name="${registry}/${image_name}"
        local new_image_name="${LOCAL_REGISTRY}/${image_name}"
    elif [ ${#parts[@]} -eq 4 ]; then
        # Case: registry_repository_image_tag
        local repository="${parts[1]}"
        local image_name="${parts[2]}"
        local full_image_name="${registry}/${repository}/${image_name}"
        local new_image_name="${LOCAL_REGISTRY}/${repository}/${image_name}"
    else
        echo "Unexpected filename format: $filename"
        return 1
    fi
    
    echo "Processing image:"
    echo "Registry: $registry"
    [ -n "$repository" ] && echo "Repository: $repository"
    echo "Image Name: $image_name"
    echo "Tag: $tag"
    
    # Check if image exists in local registry
    if check_image_exists "${new_image_name#${LOCAL_REGISTRY}/}" "${tag}"; then
        echo "Image ${new_image_name}:${tag} already exists in local registry. Skipping."
    else
        echo "===> Loading $tar_file"
        sudo $NERDCTL load -i "$tar_file" || exit 1
        
        echo "===> Tag ${full_image_name}:${tag} -> ${new_image_name}:${tag}"
        sudo $NERDCTL tag "${full_image_name}:${tag}" "${new_image_name}:${tag}" || exit 1
        
        echo "===> Push ${new_image_name}:${tag}"
        sudo $NERDCTL push "${new_image_name}:${tag}" || exit 1
    fi
}

load_images() {
    IMAGES_TO_DELETE=()
    for tar_image in $BASEDIR/images/*.tar.gz; do
        process_image "$tar_image"
    done
}

load_images
