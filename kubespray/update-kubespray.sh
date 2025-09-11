#!/bin/bash
# kubespray/update-kubespray.sh - Kubespray 버전 관리

set -e

SCRIPT_DIR="$(dirname $(realpath $0))"
VERSIONS_DIR="$SCRIPT_DIR/versions"

# 컬러 출력
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_usage() {
    echo "Usage: $0 <command> [version]"
    echo ""
    echo "Commands:"
    echo "  install <version>     특정 버전 설치/업데이트"
    echo "  install-all          모든 필요 버전 설치"
    echo "  list                 설치된 버전 목록"
    echo "  remove <version>     특정 버전 제거"
    echo "  status              지원 버전 상태 확인"
    echo ""
    echo "지원하는 버전:"
    echo "  v2.23.3             Kubernetes 1.28.14용"
    echo "  v2.25.0             Kubernetes 1.32.8용"
    echo ""
    echo "Examples:"
    echo "  $0 install v2.25.0"
    echo "  $0 install-all"
    echo "  $0 list"
    echo "  $0 status"
}

install_kubespray_version() {
    local version=$1
    local version_dir="$VERSIONS_DIR/$version"
    local kubespray_dir="$version_dir/kubespray"
    
    echo -e "${GREEN}📥 Kubespray $version 설치 중...${NC}"
    
    # 기존 버전 백업 (있다면)
    if [[ -d "$version_dir" ]]; then
        echo "🔄 기존 $version 백업 중..."
        mv "$version_dir" "${version_dir}-backup-$(date +%Y%m%d-%H%M%S)"
    fi
    
    # 새 버전 다운로드
    mkdir -p "$version_dir"
    TEMP_DIR=$(mktemp -d)
    
    echo "📡 GitHub에서 다운로드 중..."
    cd "$TEMP_DIR"
    git clone --depth 1 --branch "$version" https://github.com/kubernetes-sigs/kubespray.git
    cd kubespray
    
    # Git 히스토리 제거 (용량 절약)
    rm -rf .git
    
    # 버전 정보 저장
    cat > .version-info << EOF
version=$version
installed_at=$(date)
downloaded_from=https://github.com/kubernetes-sigs/kubespray
EOF
    
    # 지원 K8s 버전 확인 및 저장
    if [[ -f "roles/kubernetes/defaults/main.yml" ]]; then
        K8S_SUPPORT=$(grep "kube_version:" roles/kubernetes/defaults/main.yml | head -1 | cut -d: -f2 | tr -d ' "v')
        echo "k8s_default=$K8S_SUPPORT" >> .version-info
    fi
    
    # 최종 위치로 이동
    mv "$TEMP_DIR/kubespray" "$kubespray_dir"
    mv "$kubespray_dir/.version-info" "$version_dir/"
    rm -rf "$TEMP_DIR"
    
    echo -e "${GREEN}✅ Kubespray $version 설치 완료${NC}"
    echo "📁 위치: $kubespray_dir"
    
    # 버전 정보 표시
    echo "📋 버전 정보:"
    cat "$version_dir/.version-info" | sed 's/^/   /'
    echo ""
}

install_all_required_versions() {
    echo -e "${GREEN}🔧 필수 Kubespray 버전들 설치 중...${NC}"
    echo ""
    
    source "$SCRIPT_DIR/version-matrix.conf"
    
    REQUIRED_VERSIONS=(
        "$K8S_STABLE_KUBESPRAY"
        "$K8S_LATEST_KUBESPRAY"
    )
    
    # 중복 제거
    UNIQUE_VERSIONS=($(printf "%s\n" "${REQUIRED_VERSIONS[@]}" | sort -u))
    
    echo "📋 설치할 버전들:"
    for version in "${UNIQUE_VERSIONS[@]}"; do
        case "$version" in
            "$K8S_STABLE_KUBESPRAY")
                echo "   - $version (안정 버전 - K8s $K8S_STABLE_VERSION)"
                ;;
            "$K8S_LATEST_KUBESPRAY")
                echo "   - $version (최신 버전 - K8s $K8S_LATEST_VERSION)"
                ;;
        esac
    done
    echo ""
    
    for version in "${UNIQUE_VERSIONS[@]}"; do
        install_kubespray_version "$version"
    done
    
    echo -e "${GREEN}🎉 모든 필요 버전 설치 완료!${NC}"
}

