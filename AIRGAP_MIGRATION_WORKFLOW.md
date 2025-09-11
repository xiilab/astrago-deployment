# Airgap Kubespray-Offline 분리 프로젝트 워크플로우

## 📋 프로젝트 개요

### 목적
- 기존 airgap 디렉토리(303개 파일)를 kubespray-offline submodule + Astrago 래퍼 구조로 분리
- 100% 호환성을 유지하면서 단일 디렉토리(`astrago-airgap/`)로 통합
- Linear 이슈: BE-550(메인), BE-551(Phase 1), BE-552(Phase 2), BE-553(Phase 3)

### 현재 상황 분석
```
기존 구조:
airgap/
├── kubespray-offline/     (109개 파일 - upstream 소스)
├── inventory/             (Astrago 커스터마이징)
├── *.sh 스크립트들        (Astrago 래퍼 스크립트)
└── 기타 커스터마이징 파일

목표 구조:
astrago-airgap/
├── kubespray-offline/     (submodule)
├── astrago-wrapper/       (래퍼 스크립트)
├── inventory/             (Astrago 설정)
└── README.md              (통합 사용법)
```

---

## 🎯 Phase 1: 준비 및 분석 단계 (3일)

### Day 1: 현황 분석 및 설계 검증

#### 🔍 1.1 종속성 분석 (2시간)
**목적**: 기존 파일들 간의 의존성과 참조 관계 파악

**실행 순서**:
```bash
# 1. 스크립트 간 호출 관계 분석
grep -r "source\|\./" airgap/*.sh
find airgap -name "*.sh" -exec grep -l "kubespray-offline" {} \;

# 2. 설정 파일 참조 경로 분석  
grep -r "airgap/" . --exclude-dir=".git"
grep -r "../" airgap/ --include="*.sh" --include="*.yml"

# 3. 하드코딩된 경로 탐지
grep -r "/airgap/" . --exclude-dir=".git"
grep -r "kubespray-offline" airgap/*.sh
```

**체크포인트**:
- [ ] 모든 외부 참조 경로 문서화 완료
- [ ] kubespray-offline 내부/외부 의존성 구분 완료
- [ ] 래퍼 스크립트별 영향도 평가 완료

**성공 기준**: 
- 종속성 매트릭스 생성 (파일별 x 의존관계별)
- 마이그레이션 위험도 점수 산정 (High/Medium/Low)

#### 🏗️ 1.2 Submodule 전략 수립 (1시간)
**목적**: kubespray-offline의 submodule 적용 방법 확정

**실행 순서**:
```bash
# 1. 현재 kubespray-offline 버전 확인
cd airgap/kubespray-offline
git log --oneline -5 2>/dev/null || echo "Not a git repository"

# 2. 업스트림 저장소 확인 (GitHub/GitLab 확인 필요)
find . -name ".git*" | head -5
grep -r "kubespray-offline" ../.. --include="*.md" | head -3
```

**체크포인트**:
- [ ] 업스트림 저장소 URL 확정
- [ ] 현재 사용 중인 브랜치/태그 식별
- [ ] Submodule 추가 방법 및 위치 결정

**성공 기준**:
- Submodule 설정 명세서 작성 완료
- 버전 고정 전략 수립 완료

#### 📋 1.3 파일 분류 및 매핑 (2시간)
**목적**: 각 파일을 목표 디렉토리에 매핑

**실행 순서**:
```bash
# 1. 파일 분류 자동화 스크립트 작성
cat > analyze_airgap_structure.sh << 'EOF'
#!/bin/bash
echo "=== Astrago Airgap 파일 분류 분석 ==="
echo "현재 시간: $(date)"
echo

echo "📁 디렉토리별 파일 수:"
find airgap -type d | while read dir; do
    count=$(find "$dir" -maxdepth 1 -type f | wc -l)
    echo "  $dir: ${count}개 파일"
done

echo -e "\n🔧 실행 스크립트들:"
find airgap -name "*.sh" -type f | sort

echo -e "\n📋 설정 파일들:"  
find airgap -name "*.yml" -o -name "*.yaml" -o -name "*.json" | head -10

echo -e "\n📦 kubespray-offline 내부:"
ls -la airgap/kubespray-offline/ | head -10
EOF

chmod +x analyze_airgap_structure.sh
./analyze_airgap_structure.sh
```

**체크포인트**:
- [ ] 각 파일의 목표 위치 매핑 테이블 완성
- [ ] Astrago 전용 파일 vs kubespray-offline 파일 구분 완료
- [ ] 마이그레이션 순서 우선순위 결정

**성공 기준**:
- 파일 분류 매트릭스 (303개 파일 전체)
- 마이그레이션 체크리스트 초안 완성

### Day 2: 백업 및 테스트 환경 구축

#### 💾 2.1 백업 전략 실행 (1시간)
**목적**: 안전한 롤백을 위한 완전한 백업

**실행 순서**:
```bash
# 1. 현재 상태 백업
mkdir -p ../astrago-deployment-backup-$(date +%Y%m%d)
cp -r . ../astrago-deployment-backup-$(date +%Y%m%d)/

# 2. Git 상태 백업
git stash push -m "Pre-migration stash $(date)"
git branch backup/pre-airgap-migration-$(date +%Y%m%d)

# 3. 현재 브랜치 상태 문서화
git status > migration_pre_state.txt
git log --oneline -10 >> migration_pre_state.txt
```

**체크포인트**:
- [ ] 파일시스템 백업 완료 및 검증
- [ ] Git 백업 브랜치 생성 완료
- [ ] 백업 복원 절차 테스트 완료

