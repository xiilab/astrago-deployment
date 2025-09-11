#!/bin/bash
# kubespray/install.sh - 사용자 선택형 Kubernetes 설치

set -e

SCRIPT_DIR="$(dirname $(realpath $0))"
source "$SCRIPT_DIR/version-matrix.conf"

# 컬러 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 전역 변수
CUSTOMER_NAME=""
K8S_VERSION=""
KUBESPRAY_VERSION=""
KUBESPRAY_SOURCE_DIR=""
INVENTORY_FILE=""
EXTRA_VARS_FILE=""
VENV_DIR=""
RESET_MODE=false

print_banner() {
    clear
    if [[ "$RESET_MODE" == true ]]; then
        echo -e "${RED}=================================="
        echo -e "   Kubernetes 제거 도구           "
        echo -e "   클러스터 완전 삭제             "
        echo -e "==================================${NC}"
    else
        echo -e "${GREEN}=================================="
        echo -e "   Kubernetes 설치 도구           "
        echo -e "   사용자 선택형 버전 관리         "
        echo -e "==================================${NC}"
    fi
    echo ""
}

print_step() {
    echo -e "${GREEN}[단계 $1/7]${NC} $2"
    echo "=================================="
}

print_usage() {
    echo "Usage: $0 <customer_name> [options]"
    echo "       $0 --reset <customer_name> [options]"
    echo ""
    echo "Options:"
    echo "  --k8s-version <version>    Kubernetes 버전 선택"
    echo "    - $K8S_STABLE_VERSION (안정 버전, 모든 환경 호환)"
    echo "    - $K8S_LATEST_VERSION  (최신 버전, cgroup v2 권장)"
    echo "  --inventory <file>         커스텀 인벤토리 파일"
    echo "  --dry-run                  실제 설치 없이 확인만"
    echo "  --reset                    클러스터 제거 (reset.yml 실행)"
    echo "  --help                     도움말 출력"
    echo ""
    echo "Examples:"
    echo "  # 설치"
    echo "  $0 samsung --k8s-version $K8S_STABLE_VERSION    # 안정 버전"
    echo "  $0 lg --k8s-version $K8S_LATEST_VERSION          # 최신 버전"
    echo "  $0 hyundai                                       # 대화형 선택"
    echo ""
    echo "  # 제거"
    echo "  $0 --reset samsung                              # 삼성 클러스터 제거"
    echo "  $0 --reset lg --k8s-version $K8S_LATEST_VERSION  # 특정 버전 환경에서 제거"
}

select_kubernetes_version() {
    print_step 1 "Kubernetes 버전 선택"
    
    if [[ -n "$REQUESTED_K8S_VERSION" ]]; then
        K8S_VERSION="$REQUESTED_K8S_VERSION"
        echo "✅ 명령행에서 지정된 버전: $K8S_VERSION"
    else
        echo -e "${BLUE}🐳 Kubernetes 버전을 선택하세요:${NC}"
        echo ""
        echo "1) $K8S_STABLE_VERSION (RHEL8/cgroup v1 호환)"
        echo "   - RHEL8 cgroup v1 환경에서 동작"
        echo "   - Kubernetes 1.31부터 cgroup v1은 유지보수 모드"
        echo "   - 레거시 환경에 필요시 사용"
        echo ""
        echo "2) $K8S_LATEST_VERSION (최신 버전 - 권장)"
        echo "   - 최신 기능 및 성능 개선사항 포함"
        echo "   - cgroup v2 환경 필요 (RHEL9+ 기본)"
        echo "   - 프로덕션 환경 권장"
        echo ""
        
        while true; do
            read -p "선택 (1/2) [기본: 1]: " choice
            choice=${choice:-1}
            
            case $choice in
                1)
                    K8S_VERSION="$K8S_STABLE_VERSION"
                    echo -e "${GREEN}✅ 안정 버전 선택: Kubernetes $K8S_VERSION${NC}"
                    break
                    ;;
                2)
                    K8S_VERSION="$K8S_LATEST_VERSION"
                    echo -e "${GREEN}✅ 최신 버전 선택: Kubernetes $K8S_VERSION${NC}"
                    break
                    ;;
                *)
                    echo -e "${RED}❌ 잘못된 선택입니다. 1 또는 2를 입력하세요.${NC}"
                    ;;
            esac
        done
    fi
    
    # 버전에 따른 Kubespray 경로 설정
    case "$K8S_VERSION" in
        "$K8S_STABLE_VERSION")
            KUBESPRAY_VERSION="$K8S_STABLE_KUBESPRAY"
            ;;
        "$K8S_LATEST_VERSION")
            KUBESPRAY_VERSION="$K8S_LATEST_KUBESPRAY"
            ;;
        *)
            echo -e "${RED}❌ 지원하지 않는 Kubernetes 버전: $K8S_VERSION${NC}"
            echo "지원 버전: $K8S_STABLE_VERSION, $K8S_LATEST_VERSION"
            exit 1
            ;;
    esac
    
    KUBESPRAY_SOURCE_DIR="$SCRIPT_DIR/versions/$KUBESPRAY_VERSION/kubespray"
    
    echo "📁 사용할 Kubespray: $KUBESPRAY_VERSION"
    echo ""
}

