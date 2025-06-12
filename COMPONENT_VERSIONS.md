# Astrago Deployment GitLab - 구성요소 버전 분석 문서

## 📋 **프로젝트 개요**

이 문서는 `astrago-deployment-gitlab` 프로젝트의 모든 구성요소와 버전 정보를 체계적으로 정리한 종합 분석 문서입니다.

### **프로젝트 구조**

```
astrago-deployment-gitlab/
├── kubespray/           # Kubernetes 클러스터 설치
├── applications/        # 애플리케이션 차트들  
├── environments/        # 환경별 설정
├── ansible/            # Ansible 역할들
├── airgap/             # 오프라인 설치 지원
└── tools/              # 설치 도구들
```

---

## 🚀 **1. 인프라 구성요소**

### **1.1 Kubernetes (Kubespray)**

- **설치 방식**: Kubespray (Ansible 기반)
- **Kubernetes 버전**: `v1.28.6`
- **네트워크 플러그인**: Calico
- **프록시 모드**: IPVS
- **DNS**: CoreDNS + NodeLocalDNS
- **설정 파일**: `kubespray/inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`

#### **주요 설정값**

```yaml
kube_version: v1.28.6
kube_network_plugin: calico
kube_proxy_mode: ipvs
dns_mode: coredns
enable_nodelocaldns: true
```

### **1.2 GPU 지원**

#### **GPU Operator**

- **현재 버전**: `v24.9.2`
- **Kubernetes 지원 범위**: `>= 1.26.0`
- **DCGM Exporter**: `3.3.8-3.6.0-ubuntu22.04`
- **설정 파일**: `applications/gpu-operator/`

#### **NVIDIA Driver**

- **Branch**: `535` (535.129.03)
- **설치 방식**: Ansible Role (`nvidia.nvidia_driver`)
- **Ubuntu 패키지**: `nvidia-headless-535-server`
- **설정 파일**: `ansible/roles/nvidia.nvidia_driver/defaults/main.yml`

#### **GPU Operator 컴포넌트 버전**

```yaml
dcgmExporter: 3.3.8-3.6.0-ubuntu22.04
toolkit: v1.17.0-ubuntu20.04
devicePlugin: v0.17.0-ubi8
gfd: v0.17.0-ubi8
migManager: v0.10.0-ubuntu20.04
```

#### **GPU 세션 모니터링 (신규)**

- **차트 버전**: `0.1.0`
- **수집기 이미지**: `nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.1-ubuntu22.04`
- **수집 주기**: `*/1 * * * *` (1분마다)
- **지원 기능**:
  - ✅ nvidia-smi PID 정확 매핑
  - ✅ MIG (Multi-Instance GPU) 지원
  - ✅ 동적 GPU 감지
  - ✅ Pod 정보 자동 연결
  - ✅ Prometheus 메트릭 연동

---

## 📱 **2. 애플리케이션 구성요소**

### **2.1 Astrago 플랫폼**

- **차트 버전**: `0.1.0`
- **애플리케이션 버전**: `1.16.0`

#### **Astrago 컴포넌트 버전**

```yaml
core: "core-v1.0.79"
batch: "batch-v1.0.79" 
monitor: "monitor-v1.0.79"
frontend: "frontend-v1.0.50"
```

#### **MariaDB (내장)**

- **차트 버전**: `12.2.9`
- **설정**: `applications/astrago/astrago/charts/mariadb/`

### **2.2 인증 및 보안**

#### **Keycloak**

- **차트 버전**: `17.3.5`
- **애플리케이션 버전**: `22.0.5`
- **테마 버전**: `v1.1.5`
- **PostgreSQL**: `13.x.x` (dependency)

### **2.3 모니터링**

#### **Prometheus Stack**

- **차트 버전**: `55.4.0`
- **애플리케이션 버전**: `v0.70.0`
- **Kubernetes 지원**: `>=1.19.0-0`

#### **구성 요소**

