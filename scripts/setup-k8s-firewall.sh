#!/bin/bash

# Kubernetes 클러스터 방화벽 설정 통합 스크립트
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

# 설정 방법 선택
select_method() {
    echo "=== Kubernetes 방화벽 설정 방법 선택 ==="
    echo "1) Ansible 기반 설정 (권장)"
    echo "2) 동적 스크립트 설정"
    echo "3) 둘 다 실행"
    echo "4) 설정 확인만"
    echo
    read -p "선택하세요 (1-4): " choice
    
    case $choice in
        1) run_ansible_setup ;;
        2) run_dynamic_script ;;
        3) run_both ;;
        4) verify_only ;;
        *) log_error "잘못된 선택입니다"; exit 1 ;;
    esac
}

# Ansible 설정 실행
run_ansible_setup() {
    log_info "Ansible 기반 방화벽 설정 시작..."
    
    # Ansible 설치 확인
    if ! command -v ansible-playbook &> /dev/null; then
        log_info "Ansible 설치 중..."
        yum install -y ansible || apt-get install -y ansible
    fi
    
    # 인벤토리 파일 동적 생성
    INVENTORY_GENERATOR="$PROJECT_ROOT/scripts/generate-ansible-inventory.sh"
    INVENTORY_FILE="$PROJECT_ROOT/ansible/k8s-hosts.ini"
    
    if [ -f "$INVENTORY_GENERATOR" ]; then
        log_info "동적으로 Ansible 인벤토리 생성 중..."
        chmod +x "$INVENTORY_GENERATOR"
        "$INVENTORY_GENERATOR" generate
    else
        log_warning "인벤토리 생성 스크립트가 없습니다. 기존 파일 사용..."
        if [ ! -f "$INVENTORY_FILE" ]; then
            log_error "인벤토리 파일을 찾을 수 없습니다: $INVENTORY_FILE"
            log_info "다음 명령으로 인벤토리를 생성하세요: $INVENTORY_GENERATOR generate"
            exit 1
        fi
    fi
    
    # 플레이북 실행
    PLAYBOOK_FILE="$PROJECT_ROOT/ansible/k8s-firewall-playbook.yml"
    if [ ! -f "$PLAYBOOK_FILE" ]; then
        log_error "플레이북 파일을 찾을 수 없습니다: $PLAYBOOK_FILE"
        exit 1
    fi
    
    log_info "Ansible 플레이북 실행 중..."
    ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" -v
    
    if [ $? -eq 0 ]; then
        log_success "Ansible 기반 방화벽 설정 완료"
    else
        log_error "Ansible 실행 실패"
        exit 1
    fi
}

# 동적 스크립트 실행
run_dynamic_script() {
    log_info "동적 스크립트 방화벽 설정 시작..."
    
    DYNAMIC_SCRIPT="$PROJECT_ROOT/scripts/dynamic-firewall-setup.sh"
    if [ ! -f "$DYNAMIC_SCRIPT" ]; then
        log_error "동적 스크립트를 찾을 수 없습니다: $DYNAMIC_SCRIPT"
        exit 1
    fi
    
    chmod +x "$DYNAMIC_SCRIPT"
    "$DYNAMIC_SCRIPT"
    
    if [ $? -eq 0 ]; then
        log_success "동적 스크립트 방화벽 설정 완료"
    else
        log_error "동적 스크립트 실행 실패"
        exit 1
    fi
}

# 둘 다 실행
run_both() {
    log_info "통합 방화벽 설정 시작..."
    
    # 먼저 동적 스크립트로 포트 스캔
    log_info "1단계: 동적 포트 스캔..."
    run_dynamic_script
    
    # 그 다음 Ansible로 표준화된 설정
    log_info "2단계: Ansible 표준 설정..."
    run_ansible_setup
    
    log_success "통합 방화벽 설정 완료"
}

