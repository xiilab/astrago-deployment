# Kubespray 기반 Kubernetes 설치 도구

사용자 친화적이고 자동화된 Kubernetes 설치 시스템입니다.

## 🎯 주요 특징

- **Non-Interactive 설치**: 설정 파일 기반의 자동화된 설치 프로세스
- **멀티 버전 지원**: RHEL8 cgroup v1 호환 + 최신 cgroup v2 환경 지원
- **CRI-O 기본 지원**: 컨테이너 런타임으로 CRI-O 사용
- **Pre-configured**: 사전 설정된 sample 기반의 빠른 구성
- **Clean Architecture**: 복잡한 대화형 프롬프트 제거로 단순화

## 📁 디렉토리 구조

```
kubespray/
├── versions/                    # Kubespray 버전들
│   ├── v2.24.3/kubespray/      # K8s 1.28.14용 (RHEL8 cgroup v1 호환)
│   └── v2.28.1/kubespray/      # K8s 1.32.8용 (cgroup v2 환경)
├── customers/                   # 고객별 설정
│   ├── sample/                 # 샘플 설정 템플릿
│   │   ├── hosts.yml          # 서버 인벤토리 템플릿
│   │   └── extra-vars.yml     # CRI-O 설정 템플릿
│   └── <고객명>/              # 고객별 복사본
│       ├── hosts.yml          # 실제 서버 정보
│       └── extra-vars.yml     # 고객 맞춤 설정
├── version-matrix.conf         # 버전 매핑 설정
├── update-kubespray.sh        # 버전 관리 도구
├── install.sh                 # 설치 스크립트
└── README.md                  # 이 문서
```

## 🚀 설치 방법

### 1단계: 필요한 Kubespray 버전 설치

```bash
# 모든 버전 자동 설치
./update-kubespray.sh install-all

# 개별 설치 (선택사항)
./update-kubespray.sh install v2.24.3  # RHEL8 cgroup v1용
./update-kubespray.sh install v2.28.1  # 최신 cgroup v2용
```

### 2단계: 고객 설정 준비

```bash
# 1. sample 폴더를 고객명으로 복사
cp -r customers/sample customers/my-customer

# 2. 서버 정보 설정
vi customers/my-customer/hosts.yml
# - 실제 서버 IP 주소 입력
# - SSH 사용자 및 키 파일 경로 설정
# - 노드 역할 구성 (master/worker)

# 3. 추가 설정 (필요시)
vi customers/my-customer/extra-vars.yml
# - CRI-O 이미지 저장 위치 변경
# - 추가 레지스트리 설정
# - 기타 고객 맞춤 설정
```

### 3단계: Kubernetes 설치

```bash
# 대화형 버전 선택으로 설치
./install.sh my-customer

# 또는 명시적 버전 지정
./install.sh my-customer --k8s-version 1.28.14    # RHEL8 호환
./install.sh my-customer --k8s-version 1.32.8     # 최신 버전

# 테스트 실행 (실제 설치 안함)
./install.sh my-customer --dry-run
```

## 📋 지원 버전 매트릭스

| Kubernetes | Kubespray | 용도 | 환경 요구사항 |
|------------|-----------|------|---------------|
| **1.28.14** | **v2.24.3** | RHEL8 cgroup v1 호환 | cgroup v1 환경 (레거시) |
| **1.32.8** | **v2.28.1** | 최신 버전 (권장) | cgroup v2 환경 (RHEL9+) |

> **참고**: Kubernetes 1.31부터 cgroup v1 지원은 유지보수 모드로 전환되었습니다.

## 🔧 CRI-O 설정

기본 CRI-O 설정 (`customers/sample/extra-vars.yml`):

```yaml
# 컨테이너 런타임 설정
container_manager: crio

# CRI-O 이미지 저장 위치
crio_storage_driver: overlay2
crio_root_dir: /var/lib/containers

# CRI-O 레지스트리 설정 (unqualified-search-registries)
crio_registries_conf: |
  unqualified-search-registries = ["docker.io"]
  
  [[registry]]
  prefix = "docker.io"
  location = "docker.io"
```

