#!/bin/bash
export LANG=en_US.UTF-8

# Fixing the environment name
environment_name="prod"

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
    
    # Set ingress.enabled based on ACCESS_MODE
    if [ "$ACCESS_MODE" = "ingress" ]; then
        INGRESS_ENABLED="true"
        echo "===> Access Mode: Ingress"
    else
        INGRESS_ENABLED="false"
        echo "===> Access Mode: NodePort (default)"
    fi
    
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
            elif [ -n "$APP_NAME" ]; then
                echo "Running helmfile -e $environment_name -l app=$APP_NAME $COMMAND."
                if [ "$COMMAND" = "sync" ]; then
                    # sync는 --set 옵션 사용
                    helmfile -e "$environment_name" -l "app=$APP_NAME" \
                        --set ingress.enabled=$INGRESS_ENABLED \
                        --set astrago.ingress.enabled=$INGRESS_ENABLED \
                        --set astrago.ingress.tls.enabled=$INGRESS_ENABLED \
                        --set astrago.truststore.enabled=$INGRESS_ENABLED \
                        "$COMMAND"
                else
                    # destroy는 --set 옵션 없이
                    helmfile -e "$environment_name" -l "app=$APP_NAME" "$COMMAND"
                fi
            else
                echo "Running helmfile -e $environment_name $COMMAND."
                if [ "$COMMAND" = "sync" ]; then
                    # sync는 --set 옵션 사용
                    helmfile -e "$environment_name" \
                        --set ingress.enabled=$INGRESS_ENABLED \
                        --set astrago.ingress.enabled=$INGRESS_ENABLED \
                        --set astrago.ingress.tls.enabled=$INGRESS_ENABLED \
                        --set astrago.truststore.enabled=$INGRESS_ENABLED \
                        "$COMMAND"
                else
                    # destroy는 --set 옵션 없이
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