list_installed_versions() {
    echo -e "${GREEN}📋 설치된 Kubespray 버전들:${NC}"
    echo "=========================="
    
    if [[ ! -d "$VERSIONS_DIR" ]] || [[ -z "$(ls -A $VERSIONS_DIR 2>/dev/null)" ]]; then
        echo "설치된 버전이 없습니다."
        echo ""
        echo "💡 설치 명령: $0 install-all"
        return
    fi
    
    source "$SCRIPT_DIR/version-matrix.conf"
    
    for version_dir in "$VERSIONS_DIR"/*; do
        if [[ -d "$version_dir" ]] && [[ -f "$version_dir/.version-info" ]]; then
            version=$(basename "$version_dir")
            echo ""
            echo "📦 $version"
            
            # 용도 표시
            case "$version" in
                "$K8S_STABLE_KUBESPRAY")
                    echo "   🎯 용도: 안정 버전 (K8s $K8S_STABLE_VERSION)"
                    ;;
                "$K8S_LATEST_KUBESPRAY")
                    echo "   🎯 용도: 최신 버전 (K8s $K8S_LATEST_VERSION)"
                    ;;
            esac
            
            # 버전 정보 표시
            while IFS='=' read -r key value; do
                case $key in
                    "installed_at") echo "   🕐 설치일: $value" ;;
                    "k8s_default") echo "   🐳 K8s 기본: v$value" ;;
                esac
            done < "$version_dir/.version-info"
            
            # 디스크 사용량
            SIZE=$(du -sh "$version_dir" 2>/dev/null | cut -f1)
            echo "   💾 크기: $SIZE"
        fi
    done
    echo ""
}

show_version_status() {
    echo -e "${GREEN}🔍 지원 버전 상태 확인${NC}"
    echo "===================="
    
    source "$SCRIPT_DIR/version-matrix.conf"
    
    echo "📋 지원하는 Kubernetes 버전:"
    echo ""
    
    echo "🔒 안정 버전:"
    echo "   K8s: $K8S_STABLE_VERSION → Kubespray: $K8S_STABLE_KUBESPRAY"
    check_version_available "$K8S_STABLE_KUBESPRAY"
    echo ""
    
    echo "🚀 최신 버전:"
    echo "   K8s: $K8S_LATEST_VERSION → Kubespray: $K8S_LATEST_KUBESPRAY"
    check_version_available "$K8S_LATEST_KUBESPRAY"
    echo ""
}

check_version_available() {
    local version=$1
    if [[ -d "$VERSIONS_DIR/$version/kubespray" ]]; then
        echo -e "   ${GREEN}✅ 설치됨${NC}"
    else
        echo -e "   ${RED}❌ 미설치${NC} - $0 install $version 실행 필요"
    fi
}

remove_version() {
    local version=$1
    local version_dir="$VERSIONS_DIR/$version"
    
    if [[ ! -d "$version_dir" ]]; then
        echo -e "${RED}❌ 버전이 존재하지 않습니다: $version${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}⚠️  $version 버전을 제거하시겠습니까?${NC}"
    read -p "삭제하려면 'yes' 입력: " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        rm -rf "$version_dir"
        echo -e "${GREEN}✅ $version 제거 완료${NC}"
    else
        echo "취소되었습니다."
    fi
}

# 메인 실행
main() {
    local command="${1:-}"
    local version="${2:-}"
    
    case "$command" in
        "install")
            if [[ -z "$version" ]]; then
                echo -e "${RED}❌ 버전을 지정해야 합니다${NC}"
                print_usage
                exit 1
            fi
            install_kubespray_version "$version"
            ;;
        "install-all")
            install_all_required_versions
            ;;
        "list")
            list_installed_versions
            ;;
        "status")
            show_version_status
            ;;
        "remove")
            if [[ -z "$version" ]]; then
                echo -e "${RED}❌ 제거할 버전을 지정해야 합니다${NC}"
                print_usage
                exit 1
            fi
            remove_version "$version"
            ;;
        *)
            print_usage
            ;;
    esac
}

main "$@"