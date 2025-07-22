# Build stage: Compile Go binary
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY scripts/http_server.go .

# Compile static binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o http_server http_server.go

# Runtime stage: NVIDIA CUDA base with compiled binary
FROM nvidia/cuda:12.2.2-runtime-ubuntu22.04

# 환경 변수 설정
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=utility

# 필요한 패키지 설치 (Go 바이너리는 Python 불필요)
RUN apt-get update && apt-get install -y \
    # System utilities
    curl \
    procps \
    # Cleanup
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# 작업 디렉토리 설정
WORKDIR /app

# 컴파일된 Go 바이너리 복사
COPY --from=builder /app/http_server /usr/local/bin/http_server

# GPU 메트릭 수집 스크립트 복사
COPY scripts/collect_metrics.sh /usr/local/bin/collect_metrics.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

# 실행 권한 부여
RUN chmod +x /usr/local/bin/collect_metrics.sh \
    && chmod +x /usr/local/bin/http_server \
    && chmod +x /usr/local/bin/entrypoint.sh

# 메트릭 디렉토리 생성
RUN mkdir -p /tmp/metrics

# Cron 설정은 사용하지 않음 (백그라운드 루프 사용)

# 포트 노출
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 엔트리포인트 설정
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"] 