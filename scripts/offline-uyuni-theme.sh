#!/bin/bash

# Offline Uyuni theme version auto-update
# Usage: ./scripts/offline-uyuni-theme.sh [theme_version]
# If theme_version is not provided, automatically finds the latest version from keycloak.txt

set -e

CURRENT_DIR=$(dirname "$(realpath "$0")")
cd "$CURRENT_DIR/.."

# Environment name (same as offline_deploy_astrago.sh)
ENVIRONMENT="astrago"

# Theme version parameter check
if [ $# -eq 1 ]; then
    THEME_VERSION=$1
    echo "=== Offline Uyuni Theme Version Update ==="
    echo "Environment: $ENVIRONMENT"
    echo "Theme Version: $THEME_VERSION (user specified)"
else
    echo "=== Offline Uyuni Theme Version Auto-Update ==="
    echo "Environment: $ENVIRONMENT"
    echo "Theme Version: auto-detect"
fi

# 1. Environment check
if [ ! -d "environments/$ENVIRONMENT" ]; then
    echo "Environment '$ENVIRONMENT' does not exist."
    echo "Please run './offline_deploy_astrago.sh env' first to configure the environment."
    exit 1
fi

# 2. Check images in keycloak.txt and auto-detect version
KEYCLOAK_TXT="airgap/kubespray-offline/imagelists/keycloak.txt"
if [ -f "$KEYCLOAK_TXT" ]; then
    echo "Checking keycloak.txt..."
    
    if [ -z "$THEME_VERSION" ]; then
        # Auto-detect latest version
        THEME_VERSION=$(grep "astrago-keycloak:" "$KEYCLOAK_TXT" | tail -1 | sed 's/.*astrago-keycloak://')
        if [ -z "$THEME_VERSION" ]; then
            echo "astrago-keycloak image not found in keycloak.txt."
            exit 1
        fi
        echo "Auto-detected theme version: $THEME_VERSION"
    fi
    
    if grep -q "astrago-keycloak:$THEME_VERSION" "$KEYCLOAK_TXT"; then
        echo "Image is registered in keycloak.txt."
    else
        echo "Image is not registered in keycloak.txt."
        echo "Please download images in online environment and try again."
        exit 1
    fi
else
    echo "keycloak.txt file not found."
    echo "Please run './airgap/download-all.sh' in online environment to download images."
    exit 1
fi

# 3. Update values.yaml
echo "Updating values.yaml..."
yq eval ".keycloak.themeVersion = \"$THEME_VERSION\"" -i "environments/$ENVIRONMENT/values.yaml"

echo "Theme version update completed!"
echo ""
echo "Next steps:"
echo "1. Deploy AstraGo:"
echo "   ./offline_deploy_astrago.sh sync" 