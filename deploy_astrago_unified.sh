#!/bin/bash
export LANG=en_US.UTF-8

# Unified Astrago Deployment Script
# Supports both online and offline (airgap) installations

CURRENT_DIR=$(dirname "$(realpath "$0")")
environment_name="astrago"

# Prompt user to select installation mode
select_installation_mode() {
    echo "🔧 Select Installation Mode"
    echo "=========================="
    echo "1) Online Installation  - Install from internet repositories"
    echo "2) Offline Installation - Install from local packages"
    echo ""
    
    while true; do
        read -p "Choose installation mode [1-2]: " choice
        case $choice in
            1)
                echo "online"
                return
                ;;
            2)
                echo "offline"
                return
                ;;
            *)
                echo "❌ Invalid choice. Please select 1 or 2."
                ;;
        esac
    done
}

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
    echo "🚀 Unified Astrago Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "COMMANDS:"
echo "  env                    : Create environment configuration"
echo "  prepare               : Prepare offline packages (offline mode only)"
echo "  cluster               : Deploy Kubernetes cluster"
echo "  sync                  : Install/update applications"
echo "  destroy               : Uninstall applications"
echo "  status                : Show installation status"
    echo ""
    echo "OPTIONS:"
    echo "  --mode [online|offline] : Force installation mode"
    echo "  --app <name>           : Target specific application"
    echo "  --help                 : Show this help"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 env                 : Configure environment (prompt for mode)"
    echo "  $0 --mode online cluster : Deploy K8s cluster (online)"
    echo "  $0 --mode offline cluster : Deploy K8s cluster (offline)"
    echo "  $0 sync                : Install all applications"
    echo "  $0 sync --app keycloak : Install only Keycloak"
    echo ""
    echo "Available Apps:"
    echo "  csi-driver-nfs, gpu-operator, gpu-process-exporter,"
    echo "  loki-stack, prometheus, keycloak, astrago, harbor,"
    echo "  mpi-operator, flux"
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
    echo "📁 Environment file created: $(realpath "environments/$environment_name/values.yaml")"
}

# Function to get user input
get_user_input() {
    local var_name=$1
    local message=$2
    local is_password=${3:-false}
    
    if [ "$is_password" = true ]; then
        echo -n "$message: "
        read -s value
        echo ""
    else
        echo -n "$message: "
        read -r value
    fi
    eval "$var_name='$value'"
}

# Function to configure environment
configure_environment() {
    local mode=$1
    
    echo "🔧 Configuring environment for $mode mode..."
    
    # Common settings
    get_user_input external_ip "Enter the connection URL (e.g. 10.61.3.12)"
    get_user_input nfs_server_ip "Enter the NFS server IP address"
    get_user_input nfs_base_path "Enter the base path of NFS"
    
    values_file="environments/$environment_name/values.yaml"
    create_environment_directory
    
    # Apply common settings
    yq -i ".externalIP = \"$external_ip\"" "$values_file"
    yq -i ".nfs.server = \"$nfs_server_ip\"" "$values_file"
    yq -i ".nfs.basePath = \"$nfs_base_path\"" "$values_file"
    
    # Offline-specific settings
    if [ "$mode" = "offline" ]; then
        echo ""
        echo "📡 Offline-specific configuration:"
        get_user_input offline_registry "Enter the offline registry (e.g. 10.61.3.8:35000)"
        get_user_input offline_http_server "Enter the HTTP server (e.g. http://10.61.3.8)"
        
        yq -i ".offline.registry = \"$offline_registry\"" "$values_file"
        yq -i ".offline.httpServer = \"$offline_http_server\"" "$values_file"
    fi
    
    echo "✅ Environment configuration completed!"
}

# Function to prepare offline packages
prepare_offline_packages() {
    echo "📦 Preparing offline packages..."
    if [ ! -d "$CURRENT_DIR/airgap/kubespray-offline" ]; then
        echo "❌ Airgap directory not found. This command is for offline mode only."
        exit 1
    fi
    
    cd "$CURRENT_DIR/airgap/kubespray-offline"
    ./download-all.sh
    echo "✅ Offline packages prepared!"
}

