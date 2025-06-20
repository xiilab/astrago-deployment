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
    echo -e "${GRADIENT4}║  ${DIM}${WHITE}통합 설치 환경 구성 - 온라인/오프라인 모드 지원${RESET}${GRADIENT4}                      ║${RESET}"
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

# Print warning message
print_warning() {
    local message="$1"
    echo -e "${YELLOW}   ⚠️  ${BOLD}${message}${RESET}"
}

# Print error message
print_error() {
    local message="$1"
    echo -e "${RED}   ❌ ${BOLD}${message}${RESET}"
}

# ==========================================
# � System Checking Functions
# ==========================================

# Function to detect Python version
detect_python_version() {
    for py_version in python3.12 python3.11 python3.10 python3; do
        if command -v "$py_version" &> /dev/null; then
            local version_string=$($py_version --version 2>&1 | cut -d' ' -f2)
            local major_minor=$(echo "$version_string" | cut -d'.' -f1,2)
            
            if python3 -c "import sys; exit(0 if sys.version_info >= (3, 9) else 1)" 2>/dev/null; then
                echo "$py_version:$major_minor"
                return 0
            fi
        fi
    done
    
    echo "none:0"
    return 1
}

# Function to check system requirements
check_system_requirements() {
    print_section "시스템 요구사항 검사" "🔍"
    
    # Check OS
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        print_info "감지된 운영체제: ${BOLD}${ID} ${VERSION_ID}${RESET}"
    elif [ "$(uname)" = "Darwin" ]; then
        print_info "감지된 운영체제: ${BOLD}macOS $(sw_vers -productVersion)${RESET}"
        export ID="macos"
        export VERSION_ID=$(sw_vers -productVersion)
    else
        print_warning "운영체제를 정확히 감지할 수 없습니다. 계속 진행합니다."
        export ID="unknown"
        export VERSION_ID="unknown"
    fi
    
    print_info "시스템 아키텍처: ${BOLD}$(uname -m)${RESET}"
    
    # Check for required commands
    local missing_commands=()
    for cmd in git curl wget; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        print_error "필수 명령어가 누락되었습니다: ${missing_commands[*]}"
        print_info "패키지 매니저를 사용하여 설치해주세요"
        exit 1
    fi
    
    # Check disk space (minimum 10GB)
    local available_space=$(df "$CURRENT_DIR" | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 10485760 ]; then # 10GB in KB
        print_warning "디스크 공간이 부족합니다. 최소 10GB 권장"
    else
        print_success "디스크 공간 충분: $(( available_space / 1024 / 1024 ))GB 사용 가능"
    fi
    
    print_success "시스템 요구사항 검사 완료"
}

# Function to select installation mode
select_installation_mode() {
    # Check if AUTO_MODE is set
    if [ -n "$AUTO_MODE" ]; then
        print_info "자동 모드: 온라인 설치로 진행합니다"
        echo "online"
        return
    fi
    
    echo ""
    echo ""
    print_section "설치 모드 선택" "🔧"
    echo ""
    echo -e "${BOLD}${CYAN}설치 모드를 선택해주세요:${RESET}"
    echo ""
    echo -e "  ${GREEN}${BOLD}1)${RESET} ${GREEN}온라인 설치${RESET}"
    echo -e "     ${DIM}→ 인터넷을 통한 패키지 다운로드 및 설치${RESET}"
    echo -e "     ${DIM}→ 최신 버전 사용 가능${RESET}"
    echo ""
    echo -e "  ${BLUE}${BOLD}2)${RESET} ${BLUE}오프라인 설치${RESET}"
    echo -e "     ${DIM}→ 로컬 패키지를 사용한 에어갭 환경 설치${RESET}"
    echo -e "     ${DIM}→ 사전에 패키지 준비 필요${RESET}"
    echo ""
    echo -e "${DIM}💡 팁: 자동 모드로 실행하려면 AUTO_MODE=1 환경변수를 설정하세요${RESET}"
    echo ""
    
    while true; do
        echo -n -e "${BOLD}${YELLOW}설치 모드를 선택하세요 [1-2] (기본값: 1): ${RESET}"
        
        # Force flush output
        exec 1>&1
        
        # Read user input with timeout
        if read -t 60 -r choice; then
            echo ""  # New line after input
            case $choice in
                1|"")
                    print_success "온라인 설치 모드가 선택되었습니다"
                    echo "online"
                    return
                    ;;
                2)
                    print_success "오프라인 설치 모드가 선택되었습니다"
                    echo "offline"
                    return
                    ;;
                *)
                    print_error "잘못된 선택입니다: '$choice'. 1 또는 2를 선택해주세요."
                    echo ""
                    ;;
            esac
        else
            # Timeout occurred
            echo ""
            print_warning "입력 시간 초과. 기본값(온라인 설치)으로 진행합니다."
            echo "online"
            return
        fi
    done
}