```yaml
kube-state-metrics: 5.15.*
prometheus-node-exporter: 4.24.*
grafana: 7.0.*
prometheus-windows-exporter: 0.1.*
```

### **2.4 컨테이너 레지스트리**

#### **Harbor**

- **차트 버전**: `1.15.1`
- **애플리케이션 버전**: `2.11.1`
- **서비스 포트**: `30002`

### **2.5 MPI 작업 지원**

#### **MPI Operator**

- **차트 버전**: `0.1.0`
- **애플리케이션 버전**: `1.16.0`

### **2.6 스토리지**

#### **CSI Driver NFS**

- **차트 버전**: `v4.7.0`
- **애플리케이션 버전**: `v4.7.0`

### **2.7 GitOps**

#### **Flux2**

- **차트 버전**: `2.13.0`
- **애플리케이션 버전**: `2.3.0`

### **2.8 GPU 리소스 모니터링**

#### **GPU 세션 모니터링**

- **차트 버전**: `0.1.0`
- **수집기 이미지**: `nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.1-ubuntu22.04`
- **수집 방식**: CronJob (Node Exporter textfile collector)
- **주요 메트릭**:

```yaml
# GPU 세션 관련
gpu_session_count                     # GPU별 활성 세션 수
gpu_total_sessions                    # 전체 GPU 세션 수

# 프로세스 상세 정보
gpu_process_info                      # PID, 명령어, Pod 정보
gpu_process_utilization               # 프로세스별 GPU 사용률
gpu_process_memory_utilization        # 프로세스별 메모리 사용률
```

---

## 🔧 **3. 환경별 설정**

### **3.1 환경 종류**

```yaml
environments:
  - prod     # 프로덕션
  - dev      # 개발
  - dev2     # 개발2  
  - stage    # 스테이징
  - astrago  # Astrago 전용
```

### **3.2 주요 설정값 (Production)**

```yaml
# 서비스 포트
keycloak.servicePort: 30001
astrago.servicePort: 30080
harbor.servicePort: 30002

# 기본 패스워드
keycloak.adminPassword: xiirocks
astrago.userInitPassword: astrago
harbor.adminPassword: Harbor12345
```

---

## 📦 **4. 설치 도구**

### **4.1 GUI 설치 도구**

- **파일**: `astrago_gui_installer.py`
- **기능**:
  - 노드 관리
  - Kubernetes 설치/리셋
  - GPU 드라이버 설치
  - NFS 서버 설정
  - Astrago 설치/제거

### **4.2 스크립트 도구**

```bash
deploy_astrago.sh           # 온라인 배포
offline_deploy_astrago.sh   # 오프라인 배포  
run_gui_installer.sh        # GUI 설치 도구 실행
```

---

## 🌐 **5. 오프라인 지원**

### **5.1 Airgap 구성**

- **경로**: `airgap/`
- **기능**: 완전 오프라인 환경 지원
- **포함 요소**:
  - Kubespray Offline
  - 컨테이너 이미지 목록
  - 패키지 목록 (Ubuntu/RHEL)

### **5.2 Offline Registry 설정**

```yaml
offline:
  registry: ""          # 프라이빗 레지스트리 URL
  httpServer: ""        # HTTP 서버 URL
```

---

## 🔄 **6. 버전 호환성 매트릭스**

### **6.1 Kubernetes ↔ GPU Operator**

| Kubernetes | GPU Operator | 지원 상태 |
|------------|-------------|----------|
| 1.26.x     | v24.9.2     | ✅ 지원    |
| 1.27.x     | v24.9.2     | ✅ 지원    |
| 1.28.x     | v24.9.2     | ✅ 지원    |
| 1.29.x     | v24.9.2     | ✅ 지원    |
| 1.30.x     | v24.9.2     | ✅ 지원    |

### **6.2 GPU Operator ↔ NVIDIA Driver**

| GPU Operator | NVIDIA Driver | DCGM | 호환성 |
|-------------|---------------|------|-------|
| v24.9.2     | 535.129.03    | 3.3.8| ✅ 검증됨 |