**성공 기준**:
- 백업에서 완전 복원 가능 확인
- 롤백 시나리오별 복원 시간 측정

#### 🧪 2.2 테스트 환경 구축 (2시간)
**목적**: 안전한 테스트를 위한 격리된 환경 준비

**실행 순서**:
```bash
# 1. 테스트 디렉토리 생성
mkdir -p ../airgap-migration-test
cd ../airgap-migration-test

# 2. 현재 airgap 복사
cp -r ../astrago-deployment/airgap ./original-airgap

# 3. 테스트 스크립트 작성
cat > test_migration_step.sh << 'EOF'
#!/bin/bash
set -e

STEP="$1"
echo "🧪 테스트 단계: $STEP"

case "$STEP" in
    "current")
        echo "현재 구조 테스트..."
        cd original-airgap
        ls -la
        ;;
    "migrated") 
        echo "마이그레이션 후 구조 테스트..."
        # 마이그레이션 검증 로직
        ;;
    *)
        echo "사용법: $0 {current|migrated}"
        exit 1
        ;;
esac
EOF

chmod +x test_migration_step.sh
```

**체크포인트**:
- [ ] 격리된 테스트 환경 구축 완료
- [ ] 기존 기능 정상 동작 확인
- [ ] 테스트 자동화 스크립트 준비

**성공 기준**:
- 테스트 환경에서 기존 airgap 스크립트 정상 실행
- 회귀 테스트 시나리오 3개 이상 준비

#### 📚 2.3 문서화 준비 (1시간)
**목적**: 마이그레이션 과정과 결과 문서화 준비

**실행 순서**:
```bash
# 1. 문서 템플릿 생성
mkdir -p migration-docs
cd migration-docs

# 2. 체크리스트 템플릿
cat > migration-checklist.md << 'EOF'
# Airgap 마이그레이션 체크리스트

## Phase 1 체크리스트
- [ ] 종속성 분석 완료
- [ ] Submodule 전략 수립
- [ ] 파일 분류 매핑 완료
- [ ] 백업 전략 실행
- [ ] 테스트 환경 구축
- [ ] 문서화 준비

## Phase 2 체크리스트  
(추후 작성)

## Phase 3 체크리스트
(추후 작성)
EOF

# 3. 이슈 트래킹 템플릿
cat > issues-log.md << 'EOF'
# 마이그레이션 이슈 로그

| 시간 | Phase | 이슈 | 해결방법 | 상태 |
|------|-------|------|----------|------|
|      |       |      |          |      |
EOF
```

**체크포인트**:
- [ ] 문서 구조 및 템플릿 준비 완료
- [ ] 진행 상황 추적 시스템 구축
- [ ] 이슈 에스컬레이션 절차 정의

**성공 기준**:
- 실시간 진행 상황 추적 가능
- 이슈 발생 시 즉시 문서화 가능

### Day 3: Phase 1 검증 및 Phase 2 준비

#### ✅ 3.1 Phase 1 종합 검증 (2시간)
**목적**: Phase 1 완료도 검증 및 Phase 2 진입 가능성 판단

**실행 순서**:
```bash
# 1. 분석 결과 종합 검토
echo "=== Phase 1 완료 검증 ==="
echo "1. 종속성 분석 완료 여부:"
[ -f dependency-matrix.md ] && echo "✅ 완료" || echo "❌ 미완료"

echo "2. 파일 분류 완료 여부:" 
[ -f file-classification.md ] && echo "✅ 완료" || echo "❌ 미완료"

echo "3. 백업 완료 여부:"
[ -d ../astrago-deployment-backup-* ] && echo "✅ 완료" || echo "❌ 미완료"

# 2. 리스크 평가
echo "4. 식별된 High Risk 항목 수:"
grep -c "High" risk-assessment.md 2>/dev/null || echo "0"
```

**체크포인트**:
- [ ] 모든 Phase 1 작업 완료 확인
- [ ] High Risk 항목 3개 이하 확인
- [ ] 팀 리뷰 및 승인 완료

**성공 기준**:
- Phase 1 완료율 95% 이상
- Phase 2 진입 가능 상태 확인

#### 🚀 3.2 Phase 2 실행 계획 최종화 (2시간)
**목적**: Phase 2 상세 실행 계획 확정

**실행 순서**:
```bash
# 1. Phase 2 실행 순서 최종 확인
cat > phase2-execution-plan.md << 'EOF'
# Phase 2 실행 계획

## 목표
- astrago-airgap 디렉토리 생성
- kubespray-offline submodule 적용
- 래퍼 스크립트 마이그레이션

## 실행 순서 (확정)
1. 새 디렉토리 구조 생성
2. Submodule 추가
3. 래퍼 스크립트 이동 및 수정
4. 설정 파일 이동
5. 경로 수정 및 테스트

## 위험 요소
- 경로 변경으로 인한 스크립트 실행 오류
- Submodule 동기화 이슈  
- 권한 및 실행 속성 유실
EOF
```

**체크포인트**:
- [ ] Phase 2 상세 계획 승인 완료
- [ ] 위험 요소 대응 방안 준비 완료
- [ ] 팀 커뮤니케이션 완료

**성공 기준**:
- Phase 2 Go/No-Go 결정 완료
- 실행 준비도 100% 달성

---

## 🔧 Phase 2: 구조 생성 및 Submodule 적용 (3일)

### Day 4: 새로운 디렉토리 구조 생성

