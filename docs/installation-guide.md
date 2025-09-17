# ⚙️ Astrago 설치 가이드

## 📋 개요

이 문서는 Astrago 플랫폼을 Kubernetes 환경에 설치하는 과정을 단계별로 안내합니다. 온라인 및 오프라인 환경 모두 지원하며, 다양한 설치 방법을 제공합니다.

## 🔧 사전 요구사항

### 시스템 요구사항

#### 최소 시스템 사양

- **CPU**: 4 cores 이상
- **메모리**: 8GB RAM 이상
- **스토리지**: 100GB 이상
- **네트워크**: 1Gbps 이상

#### 권장 시스템 사양

- **CPU**: 8 cores 이상
- **메모리**: 16GB RAM 이상
- **스토리지**: 500GB 이상 (SSD 권장)
- **네트워크**: 10Gbps 이상

### 소프트웨어 요구사항

#### 필수 소프트웨어

- **OS**: CentOS 7/8, Ubuntu 18.04/20.04, RHEL 7/8
- **Kubernetes**: v1.21 이상
- **Docker**: v20.10 이상 또는 containerd v1.4 이상
- **Helm**: v3.7 이상
- **Python**: v3.8 이상 (GUI 인스톨러용)

#### 선택적 소프트웨어

- **NFS Server**: 외부 스토리지 사용시
- **GPU Driver**: GPU 사용시
- **MPI**: 분산 컴퓨팅 사용시

## 🚀 설치 방법

### 방법 1: 스크립트 자동 설치 (권장)

#### 1-1. 온라인 설치

```bash
# 저장소 클론
git clone https://github.com/your-org/astrago-deployment.git
cd astrago-deployment

# 환경 설정
./deploy_astrago.sh env

# 애플리케이션 배포
./deploy_astrago.sh sync
```

#### 1-2. 오프라인 설치

```bash
# 오프라인 환경 설정
./offline_deploy_astrago.sh env

# 오프라인 배포 실행
./offline_deploy_astrago.sh sync
```

### 방법 2: GUI 인스톨러

```bash
# GUI 인스톨러 실행
python3 astrago_gui_installer.py
```

### 방법 3: 수동 설치

#### 3-1. 환경 준비

```bash
# 필수 도구 설치
sudo snap install yq
bash tools/install_helmfile.sh
```

#### 3-2. 환경 설정

```bash
# 환경 설정 파일 생성
mkdir -p environments/astrago
cp -r environments/prod/* environments/astrago/

# 설정 파일 편집
vi environments/astrago/values.yaml
```

#### 3-3. 애플리케이션 배포

```bash
# 전체 배포
helmfile -e astrago sync

# 특정 애플리케이션 배포
helmfile -e astrago -l app=keycloak sync
```

## 🔧 상세 설치 단계

### 1단계: 환경 준비

#### Kubernetes 클러스터 설정

```bash
# Kubespray를 사용한 클러스터 설치
cd kubespray
ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml
```

#### 필수 도구 설치

```bash
# Helm 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Helmfile 설치
wget https://github.com/roboll/helmfile/releases/download/v0.144.0/helmfile_linux_amd64
chmod +x helmfile_linux_amd64
sudo mv helmfile_linux_amd64 /usr/local/bin/helmfile

# yq 설치
sudo snap install yq
```

### 2단계: 스토리지 설정

#### NFS 스토리지 설정

```bash
# NFS 서버 설치 (별도 서버)
sudo yum install -y nfs-utils
sudo systemctl enable nfs-server
sudo systemctl start nfs-server

# 공유 디렉토리 생성
sudo mkdir -p /nfs-data/astrago
sudo chown -R nobody:nobody /nfs-data
sudo chmod -R 755 /nfs-data

# exports 설정
echo "/nfs-data *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -a
```

#### 로컬 스토리지 설정

```bash
# 로컬 디렉토리 생성
sudo mkdir -p /local-data/astrago
sudo chown -R 1000:1000 /local-data
sudo chmod -R 755 /local-data
```

### 3단계: 환경 설정

#### 환경 변수 설정

