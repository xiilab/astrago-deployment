# Astrago Airgap Makefile
# 표준 명령어 인터페이스

.PHONY: help download package deploy clean test

# Load configuration
include airgap.conf

help: ## 사용 가능한 명령어 목록 표시
	@echo "Astrago Airgap 배포 도구"
	@echo "========================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

download: ## 모든 이미지 및 패키지 다운로드
	@echo "🔽 Downloading all images and packages..."
	@$(KUBESPRAY_PATH)/download-all.sh
	@$(ASTRAGO_SCRIPTS_PATH)/extract_astrago_images.sh
	@echo "✅ Download completed"

package: ## 배포 패키지 생성
	@echo "📦 Creating deployment package..."
	@mkdir -p $(PACKAGE_OUTPUT_DIR)
	@$(ASTRAGO_SCRIPTS_PATH)/create_astrago_only_package.sh
	@echo "✅ Package created in $(PACKAGE_OUTPUT_DIR)"

package-full: ## 전체 배포 패키지 생성 (Kubernetes 포함)
	@echo "📦 Creating full deployment package..."
	@mkdir -p $(PACKAGE_OUTPUT_DIR)
	@$(ASTRAGO_SCRIPTS_PATH)/create_delivery_package.sh
	@echo "✅ Full package created in $(PACKAGE_OUTPUT_DIR)"

deploy: ## Astrago 오프라인 배포
	@echo "🚀 Deploying Astrago..."
	@$(ASTRAGO_SCRIPTS_PATH)/offline_deploy_astrago.sh
	@echo "✅ Deployment completed"

clean: ## 임시 파일 및 캐시 정리
	@echo "🧹 Cleaning up..."
	@rm -rf $(PACKAGE_OUTPUT_DIR)/temp
	@rm -rf ./tmp
	@echo "✅ Cleanup completed"

sync-images: ## helmfile에서 모든 이미지 동기화
	@echo "🔄 Syncing all images from helmfile..."
	@$(ASTRAGO_SCRIPTS_PATH)/sync_all_images.sh
	@echo "✅ Image synchronization completed"

test: ## 기본 기능 테스트
	@echo "🧪 Running tests..."
	@./bin/test-compatibility.sh
	@echo "✅ Tests completed"

status: ## 현재 상태 확인
	@echo "📊 Astrago Airgap Status:"
	@echo "========================="
	@echo "Kubespray-offline: $(shell cd $(KUBESPRAY_PATH) && git describe --tags --always)"
	@echo "Configuration: $(shell test -f airgap.conf && echo "✅ OK" || echo "❌ Missing")"
	@echo "Astrago scripts: $(shell test -d $(ASTRAGO_SCRIPTS_PATH) && echo "✅ OK" || echo "❌ Missing")"
	@echo "Image lists: $(shell ls $(ASTRAGO_IMAGELISTS_PATH)/*.txt 2>/dev/null | wc -l | xargs) files"

# 개발용 명령어
dev-setup: ## 개발 환경 설정
	@echo "🔧 Setting up development environment..."
	@git submodule update --init --recursive
	@echo "✅ Development environment ready"

dev-reset: ## 개발 환경 리셋
	@echo "🔄 Resetting development environment..."
	@git submodule update --init --recursive
	@git clean -fd
	@echo "✅ Environment reset"