---

## 📊 **7. 메트릭 지원**

### **7.1 GPU 메트릭 (DCGM 3.3.8 기준)**

#### **기본 메트릭**

- ✅ GPU 사용률
- ✅ 메모리 사용률  
- ✅ 온도
- ✅ 전력 소비
- ✅ Memory_Clock
- ✅ SM_Clock
- ✅ Framebuffer_Memory_Used

#### **고급 메트릭**

- ✅ Memory_Bandwidth_Utilization
- ✅ Memory_Interface_Utilization
- ✅ Tensor_Core_Utilization
- ✅ MIG 파티션 메트릭
- ✅ NVLink 메트릭

### **7.2 GPU 세션 모니터링 메트릭 (신규)**

#### **프로세스 추적 메트릭**

- ✅ `gpu_session_count` - GPU별 활성 세션 수
- ✅ `gpu_total_sessions` - 전체 GPU 세션 수  
- ✅ `gpu_process_info` - 프로세스 상세 정보 (PID, 명령어, Pod 정보)
- ✅ `gpu_process_utilization` - 프로세스별 GPU 사용률
- ✅ `gpu_process_memory_utilization` - 프로세스별 메모리 사용률

#### **특징**

- 🎯 **정확한 PID 매핑**: nvidia-smi와 Prometheus PID 완전 일치
- 🔧 **MIG 지원**: Multi-Instance GPU 환경 자동 감지
- 🏷️ **Pod 연결**: Kubernetes Pod와 GPU 프로세스 자동 매핑
- 🔄 **동적 감지**: GPU 개수 및 MIG 인스턴스 자동 인식

---

## 🛠 **8. 업그레이드 고려사항**

### **8.1 현재 안정 버전**

- **Kubernetes**: v1.28.6 (LTS)
- **GPU Operator**: v24.9.2 (안정)
- **NVIDIA Driver**: 535 Branch (LTS)

### **8.2 향후 업그레이드 후보**

- **Kubernetes**: v1.29.x → v1.30.x
- **GPU Operator**: v24.9.2 → v25.3.0 (Kubernetes 1.29+ 필요)
- **NVIDIA Driver**: 535 → 550 Branch

---

## 📝 **9. 설정 파일 위치**

### **9.1 주요 설정 파일**

```
kubespray/inventory/mycluster/group_vars/
├── all/all.yml                    # 전역 설정
└── k8s_cluster/k8s-cluster.yml   # Kubernetes 설정

applications/
├── gpu-operator/values.yaml.gotmpl    # GPU Operator 설정
├── astrago/helmfile.yaml              # Astrago 배포 설정
├── keycloak/helmfile.yaml             # Keycloak 배포 설정
└── prometheus/helmfile.yaml           # 모니터링 설정

environments/
├── common/values.yaml                 # 공통 설정
├── prod/values.yaml                   # 프로덕션 설정
└── dev/values.yaml                    # 개발 설정
```

---

## ⚠️ **10. 중요 참고사항**

### **10.1 버전 의존성**

1. **GPU Operator v25.3.0+**는 **Kubernetes 1.29+** 필수
2. **DCGM 4.x**는 **GPU Operator v24.6+**에서 지원
3. **최신 메트릭**은 **DCGM 3.3.8+**에서 안정적

### **10.2 업그레이드 권장사항**

1. **단계적 업그레이드**: Kubernetes → GPU Operator → Applications 순서
2. **테스트 환경 검증**: 프로덕션 적용 전 충분한 테스트
3. **백업**: 업그레이드 전 설정 및 데이터 백업 필수

---

## 📞 **11. 지원 및 문의**

이 문서는 `astrago-deployment` 프로젝트의 구성요소 분석을 위해 작성되었습니다.
업데이트가 필요한 경우 해당 구성요소의 설정 파일을 직접 수정하거나 GUI 설치 도구를 활용하세요.

**문서 작성일**: 2025년 1월 15일  
**프로젝트 버전**: Latest (분석 시점 기준)
