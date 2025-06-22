#!/bin/bash

# AstraGo 컨테이너 이미지 전달 패키지 생성 스크립트
# 작성일: $(date '+%Y-%m-%d')

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/kubespray-offline/outputs"
IMAGES_DIR="${OUTPUT_DIR}/images"
DELIVERY_DIR="${OUTPUT_DIR}/delivery"

echo "=== AstraGo 컨테이너 이미지 전달 패키지 생성 ==="

# 전달 디렉토리 생성
mkdir -p "${DELIVERY_DIR}"

# 1. 이미지 파일들을 압축
echo "1. 컨테이너 이미지 파일 압축 중..."
cd "${OUTPUT_DIR}"
tar -czf "${DELIVERY_DIR}/astrago-container-images.tar.gz" images/
echo "   압축 완료: astrago-container-images.tar.gz"

# 2. Harbor 푸시 스크립트 생성
echo "2. Harbor 푸시 스크립트 생성 중..."
cat > "${DELIVERY_DIR}/push_to_harbor.sh" << 'EOF'
#!/bin/bash

# AstraGo 컨테이너 이미지 Harbor 푸시 스크립트
# 사용법: ./push_to_harbor.sh <HARBOR_URL> <HARBOR_PROJECT> [USERNAME] [PASSWORD]

set -e

