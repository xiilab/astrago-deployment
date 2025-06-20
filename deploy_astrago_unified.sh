#!/bin/bash
export LANG=en_US.UTF-8

# Unified Astrago Deployment Script
# Supports both online and offline (airgap) installations

CURRENT_DIR=$(dirname "$(realpath "$0")")
environment_name="astrago"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${RESET}"
}

print_success() {
    echo -e "${GREEN}✅ $1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${RESET}"
}

print_error() {
    echo -e "${RED}❌ $1${RESET}"
}

print_header() {
    echo -e "${CYAN}${BOLD}$1${RESET}"
}

# Function to detect Python version
detect_python_version() {
    # Try different Python versions
    for py_version in python3.12 python3.11 python3.10 python3; do
        if command -v "$py_version" &> /dev/null; then
            # Extract version number
            local version_string=$($py_version --version 2>&1 | cut -d' ' -f2)
            local major_minor=$(echo "$version_string" | cut -d'.' -f1,2)
            
            # Check if version is 3.9 or higher (required for ansible)
            if python3 -c "import sys; exit(0 if sys.version_info >= (3, 9) else 1)" 2>/dev/null; then
                echo "$py_version:$major_minor"
                return 0
            fi
        fi
    done
    
    echo "none:0"
    return 1
}

# Function to setup Python environment
setup_python_environment() {
    local python_info=$(detect_python_version)
    local python_cmd=$(echo "$python_info" | cut -d':' -f1)
    local python_version=$(echo "$python_info" | cut -d':' -f2)
    
    if [ "$python_cmd" = "none" ]; then
        print_error "Python 3.9+ not found. Please install Python 3.9 or higher."
        exit 1
    fi
    
    print_info "Using $python_cmd (version $python_version)"
    
    # Create virtual environment directory name based on detected version
    local venv_dir="$HOME/.venv/$python_version"
    
    if [ ! -d "$venv_dir" ]; then
        print_info "Creating Python virtual environment at $venv_dir"
        $python_cmd -m venv "$venv_dir" || {
            print_error "Failed to create virtual environment"
            exit 1
        }
    fi
    
    print_info "Activating virtual environment"
    source "$venv_dir/bin/activate" || {
        print_error "Failed to activate virtual environment"
        exit 1
    }
    
    # Store the environment info for later use
    export PYTHON_CMD="$python_cmd"
    export VENV_DIR="$venv_dir"
    export PYTHON_VERSION="$python_version"
}

# Function to check system requirements
check_system_requirements() {
    print_header "🔍 Checking System Requirements"
    
    # Check OS
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    source /etc/os-release
    print_info "Detected OS: $NAME $VERSION"
    
    # Check for required commands
    local missing_commands=()
    for cmd in git curl wget; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        print_error "Missing required commands: ${missing_commands[*]}"
        print_info "Please install them using your package manager"
        exit 1
    fi
    
    # Check disk space (minimum 10GB)
    local available_space=$(df "$CURRENT_DIR" | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 10485760 ]; then # 10GB in KB
        print_warning "Low disk space. At least 10GB recommended."
    fi
    
    print_success "System requirements check passed"
}

# Prompt user to select installation mode
select_installation_mode() {
    echo ""
    print_header "🔧 Select Installation Mode"
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
                print_error "Invalid choice. Please select 1 or 2."
                ;;
        esac
    done
}

# Function to check and install binaries
install_binary() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        print_info "Installing $cmd"
        if [[ -f "$CURRENT_DIR/tools/linux/$cmd" ]]; then
            sudo cp "$CURRENT_DIR/tools/linux/$cmd" /usr/local/bin/
            sudo chmod +x "/usr/local/bin/$cmd"
            print_success "$cmd installed successfully"
        else
            print_error "$cmd binary not found in tools folder."
            exit 1
        fi
    else
        print_success "$cmd is already installed."
    fi
}

