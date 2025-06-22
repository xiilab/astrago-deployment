#!/bin/bash

# 동적 Kubernetes 방화벽 설정 스크립트
# 작성자: Astrago DevOps Team
# 버전: 2.0
# 설명: 클러스터의 실제 서비스를 스캔하여 동적으로 방화벽 설정

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 클러스터 정보 수집
get_cluster_info() {
    log_info "클러스터 정보 수집 중..."
    
    # Pod CIDR 자동 감지
    POD_CIDR=$(kubectl cluster-info dump | grep -oP 'cluster-cidr=\K[0-9./]+' | head -1)
    if [ -z "$POD_CIDR" ]; then
        POD_CIDR="10.233.0.0/16"  # 기본값
        log_warning "Pod CIDR을 자동 감지할 수 없어 기본값 사용: $POD_CIDR"
    fi
    
    # 노드 IP 범위 자동 감지
    NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
    NODE_CIDR=$(echo $NODE_IPS | tr ' ' '\n' | head -1 | sed 's/\.[0-9]*$/\.0\/24/')
    
    log_info "감지된 Pod CIDR: $POD_CIDR"
    log_info "감지된 Node CIDR: $NODE_CIDR"
}

# NodePort 서비스 스캔
scan_nodeport_services() {
    log_info "NodePort 서비스 스캔 중..."
    
    NODEPORT_SERVICES=$(kubectl get svc --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="NodePort")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.ports[*].nodePort}{"\n"}{end}')
    
    echo "=== NodePort 서비스 목록 ===" > /tmp/k8s-ports.txt
    echo "$NODEPORT_SERVICES" >> /tmp/k8s-ports.txt
    
    # 고유한 NodePort 추출
    UNIQUE_NODEPORTS=$(echo "$NODEPORT_SERVICES" | awk '{for(i=3;i<=NF;i++) print $i}' | sort -u | grep -E '^[0-9]+$')
    
    log_info "발견된 NodePort 포트들:"
    echo "$UNIQUE_NODEPORTS" | while read port; do
        if [ ! -z "$port" ]; then
            log_info "  - $port"
        fi
    done
}

# 내부 서비스 포트 스캔
scan_internal_services() {
    log_info "내부 서비스 포트 스캔 중..."
    
    # 컨테이너 포트 수집
    CONTAINER_PORTS=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.ports[*].containerPort}{" "}{end}{"\n"}{end}' | grep -E '[0-9]+')
    
    echo "=== 컨테이너 포트 목록 ===" >> /tmp/k8s-ports.txt
    echo "$CONTAINER_PORTS" >> /tmp/k8s-ports.txt
    
    # 고유한 컨테이너 포트 추출 (내부 통신용)
    UNIQUE_CONTAINER_PORTS=$(echo "$CONTAINER_PORTS" | awk '{for(i=3;i<=NF;i++) print $i}' | sort -u | grep -E '^[0-9]+$')
    
    log_info "발견된 주요 내부 포트들:"
    echo "$UNIQUE_CONTAINER_PORTS" | head -10 | while read port; do
        if [ ! -z "$port" ]; then
            log_info "  - $port"
        fi
    done
}

# 방화벽 설정 적용
apply_firewall_rules() {
    log_info "방화벽 규칙 적용 중..."
    
    # firewalld 시작
    systemctl enable firewalld
    systemctl start firewalld
    
    # 기본 Kubernetes 포트들
    K8S_BASIC_PORTS=(
        "6443/tcp"      # API Server
        "2379-2380/tcp" # etcd
        "10250/tcp"     # kubelet
        "10257/tcp"     # controller-manager
        "10259/tcp"     # scheduler
        "10256/tcp"     # kubelet health
    )
    
    # CNI 포트들 (Calico)
    CNI_PORTS=(
        "179/tcp"       # BGP
        "4789/udp"      # VXLAN
    )
    
    # DNS 포트들
    DNS_PORTS=(
        "53/tcp"
        "53/udp"
        "9153/tcp"      # CoreDNS metrics
    )
    
    # 웹 서비스
    WEB_PORTS=(
        "80/tcp"
        "443/tcp"
    )
    
    # 모니터링
    MONITORING_PORTS=(
        "9100/tcp"      # Node Exporter
        "9400/tcp"      # DCGM Exporter
    )
    
    # 레지스트리
    REGISTRY_PORTS=(
        "35000/tcp"     # Docker Registry
    )
    
    log_info "기본 Kubernetes 포트 설정..."
    for port in "${K8S_BASIC_PORTS[@]}"; do
        firewall-cmd --permanent --add-port=$port
        log_success "포트 $port 추가됨"
    done
    
    log_info "CNI 포트 설정..."
    for port in "${CNI_PORTS[@]}"; do
        firewall-cmd --permanent --add-port=$port
        log_success "포트 $port 추가됨"
    done
    
    log_info "DNS 포트 설정..."
    for port in "${DNS_PORTS[@]}"; do
        firewall-cmd --permanent --add-port=$port
        log_success "포트 $port 추가됨"
    done
    
    log_info "웹 서비스 포트 설정..."
    for port in "${WEB_PORTS[@]}"; do
        firewall-cmd --permanent --add-port=$port
        log_success "포트 $port 추가됨"
    done
    
    log_info "모니터링 포트 설정..."
    for port in "${MONITORING_PORTS[@]}"; do
        firewall-cmd --permanent --add-port=$port
        log_success "포트 $port 추가됨"
    done
    
    log_info "레지스트리 포트 설정..."
    for port in "${REGISTRY_PORTS[@]}"; do
        firewall-cmd --permanent --add-port=$port
        log_success "포트 $port 추가됨"
    done
    
    # NodePort 범위
    log_info "NodePort 범위 설정..."
    firewall-cmd --permanent --add-port=30000-32767/tcp
    log_success "NodePort 범위 30000-32767/tcp 추가됨"
    
    # 동적으로 발견된 NodePort들 개별 설정 (UDP도 고려)
    if [ ! -z "$UNIQUE_NODEPORTS" ]; then
        log_info "발견된 NodePort UDP 포트들 설정..."
        echo "$UNIQUE_NODEPORTS" | while read port; do
            if [ ! -z "$port" ]; then
                firewall-cmd --permanent --add-port=$port/udp
                log_success "NodePort UDP $port 추가됨"
            fi
        done
    fi
    
    # NFS 서비스
    log_info "NFS 서비스 설정..."
    firewall-cmd --permanent --add-service=nfs
    firewall-cmd --permanent --add-service=rpc-bind
    firewall-cmd --permanent --add-service=mountd
    log_success "NFS 서비스들 추가됨"
    
    # 마스커레이드 활성화
    log_info "마스커레이드 활성화..."
    firewall-cmd --permanent --add-masquerade
    log_success "마스커레이드 활성화됨"
    
    # 신뢰 네트워크 설정
    log_info "신뢰 네트워크 설정..."
    firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$NODE_CIDR' accept"
    firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$POD_CIDR' accept"
    log_success "신뢰 네트워크 설정 완료"
    
    # 설정 적용
    log_info "방화벽 설정 적용 중..."
    firewall-cmd --reload
    log_success "방화벽 설정이 적용되었습니다"
}