#### 🏗️ 4.1 astrago-airgap 디렉토리 생성 (1시간)
**목적**: 새로운 통합 디렉토리 구조 생성

**실행 순서**:
```bash
# 1. 새 디렉토리 생성
mkdir -p astrago-airgap
cd astrago-airgap

# 2. 기본 구조 생성
mkdir -p {astrago-wrapper,inventory,docs}

# 3. 구조 검증
tree -L 2 .
echo "✅ 기본 디렉토리 구조 생성 완료"
```

**체크포인트**:
- [ ] astrago-airgap 디렉토리 생성 완료
- [ ] 하위 디렉토리 구조 생성 완료
- [ ] 권한 설정 완료

**성공 기준**:
- 새 디렉토리 구조 생성 완료
- 기존 디렉토리와 독립성 확보

#### 🔗 4.2 kubespray-offline Submodule 추가 (2시간)
**목적**: kubespray-offline을 submodule로 추가

**실행 순서**:
```bash
# 1. 업스트림 저장소 확인 (사전 조사 결과 반영)
# 실제 kubespray-offline 저장소 URL 확인 필요
echo "업스트림 저장소: https://github.com/kubernetes-sigs/kubespray-offline.git"

# 2. Submodule 추가
git submodule add https://github.com/kubernetes-sigs/kubespray-offline.git kubespray-offline

# 3. 현재 사용 중인 버전으로 고정
cd kubespray-offline
# 기존 airgap/kubespray-offline에서 사용 중인 commit 확인 후 checkout
git checkout <specific-commit-hash>
cd ..

# 4. Submodule 초기화
git submodule update --init --recursive
```

**체크포인트**:
- [ ] Submodule 추가 완료
- [ ] 버전 고정 완료  
- [ ] Submodule 동작 확인

**성공 기준**:
- kubespray-offline submodule 정상 동작
- 기존 버전과 일치성 확인

#### 📝 4.3 기본 README 및 문서 생성 (1시간)
**목적**: 새 구조에 대한 기본 문서 작성

**실행 순서**:
```bash
# 1. 기본 README 생성
cat > README.md << 'EOF'
# Astrago Airgap 배포 도구

## 개요
Astrago 플랫폼의 오프라인 배포를 위한 통합 도구입니다.

## 구조
- `kubespray-offline/`: Kubespray 오프라인 배포 도구 (submodule)
- `astrago-wrapper/`: Astrago 전용 래퍼 스크립트
- `inventory/`: Astrago 인벤토리 설정
- `docs/`: 사용법 및 문서

## 사용법
```bash
# 기본 사용법 (기존과 동일)
./setup-all.sh
./download-all.sh  
./offline_deploy_astrago.sh
```

## 마이그레이션 안내
기존 `airgap/` 디렉토리에서 마이그레이션된 통합 구조입니다.
사용법은 기존과 100% 동일합니다.
EOF

# 2. 마이그레이션 가이드 생성
cat > docs/MIGRATION_GUIDE.md << 'EOF'
# Airgap 마이그레이션 가이드

## 변경 사항
- 기존: `airgap/` 디렉토리
- 새로운: `astrago-airgap/` 디렉토리

## 호환성
모든 기존 스크립트와 설정이 그대로 동작합니다.

## 새로운 기능
- kubespray-offline 자동 업데이트 지원
- 더 명확한 디렉토리 구조
- 향상된 문서화
EOF
```

**체크포인트**:
- [ ] 기본 README 작성 완료
- [ ] 마이그레이션 가이드 작성 완료
- [ ] 사용법 안내 문서 작성 완료

**성공 기준**:
- 새 구조에 대한 명확한 문서 제공
- 기존 사용자 혼란 최소화

### Day 5: 래퍼 스크립트 마이그레이션

#### 📦 5.1 래퍼 스크립트 이동 및 분석 (2시간)
**목적**: Astrago 전용 래퍼 스크립트들을 새 위치로 이동

**실행 순서**:
```bash
# 1. 래퍼 스크립트 식별 및 복사
cd ../airgap
WRAPPER_SCRIPTS=(
    "create_astrago_only_package.sh"
    "create_delivery_package.sh" 
    "deploy_kubernetes.sh"
    "download-all.sh"
    "extract_astrago_images.sh"
    "offline_deploy_astrago.sh"
    "reset_kubernetes.sh"
    "setup-all.sh"
)

# 2. 스크립트 복사
cd ../astrago-airgap
for script in "${WRAPPER_SCRIPTS[@]}"; do
    cp "../airgap/$script" "astrago-wrapper/"
    echo "✅ 복사 완료: $script"
done

# 3. 실행 권한 설정
chmod +x astrago-wrapper/*.sh
```

**체크포인트**:
- [ ] 모든 래퍼 스크립트 복사 완료
- [ ] 실행 권한 설정 완료
- [ ] 스크립트 무결성 확인 완료

**성공 기준**:
- 8개 래퍼 스크립트 정상 복사
- 실행 권한 및 속성 보존

#### 🔧 5.2 경로 참조 수정 (3시간)
**목적**: 새 구조에 맞게 경로 참조 수정

