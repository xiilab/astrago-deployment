#!/bin/bash
export LANG=en_US.UTF-8

# Fixing the environment name
environment_name="astrago"

CURRENT_DIR=$(dirname "$(realpath "$0")")

# Function to check and install binaries
install_binary() {
    local cmd=$1
    if ! command -v $cmd &> /dev/null; then
        echo "===> Installing $cmd"
        if [[ -f "$CURRENT_DIR/tools/linux/$cmd" ]]; then
            sudo cp "$CURRENT_DIR/tools/linux/$cmd" /usr/local/bin/
            sudo chmod +x /usr/local/bin/$cmd
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
    echo "Usage: $0 [env|sync|destroy]"
    echo ""
    echo "env          : Create a new environment configuration file. Prompts the user for the external connection IP address, NFS server IP address, and base path of NFS."
    echo "sync         : Install (or update) the entire Astrago app for the already configured environment."
    echo "destroy      : Uninstall the entire Astrago app for the already configured environment."
    echo "sync <app name>    : Install (or update) a specific app."
    echo "                Usage: $0 sync <app name>"
    echo "destroy <app name> : Uninstall a specific app."
    echo "                Usage: $0 destroy <app name>"
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
    if [ ! -d "astrago-platform/environments/$environment_name" ]; then
        echo "Environment directory does not exist. Creating..."
        mkdir -p "astrago-platform/environments/$environment_name"
        echo "Environment directory has been created."
    else
        echo "Environment directory already exists."
    fi
    cp -r astrago-platform/environments/prod/* "astrago-platform/environments/$environment_name/"
    # Print the path of the created environment file
    echo "Path where environment file is created: $(realpath "astrago-platform/environments/$environment_name/values.yaml"), Please modify this file for detailed settings."
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
    case "$1" in
        "--help")
            print_usage
            ;;
        "env")
            # Get the external IP address from the user
            get_ip_address external_ip "Enter the connection URL (e.g. 10.61.3.12)"

            # Get the NFS server IP address from the user
            get_ip_address nfs_server_ip "Enter the NFS server IP address"

            # Get the base path of NFS from the user
            get_base_path nfs_base_path "Enter the base path of NFS"

            values_file="astrago-platform/environments/$environment_name/values.yaml"

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
            if [ ! -d "astrago-platform/environments/$environment_name" ]; then
                echo "Environment is not configured. Please run env first."
            elif [ -n "$2" ]; then
                echo "Running helmfile -e $environment_name -l app=$2 $1."
                cd astrago-platform && helmfile -e "$environment_name" -l "app=$2" "$1"
            else
                echo "Running helmfile -e $environment_name $1."
                cd astrago-platform && helmfile -e "$environment_name" "$1"
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