# ==========================================
# 📦 Installation Functions
# ==========================================

# Get the current directory of the script
CURRENT_DIR=$(dirname "$(realpath "$0")")

# Source OS release information if available
if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

# Function to install Python 3.11 on RHEL/CentOS
install_python_rhel() {
    local mode="$1"
    local DNF_OPTS=""
    if [[ $mode == "offline" ]]; then
        DNF_OPTS="--disablerepo=* --enablerepo=offline-repo"
    fi

    if [[ "$VERSION_ID" =~ ^7.* ]]; then
        print_error "RHEL/CentOS 7은 더 이상 지원되지 않습니다."
        exit 1
    fi

    print_step "RHEL/CentOS용 Python 설치 중..."
    sudo dnf install -y $DNF_OPTS python3.11 python3.11-venv || exit 1
    print_success "Python 3.11 설치 완료!"
}

# Function to install Python on Ubuntu
install_python_ubuntu() {
    local mode="$1"
    local PY="3.11"
    
    case "$VERSION_ID" in
        20.04)
            if [[ $mode == "online" ]]; then
                print_step "Ubuntu 20.04용 Python 저장소 추가 중..."
                sudo apt install -y software-properties-common
                sudo add-apt-repository ppa:deadsnakes/ppa -y || exit 1
                sudo apt update
                print_success "저장소 추가 완료!"
            fi
            ;;
        24.04)
            PY="3.12"
            print_info "Ubuntu 24.04에서는 Python 3.12 사용"
            ;;
    esac
    
    print_step "Python ${PY} 및 가상환경 지원 패키지 설치 중..."
    sudo apt install -y python${PY}-venv || exit 1
    print_success "Python ${PY} 설치 완료!"
}

# Function to setup Python environment
setup_python_environment() {
    local mode="$1"
    local python_info=$(detect_python_version)
    local python_cmd=$(echo "$python_info" | cut -d':' -f1)
    local python_version=$(echo "$python_info" | cut -d':' -f2)
    
    if [ "$python_cmd" = "none" ]; then
        print_step "Python 설치 중..."
        if [[ -e /etc/redhat-release ]]; then
            install_python_rhel "$mode"
        else
            sudo apt update
            install_python_ubuntu "$mode"
        fi
        
        # Re-detect after installation
        python_info=$(detect_python_version)
        python_cmd=$(echo "$python_info" | cut -d':' -f1)
        python_version=$(echo "$python_info" | cut -d':' -f2)
    fi
    
    print_info "Python 버전: $python_cmd ($python_version)"
    
    # Create virtual environment directory name based on detected version
    local venv_dir="$HOME/.venv/$python_version"
    
    if [ ! -d "$venv_dir" ]; then
        print_step "Python 가상환경 생성 중: $venv_dir"
        $python_cmd -m venv "$venv_dir" || {
            print_error "가상환경 생성 실패"
            exit 1
        }
        print_success "가상환경 생성 완료!"
    else
        print_success "가상환경이 이미 존재합니다"
    fi
    
    print_step "가상환경 활성화 중..."
    source "$venv_dir/bin/activate" || {
        print_error "가상환경 활성화 실패"
        exit 1
    }
    
    # Store the environment info for later use
    export PYTHON_CMD="$python_cmd"
    export VENV_DIR="$venv_dir"
    export PYTHON_VERSION="$python_version"
    
    print_success "Python 환경 설정 완료!"
}

