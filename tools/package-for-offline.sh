#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/versions.conf"

# Package name with version
PACKAGE_NAME="astrago-tools-offline-$(date +%Y%m%d).tar.gz"

print_info "Creating offline package..."

# Check if binaries exist
if [ ! -d "${SCRIPT_DIR}/linux" ] || [ -z "$(ls -A ${SCRIPT_DIR}/linux)" ]; then
    print_warn "Binaries not found. Downloading first..."
    bash "${SCRIPT_DIR}/download-binaries.sh"
fi

# Create package
cd "${SCRIPT_DIR}/.."
tar czf "${PACKAGE_NAME}" \
    tools/linux/ \
    tools/versions.conf \
    tools/download-binaries.sh \
    tools/install_helmfile.sh \
    deploy_astrago.sh \
    deploy_astrago_v2.sh \
    --exclude='*.tar.gz'

print_info "✓ Offline package created: ${PACKAGE_NAME}"
print_info "Size: $(du -h ${PACKAGE_NAME} | cut -f1)"
print_info ""
print_info "To use in offline environment:"
print_info "1. Copy ${PACKAGE_NAME} to target server"
print_info "2. Extract: tar xzf ${PACKAGE_NAME}"
print_info "3. Run: ./deploy_astrago.sh or ./deploy_astrago_v2.sh"