check_system_requirements() {
    print_step 2 "시스템 요구사항 확인"
    
    if [[ "$K8S_VERSION" == "$K8S_LATEST_VERSION" ]]; then
        echo -e "${YELLOW}⚠️  최신 버전 요구사항 확인 중...${NC}"
        echo ""
        echo "📋 Kubernetes $K8S_LATEST_VERSION 권장 요구사항:"
        echo "   - cgroup v2 활성화 (systemd 기반 시스템)"
        echo "   - 커널 버전 4.15 이상"
        echo "   - 충분한 리소스 (CPU 2+ 코어, RAM 4GB+)"
        echo "   - 최신 컨테이너 런타임"
        echo ""
        
        # cgroup 버전 확인 (가능한 경우)
        if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
            echo "✅ cgroup v2가 활성화되어 있습니다."
        elif [[ -d /sys/fs/cgroup/systemd ]]; then
            echo -e "${YELLOW}ℹ️  cgroup v1이 감지되었습니다. cgroup v2 업그레이드를 권장합니다.${NC}"
        fi
        
        echo ""
        read -p "시스템이 요구사항을 만족한다고 확신합니까? (Y/n): " meets_requirements
        if [[ "$meets_requirements" =~ ^[Nn]$ ]]; then
            echo ""
            echo -e "${BLUE}💡 안정 버전($K8S_STABLE_VERSION) 사용을 권장합니다${NC}"
            read -p "안정 버전으로 변경하시겠습니까? (y/N): " change_version
            if [[ "$change_version" =~ ^[Yy]$ ]]; then
                K8S_VERSION="$K8S_STABLE_VERSION"
                KUBESPRAY_VERSION="$K8S_STABLE_KUBESPRAY"
                KUBESPRAY_SOURCE_DIR="$SCRIPT_DIR/versions/$KUBESPRAY_VERSION/kubespray"
                echo -e "${GREEN}✅ 안정 버전으로 변경: $K8S_VERSION${NC}"
            fi
        fi
    else
        echo "✅ 안정 버전 선택 - 모든 환경에서 호환됩니다."
    fi
    echo ""
}

check_kubespray_availability() {
    print_step 3 "Kubespray 환경 확인"
    
    if [[ ! -d "$KUBESPRAY_SOURCE_DIR" ]]; then
        echo -e "${RED}❌ 필요한 Kubespray 버전이 설치되지 않았습니다: $KUBESPRAY_VERSION${NC}"
        echo ""
        echo "💡 다음 명령으로 설치하세요:"
        echo "   ./update-kubespray.sh install $KUBESPRAY_VERSION"
        echo "   또는"  
        echo "   ./update-kubespray.sh install-all"
        echo ""
        exit 1
    fi
    
    echo "✅ 사용할 Kubespray: $KUBESPRAY_VERSION"
    echo "📁 경로: $KUBESPRAY_SOURCE_DIR"
    
    # Python 가상환경 설정
    setup_python_venv
    
    echo ""
}