# Function to check and install binaries
install_binary() {
    local cmd=$1
    if ! command -v $cmd &> /dev/null; then
        print_step "${cmd} 설치 중..."
        if [[ -f "$CURRENT_DIR/tools/linux/$cmd" ]]; then
            sudo cp "$CURRENT_DIR/tools/linux/$cmd" /usr/local/bin/
            sudo chmod +x /usr/local/bin/$cmd
            print_success "${cmd} 설치 완료!"
        else
            print_error "${cmd} 바이너리가 tools 폴더에서 찾을 수 없습니다."
            exit 1
        fi
    else
        print_success "${cmd}이(가) 이미 설치되어 있습니다."
    fi
}

# Function to install system dependencies
install_system_dependencies() {
    local mode="$1"
    
    print_section "시스템 의존성 설치" "📦"
    
    # Skip sshpass installation on macOS for now
    if [ "$ID" = "macos" ]; then
        print_info "macOS에서는 sshpass 설치를 건너뜁니다."
        print_warning "필요시 'brew install hudochenkov/sshpass/sshpass' 명령으로 설치하세요."
        return
    fi
    
    # Install sshpass if not available
    if ! command -v sshpass &> /dev/null; then
        print_step "SSH 연결을 위한 sshpass 설치 중..."
        case $ID_LIKE in
            *debian*)
                if [[ $mode == "online" ]]; then
                    sudo apt update
                fi
                sudo apt install -y sshpass || exit 1
                ;;
            *rhel*|*fedora*)
                if [[ $mode == "online" ]]; then
                    sudo dnf check-update
                fi
                sudo dnf install -y sshpass || exit 1
                ;;
            *)
                if [[ -e /etc/redhat-release ]]; then
                    sudo dnf install -y sshpass || exit 1
                else
                    sudo apt install -y sshpass || exit 1
                fi
                ;;
        esac
        print_success "sshpass 설치 완료!"
    else
        print_success "sshpass가 이미 설치되어 있습니다."
    fi
}

# ==========================================
# 🚀 Main Installation Process
# ==========================================

# Print beautiful header
print_header

# Check system requirements
check_system_requirements

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Select installation mode
INSTALLATION_MODE=$(select_installation_mode)
export IS_OFFLINE=$([ "$INSTALLATION_MODE" = "offline" ] && echo "true" || echo "false")

print_section "설치 모드" "⚙️"
if [ "$INSTALLATION_MODE" = "offline" ]; then
    print_info "선택된 모드: ${BOLD}오프라인 설치${RESET}"
    print_warning "오프라인 모드에서는 로컬 패키지만 사용됩니다"
else
    print_info "선택된 모드: ${BOLD}온라인 설치${RESET}"
    print_info "인터넷을 통해 최신 패키지를 다운로드합니다"
fi

# System Dependencies Installation
install_system_dependencies "$INSTALLATION_MODE"

# Python Environment Setup
print_section "Python 환경 설정" "🐍"
setup_python_environment "$INSTALLATION_MODE"

# Install Python dependencies
print_step "Python 의존성 설치 중..."
pip install -r "$CURRENT_DIR/kubespray/requirements.txt" || {
    print_error "Python 의존성 설치 실패"
    exit 1
}
print_success "Python 의존성 설치 완료!"

# Kubernetes Tools Installation
print_section "Kubernetes 도구 설치" "☸️"

# Check and install helm, helmfile, kubectl, and yq if necessary
for cmd in helm helmfile kubectl yq; do
    install_binary $cmd
done

# Final Launch
print_section "GUI 인스톨러 실행" "🎯"

echo ""
echo -e "${GRADIENT1}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GRADIENT2}║                                                                              ║${RESET}"
echo -e "${GRADIENT3}║  ${BOLD}${WHITE}🎉 설치 환경 구성 완료! ${RESET}${GRADIENT3}                                              ║${RESET}"
echo -e "${GRADIENT4}║  ${DIM}${WHITE}Astrago GUI 인스톨러를 시작합니다...${RESET}${GRADIENT4}                                ║${RESET}"
echo -e "${GRADIENT1}║                                                                              ║${RESET}"
echo -e "${GRADIENT2}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# Pass installation mode to the GUI installer
export ASTRAGO_INSTALLATION_MODE="$INSTALLATION_MODE"

# Run the installer script
$PYTHON_CMD "$CURRENT_DIR/astrago_gui_installer.py"