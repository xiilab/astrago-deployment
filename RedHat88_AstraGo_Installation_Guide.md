# RedHat 8.8 AstraGo 설치 가이드

### 1.3 NVIDIA 드라이버 런파일 설치
```bash
# GPU Operator v24.9.2 호환 드라이버 다운로드
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/550.144.03/NVIDIA-Linux-x86_64-550.144.03.run

# 실행 권한 부여
sudo chmod +x NVIDIA-Linux-x86_64-550.144.03.run

# 무인 설치 실행
sudo ./NVIDIA-Linux-x86_64-550.144.03.run --silent

# 시스템 재부팅
sudo reboot
```

### 1.4 설치 확인
```bash
# 재부팅 후 GPU 드라이버 확인
nvidia-smi

# 드라이버 버전 확인
cat /proc/driver/nvidia/version

# 커널 모듈 로드 확인
lsmod | grep nvidia
```

---

## 🚀 2단계: 쿠버네티스 클러스터 설치 (Kubespray)

### 2.1 사전 준비
```bash
sudo yum install git

git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# 프로젝트 클론 (처음 설치하는 경우)
git clone https://github.com/xiilab/astrago-deployment.git
cd astrago-deployment

# doosan/main 브랜치 체크아웃
git checkout doosan/main
git pull origin doosan/main

# Kubespray 디렉토리로 이동
cd kubespray
```

### 2.2 Python 환경 설정
```bash

# Ansible 의존성 설치
pip install -r requirements.txt

# Ansible 버전 확인
ansible --version
```

### 2.3 인벤토리 파일 설정
```bash
# 인벤토리 파일 편집 (실제 환경에 맞게 IP 수정)
vi inventory/mycluster/astrago.yaml
```

**인벤토리 파일 예시:**
```yaml
all:
  hosts:
    master-1:
      ansible_host: 192.168.1.10    # 실제 마스터 노드 IP
      ip: 192.168.1.10
      access_ip: 192.168.1.10
    worker-1:
      ansible_host: 192.168.1.11    # 실제 워커 노드 IP
      ip: 192.168.1.11
      access_ip: 192.168.1.11
    worker-2:
      ansible_host: 192.168.1.12    # GPU가 있는 워커 노드
      ip: 192.168.1.12
      access_ip: 192.168.1.12
  children:
    kube-master:
      hosts:
        master-1:
    kube-node:
      hosts:
        worker-1:
        worker-2:
    etcd:
      hosts:
        master-1:
    k8s-cluster:
      children:
        kube-master:
        kube-node:
    calico-rr:
      hosts: {}
```

### 2.4 SSH 키 설정
```bash
# SSH 키 생성 (없는 경우)
ssh-keygen -t rsa -b 4096

# 모든 노드에 SSH 키 배포
ssh-copy-id root@192.168.1.10  # 마스터 노드
ssh-copy-id root@192.168.1.11  # 워커 노드 1  
ssh-copy-id root@192.168.1.12  # 워커 노드 2

# SSH 연결 테스트
ansible all -i inventory/mycluster/astrago.yaml -m ping --become
```

### 2.5 쿠버네티스 클러스터 설치 실행
```bash
# Kubespray로 쿠버네티스 설치
ansible-playbook -i inventory/mycluster/astrago.yaml \
  --become --become-user=root cluster.yml

# 설치 진행 시간: 약 15-30분 소요
```

### 2.6 kubectl 설정 및 확인
```bash

# 클러스터 상태 확인
kubectl get nodes

# 모든 Pod 상태 확인
kubectl get pods -A

# 클러스터 정보 확인
kubectl cluster-info
```

**예상 출력:**
```
NAME       STATUS   ROLES           AGE   VERSION
master-1   Ready    control-plane   5m    v1.29.0
worker-1   Ready    <none>          4m    v1.29.0
worker-2   Ready    <none>          4m    v1.29.0
```

---

## ✅ 다음 단계
쿠버네티스 클러스터 설치가 완료되면 다음과 같이 AstraGo 애플리케이션을 설치할 수 있습니다:

# environments/dev/values.yaml
astrago:
  tls:
    secretName: "astrago-tls-secret"  # 원하는 Secret 이름 설정
  
  ingress:
    enabled: true
    tls:
      enabled: true  # TLS 활성화
  
  truststore:
    enabled: true  # Java Truststore 설정

# 1️⃣ TLS Secret 생성 (기본 이름)

cd /etc/ssl/astrago

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=Company/OU=IT/CN=astrago.local"

chmod 644 cert.pem
chmod 600 key.pem


# 2️⃣ 사용자 정의 Secret 이름으로 생성
kubectl create secret tls astrago-tls-secret \
  --cert=/etc/ssl/astrago/cert.pem \
  --key=/etc/ssl/astrago/key.pem \
  -n astrago

# 3️⃣ values.yaml에서 해당 Secret 이름 설정
# astrago.tls.secretName: "my-custom-secret"

# 4️⃣ 배포



# 개발 환경
environments/dev/values.yaml:
  tls.secretName: "dev-tls-secret"

# 스테이징 환경  
environments/stage/values.yaml:
  tls.secretName: "stage-tls-secret"

# 프로덕션 환경
environments/prod/values.yaml:
  tls.secretName: "prod-tls-secret"


## 🚀 4단계: AstraGo 애플리케이션 배포

# 전체 설치
helmfile -e dev sync

**Ubuntu 22.04에서 RedHat 8.8로 변경 시 문제가 발생할 수 있으므로 개별 설치 권장:**

```bash
# 프로젝트 루트 경로: /path/to/astrago-deployment

# 1. NFS CSI Driver 설치
helmfile -e dev -l app=csi-driver-nfs sync

# 2. GPU Operator 설치
helmfile -e dev -l app=gpu-operator sync

# 3. 모니터링 스택 설치
helmfile -e dev -l app=prometheus sync
helmfile -e dev -l app=loki-stack sync

# 4. 인증 시스템 설치
helmfile -e dev -l app=keycloak sync

# 5. 컨테이너 레지스트리 설치 (선택)
helmfile -e dev -l app=harbor sync

# 6. AstraGo 핵심 애플리케이션 설치
helmfile -e dev -l app=astrago sync

# 7. MPI Operator 설치 (분산 컴퓨팅용)
helmfile -e dev -l app=mpi-operator sync
```

```

### 4.6 문제 해결

#### **Helmfile 명령어가 없는 경우:**
```bash
# Helmfile 설치
curl -LO https://github.com/helmfile/helmfile/releases/download/v0.157.0/helmfile_0.157.0_linux_amd64.tar.gz
tar -xzf helmfile_0.157.0_linux_amd64.tar.gz
sudo mv helmfile /usr/local/bin/
chmod +x /usr/local/bin/helmfile
```

#### **특정 애플리케이션 설치 실패 시:**
```bash
# 강제 재설치
helmfile -e dev -l app=<app-name> destroy
helmfile -e dev -l app=<app-name> sync
```

#### **환경별 설정 파일 위치:**
- **dev**: `environments/dev/values.yaml`
- **prod**: `environments/prod/values.yaml`  
- **astrago**: `environments/astrago/values.yaml`

---

## 📝 주의사항
- GPU 드라이버 설치 후 반드시 재부팅 필요
- 모든 노드에서 방화벽/SELinux 설정 확인
- SSH 키 기반 인증 필수
- 충분한 디스크 공간 확보 (최소 20GB)
- RedHat 8.8에서는 Helmfile 직접 사용 권장