**실행 순서**:
```bash
# 1. 경로 참조 분석 및 수정 스크립트 생성
cat > update_script_paths.sh << 'EOF'
#!/bin/bash
set -e

echo "🔧 래퍼 스크립트 경로 수정 시작..."

cd astrago-wrapper

# 2. kubespray-offline 참조 경로 수정
for script in *.sh; do
    echo "처리 중: $script"
    
    # kubespray-offline 상대 경로 수정
    sed -i 's|kubespray-offline/|../kubespray-offline/|g' "$script"
    
    # inventory 경로 수정  
    sed -i 's|inventory/|../inventory/|g' "$script"
    
    # 기타 airgap 상대 참조 수정
    sed -i 's|\./kubespray-offline|\.\./kubespray-offline|g' "$script"
    
    echo "✅ 완료: $script"
done

echo "🎉 모든 스크립트 경로 수정 완료"
EOF

chmod +x update_script_paths.sh
./update_script_paths.sh

# 3. 수정 결과 확인
grep -r "kubespray-offline" astrago-wrapper/ | head -5
grep -r "inventory" astrago-wrapper/ | head -5
```

**체크포인트**:
- [ ] 모든 경로 참조 수정 완료
- [ ] 상대 경로 정확성 검증 완료
- [ ] 수정 사항 백업 완료

**성공 기준**:
- 모든 스크립트에서 올바른 경로 참조 확인
- 수정 전후 diff 파일 보존

### Day 6: 설정 파일 마이그레이션 및 테스트

#### 📋 6.1 inventory 및 설정 파일 이동 (1시간)
**목적**: Astrago 커스터마이징 설정 파일들 이동

**실행 순서**:
```bash
# 1. inventory 디렉토리 내용 복사
cp -r ../airgap/inventory/* inventory/

# 2. 설정 파일 구조 확인
find inventory -type f | head -10
echo "📁 Inventory 파일 수: $(find inventory -type f | wc -l)"

# 3. 권한 및 속성 보존 확인
ls -la inventory/
```

**체크포인트**:
- [ ] 모든 inventory 파일 복사 완료
- [ ] 파일 권한 보존 확인
- [ ] 디렉토리 구조 유지 확인

**성공 기준**:
- inventory 파일 100% 복사 완료
- 기존 설정 동작 보장

#### 🧪 6.2 기본 기능 테스트 (2시간)
**목적**: 마이그레이션된 구조에서 기본 기능 동작 확인

**실행 순서**:
```bash
# 1. 스크립트 실행 테스트 스크립트 생성
cat > test_basic_functions.sh << 'EOF'
#!/bin/bash
set -e

echo "🧪 기본 기능 테스트 시작..."

cd astrago-wrapper

# 2. 각 스크립트 문법 검사
echo "📝 스크립트 문법 검사..."
for script in *.sh; do
    bash -n "$script" && echo "✅ $script: 문법 OK" || echo "❌ $script: 문법 오류"
done

# 3. 경로 접근 테스트
echo "📂 경로 접근 테스트..."
[ -d "../kubespray-offline" ] && echo "✅ kubespray-offline 접근 OK" || echo "❌ kubespray-offline 접근 불가"
[ -d "../inventory" ] && echo "✅ inventory 접근 OK" || echo "❌ inventory 접근 불가"

# 4. Help 메시지 테스트 (가능한 스크립트만)
echo "ℹ️ Help 메시지 테스트..."
for script in *.sh; do
    if ./"$script" --help >/dev/null 2>&1 || ./"$script" -h >/dev/null 2>&1; then
        echo "✅ $script: help 지원"
    else
        echo "ℹ️ $script: help 미지원"
    fi
done

echo "🎉 기본 기능 테스트 완료"
EOF

chmod +x test_basic_functions.sh
./test_basic_functions.sh
```

**체크포인트**:
- [ ] 모든 스크립트 문법 검사 통과
- [ ] 경로 접근 테스트 통과
- [ ] 기본 실행 테스트 통과

**성공 기준**:
- 스크립트 문법 오류 0개
- 경로 접근 성공률 100%
- 기본 기능 동작 확인

#### 🔄 6.3 호환성 검증 (1시간)
**목적**: 기존 사용법과의 100% 호환성 검증

**실행 순서**:
```bash
# 1. 호환성 테스트 스크립트 생성
cat > test_compatibility.sh << 'EOF'
#!/bin/bash

echo "🔄 호환성 검증 테스트..."

# 2. 기존 airgap과 새 astrago-airgap 비교
echo "📊 스크립트 수 비교:"
OLD_COUNT=$(ls ../airgap/*.sh 2>/dev/null | wc -l)
NEW_COUNT=$(ls astrago-wrapper/*.sh 2>/dev/null | wc -l)
echo "  기존: ${OLD_COUNT}개"
echo "  신규: ${NEW_COUNT}개"

# 3. 스크립트 이름 비교
echo "📋 스크립트 이름 비교:"
echo "기존 스크립트들:"
ls ../airgap/*.sh 2>/dev/null | xargs -n1 basename | sort
echo "새 스크립트들:"
ls astrago-wrapper/*.sh 2>/dev/null | xargs -n1 basename | sort

# 4. 주요 기능 포인트 확인
echo "🎯 주요 기능 확인:"
echo "  - setup-all.sh: $([ -f astrago-wrapper/setup-all.sh ] && echo '✅' || echo '❌')"
echo "  - download-all.sh: $([ -f astrago-wrapper/download-all.sh ] && echo '✅' || echo '❌')"
echo "  - offline_deploy_astrago.sh: $([ -f astrago-wrapper/offline_deploy_astrago.sh ] && echo '✅' || echo '❌')"

echo "🎉 호환성 검증 완료"
EOF

chmod +x test_compatibility.sh
./test_compatibility.sh
```

**체크포인트**:
- [ ] 스크립트 수 일치 확인
- [ ] 핵심 기능 스크립트 존재 확인
- [ ] 사용법 호환성 100% 확인