# Function to manage nodes configuration
manage_nodes() {
    local nodes_file="$CURRENT_DIR/nodes.yaml"
    
    echo "📋 Node Management"
    echo "=================="
    
    # Show existing nodes if any
    if [ -f "$nodes_file" ]; then
        echo "Current nodes:"
        if [ -r "$nodes_file" ]; then
            cat "$nodes_file"
        else
            echo "❌ Cannot read nodes file due to permission issues."
            echo "Please check file permissions: $nodes_file"
            exit 1
        fi
        echo ""
    fi
    
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        echo "Select action:"
        echo "1) Add node"
        echo "2) Edit nodes file manually"
        echo "3) Continue with current nodes"
        read -p "Choice [1-3]: " choice || {
            echo "❌ Input error. Exiting."
            exit 1
        }
        
        case $choice in
            1)
                add_node "$nodes_file"
                return
                ;;
            2)
                echo "Opening nodes file for editing..."
                ${EDITOR:-nano} "$nodes_file"
                return
                ;;
            3)
                if [ ! -f "$nodes_file" ]; then
                    echo "❌ No nodes configured. Please add at least one node."
                    attempts=$((attempts + 1))
                    continue
                fi
                return
                ;;
            *)
                echo "Invalid choice. Please try again."
                attempts=$((attempts + 1))
                ;;
        esac
    done
    
    echo "❌ Too many invalid attempts. Exiting."
    exit 1
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a ip_parts=($ip)
        for part in "${ip_parts[@]}"; do
            if [ $part -gt 255 ]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to validate node name (Kubernetes naming conventions)
