#!/bin/bash
export LANG=en_US.UTF-8

CURRENT_DIR=$(dirname "$(realpath "$0")")
HELMFILE_DIR="$CURRENT_DIR/helmfile"
TOOLS_DIR="$CURRENT_DIR/tools"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to setup tools
setup_tools() {
    # Detect OS
    local OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    local BINARY_DIR="$TOOLS_DIR/$OS"
    
    # Check if binaries exist
    local tools_missing=false
    for cmd in helm helmfile kubectl yq; do
        if [[ ! -f "$BINARY_DIR/$cmd" ]]; then
            tools_missing=true
            break
        fi
    done
    
    # Download binaries if missing
    if [[ "$tools_missing" == "true" ]]; then
        print_info "Required tools not found. Downloading..."
        if [[ -f "$TOOLS_DIR/download-binaries.sh" ]]; then
            bash "$TOOLS_DIR/download-binaries.sh" || {
                print_error "Failed to download binaries"
                exit 1
            }
        else
            print_error "download-binaries.sh not found"
            exit 1
        fi
    fi
    
    # Add tools to PATH instead of installing to system
    export PATH="$BINARY_DIR:$PATH"
    
    # Set HELM_PLUGINS environment for offline plugin support
    export HELM_PLUGINS="$BINARY_DIR/.helm/plugins"
    
    # Verify all tools are available
    for cmd in helm helmfile kubectl yq; do
        if ! command -v $cmd &> /dev/null; then
            print_error "$cmd not available after setup"
            exit 1
        fi
    done
    
    print_info "All tools are ready"
}

# Function to print usage
print_usage() {
    cat << EOF
Usage: $0 <command> [customer_name] [options]

Commands:
  init <customer>     Initialize a new customer environment
  deploy [customer]   Deploy environment (default or customer)
  destroy [customer]  Destroy environment
  list                List all customer environments
  update-tools        Update tools to latest versions
  
Options:
  --ip <IP>          External IP address
  --nfs-server <IP>  NFS server IP
  --nfs-path <path>  NFS base path
  --help             Show this help message

Examples:
  $0 init samsung --ip 10.1.2.3 --nfs-server 10.1.2.4 --nfs-path /samsung-vol
  $0 deploy samsung
  $0 deploy           # Deploy default environment (branch-based)
  $0 list
  $0 update-tools    # Update binaries to latest versions
EOF
    exit 0
}

# Function to update tools
update_tools() {
    print_info "Updating tools to latest versions..."
    local OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    rm -rf "$TOOLS_DIR/$OS"/*
    bash "$TOOLS_DIR/download-binaries.sh" || {
        print_error "Failed to update tools"
        exit 1
    }
    print_info "Tools updated successfully"
}

# Function to initialize customer environment
init_customer() {
    local customer=$1
    shift
    
    # Parse options
    local external_ip=""
    local nfs_server=""
    local nfs_path=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ip) external_ip="$2"; shift 2 ;;
            --nfs-server) nfs_server="$2"; shift 2 ;;
            --nfs-path) nfs_path="$2"; shift 2 ;;
            *) print_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$customer" ]]; then
        print_error "Customer name is required"
        exit 1
    fi
    
    # Create customer directory
    local customer_dir="$HELMFILE_DIR/environments/customers/$customer"
    if [[ -d "$customer_dir" ]]; then
        print_warn "Customer environment '$customer' already exists"
        read -p "Do you want to overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    mkdir -p "$customer_dir"
    
    # If no parameters provided, prompt for them
    if [[ -z "$external_ip" ]]; then
        read -p "Enter external IP address: " external_ip
    fi
    if [[ -z "$nfs_server" ]]; then
        read -p "Enter NFS server IP: " nfs_server
    fi
    if [[ -z "$nfs_path" ]]; then
        read -p "Enter NFS base path: " nfs_path
    fi
    
    # Create customer values.yaml with overrides only
    cat > "$customer_dir/values.yaml" << EOF
# Customer: $customer
# Generated: $(date)

# Network Configuration
externalIP: $external_ip

# Storage Configuration
nfs:
  server: $nfs_server
  basePath: $nfs_path

# Add customer-specific overrides below
# Example:
# astrago:
#   mariadb:
#     password: custom-password
EOF
    
    # Add customer to helmfile.yaml if not exists
    if ! grep -q "^  $customer:" "$HELMFILE_DIR/helmfile.yaml.gotmpl"; then
        # This would need more complex logic to insert into helmfile.yaml
        print_warn "Please manually add '$customer' environment to helmfile.yaml"
    fi
    
    print_info "Customer environment '$customer' initialized successfully"
    print_info "Configuration saved to: $customer_dir/values.yaml"
    print_info "You can now deploy with: $0 deploy $customer"
}

# Function to deploy environment
deploy_environment() {
    local environment="${1:-default}"
    
    cd "$HELMFILE_DIR" || exit 1
    
    if [[ "$environment" == "default" ]]; then
        print_info "Deploying default environment (branch-based)"
        helmfile -e default apply
    else
        # Check if customer environment exists
        if [[ ! -d "environments/customers/$environment" ]]; then
            print_error "Customer environment '$environment' not found"
            print_info "Run '$0 init $environment' first"
            exit 1
        fi
        
        print_info "Deploying customer environment: $environment"
        # Using environment variable approach for dynamic customer
        CUSTOMER_NAME="$environment" helmfile -e customer apply 2>/dev/null || \
        helmfile -e "$environment" apply
    fi
}

# Function to destroy environment
destroy_environment() {
    local environment="${1:-default}"
    
    cd "$HELMFILE_DIR" || exit 1
    
    print_warn "This will destroy the $environment environment"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    if [[ "$environment" == "default" ]]; then
        helmfile -e default destroy
    else
        CUSTOMER_NAME="$environment" helmfile -e customer destroy 2>/dev/null || \
        helmfile -e "$environment" destroy
    fi
}

# Function to list customer environments
list_customers() {
    print_info "Customer environments:"
    local customer_dir="$HELMFILE_DIR/environments/customers"
    
    if [[ -d "$customer_dir" ]]; then
        for dir in "$customer_dir"/*; do
            if [[ -d "$dir" ]]; then
                local customer=$(basename "$dir")
                local values_file="$dir/values.yaml"
                if [[ -f "$values_file" ]]; then
                    local ip=$(grep "externalIP:" "$values_file" | awk '{print $2}')
                    echo "  - $customer (IP: $ip)"
                fi
            fi
        done
    else
        print_info "No customer environments found"
    fi
}

# Main function
main() {
    # Parse command first to check if it's help or update-tools
    case "${1:-}" in
        --help|help|-h)
            print_usage
            ;;
        update-tools)
            update_tools
            exit 0
            ;;
    esac
    
    # Setup tools for other commands
    setup_tools
    
    # Parse command
    case "${1:-}" in
        init)
            shift
            init_customer "$@"
            ;;
        deploy|sync)
            shift
            deploy_environment "$@"
            ;;
        destroy)
            shift
            destroy_environment "$@"
            ;;
        list|ls)
            list_customers
            ;;
        "")
            print_usage
            ;;
        *)
            print_error "Unknown command: $1"
            print_usage
            ;;
    esac
}

# Script execution
main "$@"