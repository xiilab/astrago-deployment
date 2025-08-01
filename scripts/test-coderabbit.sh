#!/bin/bash

# CodeRabbit 테스트용 스크립트
# 이 스크립트는 CodeRabbit의 코드 리뷰 기능을 테스트하기 위해 작성되었습니다.

set -e

# 변수 설정
PROJECT_NAME="astrago-deployment"
TEST_FILE="coderabbit-test.log"

# 함수 정의
function print_info() {
    echo "[INFO] $1"
}

function print_error() {
    echo "[ERROR] $1" >&2
}

# 메인 로직
main() {
    print_info "CodeRabbit 테스트 시작"
    
    # 현재 날짜 및 시간 기록
    current_time=$(date '+%Y-%m-%d %H:%M:%S')
    print_info "테스트 시간: $current_time"
    
    # 프로젝트 정보 출력
    print_info "프로젝트: $PROJECT_NAME"
    
    # Git 정보 확인
    if git rev-parse --git-dir > /dev/null 2>&1; then
        branch_name=$(git branch --show-current)
        commit_hash=$(git rev-parse --short HEAD)
        print_info "현재 브랜치: $branch_name"
        print_info "커밋 해시: $commit_hash"
    else
        print_error "Git 저장소가 아닙니다"
        exit 1
    fi
    
    # 테스트 로그 파일 생성
    cat > "$TEST_FILE" << EOF
CodeRabbit Integration Test Log
==============================
테스트 시간: $current_time
프로젝트: $PROJECT_NAME
브랜치: $branch_name
커밋: $commit_hash

테스트 항목:
1. 자동 리뷰 기능
2. 한국어 응답
3. 코드 품질 분석
4. 보안 검사

상태: 진행 중
EOF
    
    print_info "테스트 로그 파일 생성 완료: $TEST_FILE"
    print_info "CodeRabbit 테스트 완료"
}

# 스크립트 실행
main "$@"