validate_node_name() {
    local name=$1
    # Kubernetes node names must be lowercase alphanumeric with hyphens
    # and cannot start or end with a hyphen
    if [[ $name =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] && [ ${#name} -le 63 ]; then
        return 0
    else
        return 1
    fi
}

# Function to add a node
add_node() {
    local nodes_file="$1"
    local node_name=""
    local node_ip=""
    local node_roles=""
    local etcd_choice=""
    local attempts=0
    local max_attempts=3
    
    echo ""
    echo "➕ Adding new node"
    
    # Get node name with validation
    while [ $attempts -lt $max_attempts ]; do
        read -p "Node name: " node_name || {
            echo "❌ Input error. Exiting."
            exit 1
        }
        
        if [ -z "$node_name" ]; then
            echo "❌ Node name cannot be empty."
            attempts=$((attempts + 1))
            continue
        fi
        
        if ! validate_node_name "$node_name"; then
            echo "❌ Invalid node name. Must be lowercase alphanumeric with hyphens, max 63 chars."
            echo "   Valid examples: node1, master-node, worker-01"
            attempts=$((attempts + 1))
            continue
        fi
        
        # Check for duplicate node names
        if [ -f "$nodes_file" ]; then
            if [ ! -r "$nodes_file" ]; then
                echo "❌ Cannot read nodes file for duplicate check. Check permissions."
                exit 1
            fi
            if yq -e ".[] | select(.name == \"$node_name\")" "$nodes_file" > /dev/null 2>&1; then
                echo "❌ Node name '$node_name' already exists."
                attempts=$((attempts + 1))
                continue
            fi
        fi
        
        break
    done
    
    if [ $attempts -eq $max_attempts ]; then
        echo "❌ Too many invalid attempts for node name. Exiting."
        exit 1
    fi
    
    # Get IP address with validation
    attempts=0
    while [ $attempts -lt $max_attempts ]; do
        read -p "IP address: " node_ip || {
            echo "❌ Input error. Exiting."
            exit 1
        }
        
        if [ -z "$node_ip" ]; then
            echo "❌ IP address cannot be empty."
            attempts=$((attempts + 1))
            continue
        fi
        
        if ! validate_ip "$node_ip"; then
            echo "❌ Invalid IP address format."
            attempts=$((attempts + 1))
            continue
        fi
        
        # Check for duplicate IP addresses
        if [ -f "$nodes_file" ]; then
            if [ ! -r "$nodes_file" ]; then
                echo "❌ Cannot read nodes file for duplicate check. Check permissions."
                exit 1
            fi
            if yq -e ".[] | select(.ip == \"$node_ip\")" "$nodes_file" > /dev/null 2>&1; then
                echo "❌ IP address '$node_ip' already exists."
                attempts=$((attempts + 1))
                continue
            fi
        fi
        
        break
    done
    
    if [ $attempts -eq $max_attempts ]; then
        echo "❌ Too many invalid attempts for IP address. Exiting."
        exit 1
    fi
    
    # Get roles
    echo "Select roles (comma-separated):"
    echo "  - kube-master: Master node"
    echo "  - kube-node: Worker node"
    read -p "Roles [kube-master,kube-node]: " node_roles || {
        echo "❌ Input error. Exiting."
        exit 1
    }
    node_roles=${node_roles:-"kube-master,kube-node"}
    
    # Get etcd choice
    read -p "Include in etcd cluster? [Y/n]: " etcd_choice || {
        echo "❌ Input error. Exiting."
        exit 1
    }
    etcd_choice=${etcd_choice:-Y}
    
    # Create or append to nodes file
    if [ ! -f "$nodes_file" ]; then
        if ! echo "[]" > "$nodes_file" 2>/dev/null; then
            echo "❌ Cannot create nodes file. Check directory permissions."
            exit 1
        fi
    elif [ ! -w "$nodes_file" ]; then
        echo "❌ Cannot write to nodes file due to permission issues."
        echo "Please check file permissions: $nodes_file"
        exit 1
    fi
    
    # Add node using yq
    if ! yq -i ". += [{\"name\": \"$node_name\", \"ip\": \"$node_ip\", \"role\": \"$node_roles\", \"etcd\": \"$etcd_choice\"}]" "$nodes_file" 2>/dev/null; then
        echo "❌ Failed to add node to file. Check file permissions and disk space."
        exit 1
    fi
    
    echo "✅ Node $node_name added!"
    
    read -p "Add another node? [y/N]: " add_more || {
        echo "❌ Input error. Exiting."
        exit 1
    }
    if [[ "$add_more" =~ ^[Yy]$ ]]; then
        add_node "$nodes_file"
    fi
}

# Function to generate kubespray inventory
generate_kubespray_inventory() {
    local nodes_file="$CURRENT_DIR/nodes.yaml"
    local inventory_file="$CURRENT_DIR/kubespray/inventory/mycluster/astrago.yaml"
    
    if [ ! -f "$nodes_file" ]; then
        echo "❌ Nodes configuration not found. Please run node management first."
        return 1
    fi
    
    if [ ! -r "$nodes_file" ]; then
        echo "❌ Cannot read nodes configuration file due to permission issues."
        echo "Please check file permissions: $nodes_file"
        return 1
    fi
    
    echo "📝 Generating kubespray inventory..."
    
    # Create base inventory structure
    cat > "$inventory_file" << 'EOF'
all:
  children:
    calico-rr:
      hosts: {}
    etcd:
      hosts: {}
    k8s-cluster:
      children:
        kube-master:
          hosts: {}
        kube-node:
          hosts: {}
    kube-master:
      hosts: {}
    kube-node:
      hosts: {}
  hosts: {}
EOF
    
    # Process each node from nodes.yaml
    local node_count=$(yq '. | length' "$nodes_file" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$node_count" ] || ! [[ "$node_count" =~ ^[0-9]+$ ]]; then
        echo "❌ Failed to read nodes configuration. File may be corrupted or inaccessible."
        return 1
    fi
    
    if [ "$node_count" -eq 0 ]; then
        echo "❌ No nodes found in configuration"
        return 1
    fi
    
    for i in $(seq 0 $((node_count - 1))); do
        local node_name=$(yq ".[$i].name" "$nodes_file")
        local node_ip=$(yq ".[$i].ip" "$nodes_file")
        local node_role=$(yq ".[$i].role" "$nodes_file")
        local node_etcd=$(yq ".[$i].etcd" "$nodes_file")
        
        # Remove quotes from yq output
        node_name=$(echo "$node_name" | tr -d '"')
        node_ip=$(echo "$node_ip" | tr -d '"')
        node_role=$(echo "$node_role" | tr -d '"')
        node_etcd=$(echo "$node_etcd" | tr -d '"')
        
        # Add host to all.hosts
        yq -i ".all.hosts.\"$node_name\" = {\"ansible_host\": \"$node_ip\", \"ip\": \"$node_ip\", \"access_ip\": \"$node_ip\"}" "$inventory_file"
        
        # Add to role groups
        IFS=',' read -ra ROLES <<< "$node_role"
        for role in "${ROLES[@]}"; do
            role=$(echo "$role" | xargs) # trim whitespace
            case "$role" in
                kube-master)
                    yq -i ".all.children.\"kube-master\".hosts.\"$node_name\" = null" "$inventory_file"
                    ;;
                kube-node)
                    yq -i ".all.children.\"kube-node\".hosts.\"$node_name\" = null" "$inventory_file"
                    ;;
            esac
        done
        
        # Add to etcd if specified
        if [[ "$node_etcd" =~ ^[Yy]$ ]]; then
            yq -i ".all.children.etcd.hosts.\"$node_name\" = null" "$inventory_file"
        fi
    done
    
    echo "✅ Kubespray inventory generated!"
}

# Function to apply offline settings to kubespray inventory
apply_offline_settings() {
    local mode="$1"
    
    if [ "$mode" = "offline" ]; then
        local offline_config_dir="$CURRENT_DIR/kubespray/inventory/mycluster/group_vars/all"
        local offline_config_file="$offline_config_dir/offline.yml"
        
        echo "📡 Applying offline settings..."
        
        # Create group_vars/all directory if it doesn't exist
        mkdir -p "$offline_config_dir"
        
        # Get offline settings from environment configuration
        local values_file="environments/$environment_name/values.yaml"
        if [ -f "$values_file" ]; then
            local registry_host=$(yq '.offline.registry' "$values_file" | tr -d '"')
            local http_server=$(yq '.offline.httpServer' "$values_file" | tr -d '"')
            
            if [ "$registry_host" != "null" ] && [ "$http_server" != "null" ]; then
                # Create offline configuration
                cat > "$offline_config_file" << EOF
# Offline configuration for kubespray
http_server: "$http_server"
registry_host: "$registry_host"

# Insecure registries for containerd
containerd_registries_mirrors:
  - prefix: "{{ registry_host }}"
    mirrors:
      - host: "http://{{ registry_host }}"
        capabilities: ["pull", "resolve"]
        skip_verify: true

files_repo: "{{ http_server }}/files"
yum_repo: "{{ http_server }}/rpms"
ubuntu_repo: "{{ http_server }}/debs"

# Registry overrides - redirect all image repositories to offline registry
kube_image_repo: "{{ registry_host }}"
gcr_image_repo: "{{ registry_host }}"
docker_image_repo: "{{ registry_host }}"
quay_image_repo: "{{ registry_host }}"

# Download URLs for offline installation
kubeadm_download_url: "{{ files_repo }}/kubernetes/{{ kube_version }}/kubeadm"
kubectl_download_url: "{{ files_repo }}/kubernetes/{{ kube_version }}/kubectl"
kubelet_download_url: "{{ files_repo }}/kubernetes/{{ kube_version }}/kubelet"
etcd_download_url: "{{ files_repo }}/kubernetes/etcd/etcd-{{ etcd_version }}-linux-amd64.tar.gz"
cni_download_url: "{{ files_repo }}/kubernetes/cni/cni-plugins-linux-{{ image_arch }}-{{ cni_version }}.tgz"
crictl_download_url: "{{ files_repo }}/kubernetes/cri-tools/crictl-{{ crictl_version }}-{{ ansible_system | lower }}-{{ image_arch }}.tar.gz"
calicoctl_download_url: "{{ files_repo }}/kubernetes/calico/{{ calico_ctl_version }}/calicoctl-linux-{{ image_arch }}"
calico_crds_download_url: "{{ files_repo }}/kubernetes/calico/{{ calico_version }}.tar.gz"
runc_download_url: "{{ files_repo }}/runc/{{ runc_version }}/runc.{{ image_arch }}"
nerdctl_download_url: "{{ files_repo }}/nerdctl-{{ nerdctl_version }}-{{ ansible_system | lower }}-{{ image_arch }}.tar.gz"
containerd_download_url: "{{ files_repo }}/containerd-{{ containerd_version }}-linux-{{ image_arch }}.tar.gz"
EOF
                echo "✅ Offline settings applied to kubespray inventory"
            else
                echo "⚠️  Offline registry and HTTP server not configured in environment"
            fi
        else
            echo "⚠️  Environment configuration not found. Using default offline settings."
        fi
    fi
}

# Function to deploy Kubernetes cluster
deploy_kubernetes_cluster() {
    local mode="$1"
    
    echo "🏗️ Deploying Kubernetes cluster..."
    
    if [ "$mode" = "offline" ]; then
        # Offline mode - use existing airgap script
        if [ ! -f "$CURRENT_DIR/airgap/deploy_kubernetes.sh" ]; then
            echo "❌ Kubernetes deployment script not found."
            exit 1
        fi
        
        echo "🔧 Using existing airgap deployment script for offline mode..."
        cd "$CURRENT_DIR/airgap"
        ./deploy_kubernetes.sh
    else
        # Online mode - use kubespray directly
        echo ""
        echo "🔧 Online Kubernetes Installation"
        echo "================================="
        
        # Check if kubespray is available
        if [ ! -d "$CURRENT_DIR/kubespray" ]; then
            echo "❌ Kubespray directory not found."
            exit 1
        fi
        
        # Node management
        manage_nodes
        
        # Generate inventory
        generate_kubespray_inventory
        
        # Apply offline settings if in offline mode
        apply_offline_settings "$mode"
        
        # Get SSH credentials
        echo ""
        echo "🔐 SSH Configuration"
        read -p "SSH Username: " ssh_username
        read -s -p "SSH Password: " ssh_password
        echo ""
        
        # Install Python dependencies if needed
        if [ ! -f "$HOME/.venv/3.11/bin/activate" ]; then
            echo "📦 Setting up Python virtual environment..."
            python3 -m venv "$HOME/.venv/3.11"
        fi
        
        source "$HOME/.venv/3.11/bin/activate"
        pip install -r "$CURRENT_DIR/kubespray/requirements.txt" > /dev/null 2>&1
        
        # Run kubespray
        echo "🚀 Starting Kubernetes installation..."
        cd "$CURRENT_DIR/kubespray"
        
        # For offline mode, run offline repository setup first
        if [ "$mode" = "offline" ]; then
            echo "📦 Setting up offline repositories..."
            ansible-playbook \
                -i "inventory/mycluster/astrago.yaml" \
                --become --become-user=root \
                "$CURRENT_DIR/ansible/offline-repo.yml" \
                --extra-vars "ansible_user=$ssh_username ansible_password=$ssh_password ansible_become_pass=$ssh_password"
        fi
        
        ansible-playbook \
            -i "inventory/mycluster/astrago.yaml" \
            --become --become-user=root \
            "cluster.yml" \
            --extra-vars "reset_confirmation=yes ansible_ssh_timeout=30 ansible_user=$ssh_username ansible_password=$ssh_password ansible_become_pass=$ssh_password"
        
        # Copy kubeconfig
        local kubeconfig_src="$CURRENT_DIR/kubespray/inventory/mycluster/artifacts/admin.conf"
        local kubeconfig_dst="$HOME/.kube/config"
        
        if [ -f "$kubeconfig_src" ]; then
            echo "📋 Setting up kubeconfig..."
            mkdir -p "$HOME/.kube"
            cp "$kubeconfig_src" "$kubeconfig_dst"
            chmod 600 "$kubeconfig_dst"
            echo "✅ Kubeconfig copied to $kubeconfig_dst"
        fi
    fi
    
    echo "✅ Kubernetes cluster deployed!"
}

# Function to sync applications
sync_applications() {
    local app_name=$1
    
    if [ ! -d "environments/$environment_name" ]; then
        echo "❌ Environment is not configured. Please run 'env' command first."
        exit 1
    fi
    
    if [ -n "$app_name" ]; then
        echo "🚀 Installing/updating application: $app_name"
        helmfile -e "$environment_name" -l "app=$app_name" sync
    else
        echo "🚀 Installing/updating all applications..."
        helmfile -e "$environment_name" sync
    fi
    echo "✅ Application sync completed!"
}

# Function to destroy applications
destroy_applications() {
    local app_name=$1
    
    if [ ! -d "environments/$environment_name" ]; then
        echo "❌ Environment is not configured."
        exit 1
    fi
    
    if [ -n "$app_name" ]; then
        echo "🗑️ Uninstalling application: $app_name"
        helmfile -e "$environment_name" -l "app=$app_name" destroy
    else
        echo "🗑️ Uninstalling all applications..."
        helmfile -e "$environment_name" destroy
    fi
    echo "✅ Application destruction completed!"
}

# Function to show status
show_status() {
    echo "📊 Astrago Deployment Status"
    echo "============================="
    echo "📁 Environment: $environment_name"
    
    if [ -d "environments/$environment_name" ]; then
        echo "✅ Environment configured"
    else
        echo "❌ Environment not configured"
    fi
    
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        echo "✅ Kubernetes cluster accessible"
        echo "📈 Cluster info:"
        kubectl cluster-info | head -2
    else
        echo "❌ Kubernetes cluster not accessible"
    fi
    
    # Check offline packages availability
    if [ -d "$CURRENT_DIR/airgap/kubespray-offline/outputs" ]; then
        echo "✅ Offline packages available"
    else
        echo "❌ Offline packages not prepared"
    fi
}

# Main function
main() {
    local mode=""
    local command=""
    local app_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                mode="$2"
                shift 2
                ;;
            --app)
                app_name="$2"
                shift 2
                ;;
            --help)
                print_usage
                ;;
            env|prepare|cluster|sync|destroy|status)
                command="$1"
                shift
                ;;
            *)
                echo "❌ Unknown option: $1"
                print_usage
                ;;
        esac
    done
    
    # Prompt user to select mode if not specified (except for status command)
    if [ -z "$mode" ] && [ "$command" != "status" ]; then
        mode=$(select_installation_mode)
        echo "✅ Selected mode: $mode"
    fi
    
    # Execute command
    case "$command" in
        env)
            configure_environment "$mode"
            ;;
        prepare)
            if [ "$mode" != "offline" ]; then
                echo "❌ 'prepare' command is only available in offline mode"
                exit 1
            fi
            prepare_offline_packages
            ;;
        cluster)
            deploy_kubernetes_cluster "$mode"
            ;;
        sync)
            sync_applications "$app_name"
            ;;
        destroy)
            destroy_applications "$app_name"
            ;;
        status)
            show_status
            ;;
        "")
            echo "❌ No command specified"
            print_usage
            ;;
        *)
            echo "❌ Unknown command: $command"
            print_usage
            ;;
    esac
}

# Install required binaries
for cmd in helm helmfile kubectl yq; do
    install_binary $cmd
done

# Run main function
main "$@" 