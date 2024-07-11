#!/bin/bash

# Set locale
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

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
        echo "FATAL: RHEL/CentOS 7 is not supported anymore."
        exit 1
    fi

    sudo dnf install -y $DNF_OPTS python3.11 || exit 1
}

# Function to install Python on Ubuntu
install_python_ubuntu() {
    local PY="3.11"
    case "$VERSION_ID" in
        20.04)
            if [[ $IS_OFFLINE == "false" ]]; then
                sudo apt install -y software-properties-common
                sudo add-apt-repository ppa:deadsnakes/ppa -y || exit 1
                sudo apt update
            fi
            ;;
        24.04)
            PY="3.12"
            ;;
    esac
    sudo apt install -y python${PY}-venv || exit 1
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

# Check and install Python 3.11 if not already installed
dpkg -s python3.11 &> /dev/null
if [[ $? -eq 0 ]]; then
    echo "Python 3.11 is already installed."
else
    echo "===> Installing Python 3.11 and dependencies"
    if [[ -e /etc/redhat-release ]]; then
        install_python_rhel
    else
        sudo apt update
        install_python_ubuntu
    fi
fi

# Install sshpass if not already installed
if ! command -v sshpass &> /dev/null; then
    echo "===> Installing sshpass"
    if [[ -e /etc/redhat-release ]]; then
        sudo dnf install -y sshpass || exit 1
    else
        sudo apt install -y sshpass || exit 1
    fi
else
    echo "sshpass is already installed."
fi

# Create and activate a virtual environment
python3.11 -m venv ~/.venv/3.11
source ~/.venv/3.11/bin/activate

# Install Python dependencies
pip install -r "$CURRENT_DIR/kubespray/requirements.txt"

# Check and install helm, helmfile, and kubectl if necessary
for cmd in helm helmfile kubectl; do
    install_binary $cmd
done

# Run the installer script
python3.11 "$CURRENT_DIR/astrago_gui_installer.py"