# 설정 확인만
verify_only() {
    log_info "방화벽 설정 확인 중..."
    
    # kubectl이 사용 가능한지 확인
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되지 않았습니다. 로컬 노드만 확인합니다."
        
        echo "=== 로컬 노드 방화벽 상태 ==="
        echo '--- firewalld 상태 ---'
        systemctl is-active firewalld || echo 'firewalld 비활성화'
        
        echo '--- 열린 포트 ---'
        firewall-cmd --list-ports 2>/dev/null || echo '방화벽 비활성화 상태'
        
        echo '--- 허용된 서비스 ---'
        firewall-cmd --list-services 2>/dev/null || echo '방화벽 비활성화 상태'
        
        echo '--- 마스커레이드 상태 ---'
        firewall-cmd --query-masquerade 2>/dev/null || echo '마스커레이드 확인 불가'
        return
    fi
    
    # 클러스터에서 동적으로 노드 정보 가져오기
    log_info "클러스터에서 노드 정보 수집 중..."
    
    # 클러스터의 모든 노드 정보 가져오기 (이름과 IP)
    NODE_INFO=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
    
    if [ -z "$NODE_INFO" ]; then
        log_error "클러스터 노드 정보를 가져올 수 없습니다"
        return 1
    fi
    
    log_info "발견된 노드들:"
    echo "$NODE_INFO" | while read node_name node_ip; do
        log_info "  - $node_name ($node_ip)"
    done
    
    # 각 노드에서 방화벽 상태 확인
    echo "$NODE_INFO" | while read node_name node_ip; do
        log_info "노드 $node_name ($node_ip) 확인 중..."
        
        # 노드 연결 테스트
        if ! ping -c 1 -W 2 "$node_ip" &>/dev/null; then
            log_warning "노드 $node_ip에 연결할 수 없습니다. 건너뜁니다."
            continue
        fi
        
        echo "=== 노드 $node_name ($node_ip) 방화벽 상태 ==="
        
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$node_ip "
            echo '--- firewalld 상태 ---'
            systemctl is-active firewalld || echo 'firewalld 비활성화'
            
            echo '--- 열린 포트 ---'
            firewall-cmd --list-ports 2>/dev/null || echo '방화벽 비활성화 상태'
            
            echo '--- 허용된 서비스 ---'
            firewall-cmd --list-services 2>/dev/null || echo '방화벽 비활성화 상태'
            
            echo '--- 마스커레이드 상태 ---'
            firewall-cmd --query-masquerade 2>/dev/null || echo '마스커레이드 확인 불가'
            
            echo '--- 주요 포트 접근성 테스트 ---'
            nc -z localhost 6443 && echo 'API Server (6443): OK' || echo 'API Server (6443): FAIL'
            nc -z localhost 10250 && echo 'kubelet (10250): OK' || echo 'kubelet (10250): FAIL'
            nc -z localhost 30080 && echo 'Astrago UI (30080): OK' || echo 'Astrago UI (30080): FAIL'
        "; then
            log_success "노드 $node_name 확인 완료"
        else
            log_error "노드 $node_name 확인 실패"
        fi
        echo
    done
}

# 메인 함수
main() {
    log_info "=== Kubernetes 클러스터 방화벽 설정 도구 ==="
    log_info "프로젝트: Astrago Deployment"
    log_info "시간: $(date)"
    
    # 권한 확인
    if [ "$EUID" -ne 0 ]; then
        log_error "이 스크립트는 root 권한으로 실행해야 합니다"
        exit 1
    fi
    
    # 프로젝트 루트 확인
    if [ ! -d "$PROJECT_ROOT" ]; then
        log_error "프로젝트 루트 디렉토리를 찾을 수 없습니다: $PROJECT_ROOT"
        exit 1
    fi
    
    # 인수가 있으면 자동 실행
    if [ $# -gt 0 ]; then
        case "$1" in
            "ansible") run_ansible_setup ;;
            "dynamic") run_dynamic_script ;;
            "both") run_both ;;
            "verify") verify_only ;;
            *) log_error "사용법: $0 [ansible|dynamic|both|verify]"; exit 1 ;;
        esac
    else
        select_method
    fi
    
    log_success "작업 완료!"
}

# 스크립트 실행
main "$@" 