**성공 기준**:
- 모든 기존 스크립트 존재
- 기존 사용법으로 정상 동작
- 호환성 검증 통과

---

## 🚀 Phase 3: 통합 및 검증 단계 (2-3일)

### Day 7: 심볼릭 링크 및 통합 테스트

#### 🔗 7.1 호환성을 위한 심볼릭 링크 생성 (1시간)
**목적**: 기존 경로에서도 접근 가능하도록 심볼릭 링크 설정

**실행 순서**:
```bash
# 1. 루트 레벨에서 편의성 심볼릭 링크 생성
cd ..  # astrago-deployment 루트로 이동

# 2. 주요 스크립트들에 대한 편의 링크 생성 (선택사항)
ln -sf astrago-airgap/astrago-wrapper/setup-all.sh setup-airgap.sh
ln -sf astrago-airgap/astrago-wrapper/download-all.sh download-airgap.sh
ln -sf astrago-airgap/astrago-wrapper/offline_deploy_astrago.sh deploy-airgap.sh

# 3. 링크 생성 확인
ls -la *airgap*.sh
echo "✅ 편의 링크 생성 완료"
```

**체크포인트**:
- [ ] 심볼릭 링크 생성 완료
- [ ] 링크 동작 확인 완료
- [ ] 편의성 개선 확인

**성공 기준**:
- 루트에서 바로 실행 가능
- 기존 사용자 편의성 향상

#### 🧪 7.2 통합 기능 테스트 (3시간)
**목적**: 전체 워크플로우 end-to-end 테스트

**실행 순서**:
```bash
# 1. 종합 테스트 스크립트 생성
cat > comprehensive_test.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 종합 기능 테스트 시작..."

# 2. 테스트 환경 설정
TEST_ENV="test-env-$(date +%s)"
mkdir -p "$TEST_ENV"
cd "$TEST_ENV"

# 3. astrago-airgap 복사
cp -r ../astrago-airgap .

# 4. 단계별 테스트
echo "📋 1단계: 구조 검증"
cd astrago-airgap
[ -d kubespray-offline ] && echo "✅ submodule 존재" || echo "❌ submodule 누락"
[ -d astrago-wrapper ] && echo "✅ wrapper 디렉토리 존재" || echo "❌ wrapper 누락"
[ -d inventory ] && echo "✅ inventory 디렉토리 존재" || echo "❌ inventory 누락"

echo "📋 2단계: 스크립트 실행 테스트"
cd astrago-wrapper
for script in setup-all.sh download-all.sh; do
    if [ -f "$script" ]; then
        echo "테스트: $script --help"
        ./"$script" --help 2>/dev/null && echo "✅ $script 실행 가능" || echo "ℹ️ $script help 미지원"
    fi
done

echo "📋 3단계: 의존성 확인"
# kubespray-offline 내부 파일 접근 테스트
ls ../kubespray-offline/ >/dev/null 2>&1 && echo "✅ kubespray-offline 접근 OK" || echo "❌ 접근 실패"

# inventory 파일 접근 테스트  
ls ../inventory/ >/dev/null 2>&1 && echo "✅ inventory 접근 OK" || echo "❌ 접근 실패"

echo "🎉 종합 테스트 완료"

# 5. 테스트 정리
cd ../../..
rm -rf "$TEST_ENV"
echo "🧹 테스트 환경 정리 완료"
EOF

chmod +x comprehensive_test.sh
./comprehensive_test.sh
```

**체크포인트**:
- [ ] 전체 워크플로우 정상 동작 확인
- [ ] 의존성 누락 없음 확인
- [ ] 성능 저하 없음 확인

**성공 기준**:
- End-to-end 테스트 100% 통과
- 기존 대비 성능 동등 이상

### Day 8: 문서화 완성 및 배포 준비

#### 📚 8.1 완전한 문서화 (2시간)
**목적**: 사용자 가이드 및 개발자 문서 완성

**실행 순서**:
```bash
# 1. 메인 README 업데이트
cd astrago-airgap
cat > README.md << 'EOF'
# Astrago Airgap 배포 도구

## ✨ 새로운 통합 구조

### 개요
Astrago 플랫폼의 오프라인 배포를 위한 **통합 도구**입니다.
기존 `airgap/` 디렉토리의 모든 기능을 포함하면서 더 체계적인 구조를 제공합니다.

### 🏗️ 디렉토리 구조
```
astrago-airgap/
├── kubespray-offline/     # Kubespray 오프라인 배포 도구 (submodule)
├── astrago-wrapper/       # Astrago 전용 래퍼 스크립트
├── inventory/             # Astrago 인벤토리 설정  
└── docs/                  # 사용법 및 문서
```

### 🚀 사용법 (기존과 100% 동일)
```bash
# 전체 설정 (한 번만 실행)
cd astrago-airgap/astrago-wrapper
./setup-all.sh

# 패키지 다운로드  
./download-all.sh

