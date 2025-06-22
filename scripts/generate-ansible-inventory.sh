#!/bin/bash

# Ansible 인벤토리 동적 생성 스크립트
# 작성자: Astrago DevOps Team
# 버전: 1.0

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INVENTORY_FILE="$PROJECT_ROOT/ansible/k8s-hosts.ini"

generate_inventory() {
    log_info "Kubernetes 클러스터에서 노드 정보 수집 중..."
    
    # kubectl 확인
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되지 않았습니다"
        exit 1
    fi
    
    # 클러스터 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes 클러스터에 연결할 수 없습니다"
        exit 1
    fi
    
    # 노드 정보 수집 (taint를 통한 마스터 노드 감지)
    NODE_INFO=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\t"}{.spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")].key}{"\n"}{end}')
    
    if [ -z "$NODE_INFO" ]; then
        log_error "클러스터 노드 정보를 가져올 수 없습니다"
        exit 1
    fi
    
    log_info "발견된 노드들:"
    
    # 마스터와 워커 노드 분류
    MASTER_NODES=()
    WORKER_NODES=()
    ALL_NODES=()
    
    while IFS=$'\t' read -r node_name node_ip control_plane_taint; do
        if [ -n "$node_name" ] && [ -n "$node_ip" ]; then
            # 마스터 노드 판별 (control-plane taint가 있으면)
            if [ -n "$control_plane_taint" ]; then
                log_info "  - $node_name ($node_ip) - Master"
                ALL_NODES+=("$node_name ansible_host=$node_ip ansible_user=root")
                MASTER_NODES+=("$node_name ansible_host=$node_ip ansible_user=root")
            else
                log_info "  - $node_name ($node_ip) - Worker"
                ALL_NODES+=("$node_name ansible_host=$node_ip ansible_user=root")
                WORKER_NODES+=("$node_name ansible_host=$node_ip ansible_user=root")
            fi
        fi
    done <<< "$NODE_INFO"
    
    # 인벤토리 파일 생성
    log_info "Ansible 인벤토리 파일 생성 중: $INVENTORY_FILE"
    
    # 디렉토리 생성
    mkdir -p "$(dirname "$INVENTORY_FILE")"
    
    # 인벤토리 파일 작성
    cat > "$INVENTORY_FILE" << EOF
# Kubernetes 클러스터 Ansible 인벤토리
# 자동 생성됨: $(date)
# 생성 스크립트: $0

[k8s_nodes]
$(printf '%s\n' "${ALL_NODES[@]}")

[k8s_masters]
$(printf '%s\n' "${MASTER_NODES[@]}")

[k8s_workers]
$(printf '%s\n' "${WORKER_NODES[@]}")

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_ssh_extra_args='-o ConnectTimeout=10'
EOF
    
    log_success "인벤토리 파일이 생성되었습니다: $INVENTORY_FILE"
    
    # 생성된 파일 내용 표시
    log_info "생성된 인벤토리 파일 내용:"
    echo "----------------------------------------"
    cat "$INVENTORY_FILE"
    echo "----------------------------------------"
    
    # 연결 테스트
    log_info "노드 연결 테스트 중..."
    
    for node_entry in "${ALL_NODES[@]}"; do
        node_name=$(echo "$node_entry" | awk '{print $1}')
        node_ip=$(echo "$node_entry" | grep -o 'ansible_host=[^ ]*' | cut -d'=' -f2)
        
        if ping -c 1 -W 2 "$node_ip" &>/dev/null; then
            log_success "노드 $node_name ($node_ip) 연결 가능"
        else
            log_warning "노드 $node_name ($node_ip) 연결 불가"
        fi
    done
}

# 인벤토리 테스트
test_inventory() {
    log_info "Ansible 인벤토리 테스트 중..."
    
    if [ ! -f "$INVENTORY_FILE" ]; then
        log_error "인벤토리 파일이 없습니다: $INVENTORY_FILE"
        exit 1
    fi
    
    # Ansible 설치 확인
    if ! command -v ansible &> /dev/null; then
        log_warning "Ansible이 설치되지 않았습니다. 패키지 설치 중..."
        if command -v yum &> /dev/null; then
            yum install -y ansible
        elif command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y ansible
        else
            log_error "패키지 매니저를 찾을 수 없습니다"
            exit 1
        fi
    fi
    
    # Ansible ping 테스트
    log_info "Ansible ping 테스트 실행 중..."
    ansible -i "$INVENTORY_FILE" k8s_nodes -m ping
    
    if [ $? -eq 0 ]; then
        log_success "모든 노드에 Ansible 연결 성공!"
    else
        log_warning "일부 노드에 연결 실패가 있을 수 있습니다"
    fi
}

# 메인 함수
main() {
    log_info "=== Ansible 인벤토리 동적 생성 도구 ==="
    log_info "프로젝트: Astrago Deployment"
    log_info "시간: $(date)"
    
    case "${1:-generate}" in
        "generate")
            generate_inventory
            ;;
        "test")
            test_inventory
            ;;
        "both")
            generate_inventory
            test_inventory
            ;;
        *)
            echo "사용법: $0 [generate|test|both]"
            echo "  generate: 인벤토리 파일 생성 (기본값)"
            echo "  test: 인벤토리 파일 테스트"
            echo "  both: 생성 후 테스트"
            exit 1
            ;;
    esac
    
    log_success "작업 완료!"
}

# 스크립트 실행
main "$@" 