```bash
# 환경 설정 파일 편집
vi environments/astrago/values.yaml
```

#### 주요 설정 항목

```yaml
# 외부 접근 IP
externalIP: "10.61.3.12"

# NFS 설정
nfs:
  storageClassName: astrago-nfs-csi
  server: "10.61.3.2"
  basePath: "/nfs-data/astrago"

# Keycloak 설정
keycloak:
  adminUser: admin
  adminPassword: xiirocks
  servicePort: 30001

# Astrago 설정
astrago:
  servicePort: 30080
  userInitPassword: astrago
```

### 4단계: 애플리케이션 배포

#### 순차적 배포

```bash
# 1. NFS 프로비저너 배포
helmfile -e astrago -l app=csi-driver-nfs sync

# 2. Keycloak 배포
helmfile -e astrago -l app=keycloak sync

# 3. Loki Stack 배포 (로그 수집) - 먼저 설치
helmfile -e astrago -l app=loki-stack sync

# 4. Prometheus 배포 (Loki 자동 연동)
# ⚡ Loki가 먼저 설치되어 있으면 Grafana에 자동으로 데이터소스 추가됨
helmfile -e astrago -l app=prometheus sync

# 5. GPU Operator 배포 (GPU 사용시)
helmfile -e astrago -l app=gpu-operator sync

# 6. Astrago 메인 애플리케이션 배포
helmfile -e astrago -l app=astrago sync
```

#### 한번에 배포

```bash
# 전체 애플리케이션 배포
helmfile -e astrago sync
```

## 🔍 설치 검증

### 1. Pod 상태 확인

```bash
# 모든 Pod 상태 확인
kubectl get pods -A

# Astrago 네임스페이스 확인
kubectl get pods -n astrago
```

### 2. 서비스 상태 확인

```bash
# 서비스 목록 확인
kubectl get svc -A

# 외부 접근 가능한 서비스 확인
kubectl get svc -o wide | grep NodePort
```

### 3. 애플리케이션 접속 테스트

```bash
# Astrago 웹 UI 접속
curl http://<EXTERNAL_IP>:30080

# Keycloak 접속
curl http://<EXTERNAL_IP>:30001

# Prometheus 접속
curl http://<EXTERNAL_IP>:30090

# Grafana 접속 (Prometheus 내장)
curl http://<EXTERNAL_IP>:30090/grafana
```

### 4. 🔗 Prometheus ↔ Loki 자동 연동 확인

```bash
# Grafana에서 Loki 데이터소스 확인
kubectl get configmap prometheus-grafana -n prometheus -o yaml | grep -A 10 "name: Loki"

# Loki 서비스 연결 테스트
kubectl exec -it $(kubectl get pods -n prometheus -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') -n prometheus -c grafana -- curl -s http://loki-stack.loki-stack.svc.cluster.local:3100/ready

# 자동 추가된 대시보드 확인
kubectl get configmap prometheus-grafana -n prometheus -o yaml | grep -A 5 "loki-logs"
```

**✅ 자동 연동 성공 시 확인 사항:**

- Grafana 데이터소스에 **Loki** 자동 추가
- **Loki Logs Dashboard** (ID: 13639) 자동 설치
- **Loki Operational Dashboard** (ID: 14055) 자동 설치
- Prometheus에서 Loki 메트릭 수집 확인

## 🎯 설치 옵션

### 온라인 설치 옵션

#### 기본 설치

```bash
./deploy_astrago.sh deploy
```

#### 개발 환경 설치

```bash
./deploy_astrago.sh deploy --env dev
```

#### 프로덕션 환경 설치

```bash
./deploy_astrago.sh deploy --env prod
```

### 오프라인 설치 옵션

#### 에어갭 환경 설치

```bash
# 환경 설정
./offline_deploy_astrago.sh env

# 배포 실행
./offline_deploy_astrago.sh sync
```

#### 프라이빗 레지스트리 설정

```yaml
# values.yaml
offline:
  registry: "192.168.1.100:5000"
  httpServer: "http://192.168.1.100:8080"
```