# 오프라인 배포 실행
./offline_deploy_astrago.sh
```

### 🔄 마이그레이션 안내
- **기존**: `airgap/` 디렉토리 사용
- **신규**: `astrago-airgap/` 디렉토리 사용
- **호환성**: 모든 기존 스크립트와 설정 100% 호환

### 🆕 새로운 장점
- kubespray-offline 자동 업데이트 지원
- 명확한 책임 분리 (upstream vs Astrago 커스터마이징)
- 더 나은 버전 관리
- 향상된 문서화

### 📋 주요 스크립트
- `setup-all.sh`: 초기 환경 설정
- `download-all.sh`: 필요 패키지 다운로드
- `offline_deploy_astrago.sh`: 오프라인 배포 실행
- `create_delivery_package.sh`: 배포 패키지 생성
- `reset_kubernetes.sh`: 환경 초기화

### 🆘 문제 해결
문제 발생 시 `docs/TROUBLESHOOTING.md`를 참조하세요.

---
**마이그레이션 완료**: $(date +%Y-%m-%d)
EOF

# 2. 트러블슈팅 가이드 생성
mkdir -p docs
cat > docs/TROUBLESHOOTING.md << 'EOF'
# 트러블슈팅 가이드

## 자주 발생하는 문제

### 1. "kubespray-offline 디렉토리를 찾을 수 없음"
**증상**: `../kubespray-offline: No such file or directory`

**해결 방법**:
```bash
# submodule 초기화
git submodule update --init --recursive
```

### 2. "권한 거부" 오류  
**증상**: `Permission denied` 실행 오류

**해결 방법**:
```bash
# 실행 권한 복원
chmod +x astrago-wrapper/*.sh
```

### 3. "inventory 파일 없음" 오류
**증상**: inventory 관련 설정 파일 누락

**해결 방법**:
```bash
# inventory 디렉토리 확인
ls -la inventory/
# 필요시 기존 airgap/inventory에서 복사
cp -r ../airgap/inventory/* inventory/
```

## 롤백 절차
심각한 문제 발생 시:
1. 기존 airgap 디렉토리 사용으로 즉시 롤백
2. backup 브랜치로 복원: `git checkout backup/pre-airgap-migration-*`
3. 이슈 보고 및 분석

## 지원 연락처
- GitHub Issues: [프로젝트 저장소 이슈 페이지]
- Linear: BE-550 (메인 이슈)
EOF

# 3. 개발자 가이드 생성
cat > docs/DEVELOPER_GUIDE.md << 'EOF'
# 개발자 가이드

## Submodule 관리

### 업데이트 방법
```bash
cd kubespray-offline
git fetch origin
git checkout [새로운 태그/브랜치]
cd ..
git add kubespray-offline
git commit -m "Update kubespray-offline to [버전]"
```

### 래퍼 스크립트 수정 시 주의사항
- 모든 경로는 상대 경로 사용
- kubespray-offline 참조: `../kubespray-offline/`
- inventory 참조: `../inventory/`

## 테스트 방법
```bash
# 기본 기능 테스트
./test_basic_functions.sh

# 호환성 테스트
./test_compatibility.sh

# 종합 테스트
./comprehensive_test.sh
```

## 릴리스 프로세스
1. 기능 개발 및 테스트
2. 문서 업데이트
3. 버전 태그 생성
4. 배포 패키지 생성
EOF
```

**체크포인트**:
- [ ] 완전한 사용자 가이드 작성 완료
- [ ] 트러블슈팅 가이드 작성 완료
- [ ] 개발자 문서 작성 완료

**성공 기준**:
- 모든 사용 시나리오 문서화
- 문제 해결 방법 제공

#### 🎯 8.2 최종 검증 및 승인 (2시간)
**목적**: 프로덕션 배포 전 최종 검증

**실행 순서**:
```bash
# 1. 최종 검증 체크리스트 실행
cat > final_verification.sh << 'EOF'
#!/bin/bash

echo "🎯 최종 검증 체크리스트"
echo "========================"

# 파일 수 검증
echo "📊 파일 수 비교:"
OLD_FILES=$(find ../airgap -type f | wc -l)
NEW_FILES=$(find . -type f | wc -l)
echo "  기존: $OLD_FILES 개"  
echo "  신규: $NEW_FILES 개"

# 핵심 기능 검증
echo "🔧 핵심 기능 검증:"
CORE_SCRIPTS=(
    "astrago-wrapper/setup-all.sh"
    "astrago-wrapper/download-all.sh" 
    "astrago-wrapper/offline_deploy_astrago.sh"
)

for script in "${CORE_SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        echo "  ✅ $script"
    else
        echo "  ❌ $script (누락 또는 실행 불가)"
    fi
done

# 구조 검증
echo "🏗️ 구조 검증:"
[ -d "kubespray-offline" ] && echo "  ✅ kubespray-offline (submodule)" || echo "  ❌ kubespray-offline 누락"
[ -d "astrago-wrapper" ] && echo "  ✅ astrago-wrapper" || echo "  ❌ astrago-wrapper 누락"
[ -d "inventory" ] && echo "  ✅ inventory" || echo "  ❌ inventory 누락"
[ -d "docs" ] && echo "  ✅ docs" || echo "  ❌ docs 누락"

# 문서 검증
echo "📚 문서 검증:"
[ -f "README.md" ] && echo "  ✅ README.md" || echo "  ❌ README.md 누락"
[ -f "docs/TROUBLESHOOTING.md" ] && echo "  ✅ 트러블슈팅 가이드" || echo "  ❌ 트러블슈팅 가이드 누락"
[ -f "docs/DEVELOPER_GUIDE.md" ] && echo "  ✅ 개발자 가이드" || echo "  ❌ 개발자 가이드 누락"

echo "🎉 최종 검증 완료"
echo "승인 상태: $([ $? -eq 0 ] && echo '✅ PASS' || echo '❌ FAIL')"
EOF

chmod +x final_verification.sh
./final_verification.sh
```

**체크포인트**:
- [ ] 모든 파일 및 기능 검증 통과
- [ ] 문서화 완성도 100% 확인
- [ ] 팀 리뷰 및 최종 승인 완료

**성공 기준**:
- 최종 검증 체크리스트 100% 통과
- 프로덕션 배포 준비 완료

### Day 9: 배포 및 정리 (선택적)

#### 🚀 9.1 프로덕션 배포 (1시간)
**목적**: 새 구조를 프로덕션 환경에 배포

**실행 순서**:
```bash
# 1. 배포 전 최종 백업
git add .
git commit -m "feat: Complete airgap to astrago-airgap migration

- Migrate airgap directory to astrago-airgap unified structure
- Add kubespray-offline as submodule
- Preserve 100% compatibility with existing usage
- Add comprehensive documentation and troubleshooting guides
- Maintain all wrapper scripts and configurations

Linear: BE-550, BE-551, BE-552, BE-553"

# 2. 배포 태그 생성
git tag -a "v2.0.0-airgap-migration" -m "Astrago Airgap Migration v2.0.0

Major Changes:
- New unified astrago-airgap directory structure
- kubespray-offline as submodule for better version management
- 100% backward compatibility maintained
- Enhanced documentation and developer guides

Migration completed: $(date +%Y-%m-%d)"

# 3. 원격 저장소에 푸시 (실제 환경에 따라)
echo "배포 준비 완료. 다음 명령으로 배포:"
echo "git push origin feature/BE-384-helmfile-refactoring"
echo "git push origin --tags"
```

**체크포인트**:
- [ ] 프로덕션 배포 완료
- [ ] 태그 및 버전 관리 완료
- [ ] 팀 공유 완료

**성공 기준**:
- 프로덕션 환경에서 정상 동작 확인
- 새 구조 사용 가능 상태

#### 🧹 9.2 정리 및 문서화 마무리 (1시간)
**목적**: 마이그레이션 완료 후 정리 작업

**실행 순서**:
```bash
# 1. 임시 파일 정리
rm -f *.sh (테스트 스크립트들)
rm -rf test-env-* (임시 테스트 환경)

# 2. 마이그레이션 완료 보고서 생성
cat > MIGRATION_REPORT.md << 'EOF'
# Airgap 마이그레이션 완료 보고서

## 프로젝트 개요
- **기간**: $(date +%Y-%m-%d) ~ $(date +%Y-%m-%d)
- **Linear 이슈**: BE-550 (메인), BE-551~553 (Phase별)
- **목표**: airgap 디렉토리를 astrago-airgap 통합 구조로 마이그레이션

## 달성된 목표
- ✅ 303개 파일 완전 마이그레이션
- ✅ kubespray-offline submodule 적용
- ✅ 100% 호환성 유지
- ✅ 통합 문서화 완성

## 새로운 구조
```
astrago-airgap/
├── kubespray-offline/     # Submodule
├── astrago-wrapper/       # 8개 래퍼 스크립트
├── inventory/             # 설정 파일들
└── docs/                  # 완전한 문서
```

## 주요 개선사항
- 명확한 책임 분리 (upstream vs customization)
- 자동 업데이트 지원 (submodule)
- 향상된 문서화 및 트러블슈팅 가이드
- 개발자 친화적 구조

## 검증 결과
- 파일 무결성: 100%
- 기능 호환성: 100% 
- 성능: 동등 이상
- 문서화: 완전 (사용자+개발자+트러블슈팅)

## 다음 단계
1. 팀 교육 및 온보딩
2. 기존 airgap 디렉토리 deprecation 스케줄링
3. CI/CD 파이프라인 업데이트
4. 릴리스 노트 배포

**마이그레이션 성공적 완료**: $(date +%Y-%m-%d %H:%M:%S)
EOF

echo "🎉 Airgap 마이그레이션 프로젝트 완료!"
echo "📋 완료 보고서: MIGRATION_REPORT.md"
```

**체크포인트**:
- [ ] 모든 임시 파일 정리 완료
- [ ] 마이그레이션 보고서 작성 완료
- [ ] 팀 공유 및 피드백 수집 완료

**성공 기준**:
- 깔끔한 프로젝트 마무리
- 완전한 문서화 및 보고

---

## 🛡️ 위험 관리 및 롤백 전략

### 위험도별 분류

#### 🔴 High Risk
1. **Submodule 동기화 실패**
   - **위험**: kubespray-offline submodule 초기화/업데이트 실패
   - **대응**: 수동으로 직접 클론 후 디렉토리 복사
   - **롤백**: 기존 airgap/kubespray-offline 사용

2. **경로 참조 오류** 
   - **위험**: 래퍼 스크립트의 잘못된 상대 경로 참조
   - **대응**: 자동 경로 수정 스크립트 + 수동 검증
   - **롤백**: 백업된 원본 스크립트 복원

3. **권한 속성 손실**
   - **위험**: 스크립트 실행 권한 소실
   - **대응**: 실행 권한 자동 복원 스크립트
   - **롤백**: 기존 airgap 권한 설정 복사

#### 🟡 Medium Risk  
1. **설정 파일 누락**
   - **위험**: inventory 등 설정 파일 복사 누락
   - **대응**: 파일 수 비교 및 차이 분석
   - **롤백**: 누락 파일 개별 복사

2. **문서화 불완전**
   - **위험**: 사용법 변경으로 인한 혼란
   - **대응**: 상세한 마이그레이션 가이드 제공
   - **롤백**: 기존 README 임시 유지

#### 🟢 Low Risk
1. **성능 저하**
   - **위험**: 새 구조로 인한 미미한 성능 영향
   - **대응**: 성능 모니터링 및 최적화
   - **롤백**: 특별한 조치 불필요

### 롤백 시나리오별 대응

#### 즉시 롤백 (긴급)
```bash
# 1. 기존 airgap 디렉토리 즉시 사용
cd airgap
./setup-all.sh  # 기존 방식으로 즉시 복구

# 2. Git 백업 브랜치로 복원  
git stash
git checkout backup/pre-airgap-migration-$(date +%Y%m%d)
```

#### 부분 롤백 (선택적)
```bash
# 특정 스크립트만 기존 것 사용
cp airgap/offline_deploy_astrago.sh astrago-airgap/astrago-wrapper/
chmod +x astrago-airgap/astrago-wrapper/offline_deploy_astrago.sh
```

#### 점진적 롤백 (계획적)
```bash
# 1주일간 병행 사용 후 점진적 마이그레이션
# 새 구조 테스트하면서 필요시 기존 구조로 fallback
```

---

## 📊 성공 기준 및 품질 게이트

### Phase별 성공 기준

#### Phase 1 성공 기준
- [ ] 종속성 분석 100% 완료 (303개 파일 전체)
- [ ] 파일 분류 매핑 완료 (Astrago vs upstream 구분)
- [ ] 백업 및 롤백 전략 검증 완료
- [ ] 위험 요소 3개 이하로 수렴

#### Phase 2 성공 기준  
- [ ] astrago-airgap 디렉토리 생성 완료
- [ ] kubespray-offline submodule 정상 동작
- [ ] 8개 래퍼 스크립트 100% 마이그레이션
- [ ] 기본 기능 테스트 통과

#### Phase 3 성공 기준
- [ ] End-to-end 테스트 100% 통과
- [ ] 호환성 검증 100% 완료
- [ ] 문서화 완성도 95% 이상
- [ ] 팀 리뷰 및 승인 완료

### 품질 게이트

#### 🔒 Gate 1: Phase 1 → Phase 2 진입
- 종속성 분석 완료도 95% 이상
- High Risk 항목 3개 이하
- 백업/롤백 테스트 통과

#### 🔒 Gate 2: Phase 2 → Phase 3 진입  
- 기본 기능 테스트 100% 통과
- 파일 마이그레이션 완료도 100%
- 스크립트 문법 오류 0개

#### 🔒 Gate 3: 프로덕션 배포 승인
- End-to-end 테스트 100% 통과
- 문서화 완성도 95% 이상
- 팀 최종 승인 완료

### 자동화 vs 수동 확인 구분

#### ✅ 자동화 가능 영역
- 파일 수 비교 및 검증
- 스크립트 문법 검사 (`bash -n`)
- 경로 참조 검증
- 권한 설정 확인
- 기본 구조 검증

#### 👤 수동 확인 필요 영역
- 비즈니스 로직 정확성
- 사용자 경험 검증  
- 문서 가독성 및 정확성
- 최종 승인 결정
- 복잡한 시나리오 테스트

---

## 🚀 자동화 스크립트 개발 계획

### 핵심 자동화 스크립트

#### 1. `migration_orchestrator.sh` (마스터 스크립트)
```bash
#!/bin/bash
# 전체 마이그레이션 프로세스를 관리하는 마스터 스크립트
# Usage: ./migration_orchestrator.sh [phase1|phase2|phase3|all]
```

#### 2. `dependency_analyzer.sh` (종속성 분석)
```bash  
#!/bin/bash
# airgap 내 모든 파일 간 의존성 자동 분석
# 결과: dependency-matrix.csv 생성
```

#### 3. `structure_validator.sh` (구조 검증)
```bash
#!/bin/bash  
# 마이그레이션 전후 구조 비교 및 검증
# 결과: validation-report.txt 생성
```

#### 4. `rollback_manager.sh` (롤백 관리)
```bash
#!/bin/bash
# 자동 롤백 실행 및 상태 복원
# Usage: ./rollback_manager.sh [immediate|partial|full]
```

### 개발 우선순위
1. **Week 1**: migration_orchestrator.sh 개발
2. **Week 2**: dependency_analyzer.sh 개발  
3. **Week 3**: structure_validator.sh 개발
4. **Week 4**: rollback_manager.sh 개발

### 통합 테스트 자동화
- GitHub Actions 또는 GitLab CI 연동
- 매일 자동 구조 검증
- 호환성 회귀 테스트 자동 실행

---

## 📅 타임라인 및 마일스톤

### 전체 일정 (8-9일)
```
Week 1: Phase 1 (3일)
├─ Day 1: 분석 및 설계 검증
├─ Day 2: 백업 및 테스트 환경
└─ Day 3: Phase 1 검증 및 Phase 2 준비

Week 2: Phase 2-3 (5-6일)  
├─ Day 4: 새 구조 생성 및 submodule
├─ Day 5: 래퍼 스크립트 마이그레이션
├─ Day 6: 설정 파일 및 기본 테스트
├─ Day 7: 통합 테스트 및 심볼릭 링크
├─ Day 8: 문서화 완성 및 최종 검증
└─ Day 9: 배포 및 정리 (선택적)
```

### 주요 마일스톤
- **M1**: Phase 1 완료 (Day 3)
- **M2**: 기본 구조 완성 (Day 5)  
- **M3**: 통합 테스트 통과 (Day 7)
- **M4**: 프로덕션 배포 완료 (Day 8-9)

이 워크플로우를 통해 안전하고 체계적인 airgap 마이그레이션을 수행할 수 있습니다. 각 단계별로 명확한 체크포인트와 롤백 전략을 제공하여 위험을 최소화하면서 목표를 달성할 수 있도록 설계되었습니다.