#!/usr/bin/env python3
"""
GPU Process Exporter HTTP Server
파일 기반 GPU 메트릭을 HTTP API로 제공
"""

import http.server
import socketserver
import os
import logging
import signal
import sys
from urllib.parse import urlparse

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    """GPU 메트릭을 서빙하는 HTTP 핸들러"""
    
    def __init__(self, *args, **kwargs):
        self.metrics_file = '/tmp/metrics/gpu_metrics.prom'
        super().__init__(*args, **kwargs)
    
    def log_message(self, format, *args):
        """로그 메시지를 logger로 전달"""
        logger.info(f"{self.address_string()} - {format % args}")
    
    def do_GET(self):
        """GET 요청 처리"""
        try:
            parsed_path = urlparse(self.path)
            path = parsed_path.path
            
            if path == '/metrics':
                self.handle_metrics()
            elif path == '/health':
                self.handle_health()
            elif path == '/':
                self.handle_metrics()  # 기본 경로는 메트릭으로
            else:
                self.send_error(404, "Not Found")
                
        except Exception as e:
            logger.error(f"Error handling request {self.path}: {e}")
            self.send_error(500, "Internal Server Error")
    
    def handle_metrics(self):
        """GPU 메트릭 파일을 읽어서 응답"""
        try:
            if not os.path.exists(self.metrics_file):
                logger.warning(f"Metrics file not found: {self.metrics_file}")
                content = "# Metrics file not ready yet\n"
            else:
                with open(self.metrics_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                if not content.strip():
                    content = "# Empty metrics file\n"
            
            # Prometheus 형식으로 응답
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
            self.send_header('Content-Length', str(len(content.encode('utf-8'))))
            self.send_header('Connection', 'close')
            self.end_headers()
            
            self.wfile.write(content.encode('utf-8'))
            logger.info("Metrics served successfully")
            
        except Exception as e:
            logger.error(f"Error serving metrics: {e}")
            error_content = f"# Error reading metrics: {e}\n"
            self.send_response(500)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(error_content.encode('utf-8'))))
            self.end_headers()
            self.wfile.write(error_content.encode('utf-8'))
    
    def handle_health(self):
        """헬스체크 엔드포인트"""
        try:
            # 메트릭 파일이 최근 2분 내에 업데이트되었는지 확인
            if os.path.exists(self.metrics_file):
                file_age = os.path.getmtime(self.metrics_file)
                import time
                if time.time() - file_age < 120:  # 2분 = 120초
                    status = "OK"
                    code = 200
                else:
                    status = "STALE - metrics file too old"
                    code = 503
            else:
                status = "ERROR - metrics file not found"
                code = 503
            
            self.send_response(code)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(status.encode('utf-8'))))
            self.send_header('Connection', 'close')
            self.end_headers()
            
            self.wfile.write(status.encode('utf-8'))
            logger.info(f"Health check: {status} (code: {code})")
            
        except Exception as e:
            logger.error(f"Error in health check: {e}")
            error_msg = f"ERROR: {e}"
            self.send_response(500)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(error_msg.encode('utf-8'))))
            self.end_headers()
            self.wfile.write(error_msg.encode('utf-8'))

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    """멀티스레드 TCP 서버"""
    allow_reuse_address = True
    daemon_threads = True

def signal_handler(signum, frame):
    """종료 시그널 핸들러"""
    logger.info(f"Received signal {signum}, shutting down gracefully...")
    sys.exit(0)

def main():
    """메인 함수"""
    PORT = int(os.environ.get('METRICS_PORT', 8080))
    
    # 시그널 핸들러 등록
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        # HTTP 서버 시작
        with ThreadedTCPServer(("", PORT), MetricsHandler) as httpd:
            logger.info(f"GPU Process Exporter HTTP Server starting on port {PORT}")
            logger.info(f"Metrics endpoint: http://0.0.0.0:{PORT}/metrics")
            logger.info(f"Health endpoint: http://0.0.0.0:{PORT}/health")
            
            # 메트릭 디렉토리 확인
            metrics_dir = os.path.dirname('/tmp/metrics/gpu_metrics.prom')
            if not os.path.exists(metrics_dir):
                os.makedirs(metrics_dir)
                logger.info(f"Created metrics directory: {metrics_dir}")
            
            httpd.serve_forever()
            
    except Exception as e:
        logger.error(f"Failed to start HTTP server: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 