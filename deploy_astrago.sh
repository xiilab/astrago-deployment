#!/bin/bash
export LANG=en_US.UTF-8

# Fixing the environment name
environment_name="prod"

# Portable alternative to realpath (works on Ubuntu, RedHat, and older systems)
CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)

# Function to check and install binaries
install_binary() {
    local cmd=$1
    if ! command -v $cmd &> /dev/null; then
        echo "===> Installing $cmd"
        if [[ -f "$CURRENT_DIR/tools/linux/$cmd" ]]; then
            # Handle sudo availability (works on both Ubuntu and RedHat)
            if [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null; then
                sudo cp "$CURRENT_DIR/tools/linux/$cmd" /usr/local/bin/
                sudo chmod +x /usr/local/bin/$cmd
            elif [ "$EUID" -eq 0 ]; then
                cp "$CURRENT_DIR/tools/linux/$cmd" /usr/local/bin/
                chmod +x /usr/local/bin/$cmd
            else
                echo "FATAL: This script requires root privileges. Run as root or install sudo."
                exit 1
            fi
        else
            echo "FATAL: $cmd binary not found in tools folder."
            exit 1
        fi
    else
        echo "$cmd is already installed."
    fi
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [env|sync|destroy] [OPTIONS]"
    echo ""
    echo "env          : Create a new environment configuration file. Prompts the user for the external connection IP address, NFS server IP address, and base path of NFS."
    echo "sync         : Install (or update) the entire Astrago app for the already configured environment."
    echo "destroy      : Uninstall the entire Astrago app for the already configured environment."
    echo "sync <app name>    : Install (or update) a specific app."
    echo "                Usage: $0 sync <app name> [--mode=nodeport|ingress]"
    echo "destroy <app name> : Uninstall a specific app."
    echo "                Usage: $0 destroy <app name>"
    echo ""
    echo "OPTIONS:"
    echo "  --mode=nodeport  : Use NodePort access mode (default)"
    echo "  --mode=ingress   : Use Ingress access mode"
    echo ""
    echo "Available Apps:"
    echo "nfs-provisioner"
    echo "gpu-operator"
    echo "gpu-process-exporter"
    echo "loki-stack"
    echo "prometheus"
    echo "event-exporter"
    echo "keycloak"
    echo "mpi-operator"
    echo "astrago"
    exit 0
}

# Function to create environment directory
create_environment_directory() {
    if [ ! -d "environments/$environment_name" ]; then
        echo "Environment directory does not exist. Creating..."
        mkdir "environments/$environment_name"
        echo "Environment directory has been created."
    else
        echo "Environment directory already exists."
    fi
    cp -r environments/prod/* "environments/$environment_name/"
    # Print the path of the created environment file
    echo "Path where environment file is created: $(realpath "environments/$environment_name/values.yaml"), Please modify this file for detailed settings."
}

# Function to get the IP address from the user
get_ip_address() {
    local ip_variable=$1
    local message=$2
    echo -n "$message: "
    read -r ip
    eval "$ip_variable=$ip"
}

# Function to get the volume type from the user
get_volume_type() {
    local volume_type_variable=$1
    while true; do
        echo -n "Enter the volume type (nfs or local): "
        read -r volume_type
        if [ "$volume_type" == "nfs" ] || [ "$volume_type" == "local" ]; then
            eval "$volume_type_variable=$volume_type"
            break
        else
            echo "Invalid volume type. Please enter again."
        fi
    done
}

# Function to get the base path for folder creation from the user
get_base_path() {
    local base_path_variable=$1
    local message=$2
    echo -n "$message: "
    read -r base_path
    eval "$base_path_variable=$base_path"
}

# Main function
main() {
    # Check and install yq (mikefarah/yq) if not available or wrong version
    YQ_CORRECT=false
    if command -v yq &> /dev/null; then
        # Check if it's the correct yq (mikefarah/yq)
        if yq --version 2>&1 | grep -q "mikefarah"; then
            YQ_CORRECT=true
        else
            echo "Wrong yq version detected (Python yq). Installing correct yq (mikefarah/yq)..."
        fi
    else
        echo "yq not found. Installing yq (mikefarah/yq)..."
    fi

    if [ "$YQ_CORRECT" = false ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            brew install mikefarah/tap/yq
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux - with wget/curl fallback for compatibility
            YQ_VERSION="v4.35.1"
            YQ_BINARY="yq_linux_amd64"
            YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"

            # Download with wget or curl (works on both Ubuntu and RedHat)
            if command -v wget &> /dev/null; then
                wget "${YQ_URL}" -O /tmp/yq_new
            elif command -v curl &> /dev/null; then
                curl -L "${YQ_URL}" -o /tmp/yq_new
            else
                echo "FATAL: Neither wget nor curl found. Please install wget or curl."
                exit 1
            fi

            # Handle sudo availability (works on both Ubuntu and RedHat)
            if [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null; then
                sudo mv /tmp/yq_new /usr/local/bin/yq
                sudo chmod +x /usr/local/bin/yq
            elif [ "$EUID" -eq 0 ]; then
                mv /tmp/yq_new /usr/local/bin/yq
                chmod +x /usr/local/bin/yq
            else
                echo "FATAL: This script requires root privileges. Run as root or install sudo."
                exit 1
            fi
        fi
        echo "yq (mikefarah/yq) installed successfully."
    fi

    # Parse --mode option (default: nodeport)
    ACCESS_MODE="nodeport"
    APP_NAME=""
    COMMAND=""

    for arg in "$@"; do
        case "$arg" in
            --mode=*)
                ACCESS_MODE="${arg#*=}"
                ;;
            --help)
                print_usage
                ;;
            env|sync|destroy)
                COMMAND="$arg"
                ;;
            *)
                if [ -z "$APP_NAME" ] && [ -n "$COMMAND" ]; then
                    APP_NAME="$arg"
                fi
                ;;
        esac
    done

    case "$COMMAND" in
        "env")
            # Get the external IP address from the user
            get_ip_address external_ip "Enter the connection URL (e.g. 10.61.3.12)"

            # Get the NFS server IP address from the user
            get_ip_address nfs_server_ip "Enter the NFS server IP address"

            # Get the base path of NFS from the user
            get_base_path nfs_base_path "Enter the base path of NFS"

            values_file="environments/$environment_name/values.yaml"

            create_environment_directory
            # Modify externalIP
            yq -i ".externalIP = \"$external_ip\"" "$values_file"

            # Modify nfs server IP address and base path
            yq -i ".nfs.server = \"$nfs_server_ip\"" "$values_file"
            yq -i ".nfs.server = \"$nfs_server_ip\"" "$values_file"
            yq -i ".nfs.basePath = \"$nfs_base_path\"" "$values_file"
            echo "values.yaml file has been modified."
            ;;
        "sync" | "destroy")
            if [ ! -d "environments/$environment_name" ]; then
                echo "Environment is not configured. Please run env first."
            else
                # Update values.yaml based on ACCESS_MODE
                VALUES_FILE="environments/$environment_name/values.yaml"
                if [ "$ACCESS_MODE" = "ingress" ]; then
                    echo "===> Access Mode: Ingress"
                    echo "Updating $VALUES_FILE for Ingress mode..."
                    yq -i '.ingress.enabled = true' "$VALUES_FILE"
                    yq -i '.astrago.ingress.enabled = true' "$VALUES_FILE"
                    yq -i '.astrago.ingress.tls.enabled = true' "$VALUES_FILE"
                    yq -i '.astrago.truststore.enabled = true' "$VALUES_FILE"
                else
                    echo "===> Access Mode: NodePort (default)"
                    echo "Updating $VALUES_FILE for NodePort mode..."
                    yq -i '.ingress.enabled = false' "$VALUES_FILE"
                    yq -i '.astrago.ingress.enabled = false' "$VALUES_FILE"
                    yq -i '.astrago.ingress.tls.enabled = false' "$VALUES_FILE"
                    yq -i '.astrago.truststore.enabled = false' "$VALUES_FILE"
                fi

                if [ -n "$APP_NAME" ]; then
                    echo "Running helmfile -e $environment_name -l app=$APP_NAME $COMMAND."
                    helmfile -e "$environment_name" -l "app=$APP_NAME" "$COMMAND"
                else
                    echo "Running helmfile -e $environment_name $COMMAND."
                    helmfile -e "$environment_name" "$COMMAND"
                fi
            fi
            ;;
        *)
            print_usage
            ;;
    esac
}

# Script execution
for cmd in helm helmfile kubectl; do
    install_binary $cmd
done
main "$@"