setup_python_venv() {
    VENV_DIR="$KUBESPRAY_SOURCE_DIR/venv"
    
    echo ""
    echo "🐍 Python 가상환경 설정..."
    
    # 호환되는 Python 버전 찾기
    local python_cmd=""
    if command -v python3.11 &> /dev/null; then
        python_cmd="python3.11"
        echo "✅ Python 3.11 사용"
    elif command -v python3.10 &> /dev/null; then
        python_cmd="python3.10"
        echo "✅ Python 3.10 사용"  
    elif command -v python3.9 &> /dev/null; then
        python_cmd="python3.9"
        echo "✅ Python 3.9 사용"
    else
        python_cmd="python3"
        local python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        echo "⚠️ Python $python_version 사용 (호환성 문제 가능)"
        
        if [[ "$python_version" == "3.13" ]]; then
            echo -e "${YELLOW}💡 Python 3.11 설치 권장: brew install python@3.11${NC}"
            read -p "계속 진행하시겠습니까? (y/N): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    # 가상환경이 없으면 생성
    if [[ ! -d "$VENV_DIR" ]]; then
        echo "📦 가상환경 생성 중... ($python_cmd)"
        $python_cmd -m venv "$VENV_DIR"
        
        echo "📋 패키지 설치 중..."
        source "$VENV_DIR/bin/activate"
        pip install --upgrade pip
        pip install -r "$KUBESPRAY_SOURCE_DIR/requirements.txt"
    else
        echo "✅ 기존 가상환경 사용"
        source "$VENV_DIR/bin/activate"
    fi
    
    # ansible 경로 확인
    if command -v ansible &> /dev/null; then
        echo "✅ Ansible: $(which ansible) ($(ansible --version | head -1))"
    else
        echo "❌ Ansible을 찾을 수 없습니다"
        echo "PATH: $PATH"
        exit 1
    fi
}

activate_venv() {
    if [[ -n "$VENV_DIR" ]] && [[ -d "$VENV_DIR" ]]; then
        source "$VENV_DIR/bin/activate"
    fi
}

get_customer_info() {
    print_step 4 "고객 환경 설정"
    
    CUSTOMER_DIR="$SCRIPT_DIR/customers/$CUSTOMER_NAME"

    
    echo "✅ 고객: $CUSTOMER_NAME"
    echo "📁 작업 디렉토리: $CUSTOMER_DIR"
    echo ""
}

configure_nodes() {
    print_step 5 "클러스터 노드 설정"
    
    INVENTORY_FILE="$CUSTOMER_DIR/hosts.yml"
    EXTRA_VARS_FILE="$CUSTOMER_DIR/extra-vars.yml"
    
    if [[ -n "$CUSTOM_INVENTORY_FILE" ]]; then
        if [[ -f "$CUSTOM_INVENTORY_FILE" ]]; then
            cp "$CUSTOM_INVENTORY_FILE" "$INVENTORY_FILE"
            echo "✅ 커스텀 인벤토리 파일 사용: $CUSTOM_INVENTORY_FILE"
        else
            echo -e "${RED}❌ 커스텀 인벤토리 파일을 찾을 수 없습니다: $CUSTOM_INVENTORY_FILE${NC}"
            exit 1
        fi
    fi
    
    echo "✅ 인벤토리 파일: $INVENTORY_FILE"
    echo ""
}



prepare_kubespray() {
    print_step 6 "Kubespray 환경 준비"
    
    cd "$KUBESPRAY_SOURCE_DIR"
    activate_venv
    
    # extra-vars.yml이 없으면 기본값 생성
    # 고객 설정 폴더와 파일 존재 확인
    if [[ ! -d "$CUSTOMER_DIR" ]]; then
        echo "❌ 고객 설정 폴더가 없습니다: $CUSTOMER_DIR"
        echo ""
        echo "💡 다음 단계를 따라 설정하세요:"
        echo "   1. sample 폴더를 복사:"
        echo "      cp -r customers/sample customers/$CUSTOMER_NAME"
        echo ""
        echo "   2. 설정 파일 편집:"
        echo "      - customers/$CUSTOMER_NAME/hosts.yml (서버 IP와 SSH 설정)"
        echo "      - customers/$CUSTOMER_NAME/extra-vars.yml (추가 설정)"
        echo ""
        echo "   3. 다시 설치 실행:"
        echo "      ./install.sh $CUSTOMER_NAME"
        exit 1
    fi
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "❌ hosts.yml 파일이 없습니다: $INVENTORY_FILE"
        echo "💡 customers/$CUSTOMER_NAME/hosts.yml 파일을 생성하세요"
        exit 1
    fi
    
    if [[ ! -f "$EXTRA_VARS_FILE" ]]; then
        echo "❌ extra-vars.yml 파일이 없습니다: $EXTRA_VARS_FILE" 
        echo "💡 customers/$CUSTOMER_NAME/extra-vars.yml 파일을 생성하세요"
        exit 1
    fi
    
    echo "✅ Kubernetes 버전: $K8S_VERSION (Kubespray 기본값 사용)"  
    echo "✅ 설정 파일: $EXTRA_VARS_FILE"
    echo "✅ 네트워크 설정: kubespray 기본값 사용"
    echo ""
}

