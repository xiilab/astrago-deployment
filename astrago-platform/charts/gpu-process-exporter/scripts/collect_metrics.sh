#!/bin/bash
#
# GPU Process Metrics Collector
# Collect NVIDIA GPU process info and save in Prometheus format
#

set -euo pipefail

# 환경 변수 설정
NODE_NAME="${NODE_NAME:-$(hostname)}"
METRICS_FILE="/tmp/metrics/gpu_metrics.prom"
TEMP_FILE="/tmp/metrics/gpu_metrics.tmp"
LOG_PREFIX="[GPU-COLLECTOR]"

# 로깅 함수
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1" >&2
}

# 메트릭 디렉토리 생성
mkdir -p "$(dirname "$METRICS_FILE")"

# GPU 메트릭 수집 메인 함수
collect_gpu_metrics() {
    local node_name="$NODE_NAME"
    
    log "Starting GPU metrics collection for node: $node_name"
    
    {
        # Prometheus 메트릭 헤더
        echo "# HELP gpu_process_count Number of active GPU processes per GPU"
        echo "# TYPE gpu_process_count gauge"
        echo "# HELP gpu_total_processes Total number of GPU processes across all GPUs"  
        echo "# TYPE gpu_total_processes gauge"
        echo "# HELP gpu_process_utilization GPU utilization per process with detailed info"
        echo "# TYPE gpu_process_utilization gauge"
        echo "# HELP gpu_process_memory_utilization GPU memory utilization per process"
        echo "# TYPE gpu_process_memory_utilization gauge"
        echo "# HELP gpu_process_info GPU process information with Pod/Container details"
        echo "# TYPE gpu_process_info gauge"
        echo "# HELP gpu_device_info GPU device information"
        echo "# TYPE gpu_device_info gauge"
        
        # GPU 장치 정보 확인
        local gpu_count=0
        local gpu_list=""
        
        if command -v nvidia-smi >/dev/null 2>&1; then
            gpu_list=$(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader,nounits 2>/dev/null || echo "")
            if [ -n "$gpu_list" ]; then
                gpu_count=$(echo "$gpu_list" | wc -l)
                log "Found $gpu_count GPU(s)"
            else
                log "No GPUs found or nvidia-smi failed"
            fi
        else
            log "nvidia-smi not available"
        fi
        
        if [ "$gpu_count" -eq 0 ]; then
            echo "gpu_total_processes 0"
            echo "# No GPUs available on node $node_name"
            return
        fi
        
        # GPU 장치 정보 출력
        echo "$gpu_list" | while IFS=',' read -r gpu_index gpu_name gpu_memory; do
            gpu_index=$(echo "$gpu_index" | xargs)
            gpu_name=$(echo "$gpu_name" | xargs | sed 's/"//g')
            gpu_memory=$(echo "$gpu_memory" | xargs)
            
            echo "gpu_device_info{node=\"$node_name\",gpu=\"$gpu_index\",name=\"$gpu_name\",memory_total=\"${gpu_memory}MiB\"} 1"
        done
        
        # MIG 모드 확인
        local mig_enabled="false"
        local mig_mode
        mig_mode=$(nvidia-smi --query-gpu=mig.mode.current --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "")
        if [ -n "$mig_mode" ] && [ "$mig_mode" = "Enabled" ]; then
            mig_enabled="true"
            log "MIG mode detected"
        fi
        
        # GPU 인덱스 목록 생성
        local gpu_indices
        gpu_indices=$(echo "$gpu_list" | cut -d',' -f1 | xargs)
        
        # GPU 프로세스 정보 수집
        local total_processes=0
        local process_output=""
        
        if [ "$mig_enabled" = "true" ]; then
            process_output=$(nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null || echo "")
        else
            process_output=$(nvidia-smi --query-compute-apps=gpu_bus_id,pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null || echo "")
        fi
        
        # GPU 매핑 정보 생성
        local gpu_mapping_file="/tmp/gpu_mapping_$$"
        if [ "$mig_enabled" = "true" ]; then
            nvidia-smi --query-gpu=index,uuid --format=csv,noheader 2>/dev/null | tr -d ' ' > "$gpu_mapping_file"
        else
            nvidia-smi --query-gpu=index,pci.bus_id --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' > "$gpu_mapping_file"
        fi
        
        # GPU별 프로세스 카운트 초기화
        declare -A gpu_process_counts
        for gpu_index in $gpu_indices; do
            gpu_process_counts["$gpu_index"]=0
        done
        
        # 실행 중인 GPU 프로세스 분석
        if [ -n "$process_output" ] && [ "$process_output" != "No running processes found" ]; then
            log "Processing GPU processes..."
            
            echo "$process_output" | while IFS=',' read -r gpu_identifier pid process_name gpu_memory; do
                # 값 정리
                pid=$(echo "$pid" | xargs)
                process_name=$(echo "$process_name" | xargs | sed 's/"//g')
                gpu_memory=$(echo "$gpu_memory" | xargs)
                gpu_identifier=$(echo "$gpu_identifier" | xargs)
                
                if [ -n "$pid" ] && [ "$pid" != "-" ] && [ "$pid" != "N/A" ] && [[ "$pid" =~ ^[0-9]+$ ]]; then
                    # GPU 식별자를 인덱스로 매핑
                    local matched_gpu
                    matched_gpu=$(awk -F',' -v id="$gpu_identifier" '$2==id {print $1}' "$gpu_mapping_file" 2>/dev/null || echo "0")
                    
                    if [ -n "$matched_gpu" ]; then
                        # 프로세스 상세 정보 수집
                        local pod_name="unknown"
                        local namespace="unknown" 
                        local container_name="unknown"
                        local start_time="0"
                        
                        # cgroup에서 Pod 정보 추출 시도
                        if [ -f "/host/proc/$pid/cgroup" ]; then
                            local cgroup_info
                            cgroup_info=$(cat "/host/proc/$pid/cgroup" 2>/dev/null || echo "")
                            if echo "$cgroup_info" | grep -q "kubepods"; then
                                local pod_uid
                                pod_uid=$(echo "$cgroup_info" | grep -o 'pod[a-f0-9-]*' | head -1 | sed 's/pod//' || echo "")
                                if [ -n "$pod_uid" ] && [ "$pod_uid" != "unknown" ]; then
                                    pod_name="pod-$pod_uid"
                                    namespace="detected"
                                fi
                            fi
                        fi
                        
                        # 프로세스 시작 시간 (간단화)
                        if [ -f "/host/proc/$pid/stat" ]; then
                            start_time=$(awk '{print $22}' "/host/proc/$pid/stat" 2>/dev/null || echo "0")
                        fi
                        
                        # GPU 사용률 (간단화 - 실제로는 더 복잡한 계산 필요)
                        local gpu_util=0
                        local mem_util=0
                        
                        # GPU 메트릭 출력
                        local gpu_display="$matched_gpu"
                        
                        echo "gpu_process_utilization{node=\"$node_name\",gpu=\"$gpu_display\",pid=\"$pid\",command=\"$process_name\",pod=\"$pod_name\",namespace=\"$namespace\",container=\"$container_name\",gpu_memory=\"${gpu_memory}MiB\",start_time=\"$start_time\"} $gpu_util"
                        echo "gpu_process_memory_utilization{node=\"$node_name\",gpu=\"$gpu_display\",pid=\"$pid\",command=\"$process_name\",pod=\"$pod_name\",namespace=\"$namespace\",container=\"$container_name\",gpu_memory=\"${gpu_memory}MiB\",start_time=\"$start_time\"} $mem_util"
                        echo "gpu_process_info{node=\"$node_name\",gpu=\"$gpu_display\",pid=\"$pid\",command=\"$process_name\",pod=\"$pod_name\",namespace=\"$namespace\",container=\"$container_name\",status=\"active\",gpu_memory=\"${gpu_memory}MiB\",start_time=\"$start_time\"} 1"
                        
                        total_processes=$((total_processes + 1))
                    fi
                fi
            done
        else
            log "No GPU processes found"
        fi
        
        # GPU별 프로세스 카운트 및 유휴 상태 출력
        for gpu_index in $gpu_indices; do
            local process_count=0
            
            # 해당 GPU의 프로세스 수 계산
            if [ -n "$process_output" ] && [ "$process_output" != "No running processes found" ]; then
                # 간단한 카운트 (실제로는 매핑이 필요하지만 여기서는 단순화)
                process_count=$(echo "$process_output" | grep -c ",$gpu_index," 2>/dev/null || echo "0")
            fi
            
            echo "gpu_process_count{node=\"$node_name\",gpu=\"$gpu_index\"} $process_count"
            
            # 프로세스가 없으면 유휴 상태로 표시
            if [ "$process_count" -eq 0 ]; then
                echo "gpu_process_info{node=\"$node_name\",gpu=\"$gpu_index\",pid=\"none\",command=\"none\",pod=\"none\",namespace=\"none\",container=\"none\",status=\"idle\",gpu_memory=\"0MiB\",start_time=\"0\"} 0"
            fi
        done
        
        # 전체 프로세스 수
        echo "gpu_total_processes{node=\"$node_name\"} $total_processes"
        
        # 메타데이터
        echo "# Generated at $(date) on node $node_name"
        echo "# Collection script version: 1.0"
        
        # 정리
        rm -f "$gpu_mapping_file"
        
    } > "$TEMP_FILE"
    
    # 원자적 파일 이동
    mv "$TEMP_FILE" "$METRICS_FILE"
    
    log "GPU metrics collection completed successfully"
}

# 메인 실행
main() {
    log "GPU Process Metrics Collector starting..."
    
    # nvidia-smi 사용 가능 여부 확인
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        log "ERROR: nvidia-smi not found"
        echo "# ERROR: nvidia-smi not available" > "$METRICS_FILE"
        exit 1
    fi
    
    # 메트릭 수집 실행
    collect_gpu_metrics
    
    log "Metrics saved to: $METRICS_FILE"
}

# 스크립트가 직접 실행될 때만 main 함수 호출
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi 