#!/bin/bash

REGISTRY_IMAGE=registry:2.8.2
REGISTRY_DIR=$(pwd)/outputs/registry-volume
REGISTRY_PORT=35000
LOCAL_REGISTRY=localhost:${REGISTRY_PORT}
# Exit the script if any command fails
set -e

# Function to run private Docker registry
run_private_registry() {
    echo "Running private Docker registry..."

    # Check if Registry is already running
    if nerdctl ps --format '{{.Names}}' | grep -q '^registry$'; then
        echo "Registry is already running. Skipping."
        return
    fi

    # Run private registry using nerdctl
    nerdctl run -d \
        --name registry \
        -p $REGISTRY_PORT:5000 \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Origin="[http://registry.example.com]" \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Methods="[HEAD,GET,OPTIONS,DELETE]" \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Credentials="[true]" \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Headers="[Authorization,Accept,Cache-Control]" \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Expose-Headers="[Docker-Content-Digest]" \
        -e REGISTRY_STORAGE_DELETE_ENABLED=true \
        -v $REGISTRY_DIR:/var/lib/registry \
        $REGISTRY_IMAGE

    echo "Private Docker registry has been successfully started."
    echo "Registry is accessible on localhost."
}

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

pull_and_push_images() {
    cat imagelists/*.txt | sed "s/#.*$//g" | sort -u > outputs/images/additional-images.list	
    images=$(cat outputs/images/*.list)
    for image in $images; do
        # Removes specific repo parts from each image for kubespray
        newImage=$image

        for repo in registry.k8s.io k8s.gcr.io gcr.io docker.io quay.io "nvcr.io/nvidia/cloud-native" "nvcr.io/nvidia/k8s" "nvcr.io/nvidia" "ghcr.io"; do
            newImage=$(echo ${newImage} | sed s@^${repo}/@@)
        done

        # Separate image name and tag
        image_name=$(echo ${newImage} | cut -d: -f1)
        tag=$(echo ${newImage} | cut -d: -f2)
        if [ "$tag" = "$image_name" ]; then
            tag="latest"
        fi

        # Check if image already exists in private registry
        if check_image_exists "$image_name" "$tag"; then
            echo "===> Image ${image_name}:${tag} already exists in private registry. Skipping."
            continue
        fi

        newImage=${LOCAL_REGISTRY}/${newImage}

        echo "===> Pull ${image}"
        nerdctl pull ${image} || exit 1

        echo "===> Tag ${image} -> ${newImage}"
        nerdctl tag ${image} ${newImage} || exit 1

        echo "===> Push ${newImage}"
        nerdctl push ${newImage} || exit 1

        if [[ $image != *$REGISTRY_IMAGE ]]; then
            echo "===> Remove ${image} and ${newImage}"
            nerdctl rmi ${image} ${newImage}
        fi
    done
}

stop_and_remove_registry() {
    echo "Stopping and removing the registry container..."
    nerdctl stop registry && nerdctl rm registry
    echo "Registry container has been stopped and removed."
}

# Function calls
run_private_registry
pull_and_push_images
stop_and_remove_registry
