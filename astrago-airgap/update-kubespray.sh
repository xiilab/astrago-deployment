#!/bin/bash
# kubespray-offline 업데이트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$SCRIPT_DIR/kubespray-offline"
TARGET_VERSION="${1:-latest}"

echo "🔄 kubespray-offline 업데이트 스크립트"
echo "대상 버전: $TARGET_VERSION"

# kubespray-offline이 git 저장소인지 확인
if [ ! -d "$KUBESPRAY_DIR/.git" ]; then
    echo "❌ kubespray-offline이 git 저장소가 아닙니다."
    echo "다음 명령으로 초기화하세요:"
    echo ""
    echo "# 현재 kubespray-offline 디렉토리 백업"
    echo "mv kubespray-offline kubespray-offline.backup"
    echo ""
    echo "# git submodule로 다시 추가"
    echo "git submodule add https://github.com/kubespray-offline/kubespray-offline.git kubespray-offline"
    echo "git submodule update --init --recursive"
    exit 1
fi

# 변경사항 확인
cd "$KUBESPRAY_DIR"
if ! git diff --quiet; then
    echo "⚠️ kubespray-offline에 변경사항이 있습니다:"
    git status --porcelain
    echo ""
    read -p "변경사항을 무시하고 계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "업데이트가 취소되었습니다."
        exit 1
    fi
    git reset --hard
fi

# 현재 버전 확인
CURRENT_VERSION=$(git describe --tags --always 2>/dev/null || echo "unknown")
echo "현재 버전: $CURRENT_VERSION"

# 원격 저장소에서 최신 정보 가져오기
echo "🔄 원격 저장소에서 최신 정보 가져오는 중..."
git fetch origin

# 사용 가능한 태그 목록 표시
echo ""
echo "📋 사용 가능한 버전들:"
git tag --sort=-version:refname | head -10

if [ "$TARGET_VERSION" == "latest" ]; then
    # 최신 태그 찾기
    LATEST_TAG=$(git tag --sort=-version:refname | head -1)
    if [ -z "$LATEST_TAG" ]; then
        TARGET_VERSION="master"
        echo "태그가 없어서 master 브랜치를 사용합니다."
    else
        TARGET_VERSION="$LATEST_TAG"
        echo "최신 태그: $TARGET_VERSION"
    fi
fi

# 지정된 버전으로 체크아웃
echo "🔄 $TARGET_VERSION(으)로 업데이트 중..."
if git show-ref --verify --quiet "refs/tags/$TARGET_VERSION"; then
    # 태그인 경우
    git checkout "$TARGET_VERSION"
    echo "✅ 태그 $TARGET_VERSION(으)로 업데이트 완료"
elif git show-ref --verify --quiet "refs/remotes/origin/$TARGET_VERSION"; then
    # 브랜치인 경우
    git checkout -B "$TARGET_VERSION" "origin/$TARGET_VERSION"
    echo "✅ 브랜치 $TARGET_VERSION(으)로 업데이트 완료"
else
    echo "❌ 버전 '$TARGET_VERSION'을(를) 찾을 수 없습니다."
    echo "사용 가능한 태그:"
    git tag | tail -10
    echo "사용 가능한 브랜치:"
    git branch -r | grep -v HEAD
    exit 1
fi

# 업데이트 후 버전 확인
NEW_VERSION=$(git describe --tags --always)
echo "업데이트 후 버전: $NEW_VERSION"

# 변경사항 요약
if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    echo ""
    echo "🔍 주요 변경사항:"
    git log --oneline "${CURRENT_VERSION}..${NEW_VERSION}" | head -10
fi

echo ""
echo "✅ kubespray-offline 업데이트가 완료되었습니다!"
echo ""
echo "다음 단계:"
echo "1. Astrago 오버레이 스크립트들이 새 버전과 호환되는지 확인"
echo "2. 필요하면 astrago-overlay/configs/astrago.conf 설정 조정"  
echo "3. 새로 패키지 빌드: cd astrago-overlay/scripts && ./1-prepare.sh"