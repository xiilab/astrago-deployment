#!/bin/bash

export ANSIBLE_HOST_KEY_CHECKING=False
export LC_ALL=C.UTF-8


# Set the current script's directory
CURRENT_DIR=$(dirname "$(realpath "$0")")
ANSIBLE_DIR=$CURRENT_DIR/../ansible
KUBESPRAY_DIR=$CURRENT_DIR/../kubespray

# Get user input
read -p "Enter Node's username: " username
read -s -p "Enter Node's password: " password
echo ""

# Detect OS family
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_FAMILY=$ID_LIKE
    if [ -z "$OS_FAMILY" ]; then
        OS_FAMILY=$ID
    fi
else
    echo "Cannot detect OS. Exiting."
    exit 1
fi

# Install necessary packages
if ! command -v sshpass &> /dev/null; then
    case $OS_FAMILY in
        *debian*)
            sudo apt update
            sudo apt install -y sshpass
            ;;
        *rhel*|*fedora*)
            sudo dnf check-update
            sudo dnf install -y sshpass
            ;;
        *)
            echo "Unsupported OS family: $OS_FAMILY"
            exit 1
            ;;
    esac
fi

# Set up and activate Python virtual environment
if [ ! -d "$HOME/.venv/3.12" ]; then
    python3.12 -m venv ~/.venv/3.12
fi
source ~/.venv/3.12/bin/activate

# Move to Kubespray directory and install dependencies
cd "$KUBESPRAY_DIR"
pip install -r requirements.txt

# Run Ansible playbooks
ansible-playbook -i inventory/offline/astrago.yaml --become --become-user=root $ANSIBLE_DIR/offline-repo.yml --extra-vars="ansible_user=$username ansible_password=$password ansible_become_pass=$password"
ansible-playbook -i inventory/offline/astrago.yaml --become --become-user=root cluster.yml --skip-tags containerd,reset_containerd --extra-vars="ansible_user=$username ansible_password=$password ansible_become_pass=$password -vvvv"
