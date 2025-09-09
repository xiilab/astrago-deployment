#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions for colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Detect OS and Architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Convert architecture names
case ${ARCH} in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        print_error "Unsupported architecture: ${ARCH}"
        ;;
esac

# Load versions from file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/versions.conf"

# Create directories based on OS
BINARY_DIR="${SCRIPT_DIR}/${OS}"
mkdir -p "${BINARY_DIR}"

print_info "Downloading binaries for ${OS}/${ARCH}..."
print_info "Versions: helm=${HELM_VERSION}, helmfile=${HELMFILE_VERSION}, kubectl=${KUBECTL_VERSION}, yq=${YQ_VERSION}"

# Function to download and extract
download_binary() {
    local name=$1
    local url=$2
    local extract_cmd=$3
    
    print_info "Downloading ${name}..."
    
    # Download
    curl -L "${url}" -o "/tmp/${name}.tmp" || print_error "Failed to download ${name}"
    
    # Extract or move
    if [ -n "${extract_cmd}" ]; then
        eval "${extract_cmd}"
    else
        mv "/tmp/${name}.tmp" "${BINARY_DIR}/${name}"
    fi
    
    # Make executable
    chmod +x "${BINARY_DIR}/${name}"
    
    print_info "✓ ${name} downloaded successfully"
}

# Download Helm
HELM_URL="https://get.helm.sh/helm-v${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
download_binary "helm" "${HELM_URL}" \
    "tar xzf /tmp/helm.tmp -C /tmp && mv /tmp/${OS}-${ARCH}/helm ${BINARY_DIR}/helm"

# Download Helmfile
HELMFILE_URL="https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_${OS}_${ARCH}.tar.gz"
download_binary "helmfile" "${HELMFILE_URL}" \
    "tar xzf /tmp/helmfile.tmp -C ${BINARY_DIR} helmfile"

# Download kubectl
KUBECTL_URL="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
download_binary "kubectl" "${KUBECTL_URL}" ""

# Download yq
YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_${OS}_${ARCH}"
download_binary "yq" "${YQ_URL}" ""

# Download Helm Diff Plugin
print_info "Downloading Helm Diff Plugin..."
HELM_PLUGINS_DIR="${BINARY_DIR}/.helm/plugins/helm-diff"
mkdir -p "${HELM_PLUGINS_DIR}"

# Convert OS name for helm-diff (darwin -> macos)
HELM_DIFF_OS=${OS}
if [ "${OS}" = "darwin" ]; then
    HELM_DIFF_OS="macos"
fi

HELM_DIFF_URL="https://github.com/databus23/helm-diff/releases/download/v${HELM_DIFF_VERSION}/helm-diff-${HELM_DIFF_OS}-${ARCH}.tgz"
print_info "Downloading from: ${HELM_DIFF_URL}"
curl -L "${HELM_DIFF_URL}" -o "/tmp/helm-diff.tgz" || print_error "Failed to download helm-diff plugin"

# Verify the downloaded file is a valid archive
if ! tar -tzf "/tmp/helm-diff.tgz" &>/dev/null; then
    print_error "Downloaded file is not a valid tar.gz archive"
fi

# Extract to temp directory first, then move files
mkdir -p "/tmp/helm-diff-extract"
tar xzf "/tmp/helm-diff.tgz" -C "/tmp/helm-diff-extract" || print_error "Failed to extract helm-diff plugin"

# Move extracted files to plugin directory (diff/* -> helm-diff/*)
if [ -d "/tmp/helm-diff-extract/diff" ]; then
    cp -r "/tmp/helm-diff-extract/diff"/* "${HELM_PLUGINS_DIR}/"
else
    print_error "Extracted plugin structure is unexpected"
fi

# Clean up temp directory
rm -rf "/tmp/helm-diff-extract"

# Verify all binaries
print_info "Verifying binaries..."
for binary in helm helmfile kubectl yq; do
    if [ -f "${BINARY_DIR}/${binary}" ]; then
        print_info "✓ ${binary} is ready"
    else
        print_error "✗ ${binary} is missing"
    fi
done

# Verify helm diff plugin
if [ -f "${HELM_PLUGINS_DIR}/bin/diff" ]; then
    print_info "✓ helm-diff plugin is ready"
else
    print_error "✗ helm-diff plugin is missing"
fi

print_info "All binaries downloaded successfully to ${BINARY_DIR}"
print_info "Platform: ${OS}/${ARCH}"
print_info "You can now use deploy_astrago.sh script"