test_connectivity() {
    print_step 7 "노드 연결성 테스트"
    
    activate_venv
    
    echo -n "SSH 연결 테스트 중... "
    if ansible all -i "$INVENTORY_FILE" -m ping &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
        echo ""
        echo "연결 테스트 실패. 상세 정보:"
        activate_venv
        ansible all -i "$INVENTORY_FILE" -m ping
        echo ""
        echo "❌ SSH 연결 실패로 설치를 중단합니다."
        exit 1
    fi
    echo ""
}

install_kubernetes() {
    echo -e "${GREEN}🚀 Kubernetes $K8S_VERSION 설치 시작${NC}"
    echo "========================================"
    echo "📁 Kubespray: $KUBESPRAY_VERSION"
    echo "📋 인벤토리: $INVENTORY_FILE"
    echo "⚙️ 설정: $EXTRA_VARS_FILE"
    echo "예상 시간: 10-15분"
    echo ""
    
    # Python 가상환경 활성화
    activate_venv
    
    # 로그 파일 설정

    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}🔍 DRY-RUN 모드 (실제 설치 안함)${NC}"
        ansible-playbook \
            -i "$INVENTORY_FILE" \
            -e "@$EXTRA_VARS_FILE" \
            cluster.yml --check
    else
        # 실제 설치 실행
        if ansible-playbook \
            -i "$INVENTORY_FILE" \
            -e "@$EXTRA_VARS_FILE" \
            cluster.yml; then
            
            show_completion_info
        else
            echo ""
            echo -e "${RED}❌ 설치 실패${NC}"

            echo ""
            echo "일반적인 해결 방법:"
            echo "1. SSH 키 설정 확인"
            echo "2. 방화벽 설정 확인"  
            echo "3. 노드 리소스 확인 (CPU 2개, RAM 4GB 이상)"
            echo "4. 네트워크 연결 상태 확인"
            exit 1
        fi
    fi
}

show_completion_info() {
    echo ""
    echo -e "${GREEN}🎉 Kubernetes 설치 완료!${NC}"
    echo "======================================"
    echo ""
    echo "🏢 고객: $CUSTOMER_NAME"
    echo "🐳 Kubernetes: $K8S_VERSION"
    echo "📁 작업 디렉토리: $CUSTOMER_DIR"

    echo ""
    echo "📝 다음 단계:"
    echo "1. kubeconfig 파일 복사"
    echo "   scp $MASTER_USER@$MASTER_IP:/etc/kubernetes/admin.conf ~/.kube/config"
    echo ""
    echo "2. 클러스터 상태 확인"  
    echo "   kubectl get nodes"
    echo ""
    echo "3. Astrago 설치"
    echo "   cd .. && ./deploy_astrago_v3.sh init $CUSTOMER_NAME"
    echo ""
}