## 🔧 고급 설정

### 고가용성 설정

#### 다중 마스터 노드

```yaml
# kubespray inventory
[kube-master]
master1 ansible_host=10.61.3.10
master2 ansible_host=10.61.3.11
master3 ansible_host=10.61.3.12
```

#### 로드 밸런서 설정

```yaml
# values.yaml
loadBalancer:
  enabled: true
  type: "MetalLB"
  ipRange: "10.61.3.100-10.61.3.110"
```

### 보안 설정

#### SSL/TLS 설정

```yaml
# values.yaml
security:
  tls:
    enabled: true
    certManager: true
    issuer: "letsencrypt-prod"
```

#### 네트워크 정책

```yaml
# values.yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: astrago
```

## 🚨 문제 해결

### 일반적인 문제

#### Pod 시작 실패

```bash
# Pod 로그 확인
kubectl logs <pod-name> -n astrago

# Pod 상세 정보 확인
kubectl describe pod <pod-name> -n astrago
```

#### 스토리지 문제

```bash
# PVC 상태 확인
kubectl get pvc -n astrago

# StorageClass 확인
kubectl get storageclass
```

#### 네트워크 문제

```bash
# 서비스 엔드포인트 확인
kubectl get endpoints -n astrago

# DNS 확인
kubectl exec -it <pod-name> -n astrago -- nslookup kubernetes.default
```

### 성능 최적화

#### 리소스 제한 설정

```yaml
# values.yaml
resources:
  limits:
    cpu: "2000m"
    memory: "4Gi"
  requests:
    cpu: "500m"
    memory: "1Gi"
```

#### 노드 어피니티 설정

```yaml
# values.yaml
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchExpressions:
      - key: node-type
        operator: In
        values:
        - worker
```

## 20250917 업데이트 사항

### Rocky8 기준 오픈망 설치 가이드

#### Rocky VM 환경 설정

```bash
# 최신 패키지 정보 업데이트
sudo dnf -y update

# git 설치
sudo dnf -y install git

# 설치 확인
git --version
```

#### AstraGo 배포 코드 다운로드

```bash
git clone https://github.com/xiilab/astrago-deployment.git
chmod -R 775 /astrago-deployment 

git checkout release
```

#### 초기 설정

```bash
# GUI 설치 프로그램 실행 (UI 표출 시 종료)
./run_gui_installer.sh

# 가상환경 진입
source ~/.venv/3.11/bin/activate

# kubespray 디렉토리로 이동
cd kubespray
# 클러스터(서버) 설정 파일 편집
inventory/mycluster/astrago.yaml -> 클러스터(서버)설정
```

####SSH 키 생성
ssh-keygen -t rsa -b 4096
# 모든 노드에 SSH 키 배포
ssh-copy-id root@{ip}  #모든노드

#### NFS 서버 설치 및 설정

```bash
# NFS 서버 설치 
sudo yum install -y nfs-utils
sudo systemctl enable nfs-server
sudo systemctl start nfs-server

# 공유 디렉토리 생성
sudo mkdir -p /nfs-data/astrago
sudo chown -R nobody:nobody /nfs-data
sudo chmod -R 755 /nfs-data

# exports 설정
echo "/nfs-data/astrago *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -a
```

#### 쿠버네티스 클러스터 설치

```bash
# 쿠버네티스 클러스터 설치
ansible-playbook -i inventory/mycluster/astrago.yaml cluster.yml
```

#### 어플리케이션 실행

다음 두 가지 방법 중 하나를 선택하여 실행:

**방법 1: deploy_astrago.sh 스크립트 사용**
```bash
# 환경 설정 변경 필요
# vi deploy_astrago.sh에서 environment_name="prod" 환경 변경
./deploy_astrago.sh sync
```

**방법 2: helmfile 직접 사용**
```bash
# 전체 애플리케이션 배포
helmfile -e {환경명} sync

# 특정 애플리케이션만 배포 (astrago만)
helmfile -e {환경명} -l app=astrago sync

# 삭제 시
helmfile -e {환경명} destroy
```