### 고객별 커스터마이징 예시

```yaml
# 사설 레지스트리 추가
crio_registries_conf: |
  unqualified-search-registries = ["registry.company.com", "docker.io"]
  
  [[registry]]
  prefix = "registry.company.com"
  location = "registry.company.com:5000"
  insecure = true

# 이미지 저장 위치 변경
crio_root_dir: /data/crio/containers
```

## 💡 사용 시나리오

### RHEL8 cgroup v1 환경
```bash
# 1. 고객 설정 준비
cp -r customers/sample customers/rhel8-customer
vi customers/rhel8-customer/hosts.yml  # 서버 IP 설정

# 2. cgroup v1 호환 버전으로 설치
./install.sh rhel8-customer --k8s-version 1.28.14
```

### Ubuntu 22.04/RHEL9 최신 환경
```bash
# 1. 고객 설정 준비
cp -r customers/sample customers/ubuntu-customer
vi customers/ubuntu-customer/hosts.yml  # 서버 IP 설정

# 2. 최신 버전으로 설치 (기본 권장)
./install.sh ubuntu-customer
# 대화형에서 "2) 1.32.8 (최신 버전 - 권장)" 선택
```

### 사설 레지스트리 환경
```bash
# 1. 고객 설정 준비
cp -r customers/sample customers/private-registry
vi customers/private-registry/extra-vars.yml  # 레지스트리 설정 추가

# 2. 설치
./install.sh private-registry --k8s-version 1.32.8
```

## 🔍 문제 해결

### 일반적인 오류들

1. **고객 폴더가 없는 경우**
   ```
   ❌ 고객 설정 폴더가 없습니다: customers/my-customer
   💡 해결: cp -r customers/sample customers/my-customer
   ```

2. **SSH 연결 실패**
   ```
   ❌ SSH 연결 테스트 실패
   💡 해결: hosts.yml에서 ansible_user와 SSH 키 경로 확인
   ```

3. **CRI-O crio-status 바이너리 누락 (무시 가능)**
   ```
   failed: Source /tmp/releases/cri-o/bin/crio-status not found
   💡 이는 선택적 디버깅 도구로, CRI-O 설치에는 영향 없음
   ```

### 설정 파일 예시

**hosts.yml 예시:**
```yaml
all:
  hosts:
    node1:
      ansible_host: 10.61.3.123
      ip: 10.61.3.123
      access_ip: 10.61.3.123
  children:
    kube_control_plane:
      hosts:
        node1:
    kube_node:
      hosts:
        node1:
    etcd:
      hosts:
        node1:
  vars:
    ansible_user: root
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

## 🎯 설치 완료 후

1. **kubeconfig 설정**
   ```bash
   scp root@<master-ip>:/etc/kubernetes/admin.conf ~/.kube/config
   ```

2. **클러스터 상태 확인**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

3. **CRI-O 상태 확인**
   ```bash
   ssh root@<node-ip>
   systemctl status crio
   crictl info
   ```

4. **Astrago 설치**
   ```bash
   cd ..
   ./deploy_astrago_v3.sh init <고객명>
   ```

## 🔧 관리 명령어

```bash
# Kubespray 상태 확인
./update-kubespray.sh status

# 설치된 버전 목록
./update-kubespray.sh list

# 특정 버전 제거
./update-kubespray.sh remove v2.24.3

# 도움말
./install.sh --help
```

## 📈 주요 개선사항

- ✅ **Non-Interactive**: 대화형 프롬프트 제거, 자동화된 설치
- ✅ **Pre-configured**: sample 기반의 빠른 설정
- ✅ **CRI-O 최적화**: unqualified-search-registries 자동 설정
- ✅ **버전 정확성**: cgroup v1/v2 호환성 명시
- ✅ **Clean Architecture**: 불필요한 기능 제거로 단순화
- ✅ **로그 없음**: 실시간 출력으로 hang 문제 해결

---

**💡 Tip**: 처음 사용 시 `--dry-run` 옵션으로 테스트 후 실제 설치를 진행하세요!