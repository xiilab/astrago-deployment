#!/bin/bash

# 현재 스크립트의 디렉토리 설정
CURRENT_DIR=$(dirname "$(realpath "$0")")
ANSIBLE_DIR=$CURRENT_DIR/../../ansible
KUBESPRAY_DIR=$CURRENT_DIR/../../kubespray

# 사용자 입력 받기
read -p "Enter Private Server IP: " serverIp
read -s -p "Enter Node's root password: " password
echo ""

# 오프라인 설정 스크립트 실행
./setup-offline.sh "$serverIp"

# 필요한 패키지 설치
if ! command -v sshpass &> /dev/null; then
  sudo apt update
  sudo apt install -y sshpass
fi

# Python 가상 환경 설정 및 활성화
if [ ! -d "$HOME/.venv/3.11" ]; then
  python3.11 -m venv ~/.venv/3.11
fi
source ~/.venv/3.11/bin/activate

# Kubespray 디렉토리로 이동하여 의존성 설치
cd "$KUBESPRAY_DIR"
pip install -r requirements.txt

# Ansible 플레이북 실행
ansible-playbook -i inventory/offline/astrago.yaml --become --become-user=root $ANSIBLE_DIR/offline-repo.yml --extra-vars="ansible_password=$password"
ansible-playbook -i inventory/offline/astrago.yaml --become --become-user=root cluster.yml --extra-vars="ansible_password=$password"