# Function to print usage
print_usage() {
    echo ""
    print_header "🚀 Unified Astrago Deployment Script"
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
        print_info "Creating environment directory..."
        mkdir -p "environments/$environment_name" || {
            print_error "Failed to create environment directory"
            exit 1
        }
        print_success "Environment directory created"
    else
        print_info "Environment directory already exists"
    fi
    
    # Copy base configuration
    if [ -d "environments/prod" ]; then
        cp -r environments/prod/* "environments/$environment_name/" 2>/dev/null || true
        print_success "Base configuration copied"
    fi
    
    print_info "Environment file location: $(realpath "environments/$environment_name/values.yaml")"
}

# Function to get user input with validation
get_user_input() {
    local var_name=$1
    local message=$2
    local is_password=${3:-false}
    local validation_func=${4:-""}
    
    while true; do
        if [ "$is_password" = true ]; then
            echo -n "$message: "
            read -s value
            echo ""
        else
            echo -n "$message: "
            read -r value
        fi
        
        # Basic validation
        if [ -z "$value" ]; then
            print_error "Value cannot be empty. Please try again."
            continue
        fi
        
        # Custom validation if provided
        if [ -n "$validation_func" ] && ! $validation_func "$value"; then
            print_error "Invalid input. Please try again."
            continue
        fi
        
        break
    done
    
    eval "$var_name='$value'"
}

# Validation functions
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a ip_parts=($ip)
        for part in "${ip_parts[@]}"; do
            if [ "$part" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

validate_url() {
    local url=$1
    if [[ $url =~ ^https?:// ]] || [[ $url =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]]; then
        return 0
    else
        return 1
    fi
}

# Function to configure environment
configure_environment() {
    local mode=$1
    
    print_header "🔧 Configuring environment for $mode mode..."
    
    # Create environment directory first
    create_environment_directory
    
    values_file="environments/$environment_name/values.yaml"
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        print_error "yq command not found. Please install yq first."
        exit 1
    fi
    
    # Common settings
    print_info "Configuring basic settings..."
    get_user_input external_ip "Enter the external IP address" false validate_ip
    get_user_input nfs_server_ip "Enter the NFS server IP address" false validate_ip
    get_user_input nfs_base_path "Enter the base path of NFS (e.g., /mnt/nfs)"
    
    # Apply common settings with error checking
    yq -i ".externalIP = \"$external_ip\"" "$values_file" || {
        print_error "Failed to update externalIP in values file"
        exit 1
    }
    yq -i ".nfs.server = \"$nfs_server_ip\"" "$values_file" || {
        print_error "Failed to update NFS server in values file"
        exit 1
    }
    yq -i ".nfs.basePath = \"$nfs_base_path\"" "$values_file" || {
        print_error "Failed to update NFS base path in values file"
        exit 1
    }
    
    # Offline-specific settings
    if [ "$mode" = "offline" ]; then
        echo ""
        print_info "Configuring offline-specific settings..."
        get_user_input offline_registry "Enter the offline registry (e.g., 10.61.3.8:35000)"
        get_user_input offline_http_server "Enter the HTTP server (e.g., http://10.61.3.8)" false validate_url
        
        yq -i ".offline.registry = \"$offline_registry\"" "$values_file" || {
            print_error "Failed to update offline registry in values file"
            exit 1
        }
        yq -i ".offline.httpServer = \"$offline_http_server\"" "$values_file" || {
            print_error "Failed to update offline HTTP server in values file"
            exit 1
        }
    fi
    
    print_success "Environment configuration completed!"
}

# Function to prepare offline packages
prepare_offline_packages() {
    print_header "📦 Preparing offline packages..."
    
    if [ ! -d "$CURRENT_DIR/airgap/kubespray-offline" ]; then
        print_error "Airgap directory not found. This command is for offline mode only."
        exit 1
    fi
    
    cd "$CURRENT_DIR/airgap/kubespray-offline" || {
        print_error "Failed to change to airgap directory"
        exit 1
    }
    
    if [ ! -f "./download-all.sh" ]; then
        print_error "download-all.sh script not found"
        exit 1
    fi
    
    chmod +x "./download-all.sh"
    ./download-all.sh || {
        print_error "Failed to download offline packages"
        exit 1
    }
    
    cd "$CURRENT_DIR"
    print_success "Offline packages prepared successfully!"
}

# Function to manage nodes configuration
manage_nodes() {
    local nodes_file="$CURRENT_DIR/nodes.yaml"
    
    print_header "📋 Node Management"
    echo "=================="
    
    # Show existing nodes if any
    if [ -f "$nodes_file" ]; then
        print_info "Current nodes configuration:"
        if [ -r "$nodes_file" ]; then
            cat "$nodes_file"
        else
            print_error "Cannot read nodes file due to permission issues."
            print_info "Please check file permissions: $nodes_file"
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
            print_error "Input error. Exiting."
            exit 1
        }
        
        case $choice in
            1)
                add_node "$nodes_file"
                return
                ;;
            2)
                print_info "Opening nodes file for editing..."
                ${EDITOR:-nano} "$nodes_file"
                return
                ;;
            3)
                if [ ! -f "$nodes_file" ]; then
                    print_error "No nodes configured. Please add at least one node."
                    attempts=$((attempts + 1))
                    continue
                fi
                return
                ;;
            *)
                print_error "Invalid choice. Please try again."
                attempts=$((attempts + 1))
                ;;
        esac
    done
    
    print_error "Too many invalid attempts. Exiting."
    exit 1
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
    print_info "Adding new node"
    
    # Get node name with validation
    while [ $attempts -lt $max_attempts ]; do
        read -p "Node name: " node_name || {
            print_error "Input error. Exiting."
            exit 1
        }
        
        if [ -z "$node_name" ]; then
            print_error "Node name cannot be empty."
            attempts=$((attempts + 1))
            continue
        fi
        
        if ! validate_node_name "$node_name"; then
            print_error "Invalid node name. Must be lowercase alphanumeric with hyphens, max 63 chars."
            print_info "Valid examples: node1, master-node, worker-01"
            attempts=$((attempts + 1))
            continue
        fi
        
        # Check for duplicate node names
        if [ -f "$nodes_file" ]; then
            if [ ! -r "$nodes_file" ]; then
                print_error "Cannot read nodes file for duplicate check. Check permissions."
                exit 1
            fi
            if yq -e ".[] | select(.name == \"$node_name\")" "$nodes_file" > /dev/null 2>&1; then
                print_error "Node name '$node_name' already exists."
                attempts=$((attempts + 1))
                continue
            fi
        fi
        
        break
    done
    
    if [ $attempts -eq $max_attempts ]; then
        print_error "Too many invalid attempts for node name. Exiting."
        exit 1
    fi
    
    # Get IP address with validation
    attempts=0
    while [ $attempts -lt $max_attempts ]; do
        read -p "IP address: " node_ip || {
            print_error "Input error. Exiting."
            exit 1
        }
        
        if [ -z "$node_ip" ]; then
            print_error "IP address cannot be empty."
            attempts=$((attempts + 1))
            continue
        fi
        
        if ! validate_ip "$node_ip"; then
            print_error "Invalid IP address format."
            attempts=$((attempts + 1))
            continue
        fi
        
        # Check for duplicate IP addresses
        if [ -f "$nodes_file" ]; then
            if [ ! -r "$nodes_file" ]; then
                print_error "Cannot read nodes file for duplicate check. Check permissions."
                exit 1
            fi
            if yq -e ".[] | select(.ip == \"$node_ip\")" "$nodes_file" > /dev/null 2>&1; then
                print_error "IP address '$node_ip' already exists."
                attempts=$((attempts + 1))
                continue
            fi
        fi
        
        break
    done
    
    if [ $attempts -eq $max_attempts ]; then
        print_error "Too many invalid attempts for IP address. Exiting."
        exit 1
    fi
    
    # Get roles
    echo "Select roles (comma-separated):"
    echo "  - kube-master: Master node"
    echo "  - kube-node: Worker node"
    read -p "Roles [kube-master,kube-node]: " node_roles || {
        print_error "Input error. Exiting."
        exit 1
    }
    node_roles=${node_roles:-"kube-master,kube-node"}
    
    # Get etcd choice
    read -p "Include in etcd cluster? [Y/n]: " etcd_choice || {
        print_error "Input error. Exiting."
        exit 1
    }
    etcd_choice=${etcd_choice:-Y}
    
    # Create or append to nodes file
    if [ ! -f "$nodes_file" ]; then
        if ! echo "[]" > "$nodes_file" 2>/dev/null; then
            print_error "Cannot create nodes file. Check directory permissions."
            exit 1
        fi
    elif [ ! -w "$nodes_file" ]; then
        print_error "Cannot write to nodes file due to permission issues."
        print_info "Please check file permissions: $nodes_file"
        exit 1
    fi
    
    # Add node using yq
    if ! yq -i ". += [{\"name\": \"$node_name\", \"ip\": \"$node_ip\", \"role\": \"$node_roles\", \"etcd\": \"$etcd_choice\"}]" "$nodes_file" 2>/dev/null; then
        print_error "Failed to add node to file. Check file permissions and disk space."
        exit 1
    fi
    
    print_success "Node $node_name added!"
    
    read -p "Add another node? [y/N]: " add_more || {
        print_error "Input error. Exiting."
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
        print_error "Nodes configuration not found. Please run node management first."
        return 1
    fi
    
    if [ ! -r "$nodes_file" ]; then
        print_error "Cannot read nodes configuration file due to permission issues."
        print_info "Please check file permissions: $nodes_file"
        return 1
    fi
    
    print_info "Generating kubespray inventory..."
    
    # Ensure inventory directory exists
    mkdir -p "$(dirname "$inventory_file")" || {
        print_error "Failed to create inventory directory"
        return 1
    }
    
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
        print_error "Failed to read nodes configuration. File may be corrupted or inaccessible."
        return 1
    fi
    
    if [ "$node_count" -eq 0 ]; then
        print_error "No nodes found in configuration"
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
    
    print_success "Kubespray inventory generated!"
}

# Function to apply offline settings to kubespray inventory
apply_offline_settings() {
    local mode="$1"
    
    if [ "$mode" = "offline" ]; then
        local offline_config_dir="$CURRENT_DIR/kubespray/inventory/mycluster/group_vars/all"
        local offline_config_file="$offline_config_dir/offline.yml"
        
        print_info "Applying offline settings..."
        
        # Create group_vars/all directory if it doesn't exist
        mkdir -p "$offline_config_dir" || {
            print_error "Failed to create offline config directory"
            return 1
        }
        
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
                print_success "Offline settings applied to kubespray inventory"
            else
                print_warning "Offline registry and HTTP server not configured in environment"
            fi
        else
            print_warning "Environment configuration not found. Using default offline settings."
        fi
    fi
}

# Function to install system dependencies
install_system_dependencies() {
    local mode="$1"
    
    print_info "Installing system dependencies..."
    
    # Detect OS
    source /etc/os-release
    
    # Install sshpass if not available
    if ! command -v sshpass &> /dev/null; then
        case $ID_LIKE in
            *debian*)
                sudo apt update
                sudo apt install -y sshpass
                ;;
            *rhel*|*fedora*)
                sudo dnf check-update
                sudo dnf install -y sshpass
                ;;
            *)
                print_error "Unsupported OS family: $ID_LIKE"
                exit 1
                ;;
        esac
    fi
    
    print_success "System dependencies installed"
}

# Function to deploy Kubernetes cluster
deploy_kubernetes_cluster() {
    local mode="$1"
    
    print_header "🏗️ Deploying Kubernetes cluster..."
    
    # Install system dependencies
    install_system_dependencies "$mode"
    
    if [ "$mode" = "offline" ]; then
        # Offline mode - use existing airgap script
        if [ ! -f "$CURRENT_DIR/airgap/deploy_kubernetes.sh" ]; then
            print_error "Kubernetes deployment script not found."
            exit 1
        fi
        
        print_info "Using existing airgap deployment script for offline mode..."
        cd "$CURRENT_DIR/airgap"
        ./deploy_kubernetes.sh
    else
        # Online mode - use kubespray directly
        print_header "🔧 Online Kubernetes Installation"
        echo "================================="
        
        # Check if kubespray is available
        if [ ! -d "$CURRENT_DIR/kubespray" ]; then
            print_error "Kubespray directory not found."
            exit 1
        fi
        
        # Setup Python environment
        setup_python_environment
        
        # Node management
        manage_nodes
        
        # Generate inventory
        generate_kubespray_inventory
        
        # Apply offline settings if in offline mode
        apply_offline_settings "$mode"
        
        # Get SSH credentials
        echo ""
        print_header "🔐 SSH Configuration"
        get_user_input ssh_username "SSH Username"
        get_user_input ssh_password "SSH Password" true
        echo ""
        
        # Install Python dependencies
        print_info "Installing Python dependencies..."
        pip install -r "$CURRENT_DIR/kubespray/requirements.txt" || {
            print_error "Failed to install Python dependencies"
            exit 1
        }
        
        # Run kubespray
        print_info "Starting Kubernetes installation..."
        cd "$CURRENT_DIR/kubespray"
        
        # For offline mode, run offline repository setup first
        if [ "$mode" = "offline" ]; then
            print_info "Setting up offline repositories..."
            ansible-playbook \
                -i "inventory/mycluster/astrago.yaml" \
                --become --become-user=root \
                "$CURRENT_DIR/ansible/offline-repo.yml" \
                --extra-vars "ansible_user=$ssh_username ansible_password=$ssh_password ansible_become_pass=$ssh_password" || {
                print_error "Failed to setup offline repositories"
                exit 1
            }
        fi
        
        ansible-playbook \
            -i "inventory/mycluster/astrago.yaml" \
            --become --become-user=root \
            "cluster.yml" \
            --extra-vars "reset_confirmation=yes ansible_ssh_timeout=30 ansible_user=$ssh_username ansible_password=$ssh_password ansible_become_pass=$ssh_password" || {
            print_error "Failed to deploy Kubernetes cluster"
            exit 1
        }
        
        # Copy kubeconfig
        local kubeconfig_src="$CURRENT_DIR/kubespray/inventory/mycluster/artifacts/admin.conf"
        local kubeconfig_dst="$HOME/.kube/config"
        
        if [ -f "$kubeconfig_src" ]; then
            print_info "Setting up kubeconfig..."
            mkdir -p "$HOME/.kube"
            cp "$kubeconfig_src" "$kubeconfig_dst"
            chmod 600 "$kubeconfig_dst"
            print_success "Kubeconfig copied to $kubeconfig_dst"
        else
            print_warning "Kubeconfig not found at expected location"
        fi
    fi
    
    print_success "Kubernetes cluster deployment completed!"
}

# Function to sync applications
sync_applications() {
    local app_name=$1
    
    if [ ! -d "environments/$environment_name" ]; then
        print_error "Environment is not configured. Please run 'env' command first."
        exit 1
    fi
    
    # Check if helmfile command exists
    if ! command -v helmfile &> /dev/null; then
        print_error "helmfile command not found. Please install helmfile first."
        exit 1
    fi
    
    cd "$CURRENT_DIR" || {
        print_error "Failed to change to project directory"
        exit 1
    }
    
    if [ -n "$app_name" ]; then
        print_info "Installing/updating application: $app_name"
        helmfile -e "$environment_name" -l "app=$app_name" sync || {
            print_error "Failed to sync application: $app_name"
            exit 1
        }
    else
        print_info "Installing/updating all applications..."
        helmfile -e "$environment_name" sync || {
            print_error "Failed to sync applications"
            exit 1
        }
    fi
    print_success "Application sync completed!"
}

# Function to destroy applications
destroy_applications() {
    local app_name=$1
    
    if [ ! -d "environments/$environment_name" ]; then
        print_error "Environment is not configured."
        exit 1
    fi
    
    # Check if helmfile command exists
    if ! command -v helmfile &> /dev/null; then
        print_error "helmfile command not found. Please install helmfile first."
        exit 1
    fi
    
    cd "$CURRENT_DIR" || {
        print_error "Failed to change to project directory"
        exit 1
    }
    
    if [ -n "$app_name" ]; then
        print_info "Uninstalling application: $app_name"
        helmfile -e "$environment_name" -l "app=$app_name" destroy || {
            print_error "Failed to destroy application: $app_name"
            exit 1
        }
    else
        print_warning "This will uninstall ALL applications. Are you sure?"
        read -p "Type 'yes' to confirm: " confirm
        if [ "$confirm" = "yes" ]; then
            print_info "Uninstalling all applications..."
            helmfile -e "$environment_name" destroy || {
                print_error "Failed to destroy applications"
                exit 1
            }
        else
            print_info "Operation cancelled."
            return
        fi
    fi
    print_success "Application destruction completed!"
}

# Function to show status
show_status() {
    print_header "📊 Astrago Deployment Status"
    echo "============================="
    print_info "Environment: $environment_name"
    
    if [ -d "environments/$environment_name" ]; then
        print_success "Environment configured"
        
        # Show environment details
        local values_file="environments/$environment_name/values.yaml"
        if [ -f "$values_file" ]; then
            echo ""
            print_info "Environment configuration:"
            echo "  External IP: $(yq '.externalIP' "$values_file" 2>/dev/null || echo "Not set")"
            echo "  NFS Server: $(yq '.nfs.server' "$values_file" 2>/dev/null || echo "Not set")"
            echo "  NFS Path: $(yq '.nfs.basePath' "$values_file" 2>/dev/null || echo "Not set")"
            
            local offline_registry=$(yq '.offline.registry' "$values_file" 2>/dev/null)
            if [ "$offline_registry" != "null" ] && [ -n "$offline_registry" ]; then
                echo "  Offline Registry: $offline_registry"
                echo "  HTTP Server: $(yq '.offline.httpServer' "$values_file" 2>/dev/null || echo "Not set")"
            fi
        fi
    else
        print_error "Environment not configured"
    fi
    
    echo ""
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        print_success "Kubernetes cluster accessible"
        echo ""
        print_info "Cluster information:"
        kubectl cluster-info | head -2
        
        echo ""
        print_info "Node status:"
        kubectl get nodes -o wide 2>/dev/null || print_warning "Could not retrieve node information"
    else
        print_error "Kubernetes cluster not accessible"
    fi
    
    echo ""
    # Check offline packages availability
    if [ -d "$CURRENT_DIR/airgap/kubespray-offline/outputs" ]; then
        print_success "Offline packages available"
    else
        print_warning "Offline packages not prepared"
    fi
    
    # Check installed applications
    echo ""
    if command -v helmfile &> /dev/null && [ -d "environments/$environment_name" ]; then
        print_info "Application status:"
        cd "$CURRENT_DIR"
        helmfile -e "$environment_name" list 2>/dev/null || print_warning "Could not retrieve application status"
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
                if [ "$mode" != "online" ] && [ "$mode" != "offline" ]; then
                    print_error "Invalid mode. Use 'online' or 'offline'."
                    exit 1
                fi
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
                print_error "Unknown option: $1"
                print_usage
                ;;
        esac
    done
    
    # Show header
    clear
    print_header "🚀 Astrago Unified Deployment Script"
    echo "======================================"
    
    # Check system requirements (except for status command)
    if [ "$command" != "status" ]; then
        check_system_requirements
    fi
    
    # Prompt user to select mode if not specified (except for status command)
    if [ -z "$mode" ] && [ "$command" != "status" ]; then
        mode=$(select_installation_mode)
        print_success "Selected mode: $mode"
    fi
    
    # Install required binaries (except for status command)
    if [ "$command" != "status" ]; then
        print_header "🔧 Installing Required Tools"
        for cmd in helm helmfile kubectl yq; do
            install_binary "$cmd"
        done
    fi
    
    # Execute command
    case "$command" in
        env)
            configure_environment "$mode"
            ;;
        prepare)
            if [ "$mode" != "offline" ]; then
                print_error "'prepare' command is only available in offline mode"
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
            print_error "No command specified"
            print_usage
            ;;
        *)
            print_error "Unknown command: $command"
            print_usage
            ;;
    esac
    
    echo ""
    print_success "Operation completed successfully!"
}

# Run main function
main "$@" 