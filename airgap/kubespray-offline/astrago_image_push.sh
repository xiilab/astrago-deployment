#!/bin/bash

REGISTRY_IMAGE=registry:2.8.2
REGISTRY_DIR=$(pwd)/outputs/registry-volume
REGISTRY_PORT=35000
LOCAL_REGISTRY=localhost:${REGISTRY_PORT}
# Exit the script if any command fails
set -e

# Function to detect OS, version, and OS family
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VERSION=$DISTRIB_RELEASE
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | awk '{print tolower($1)}')
        VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | cut -d . -f1)
    else
        OS=$(uname -s)
        VERSION=$(uname -r)
    fi

    OS=$(echo $OS | tr '[:upper:]' '[:lower:]')

    # Determine OS family
    case $OS in
        ubuntu|debian)
            OS_FAMILY="debian"
            ;;
        centos|rhel|fedora|rocky|almalinux|ol|amzn)
            OS_FAMILY="rhel"
            # Handle CentOS Stream separately
            if [ "$OS" = "centos" ] && grep -q "Stream" /etc/centos-release 2>/dev/null; then
                OS="centosstream"
            fi
            ;;
        *)
            OS_FAMILY="unknown"
            ;;
    esac

    echo "Detected OS: $OS"
    echo "Detected Version: $VERSION"
    echo "OS Family: $OS_FAMILY"
}

# Function to install containerd and nerdctl
install_containerd_and_nerdctl() {
    # Check if containerd is already installed
    if command -v containerd &> /dev/null; then
        echo "containerd is already installed. Skipping installation."
    else
        echo "Starting containerd installation..."

        if [ "$OS_FAMILY" = "debian" ]; then
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y containerd.io
        elif [ "$OS_FAMILY" = "rhel" ]; then
            # Check CentOS version
            if [ "$(. /etc/os-release && echo "$VERSION_ID")" -ge "8" ]; then
                # CentOS 8 or later
                sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                sudo dnf install -y containerd.io --allowerasing
            else
                # CentOS 7 or earlier
                sudo yum install -y yum-utils
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                sudo yum install -y containerd.io
            fi
        else
            echo "Unsupported OS for automatic installation. Please install containerd manually."
            exit 1
        fi

	#cni plugin install
	export ARCH_CNI=$( [ $(uname -m) = aarch64 ] && echo arm64 || echo amd64)
        export CNI_PLUGIN_VERSION=v1.5.1
        curl -L -o cni-plugins.tgz "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGIN_VERSION}/cni-plugins-linux-${ARCH_CNI}-${CNI_PLUGIN_VERSION}".tgz
        sudo mkdir -p /opt/cni/bin
        sudo tar -C /opt/cni/bin -xzf cni-plugins.tgz

        # Create default configuration file
        sudo mkdir -p /etc/containerd
        sudo containerd config default | sudo tee /etc/containerd/config.toml

        # Start containerd service and enable it to start on boot
        sudo systemctl restart containerd
        sudo systemctl enable containerd

        echo "containerd has been successfully installed and configured."
    fi

    # Check if nerdctl is already installed
    if command -v nerdctl &> /dev/null; then
        echo "nerdctl is already installed. Skipping installation."
    else
        echo "Starting nerdctl installation..."
        NERDCTL_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
        curl -LO https://github.com/containerd/nerdctl/releases/download/${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION#v}-linux-amd64.tar.gz
        sudo tar Cxzvf /usr/local/bin nerdctl-${NERDCTL_VERSION#v}-linux-amd64.tar.gz
        rm nerdctl-${NERDCTL_VERSION#v}-linux-amd64.tar.gz

        echo "nerdctl has been successfully installed."
    fi
}

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
detect_os
run_private_registry
pull_and_push_images
stop_and_remove_registry