reset_kubernetes() {
    echo -e "${RED}🗑️ Kubernetes 클러스터 제거 시작${NC}"
    echo "========================================"
    echo "📁 Kubespray: $KUBESPRAY_VERSION"
    echo "📋 인벤토리: $INVENTORY_FILE"
    echo "⚙️ 설정: $EXTRA_VARS_FILE"
    echo "예상 시간: 5-10분"
    echo ""
    
    echo -e "${YELLOW}⚠️ 경고: 이 작업은 되돌릴 수 없습니다!${NC}"
    echo "다음 작업이 수행됩니다:"
    echo "- 모든 Kubernetes 구성 요소 제거"
    echo "- 컨테이너 런타임 정리"
    echo "- 네트워크 설정 초기화"
    echo "- 데이터 볼륨 정리"
    echo ""
    
    read -p "정말로 '$CUSTOMER_NAME' 클러스터를 제거하시겠습니까? (yes/NO): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "제거 작업이 취소되었습니다."
        exit 0
    fi
    
    # Python 가상환경 활성화
    activate_venv
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}🔍 DRY-RUN 모드 (실제 제거 안함)${NC}"
        ansible-playbook \
            -i "$INVENTORY_FILE" \
            -e "@$EXTRA_VARS_FILE" \
            reset.yml --check
    else
        # 실제 제거 실행
        if ansible-playbook \
            -i "$INVENTORY_FILE" \
            -e "@$EXTRA_VARS_FILE" \
            reset.yml; then
            
            show_reset_completion_info
        else
            echo ""
            echo -e "${RED}❌ 제거 실패${NC}"
            echo ""
            echo "일반적인 해결 방법:"
            echo "1. SSH 연결 상태 확인"
            echo "2. 수동으로 남은 프로세스 확인"
            echo "3. 방화벽 설정 복원"
            exit 1
        fi
    fi
}

show_reset_completion_info() {
    echo ""
    echo -e "${GREEN}✅ Kubernetes 클러스터 제거 완료!${NC}"
    echo "======================================"
    echo ""
    echo "🏢 고객: $CUSTOMER_NAME"
    echo "📁 작업 디렉토리: $CUSTOMER_DIR"
    echo ""
    echo "📝 정리 완료 항목:"
    echo "- Kubernetes 모든 구성 요소 제거"
    echo "- 컨테이너 런타임 정리"
    echo "- 네트워크 설정 초기화"
    echo "- iptables 규칙 정리"
    echo ""
    echo "💡 참고사항:"
    echo "- 노드들이 초기 상태로 복원되었습니다"
    echo "- 필요시 재설치가 가능합니다"
    echo ""
}

# 메인 실행 함수
main() {
    # 인터럽트 핸들링
    trap 'echo -e "\n${YELLOW}설치가 중단되었습니다.${NC}"; exit 1' INT
    
    local customer=""
    local requested_k8s_version=""
    local custom_inventory_file=""
    local dry_run="false"
    
    # 인자 파싱
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 1
    fi
    
    # --reset 옵션 처리
    if [[ "$1" == "--reset" ]]; then
        RESET_MODE=true
        shift
        if [[ $# -eq 0 ]]; then
            echo -e "${RED}❌ --reset 옵션 사용 시 고객명이 필요합니다${NC}"
            print_usage
            exit 1
        fi
    fi
    
    customer=$1
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --k8s-version)
                requested_k8s_version="$2"
                shift 2
                ;;
            --inventory)
                custom_inventory_file="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --reset)
                echo -e "${RED}❌ --reset 옵션은 첫 번째 인자여야 합니다${NC}"
                print_usage
                exit 1
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 알 수 없는 옵션: $1${NC}"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # 전역 변수 설정
    CUSTOMER_NAME="$customer"
    REQUESTED_K8S_VERSION="$requested_k8s_version"
    CUSTOM_INVENTORY_FILE="$custom_inventory_file"
    DRY_RUN="$dry_run"
    
    print_banner
    
    if [[ "$RESET_MODE" == true ]]; then
        # Reset 워크플로우
        select_kubernetes_version        # 사용자 선택 또는 옵션으로 지정
        check_system_requirements       # 선택한 버전 요구사항 확인
        check_kubespray_availability    # Kubespray 설치 여부 확인
        get_customer_info              # 고객 정보 및 디렉토리 설정
        configure_nodes                # 인벤토리 설정
        prepare_kubespray              # 선택한 버전의 kubespray 준비
        test_connectivity              # 연결 테스트
        reset_kubernetes               # 클러스터 제거 실행
    else
        # 일반 설치 워크플로우
        select_kubernetes_version        # 사용자 선택 또는 옵션으로 지정
        check_system_requirements       # 선택한 버전 요구사항 확인
        check_kubespray_availability    # Kubespray 설치 여부 확인
        get_customer_info              # 고객 정보 및 디렉토리 설정
        configure_nodes                # 인벤토리 설정
        prepare_kubespray              # 선택한 버전의 kubespray 준비
        test_connectivity              # 연결 테스트
        install_kubernetes             # 설치 실행
    fi
}

# 스크립트가 직접 실행될 때만 main 함수 호출
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi