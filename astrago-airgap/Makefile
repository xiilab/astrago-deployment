# Astrago Airgap Makefile - 간소화된 인터페이스
# kubespray-offline + Astrago 오버레이 방식

.PHONY: help prepare download package deploy clean update-kubespray status

OVERLAY_SCRIPTS = ./astrago-overlay/scripts

help: ## 사용 가능한 명령어 목록 표시
	@echo "Astrago Airgap 배포 도구 (kubespray-offline 기반)"
	@echo "================================================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

prepare: ## 1단계: 환경 준비 및 검증
	@$(OVERLAY_SCRIPTS)/1-prepare.sh

download: ## 2단계: 모든 이미지 및 패키지 다운로드
	@$(OVERLAY_SCRIPTS)/2-download.sh

package: ## 3단계: 오프라인 배포 패키지 생성
	@$(OVERLAY_SCRIPTS)/3-package.sh

deploy: ## 4단계: 오프라인 환경에서 배포 (타겟 환경)
	@$(OVERLAY_SCRIPTS)/4-deploy.sh

# 통합 명령
build: prepare download package ## 전체 빌드 (1-3단계 통합)
	@echo "🎉 오프라인 패키지 빌드 완료!"

# 유지보수 명령
update-kubespray: ## kubespray-offline 최신 버전으로 업데이트
	@./update-kubespray.sh

update-kubespray-tag: ## 특정 태그로 kubespray-offline 업데이트 (예: make update-kubespray-tag TAG=v1.2.3)
	@./update-kubespray.sh $(TAG)

clean: ## 임시 파일 및 빌드 캐시 정리
	@echo "🧹 정리 중..."
	@rm -rf ./outputs/temp
	@rm -rf ./temp
	@rm -rf ./astrago-overlay/images/imagelists/*.txt
	@echo "✅ 정리 완료"

status: ## 현재 환경 상태 확인
	@echo "📊 Astrago Airgap 상태 확인:"
	@echo "===================================="
	@echo "kubespray-offline: $(shell cd kubespray-offline 2>/dev/null && git describe --tags --always 2>/dev/null || echo '❌ 없음')"
	@echo "Astrago 오버레이: $(shell test -d astrago-overlay && echo '✅ 준비됨' || echo '❌ 없음')"
	@echo "Helmfile 경로: $(shell test -d ../helmfile && echo '✅ 존재' || echo '❌ 없음')"
	@echo "빌드 스크립트: $(shell test -x astrago-overlay/scripts/1-prepare.sh && echo '✅ 준비됨' || echo '❌ 없음')"

# 개발 및 테스트 명령
test: ## 호환성 및 기능 테스트
	@echo "🧪 호환성 테스트 실행 중..."
	@echo "kubespray-offline 상태 확인..."
	@test -d kubespray-offline || (echo "❌ kubespray-offline 없음" && exit 1)
	@test -f kubespray-offline/download-all.sh || (echo "❌ download-all.sh 없음" && exit 1)
	@echo "Astrago 오버레이 상태 확인..."
	@test -d astrago-overlay/scripts || (echo "❌ 오버레이 스크립트 없음" && exit 1)
	@test -f astrago-overlay/configs/astrago.conf || (echo "❌ 설정 파일 없음" && exit 1)
	@echo "✅ 모든 테스트 통과!"

init-submodule: ## Git submodule 초기화 (처음 설정 시)
	@echo "🔧 Git submodule 초기화..."
	@echo "⚠️  현재 kubespray-offline을 백업하고 submodule로 전환합니다."
	@read -p "계속하시겠습니까? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@mv kubespray-offline kubespray-offline.backup
	@git submodule add https://github.com/kubespray-offline/kubespray-offline.git kubespray-offline
	@git submodule update --init --recursive
	@echo "✅ Submodule 초기화 완료!"