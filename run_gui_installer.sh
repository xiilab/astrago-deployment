#!/bin/bash

# Set locale
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

# ==========================================
# 🎨 Beautiful Color Definitions
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Gradient colors
GRADIENT1='\033[38;5;129m'  # Purple
GRADIENT2='\033[38;5;135m'  # Light Purple
GRADIENT3='\033[38;5;141m'  # Pink Purple
GRADIENT4='\033[38;5;147m'  # Light Pink

# ==========================================
# 🎯 Beautiful UI Functions
# ==========================================

# Print beautiful header
print_header() {
    clear
    echo -e "${GRADIENT1}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GRADIENT2}║                                                                              ║${RESET}"
    echo -e "${GRADIENT3}║  ${BOLD}${WHITE}🚀 ASTRAGO GUI INSTALLER SETUP ${RESET}${GRADIENT3}                                      ║${RESET}"
    echo -e "${GRADIENT4}║  ${DIM}${WHITE}Preparing your system for the beautiful installation experience${RESET}${GRADIENT4}      ║${RESET}"
    echo -e "${GRADIENT1}║                                                                              ║${RESET}"
    echo -e "${GRADIENT2}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# Print section header
print_section() {
    local title="$1"
    local icon="$2"
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│ ${icon} ${BOLD}${WHITE}${title}${RESET}${CYAN}                                                                 │${RESET}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
}

# Print step with beautiful formatting
print_step() {
    local message="$1"
    echo -e "${BLUE}   ${BOLD}▶${RESET} ${WHITE}${message}${RESET}"
}

# Print success message
print_success() {
    local message="$1"
    echo -e "${GREEN}   ✅ ${BOLD}${message}${RESET}"
}

# Print info message
print_info() {
    local message="$1"
    echo -e "${BLUE}   ℹ️  ${message}${RESET}"
}

# Print error message
print_error() {
    local message="$1"
    echo -e "${RED}   ❌ ${BOLD}${message}${RESET}"
}

# ==========================================
# 📦 Installation Functions
# ==========================================

# Get the current directory of the script
CURRENT_DIR=$(dirname "$(realpath "$0")")

# Source OS release information
. /etc/os-release

# Check if offline mode is enabled
IS_OFFLINE=${IS_OFFLINE:-false}

# Function to install Python 3.11 on RHEL/CentOS
install_python_rhel() {
    local DNF_OPTS=""
    if [[ $IS_OFFLINE == "true" ]]; then
        DNF_OPTS="--disablerepo=* --enablerepo=offline-repo"
    fi

    if [[ "$VERSION_ID" =~ ^7.* ]]; then
        print_error "RHEL/CentOS 7 is not supported anymore."
        exit 1
    fi

    print_step "Installing Python 3.11 for RHEL/CentOS..."
    sudo dnf install -y $DNF_OPTS python3.11 || exit 1
    print_success "Python 3.11 installed successfully!"
}

# Function to install Python on Ubuntu
install_python_ubuntu() {
    local PY="3.11"
    case "$VERSION_ID" in
        20.04)
            if [[ $IS_OFFLINE == "false" ]]; then
                print_step "Adding Python repository for Ubuntu 20.04..."
                sudo apt install -y software-properties-common
                sudo add-apt-repository ppa:deadsnakes/ppa -y || exit 1
                sudo apt update
                print_success "Repository added successfully!"
            fi
            ;;
        24.04)
            PY="3.12"
            print_info "Using Python 3.12 for Ubuntu 24.04"
            ;;
    esac
    
    print_step "Installing Python ${PY} with virtual environment support..."
    sudo apt install -y python${PY}-venv || exit 1
    print_success "Python ${PY} installed successfully!"
}

# Function to check and install binaries
install_binary() {
    local cmd=$1
    if ! command -v $cmd &> /dev/null; then
        print_step "Installing ${cmd}..."
        if [[ -f "$CURRENT_DIR/tools/linux/$cmd" ]]; then
            sudo cp "$CURRENT_DIR/tools/linux/$cmd" /usr/local/bin/
            sudo chmod +x /usr/local/bin/$cmd
            print_success "${cmd} installed successfully!"
        else
            print_error "${cmd} binary not found in tools folder."
            exit 1
        fi
    else
        print_success "${cmd} is already installed."
    fi
}

# ==========================================
# 🚀 Main Installation Process
# ==========================================

# Print beautiful header
print_header

# System Information
print_section "System Information" "🖥️"
print_info "Operating System: ${BOLD}${ID} ${VERSION_ID}${RESET}"
print_info "Architecture: ${BOLD}$(uname -m)${RESET}"
print_info "Offline Mode: ${BOLD}${IS_OFFLINE}${RESET}"

# Python Installation
print_section "Python Environment Setup" "🐍"

# Check and install Python 3.11 if not already installed
dpkg -s python3.11 &> /dev/null
if [[ $? -eq 0 ]]; then
    print_success "Python 3.11 is already installed."
else
    print_step "Installing Python 3.11 and dependencies..."
    if [[ -e /etc/redhat-release ]]; then
        install_python_rhel
    else
        sudo apt update
        install_python_ubuntu
    fi
fi

# SSH Tools Installation
print_section "SSH Tools Setup" "🔐"

# Install sshpass if not already installed
if ! command -v sshpass &> /dev/null; then
    print_step "Installing sshpass for secure connections..."
    if [[ -e /etc/redhat-release ]]; then
        sudo dnf install -y sshpass || exit 1
    else
        sudo apt install -y sshpass || exit 1
    fi
    print_success "sshpass installed successfully!"
else
    print_success "sshpass is already installed."
fi

# Virtual Environment Setup
print_section "Virtual Environment" "📦"

# Create and activate a virtual environment
print_step "Creating Python virtual environment..."
python3.11 -m venv ~/.venv/3.11
print_success "Virtual environment created!"

print_step "Activating virtual environment..."
source ~/.venv/3.11/bin/activate
print_success "Virtual environment activated!"

# Install Python dependencies
print_step "Installing Python dependencies..."
pip install -r "$CURRENT_DIR/kubespray/requirements.txt"
print_success "Python dependencies installed!"

# Kubernetes Tools Installation
print_section "Kubernetes Tools" "☸️"

# Check and install helm, helmfile, and kubectl if necessary
for cmd in helm helmfile kubectl; do
    install_binary $cmd
done

# Final Launch
print_section "Launching GUI Installer" "🎯"

echo ""
echo -e "${GRADIENT1}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GRADIENT2}║                                                                              ║${RESET}"
echo -e "${GRADIENT3}║  ${BOLD}${WHITE}🎉 Setup completed successfully! ${RESET}${GRADIENT3}                                       ║${RESET}"
echo -e "${GRADIENT4}║  ${DIM}${WHITE}Launching the Astrago GUI Installer...${RESET}${GRADIENT4}                                  ║${RESET}"
echo -e "${GRADIENT1}║                                                                              ║${RESET}"
echo -e "${GRADIENT2}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# Run the installer script
python3.11 "$CURRENT_DIR/astrago_gui_installer.py"