# 설정 검증
verify_configuration() {
    log_info "방화벽 설정 검증 중..."
    
    echo "=== 현재 방화벽 설정 ===" > /tmp/firewall-status.txt
    firewall-cmd --list-all >> /tmp/firewall-status.txt
    
    log_info "방화벽 상태:"
    firewall-cmd --list-all
    
    # 주요 포트 테스트
    log_info "주요 포트 접근성 테스트..."
    
    # API Server 테스트
    if nc -z localhost 6443 2>/dev/null; then
        log_success "API Server (6443) 접근 가능"
    else
        log_warning "API Server (6443) 접근 불가 - 정상일 수 있음"
    fi
    
    # kubelet 테스트
    if nc -z localhost 10250 2>/dev/null; then
        log_success "kubelet (10250) 접근 가능"
    else
        log_warning "kubelet (10250) 접근 불가"
    fi
    
    log_success "방화벽 설정 검증 완료"
}

# 원격 노드 설정 함수
setup_remote_nodes() {
    log_info "원격 노드 설정 시작..."
    
    # 클러스터에서 동적으로 노드 정보 가져오기
    log_info "클러스터에서 노드 정보 수집 중..."
    
    # 현재 노드 IP 확인
    CURRENT_NODE_IP=$(hostname -I | awk '{print $1}')
    log_info "현재 노드 IP: $CURRENT_NODE_IP"
    
    # 클러스터의 모든 노드 IP 가져오기
    ALL_NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
    log_info "클러스터 노드 IP들: $ALL_NODE_IPS"
    
    # 현재 노드를 제외한 원격 노드들 추출
    REMOTE_NODES=()
    for node_ip in $ALL_NODE_IPS; do
        if [ "$node_ip" != "$CURRENT_NODE_IP" ]; then
            REMOTE_NODES+=("$node_ip")
        fi
    done
    
    if [ ${#REMOTE_NODES[@]} -eq 0 ]; then
        log_warning "원격 노드가 없습니다. 단일 노드 클러스터인 것 같습니다."
        return 0
    fi
    
    log_info "원격 노드 목록: ${REMOTE_NODES[*]}"
    
    for node in "${REMOTE_NODES[@]}"; do
        log_info "노드 $node 설정 중..."
        
        # 노드 연결 테스트
        if ! ping -c 1 -W 2 "$node" &>/dev/null; then
            log_warning "노드 $node에 연결할 수 없습니다. 건너뜁니다."
            continue
        fi
        
        # 스크립트 복사
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$0" root@$node:/tmp/dynamic-firewall-setup.sh; then
            log_success "스크립트 복사 완료: $node"
        else
            log_error "스크립트 복사 실패: $node"
            continue
        fi
        
        # 원격 실행
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$node "chmod +x /tmp/dynamic-firewall-setup.sh && /tmp/dynamic-firewall-setup.sh --local-only"; then
            log_success "노드 $node 설정 완료"
        else
            log_error "노드 $node 설정 실패"
        fi
    done
}

# 메인 함수
main() {
    log_info "=== Kubernetes 동적 방화벽 설정 시작 ==="
    log_info "버전: 2.0"
    log_info "시간: $(date)"
    
    # 권한 확인
    if [ "$EUID" -ne 0 ]; then
        log_error "이 스크립트는 root 권한으로 실행해야 합니다"
        exit 1
    fi
    
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
    
    # 작업 디렉토리 생성
    mkdir -p /tmp/k8s-firewall-logs
    cd /tmp/k8s-firewall-logs
    
    # 단계별 실행
    get_cluster_info
    scan_nodeport_services
    scan_internal_services
    apply_firewall_rules
    verify_configuration
    
    # 로컬 전용 모드가 아닌 경우 원격 노드도 설정
    if [ "${1:-}" != "--local-only" ]; then
        setup_remote_nodes
    fi
    
    log_success "=== 동적 방화벽 설정 완료 ==="
    log_info "로그 파일: /tmp/k8s-firewall-logs/"
    log_info "포트 정보: /tmp/k8s-ports.txt"
    log_info "방화벽 상태: /tmp/firewall-status.txt"
}

# 스크립트 실행
main "$@" 