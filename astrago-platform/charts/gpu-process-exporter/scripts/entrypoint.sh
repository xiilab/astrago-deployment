#!/bin/bash
#
# GPU Process Exporter Entrypoint
# Start cron daemon and HTTP server in container
#

set -euo pipefail

# 환경 변수 설정
NODE_NAME="${NODE_NAME:-$(hostname)}"
METRICS_PORT="${METRICS_PORT:-8080}"
LOG_PREFIX="[ENTRYPOINT]"

# 로깅 함수
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

# 종료 시그널 핸들러
cleanup() {
    log "Received termination signal, shutting down gracefully..."
    
    # 백그라운드 메트릭 수집 종료
    if [ -n "${METRICS_PID:-}" ]; then
        log "Stopping background metrics collection (PID: $METRICS_PID)..."
        kill -TERM "$METRICS_PID" 2>/dev/null || true
        wait "$METRICS_PID" 2>/dev/null || true
    fi
    
    # HTTP 서버는 Python이 알아서 종료됨
    log "Shutdown completed"
    exit 0
}

# 시그널 핸들러 등록
trap cleanup SIGTERM SIGINT

# 메인 함수
main() {
    log "=== GPU Process Exporter Starting ==="
    log "Node: $NODE_NAME"
    log "Metrics Port: $METRICS_PORT"
    
    # 환경 확인
    log "Checking environment..."
    
    # nvidia-smi 확인
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        log "ERROR: nvidia-smi not found"
        exit 1
    fi
    
    # HTTP 서버 바이너리 확인
    if ! command -v /usr/local/bin/http_server >/dev/null 2>&1; then
        log "ERROR: http_server binary not found"
        exit 1
    fi
    
    # 모든 필수 도구 확인 완료
    
    log "Environment check passed"
    
    # 메트릭 디렉토리 생성
    mkdir -p /tmp/metrics
    log "Created metrics directory: /tmp/metrics"
    
    # GPU 정보 확인
    log "GPU Information:"
    nvidia-smi --query-gpu=index,name,memory.total --format=csv 2>/dev/null || {
        log "WARNING: Failed to query GPU information"
    }
    
    # 초기 메트릭 수집
    log "Performing initial metrics collection..."
    if /usr/local/bin/collect_metrics.sh; then
        log "Initial metrics collection successful"
    else
        log "WARNING: Initial metrics collection failed"
    fi
    
    # 백그라운드에서 메트릭 수집 루프 시작
    log "Starting background metrics collection loop..."
    (
        while true; do
            sleep 30
            /usr/local/bin/collect_metrics.sh 2>&1 | while read line; do
                echo "[METRICS-LOOP] $line"
            done
        done
    ) &
    METRICS_PID=$!
    log "Background metrics collection started (PID: $METRICS_PID)"
    
    # HTTP 서버 시작
    log "Starting Go HTTP server on port $METRICS_PORT..."
    export METRICS_PORT="$METRICS_PORT"
    export NODE_NAME="$NODE_NAME"
    
    # Go HTTP 서버 실행 (포어그라운드)
    exec /usr/local/bin/http_server
}

# 스크립트 실행
log "GPU Process Exporter Entrypoint v1.0"
main "$@" 