if [ $# -lt 2 ]; then
    echo "사용법: $0 <HARBOR_URL> <HARBOR_PROJECT> [USERNAME] [PASSWORD]"
    echo "예시: $0 harbor.company.com astrago admin Harbor12345"
    exit 1
fi

HARBOR_URL="$1"
HARBOR_PROJECT="$2"
HARBOR_USERNAME="${3:-admin}"
HARBOR_PASSWORD="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"

echo "=== AstraGo 컨테이너 이미지 Harbor 푸시 시작 ==="
echo "Harbor URL: ${HARBOR_URL}"
echo "Harbor Project: ${HARBOR_PROJECT}"
echo "Harbor Username: ${HARBOR_USERNAME}"
echo ""

# Harbor 로그인
if [ -n "$HARBOR_PASSWORD" ]; then
    echo "Harbor 로그인 중..."
    echo "$HARBOR_PASSWORD" | docker login "$HARBOR_URL" -u "$HARBOR_USERNAME" --password-stdin
else
    echo "Harbor 로그인 중... (패스워드를 입력하세요)"
    docker login "$HARBOR_URL" -u "$HARBOR_USERNAME"
fi

# 이미지 로드 및 푸시 함수
load_and_push_image() {
    local tar_file="$1"
    local original_name="$2"
    
    echo "처리 중: $original_name"
    
    # 이미지 로드
    docker load -i "$tar_file"
    
    # 새로운 태그 생성 (Harbor 형식)
    local new_tag="${HARBOR_URL}/${HARBOR_PROJECT}/${original_name}"
    
    # 태그 변경
    docker tag "$original_name" "$new_tag"
    
    # Harbor에 푸시
    docker push "$new_tag"
    
    # 로컬 이미지 정리 (선택사항)
    docker rmi "$original_name" "$new_tag" 2>/dev/null || true
    
    echo "완료: $new_tag"
    echo ""
}

# 이미지 목록 파일 읽기 및 처리
if [ -f "${IMAGES_DIR}/images.list" ]; then
    echo "기본 이미지 목록 처리 중..."
    while IFS= read -r image_name; do
        if [ -n "$image_name" ] && [[ ! "$image_name" =~ ^# ]]; then
            # 파일명 변환 (슬래시와 콜론을 달러로 변환)
            tar_filename=$(echo "$image_name" | sed 's|/|\$|g' | sed 's|:|\$|g')
            tar_file="${IMAGES_DIR}/${tar_filename}.tar.gz"
            
            if [ -f "$tar_file" ]; then
                load_and_push_image "$tar_file" "$image_name"
            else
                echo "경고: $tar_file 파일을 찾을 수 없습니다."
            fi
        fi
    done < "${IMAGES_DIR}/images.list"
fi

# 추가 이미지 목록 처리
if [ -f "${IMAGES_DIR}/additional-images.list" ]; then
    echo "추가 이미지 목록 처리 중..."
    while IFS= read -r image_name; do
        if [ -n "$image_name" ] && [[ ! "$image_name" =~ ^# ]]; then
            tar_filename=$(echo "$image_name" | sed 's|/|\$|g' | sed 's|:|\$|g')
            tar_file="${IMAGES_DIR}/${tar_filename}.tar.gz"
            
            if [ -f "$tar_file" ]; then
                load_and_push_image "$tar_file" "$image_name"
            else
                echo "경고: $tar_file 파일을 찾을 수 없습니다."
            fi
        fi
    done < "${IMAGES_DIR}/additional-images.list"
fi

echo "=== 모든 이미지 푸시 완료 ==="
echo "Harbor 프로젝트 확인: https://${HARBOR_URL}/harbor/projects/${HARBOR_PROJECT}/repositories"
EOF

chmod +x "${DELIVERY_DIR}/push_to_harbor.sh"

# 3. 배치 푸시 스크립트 생성 (Windows용)
echo "3. Windows용 배치 스크립트 생성 중..."
cat > "${DELIVERY_DIR}/push_to_harbor.bat" << 'EOF'
@echo off
setlocal enabledelayedexpansion

REM AstraGo 컨테이너 이미지 Harbor 푸시 스크립트 (Windows용)
REM 사용법: push_to_harbor.bat <HARBOR_URL> <HARBOR_PROJECT> [USERNAME] [PASSWORD]

if "%~2"=="" (
    echo 사용법: %0 ^<HARBOR_URL^> ^<HARBOR_PROJECT^> [USERNAME] [PASSWORD]
    echo 예시: %0 harbor.company.com astrago admin Harbor12345
    exit /b 1
)

set HARBOR_URL=%1
set HARBOR_PROJECT=%2
set HARBOR_USERNAME=%3
set HARBOR_PASSWORD=%4

if "%HARBOR_USERNAME%"=="" set HARBOR_USERNAME=admin

set SCRIPT_DIR=%~dp0
set IMAGES_DIR=%SCRIPT_DIR%images

echo === AstraGo 컨테이너 이미지 Harbor 푸시 시작 ===
echo Harbor URL: %HARBOR_URL%
echo Harbor Project: %HARBOR_PROJECT%
echo Harbor Username: %HARBOR_USERNAME%
echo.

REM Harbor 로그인
if not "%HARBOR_PASSWORD%"=="" (
    echo Harbor 로그인 중...
    echo %HARBOR_PASSWORD% | docker login %HARBOR_URL% -u %HARBOR_USERNAME% --password-stdin
) else (
    echo Harbor 로그인 중... (패스워드를 입력하세요)
    docker login %HARBOR_URL% -u %HARBOR_USERNAME%
)

REM 이미지 처리 함수 (배치에서는 함수 대신 라벨 사용)
goto :process_images

:load_and_push_image
set tar_file=%1
set original_name=%2

echo 처리 중: %original_name%

REM 이미지 로드
docker load -i "%tar_file%"

REM 새로운 태그 생성
set new_tag=%HARBOR_URL%/%HARBOR_PROJECT%/%original_name%

REM 태그 변경
docker tag "%original_name%" "%new_tag%"

REM Harbor에 푸시
docker push "%new_tag%"

REM 로컬 이미지 정리
docker rmi "%original_name%" "%new_tag%" 2>nul

echo 완료: %new_tag%
echo.
goto :eof

:process_images
REM 이미지 목록 파일 처리는 복잡하므로 PowerShell 스크립트 호출
powershell -Command "& { Get-Content '%IMAGES_DIR%\images.list' | ForEach-Object { if ($_ -and !$_.StartsWith('#')) { $tarFile = $_ -replace '/', '$' -replace ':', '$'; $tarPath = '%IMAGES_DIR%\' + $tarFile + '.tar.gz'; if (Test-Path $tarPath) { Write-Host 'Processing:' $_; docker load -i $tarPath; $newTag = '%HARBOR_URL%/%HARBOR_PROJECT%/' + $_; docker tag $_ $newTag; docker push $newTag; docker rmi $_ $newTag 2>$null } } } }"

echo === 모든 이미지 푸시 완료 ===
echo Harbor 프로젝트 확인: https://%HARBOR_URL%/harbor/projects/%HARBOR_PROJECT%/repositories
EOF

# 4. 사용 가이드 문서 생성
echo "4. 사용 가이드 문서 생성 중..."
cat > "${DELIVERY_DIR}/README.md" << 'EOF'
# AstraGo 컨테이너 이미지 전달 패키지

## 📋 패키지 내용

- `astrago-container-images.tar.gz`: 모든 컨테이너 이미지 파일들
- `push_to_harbor.sh`: Linux/macOS용 Harbor 푸시 스크립트
- `push_to_harbor.bat`: Windows용 Harbor 푸시 스크립트
- `README.md`: 이 가이드 문서

## 🚀 사용 방법

### 1단계: 압축 파일 해제
```bash
tar -xzf astrago-container-images.tar.gz
```

### 2단계: Harbor에 이미지 푸시

#### Linux/macOS 환경:
```bash
# 실행 권한 부여
chmod +x push_to_harbor.sh

# Harbor에 푸시 (패스워드 포함)
./push_to_harbor.sh harbor.company.com astrago admin Harbor12345

# Harbor에 푸시 (패스워드 대화형 입력)
./push_to_harbor.sh harbor.company.com astrago admin
```

#### Windows 환경:
```cmd
push_to_harbor.bat harbor.company.com astrago admin Harbor12345
```

### 3단계: 푸시 확인
Harbor 웹 UI에서 다음 URL로 접속하여 이미지들이 정상적으로 푸시되었는지 확인:
```
https://harbor.company.com/harbor/projects/astrago/repositories
```

## 📊 포함된 이미지 목록

### 핵심 AstraGo 이미지:
- xiilab/astrago/core
- xiilab/astrago/batch  
- xiilab/astrago/monitor
- xiilab/astrago/frontend
- xiilab/astrago/time-prediction

### 의존성 이미지:
- Kubernetes 기본 이미지 (kube-apiserver, kube-controller-manager 등)
- NVIDIA GPU Operator 이미지
- Harbor 이미지
- Prometheus/Grafana 모니터링 이미지
- 기타 필수 컴포넌트 이미지

## ⚠️ 주의사항

1. **Docker 데몬**: 스크립트 실행 전에 Docker가 실행 중인지 확인하세요.
2. **Harbor 접근**: Harbor 서버에 네트워크 접근이 가능한지 확인하세요.
3. **권한**: Harbor 프로젝트에 이미지 푸시 권한이 있는지 확인하세요.
4. **디스크 공간**: 압축 해제 및 이미지 로드를 위한 충분한 디스크 공간(약 30GB)이 필요합니다.

## 🔧 문제 해결

### 일반적인 문제:
- **로그인 실패**: Harbor 계정 정보와 권한을 확인하세요.
- **푸시 실패**: 네트워크 연결과 Harbor 서버 상태를 확인하세요.
- **이미지 로드 실패**: 압축 파일이 손상되지 않았는지 확인하세요.

### 수동 푸시 방법:
개별 이미지를 수동으로 푸시하려면:
```bash
# 이미지 로드
docker load -i images/docker.io\$xiilab\$astrago\$core-stag-52d6.tar.gz

# 태그 변경
docker tag docker.io/xiilab/astrago/core:stag-52d6 harbor.company.com/astrago/xiilab/astrago/core:stag-52d6

# 푸시
docker push harbor.company.com/astrago/xiilab/astrago/core:stag-52d6
```

## 📞 지원

문제가 발생하면 AstraGo 기술 지원팀에 문의하세요.
EOF

# 5. 체크섬 파일 생성
echo "5. 체크섬 파일 생성 중..."
cd "${DELIVERY_DIR}"
sha256sum astrago-container-images.tar.gz > astrago-container-images.tar.gz.sha256
echo "   체크섬 파일 생성 완료"

# 6. 전달 패키지 정보 출력
echo ""
echo "=== 전달 패키지 생성 완료 ==="
echo "패키지 위치: ${DELIVERY_DIR}"
echo ""
echo "📦 전달 파일 목록:"
ls -lh "${DELIVERY_DIR}/"
echo ""
echo "📊 패키지 크기:"
du -sh "${DELIVERY_DIR}/"
echo ""
echo "✅ 고객에게 전달할 파일들:"
echo "   1. astrago-container-images.tar.gz (메인 이미지 파일)"
echo "   2. astrago-container-images.tar.gz.sha256 (체크섬)"
echo "   3. push_to_harbor.sh (Linux/macOS 푸시 스크립트)"
echo "   4. push_to_harbor.bat (Windows 푸시 스크립트)"
echo "   5. README.md (사용 가이드)"
echo ""
echo "🚀 고객 사용법:"
echo "   1. 모든 파일을 고객 서버로 전송"
echo "   2. tar -xzf astrago-container-images.tar.gz"
echo "   3. ./push_to_harbor.sh <HARBOR_URL> <PROJECT> <USER> <PASS>"
echo ""
EOF 