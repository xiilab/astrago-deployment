# 🔒 Astrago 폐쇄망 설치 가이드

<div align="center">

![Air-Gap Installation](https://img.shields.io/badge/Air--Gap-Installation-blue?style=for-the-badge)
![Security](https://img.shields.io/badge/Security-High-red?style=for-the-badge)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Offline-326ce5?style=for-the-badge)

**완전 격리된 폐쇄망 환경에서 Astrago 플랫폼 설치하기**

</div>

---

## 📋 목차

- [사전 확인사항](#-사전-확인사항)
- [설치 진행](#-설치-진행)
- [문제 해결](#-문제-해결)
- [확인 및 접속](#-확인-및-접속)

---

## ✅ 사전 확인사항

설치를 시작하기 전에 **반드시** 다음 사항들을 확인하세요.

### 1️⃣ 서버 구성 정보 확인

<table>
<tr>
<th>항목</th>
<th>확인 내용</th>
<th>예시</th>
</tr>
<tr>
<td><b>Master 노드</b></td>
<td>IP 주소, 사용자명, 패스워드</td>
<td>
<code>192.168.1.10</code><br>
<code>root</code> / <code>password123</code>
</td>
</tr>
<tr>
<td><b>Worker 노드</b></td>
<td>각 노드별 IP, 사용자명, 패스워드</td>
<td>
<code>192.168.1.11</code><br>
<code>192.168.1.12</code><br>
<code>root</code> / <code>password123</code>
</td>
</tr>
</table>

> **⚠️ 중요**: 모든 노드가 **동일한 사용자 계정**을 사용해야 설치가 원활합니다.

### 2️⃣ 방화벽 해제 여부 확인

```bash
# 방화벽 상태 확인 (비활성화되어 있어야 함)
sudo ufw status          # Ubuntu
sudo firewall-cmd --state  # CentOS/RHEL
```

### 3️⃣ 설치 파일 및 GPU 드라이버 확인

```bash
# 설치 파일 존재 여부 확인
ls -lh astrago-deployment.tar.gz

# GPU 드라이버 기 설치 여부 확인
nvidia-smi

# GPU 드라이버 설치 파일 확인
ls -lh airgap/kubespray-offline/outputs/files/gpu-driver/

# Fabric Manager 설치 필요 여부 확인 (A100/H100 GPU 사용 시)
systemctl status nvidia-fabricmanager
```

---

## 🚀 설치 진행

### 1단계: 설치 파일 압축 해제 (Master 노드)

```bash
# Master 노드에 설치 파일 복사 후 압축 해제
tar -xzf astrago-deployment.tar.gz

# 디렉토리 이동
cd astrago-deployment

# 파일 구조 확인
ls -la
```

**✅ 확인 포인트:**
- `airgap/` 디렉토리가 존재하는지 확인
- `kubespray/` 디렉토리가 존재하는지 확인

---

### 2단계: GPU 드라이버 파일 Worker 노드에 전송

각 Worker 노드에 GPU 드라이버 설치 파일을 복사합니다.

```bash
# Worker 노드별로 전송
scp airgap/kubespray-offline/outputs/files/gpu-driver/NVIDIA-Linux-x86_64-*.run root@192.168.1.11:/tmp/
scp airgap/kubespray-offline/outputs/files/gpu-driver/NVIDIA-Linux-x86_64-*.run root@192.168.1.12:/tmp/

# Fabric Manager가 필요한 경우 (A100/H100)
scp airgap/kubespray-offline/outputs/files/gpu-driver/nvidia-fabricmanager-*.deb root@192.168.1.11:/tmp/
scp airgap/kubespray-offline/outputs/files/gpu-driver/nvidia-fabricmanager-*.deb root@192.168.1.12:/tmp/
```

---

### 3단계: 로컬 레지스트리 및 Nginx 서버 구축

Master 노드에서 컨테이너 이미지 레지스트리와 패키지 서버를 실행합니다.

```bash
# Master 노드에서 실행
cd /astrago-deployment/airgap

# 레지스트리 및 Nginx 구축 스크립트 실행
./setup-all.sh
```

**⏳ 소요 시간**: 약 10-15분

**✅ 확인:**

```bash
# 컨테이너 실행 상태 확인
nerdctl ps

# 다음 컨테이너들이 실행 중이어야 합니다:
# - registry (포트: 35000)
# - nginx (포트: 8080)
```

**예상 출력:**
```
CONTAINER ID    IMAGE                             COMMAND    STATUS    PORTS
abc123def456    registry:2                        ...        Up        0.0.0.0:35000->5000/tcp
789ghi012jkl    nginx:latest                      ...        Up        0.0.0.0:8080->80/tcp
```

> **⚠️ 문제 발생 시**: 컨테이너가 실행되지 않는다면:
> ```bash
> # containerd 상태 확인
> sudo systemctl status containerd
> 
> # containerd 재시작
> sudo systemctl restart containerd
> 
> # 다시 실행
> ./setup-all.sh
> ```

---

### 4단계: Nouveau 드라이버 비활성화 (모든 Worker 노드)

NVIDIA GPU 드라이버와 충돌하는 오픈소스 Nouveau 드라이버를 비활성화합니다.

**각 Worker 노드에서 실행:**

```bash
# blacklist 설정 파일 생성
sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

# initramfs 업데이트
sudo update-initramfs -u  # Ubuntu/Debian
# 또는
sudo dracut --force       # CentOS/RHEL

# 시스템 재부팅
sudo reboot
```

**재부팅 후 확인:**

```bash
# Nouveau 드라이버가 로드되지 않았는지 확인 (출력이 없어야 정상)
lsmod | grep nouveau
```

> **✅ 정상**: 아무 출력이 없음  
> **❌ 비정상**: nouveau 관련 모듈이 출력됨 → 4단계 다시 수행

---

### 5단계: Kubernetes 클러스터 노드 설정

Kubernetes 설치를 위한 인벤토리 파일을 수정합니다.

```bash
# 인벤토리 파일 편집
vi /astrago-deployment/kubespray/inventory/offline/astrago.yaml
```

**설정 예시:**

```yaml
all:
  hosts:
    master-1:
      ansible_host: 10.61.3.161
      ip: 10.61.3.161
      access_ip: 10.61.3.161
      ansible_user: root                # SSH 접속 계정
      #ansible_become: true
      #ansible_become_method: su
      #ansible_become_user: root
      #ansible_become_password: secret1 # node1의 root 비번
    worker-1:
      ansible_host: 10.61.3.162
      ip: 10.61.3.162
      access_ip: 10.61.3.162
      ansible_user: root
    worker-2:
      ansible_host: 10.61.3.163
      ip: 10.61.3.163
      access_ip: 10.61.3.163
      ansible_user: root
  children:
    kube_control_plane:
      hosts:
        master-1:
    kube_node:
      hosts:
        worker-1:
        worker-2:
    etcd:
      hosts:
        master-1:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
```

> **💡 팁**: 노드 이름(master-1, worker-1 등)을 변경하지 않는 것을 권장합니다.  
> Kubespray 설치 시 호스트명이 자동으로 변경됩니다.

**📁 CRI-O 데이터 폴더 위치 변경이 필요한 경우:**

```bash
vi /astrago-deployment/kubespray/roles/container-engine/cri-o/tasks/main.yaml

# crio_data_dir 변수 수정
# 예: /var/lib/containers 대신 /data/containers 사용
```

---

### 6단계: Kubernetes 클러스터 설치

Kubernetes 클러스터를 배포합니다.

```bash
# Master 노드에서 실행
cd /astrago-deployment/airgap

# Kubernetes 설치 스크립트 실행
./deploy_kubernetes.sh
```

**⏳ 소요 시간**: 약 20-30분

**✅ 설치 완료 확인:**

```bash
# 노드 상태 확인
kubectl get nodes -o wide

# 예상 출력:
# NAME       STATUS   ROLES           AGE   VERSION
# master-1   Ready    control-plane   5m    v1.28.x
# worker-1   Ready    <none>          4m    v1.28.x
# worker-2   Ready    <none>          4m    v1.28.x
```

**🔧 NodeLocalDNS 설정 수정:**

```bash
# NodeLocalDNS ConfigMap 편집
kubectl edit configmap nodelocaldns -n kube-system

# .:53 섹션의 forward 라인을 주석 처리
# 변경 전:
#     forward . /etc/resolv.conf
# 변경 후:
#     # forward . /etc/resolv.conf
```

**🔄 DNS 컴포넌트 재시작:**

```bash
# NodeLocalDNS 재시작
kubectl -n kube-system rollout restart daemonset nodelocaldns

# CoreDNS 재시작
kubectl -n kube-system rollout restart deployment coredns

# 상태 확인
kubectl get pod -A
```

**📦 NFS 서버 설치 (Master 노드):**

```bash
# NFS 서버 패키지 설치
sudo apt install -y nfs-kernel-server  # Ubuntu
# 또는
sudo yum install -y nfs-utils          # CentOS/RHEL

# NFS 공유 디렉토리 생성
sudo mkdir -p /nfs-data/astrago
sudo chown -R nobody:nogroup /nfs-data  # Ubuntu
# 또는
sudo chown -R nobody:nobody /nfs-data   # CentOS/RHEL
sudo chmod -R 755 /nfs-data

# NFS exports 설정
echo "/nfs-data *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports

# NFS 서버 재시작
sudo exportfs -a
sudo systemctl restart nfs-kernel-server  # Ubuntu
# 또는
sudo systemctl restart nfs-server         # CentOS/RHEL
```

---

### 7단계: NVIDIA GPU 드라이버 설치 (모든 Worker 노드)

각 Worker 노드에서 GPU 드라이버를 설치합니다.

**필수 패키지 설치:**

```bash
# 각 Worker 노드에서 실행

# 커널 헤더 및 빌드 도구 설치
sudo apt install -y linux-headers-$(uname -r) gcc make  # Ubuntu
# 또는
sudo yum install -y kernel-devel-$(uname -r) gcc make   # CentOS/RHEL

# NFS 클라이언트 설치
sudo apt install -y nfs-common  # Ubuntu
# 또는
sudo yum install -y nfs-utils   # CentOS/RHEL
```

**GPU 드라이버 설치:**

```bash
# /tmp 디렉토리로 이동
cd /tmp

# GPU 드라이버 설치 (실행 권한 부여 후 설치)
chmod +x NVIDIA-Linux-x86_64-*.run
sudo ./NVIDIA-Linux-x86_64-*.run --silent --no-questions

# Fabric Manager 설치 (A100/H100 GPU인 경우)
sudo dpkg -i nvidia-fabricmanager-*.deb  # Ubuntu
# 또는
sudo rpm -ivh nvidia-fabricmanager-*.rpm  # CentOS/RHEL

# Fabric Manager 시작 (필요 시)
sudo systemctl enable nvidia-fabricmanager
sudo systemctl start nvidia-fabricmanager
```

**✅ 설치 확인:**

```bash
# GPU 인식 확인
nvidia-smi

# 예상 출력:
# +-----------------------------------------------------------------------------+
# | NVIDIA-SMI 525.x.xx   Driver Version: 525.x.xx   CUDA Version: 12.x       |
# |-------------------------------+----------------------+----------------------+
# | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
# | Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
# |===============================+======================+======================|
# |   0  Tesla V100          Off  | 00000000:00:1E.0 Off |                    0 |
# | N/A   35C    P0    38W / 250W |      0MiB / 16384MiB |      0%      Default |
# +-------------------------------+----------------------+----------------------+
```

---

### 8단계: CRI-O 레지스트리 설정 (모든 노드)

Kubernetes 클러스터의 모든 노드에서 로컬 레지스트리를 사용할 수 있도록 CRI-O 설정을 수정합니다.

**모든 노드 (Master + Worker)에서 실행:**

```bash
# 1. Unqualified 레지스트리 설정
sudo vi /etc/containers/registries.conf.d/01-unqualified.conf

# 다음 내용 추가 또는 수정:
unqualified-search-registries = ["192.168.1.10:35000"]
```

```bash
# 2. Insecure 레지스트리 설정
sudo vi /etc/crio/crio.conf

# [crio.image] 섹션에서 insecure_registries 찾아서 수정:
[crio.image]
insecure_registries = [
  "192.168.1.10:35000",
  "192.168.1.10:30002"
]
```

```bash
# 3. CRI-O 재시작
sudo systemctl restart crio

# CRI-O 상태 확인
sudo systemctl status crio
```

> **💡 참고**: 
> - `192.168.1.10:35000` - 배포용 로컬 레지스트리
> - `192.168.1.10:30002` - Harbor 레지스트리 (설치 시)

**✅ 설정 확인:**

```bash
# CRI-O 설정 확인
sudo crictl info | grep -A 10 registry
```

---

### 9단계: Astrago 환경 설정 파일 점검

배포 전에 환경 설정 파일을 확인하고 필요시 수정합니다.

```bash
# 환경 설정 파일 열기
vi /astrago-deployment/environments/prod/values.yaml
```

**주요 확인 항목:**

```yaml
# Offline 환경 설정
offline:
  registry: "192.168.1.10:35000"
  httpServer: "http://192.168.1.10"
```

> **💡 참고**: 이 설정들은 `./offline_deploy_astrago.sh env` 실행 후 자동으로 생성됩니다.  
> env 설정 완료 후 다시 한번 확인하세요.

**🔧 환경 설정 스크립트 실행:**

```bash
cd /astrago-deployment/airgap

# 대화형 환경 설정
./offline_deploy_astrago.sh env
```

**입력 정보:**

```
Enter the connection URL (외부 접속 IP): 192.168.1.10
Enter the NFS server IP address: 192.168.1.10
Enter the base path of NFS: /nfs-data/astrago
Enter the offline registry: 192.168.1.10:35000
Enter the HTTP server: http://192.168.1.10
```

---

### 10단계: Astrago 애플리케이션 배포

Kubernetes 클러스터에 Astrago 애플리케이션을 배포합니다.

```bash
# Master 노드에서 실행
cd /astrago-deployment/airgap

# Astrago 배포 시작
./offline_deploy_astrago.sh sync
```

**⏳ 소요 시간**: 약 15-20분

**배포 진행 순서:**

다음 순서대로 애플리케이션이 배포됩니다 (helmfile.yaml 기준):

1. **CSI Driver NFS** - 스토리지 프로비저닝
2. **GPU Operator** - GPU 리소스 관리
3. **Network Operator** - 네트워크 구성
4. **Prometheus** - 모니터링 시스템
5. **Keycloak** - 인증/인가 서비스
6. **MPI Operator** - 분산 컴퓨팅 지원
7. **Flux** - GitOps 도구
8. **Astrago** - 메인 애플리케이션
9. **Harbor** - 컨테이너 레지스트리

**✅ 배포 상태 확인:**

```bash
# 각 Namespace별 Pod 상태 확인
kubectl get pod -n astrago
kubectl get pod -n monitoring
kubectl get pod -n keycloak

# 모든 Pod가 Running 상태인지 확인
kubectl get pod -A | grep -v Running | grep -v Completed

# 서비스 목록 확인
kubectl get svc -A
```

**예상 출력 (astrago namespace):**

```
NAME                    READY   STATUS    RESTARTS   AGE
astrago-core-xxx        1/1     Running   0          5m
astrago-batch-xxx       1/1     Running   0          5m
astrago-monitor-xxx     1/1     Running   0          5m
astrago-frontend-xxx    1/1     Running   0          5m
mariadb-0               1/1     Running   0          8m
redis-master-0          1/1     Running   0          8m
```

---

### 11단계: 접속 확인 및 인증키 발급

설치가 완료되면 웹 브라우저를 통해 접속합니다.

#### 🌐 접속 정보

<table>
<tr>
<th>서비스</th>
<th>URL</th>
<th>기본 포트</th>
<th>비고</th>
</tr>
<tr>
<td><b>Astrago Nodeport방식</b></td>
<td><code>http://{EXTERNAL_IP}:30080</code></td>
<td>30080</td>
<td>메인 웹 UI</td>
</tr>
<tr>
<td><b>Astrago Ingress방식</b></td>
<td><code>https://{DOMAIN_NAME}</code></td>
<td>443</td>
<td>도메인 설정 시</td>
</tr>
<tr>
<td><b>Keycloak Admin</b></td>
<td><code>http://{EXTERNAL_IP}:30001/auth</code></td>
<td>30001</td>
<td>인증 관리</td>
</tr>
<tr>
<td><b>Prometheus</b></td>
<td><code>http://{EXTERNAL_IP}:30090</code></td>
<td>30090</td>
<td>모니터링</td>
</tr>
<tr>
<td><b>Grafana</b></td>
<td><code>http://{EXTERNAL_IP}:30091</code></td>
<td>30091</td>
<td>대시보드</td>
</tr>
<tr>
<td><b>Harbor</b></td>
<td><code>http://{EXTERNAL_IP}:30002</code></td>
<td>30002</td>
<td>컨테이너 레지스트리</td>
</tr>
</table>

**예시:**
```bash
# External IP가 192.168.1.10인 경우
http://192.168.1.10:30080         # Astrago 메인 화면
http://192.168.1.10:30001/auth    # Keycloak 로그인
```

#### 🔑 인증키 발급

> **⚠️ 중요**: Astrago 사용을 위해서는 라이선스 인증키가 필요합니다.

**인증키 발급 요청:**

1. **담당자 연락**
   - **소속**: SA 팀
   - **이메일**: sa-infra@xiilab.com
   - **Slack**: #_project_astrago_dev와sa협업

2. **제공 정보**
   ```
   - 회사명/기관명:
   - 설치 환경: 폐쇄망
   - Kubernetes 버전:
   - 노드 수 (Master/Worker):
   - GPU 모델 및 개수:
   - 용도: (개발/테스트/프로덕션)
   ```

3. **인증키 적용**
   ```
   Astrago 웹 UI 접속
   → 관리자 페이지
   → 라이선스 메뉴
   → 라이선스 번호 등록
   ```

#### ✅ 접속 확인 체크리스트

- [ ] **웹 브라우저로 `http://{IP}:30080` 접속 가능**
- [ ] **Keycloak 로그인 페이지 표시**
- [ ] **관리자 계정으로 로그인 성공**
- [ ] **Astrago 대시보드 정상 표시**
- [ ] **GPU 리소스 확인 가능** (GPU 설치 시)
- [ ] **테스트 Job 실행 성공**

---

## 🚨 문제 해결

### ❌ 일반적인 문제들

<details>
<summary><b>1. nerdctl ps 에서 컨테이너가 보이지 않음</b></summary>

**원인**: containerd가 제대로 실행되지 않음

**해결방법:**
```bash
# containerd 상태 확인
sudo systemctl status containerd

# containerd 재시작
sudo systemctl restart containerd

# setup-all.sh 다시 실행
cd /astrago-deployment/airgap
./setup-all.sh
```

</details>

<details>
<summary><b>2. Kubernetes 노드가 NotReady 상태</b></summary>

**원인**: CNI 플러그인 또는 NodeLocalDNS 문제

**해결방법:**
```bash
# 노드 상세 정보 확인
kubectl describe node <NODE_NAME>

# Calico Pod 상태 확인
kubectl get pod -n kube-system | grep calico

# Calico 재시작
kubectl rollout restart daemonset calico-node -n kube-system

# NodeLocalDNS 확인
kubectl get pod -n kube-system | grep nodelocaldns
```

</details>

<details>
<summary><b>3. Pod가 ImagePullBackOff 상태</b></summary>

**원인**: 로컬 레지스트리에 이미지가 없거나 접근 불가

**해결방법:**
```bash
# 레지스트리 상태 확인
nerdctl ps | grep registry

# 레지스트리에 이미지가 있는지 확인
curl http://192.168.1.10:35000/v2/_catalog

# Pod가 참조하는 이미지 확인
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# 레지스트리 주소가 올바른지 확인
kubectl get deployment <DEPLOYMENT_NAME> -n <NAMESPACE> -o yaml | grep image:
```

</details>

<details>
<summary><b>4. NFS 마운트 실패</b></summary>

**원인**: NFS 서버 설정 또는 방화벽 문제

**해결방법:**
```bash
# NFS 서버에서 exports 확인
sudo exportfs -v

# NFS 서비스 상태 확인
sudo systemctl status nfs-kernel-server  # Ubuntu
sudo systemctl status nfs-server         # CentOS

# Worker 노드에서 NFS 마운트 테스트
sudo mount -t nfs 192.168.1.10:/nfs-data /mnt/test
ls /mnt/test
sudo umount /mnt/test

# NFS 클라이언트 패키지 설치 확인 (Worker)
dpkg -l | grep nfs-common  # Ubuntu
rpm -qa | grep nfs-utils   # CentOS
```

</details>

<details>
<summary><b>5. nvidia-smi 명령어가 없음</b></summary>

**원인**: GPU 드라이버 설치 실패

**해결방법:**
```bash
# Nouveau 드라이버 비활성화 확인
lsmod | grep nouveau  # 출력이 없어야 정상

# GPU 드라이버 재설치
cd /tmp
sudo ./NVIDIA-Linux-x86_64-*.run --uninstall
sudo ./NVIDIA-Linux-x86_64-*.run --silent --no-questions

# 설치 로그 확인
sudo cat /var/log/nvidia-installer.log
```

</details>

<details>
<summary><b>6. Keycloak 접속 불가</b></summary>

**원인**: Keycloak Pod가 실행되지 않거나 서비스 문제

**해결방법:**
```bash
# Keycloak Pod 상태 확인
kubectl get pod -n keycloak

# Keycloak 로그 확인
kubectl logs -n keycloak deployment/keycloak --tail=100

# Keycloak 서비스 확인
kubectl get svc -n keycloak

# 데이터베이스 연결 확인
kubectl exec -it -n keycloak deployment/keycloak -- /bin/bash
# 컨테이너 내에서:
# curl http://mariadb.astrago.svc.cluster.local:3306
```

</details>

### 🔍 디버깅 명령어 모음

```bash
# 전체 시스템 상태 한눈에 보기
kubectl get all -A

# 실패한 Pod 찾기
kubectl get pod -A | grep -E "Error|CrashLoopBackOff|ImagePullBackOff"

# 특정 Pod의 상세 로그
kubectl logs -n <NAMESPACE> <POD_NAME> --tail=100 -f

# 특정 Pod의 이벤트 확인
kubectl describe pod -n <NAMESPACE> <POD_NAME>

# 노드 리소스 사용량 확인
kubectl top nodes

# Pod 리소스 사용량 확인
kubectl top pods -A

# PVC (Persistent Volume Claim) 상태 확인
kubectl get pvc -A

# StorageClass 확인
kubectl get storageclass

#Nerdctl 사용하기
nerdctl --host /run/containerd/containerd.sock
ex) nerdctl --host /run/containerd/containerd.sock pull nginx
```

---
