# 🔧 Astrago 문제 해결 가이드

## 📋 개요

이 문서는 Astrago 플랫폼 설치 및 운영 중 발생할 수 있는 일반적인 문제들과 해결 방법을 제시합니다. 단계별 진단 방법과 실용적인 해결책을 제공합니다.

## 🚨 긴급 상황 대응

### 즉시 확인할 사항

```bash
# 1. 클러스터 상태 확인
kubectl cluster-info
kubectl get nodes

# 2. 중요 Pod 상태 확인
kubectl get pods -n astrago
kubectl get pods -n kube-system

# 3. 서비스 상태 확인
kubectl get svc -n astrago

# 4. 이벤트 확인
kubectl get events --sort-by=.metadata.creationTimestamp
```

## 🔍 일반적인 문제들

### 1. 설치 관련 문제

#### 1.1 스크립트 실행 실패

**문제**: `./deploy_astrago.sh`가 실행되지 않음

```bash
bash: ./deploy_astrago.sh: Permission denied
```

**해결 방법**:

```bash
# 실행 권한 부여
chmod +x deploy_astrago.sh

# 직접 bash로 실행
bash deploy_astrago.sh env
```

#### 1.2 바이너리 누락 오류

**문제**: `helm`, `helmfile`, `kubectl` 등이 설치되지 않음

```bash
command not found: helm
```

**해결 방법**:

```bash
# tools 디렉토리 확인
ls -la tools/linux/

# 수동 설치
sudo cp tools/linux/helm /usr/local/bin/
sudo cp tools/linux/helmfile /usr/local/bin/
sudo cp tools/linux/kubectl /usr/local/bin/
sudo chmod +x /usr/local/bin/{helm,helmfile,kubectl}

# 또는 공식 설치 스크립트 사용
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### 1.3 yq 설치 실패

**문제**: `yq` 패키지를 설치할 수 없음

```bash
snap not found
```

**해결 방법**:

```bash
# CentOS/RHEL에서 yq 설치
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Ubuntu에서 yq 설치
sudo snap install yq
# 또는
sudo apt install yq
```

### 2. Kubernetes 관련 문제

#### 2.1 클러스터 접근 불가

**문제**: `kubectl` 명령이 실행되지 않음

```bash
The connection to the server localhost:8080 was refused
```

**해결 방법**:

```bash
# kubeconfig 확인
echo $KUBECONFIG
ls -la ~/.kube/config

# kubeconfig 설정
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# 또는 임시로 환경변수 설정
export KUBECONFIG=/etc/kubernetes/admin.conf
```

#### 2.2 Node NotReady 상태

**문제**: 노드가 Ready 상태가 되지 않음

```bash
NAME     STATUS     ROLES    AGE   VERSION
node1    NotReady   master   5m    v1.24.0
```

**해결 방법**:

```bash
# 노드 상세 정보 확인
kubectl describe node node1

# 일반적인 원인들:
# 1. CNI 플러그인 미설치
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# 2. kubelet 서비스 상태 확인
sudo systemctl status kubelet
sudo systemctl restart kubelet

# 3. 방화벽 문제
sudo systemctl stop firewalld
sudo systemctl disable firewalld
```

#### 2.3 Pod CrashLoopBackOff

**문제**: Pod가 계속 재시작됨

```bash
NAME           READY   STATUS             RESTARTS   AGE
astrago-core   0/1     CrashLoopBackOff   5          3m
```

**해결 방법**:

```bash
# Pod 로그 확인
kubectl logs astrago-core -n astrago --previous
kubectl logs astrago-core -n astrago -f

# Pod 상세 정보 확인
kubectl describe pod astrago-core -n astrago

# 일반적인 해결 방법:
# 1. 이미지 확인
kubectl get pod astrago-core -n astrago -o yaml | grep image

# 2. 리소스 부족 확인
kubectl top nodes
kubectl top pods -n astrago

# 3. 설정 문제 확인
kubectl get configmap -n astrago
kubectl get secret -n astrago
```

### 3. 스토리지 관련 문제

#### 3.1 PVC Pending 상태

**문제**: PersistentVolumeClaim이 Pending 상태

```bash
NAME               STATUS    VOLUME   CAPACITY   ACCESSMODES   STORAGECLASS   AGE
astrago-data-pvc   Pending                                     nfs-csi        5m
```

**해결 방법**:

```bash
# PVC 상세 정보 확인
kubectl describe pvc astrago-data-pvc -n astrago

# StorageClass 확인
kubectl get storageclass

# NFS CSI Driver 상태 확인
kubectl get pods -n kube-system | grep csi

# NFS 서버 연결 테스트
showmount -e <NFS_SERVER_IP>
```

#### 3.2 NFS 마운트 실패

**문제**: NFS 마운트 권한 오류

```bash
mount.nfs: access denied by server while mounting
```

**해결 방법**:

```bash
# NFS 서버에서 exports 확인
sudo exportfs -v

# 클라이언트에서 NFS 유틸리티 설치
sudo yum install -y nfs-utils
sudo apt install -y nfs-common

# 수동 마운트 테스트
sudo mount -t nfs <NFS_SERVER>:<PATH> /tmp/test

# NFS 서버 설정 확인 (/etc/exports)
echo "/nfs-data *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
```

### 4. 네트워크 관련 문제

#### 4.1 서비스 접근 불가

**문제**: 외부에서 Astrago 서비스에 접근할 수 없음

```bash
curl: (7) Failed to connect to 192.168.1.100 port 30080: Connection refused
```

**해결 방법**:

```bash
# 서비스 상태 확인
kubectl get svc -n astrago

# NodePort 서비스 확인
kubectl get svc astrago-frontend -n astrago -o yaml

# 방화벽 설정 확인
sudo firewall-cmd --list-all
sudo firewall-cmd --add-port=30080/tcp --permanent
sudo firewall-cmd --reload

# 포트 리스닝 확인
sudo netstat -tlnp | grep 30080
```

#### 4.2 DNS 해석 실패

**문제**: 클러스터 내부 DNS가 작동하지 않음

```bash
nslookup: can't resolve 'kubernetes.default'
```

**해결 방법**:

```bash
# CoreDNS 상태 확인
kubectl get pods -n kube-system | grep coredns

# DNS 테스트
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# CoreDNS 설정 확인
kubectl get configmap coredns -n kube-system -o yaml
```

### 5. 인증 관련 문제

#### 5.1 Keycloak 접근 불가

**문제**: Keycloak 관리 콘솔에 접근할 수 없음

```bash
Unable to connect to Keycloak server
```

**해결 방법**:

```bash
# Keycloak Pod 상태 확인
kubectl get pods -n astrago | grep keycloak

# Keycloak 로그 확인
kubectl logs deployment/keycloak -n astrago

# Keycloak 서비스 확인
kubectl get svc keycloak -n astrago

# 데이터베이스 연결 확인
kubectl get pods -n astrago | grep mariadb
kubectl logs deployment/mariadb -n astrago
```

#### 5.2 로그인 실패

**문제**: Astrago 웹 UI에 로그인할 수 없음

```bash
Authentication failed
```

**해결 방법**:

```bash
# 기본 계정 정보 확인
kubectl get secret astrago-auth -n astrago -o yaml

# Keycloak에서 사용자 확인
# Keycloak Admin Console > Users 메뉴 확인

# 초기 사용자 생성
kubectl exec -it deployment/astrago-core -n astrago -- \
  /app/manage.py createsuperuser
```

### 6. 리소스 관련 문제

#### 6.1 메모리 부족

**문제**: Pod가 OOMKilled 상태

```bash
NAME           READY   STATUS      RESTARTS   AGE
astrago-core   0/1     OOMKilled   3          5m
```

**해결 방법**:

```bash
# 리소스 사용량 확인
kubectl top nodes
kubectl top pods -n astrago

# Pod 리소스 제한 확인
kubectl describe pod astrago-core -n astrago | grep -A 5 Limits

# 리소스 제한 증가
# values.yaml에서 resources.limits.memory 값 증가
```

#### 6.2 디스크 공간 부족

**문제**: 노드의 디스크 공간 부족

```bash
DiskPressure   True   KubeletHasDiskPressure
```

**해결 방법**:

```bash
# 디스크 사용량 확인
df -h

# Docker 이미지 정리
docker system prune -a

# 로그 파일 정리
sudo journalctl --vacuum-time=7d

# 사용하지 않는 Pod 정리
kubectl delete pods --field-selector=status.phase=Succeeded -A
kubectl delete pods --field-selector=status.phase=Failed -A
```

## 🛠️ 진단 도구

### 1. 시스템 상태 체크 스크립트

```bash
#!/bin/bash
# system-check.sh

echo "=== Astrago 시스템 상태 체크 ==="

echo "1. 클러스터 상태:"
kubectl cluster-info

echo "2. 노드 상태:"
kubectl get nodes

echo "3. Astrago Pod 상태:"
kubectl get pods -n astrago

echo "4. 서비스 상태:"
kubectl get svc -n astrago

echo "5. 스토리지 상태:"
kubectl get pvc -n astrago

echo "6. 최근 이벤트:"
kubectl get events -n astrago --sort-by=.metadata.creationTimestamp | tail -10
```

### 2. 로그 수집 스크립트

```bash
#!/bin/bash
# collect-logs.sh

LOG_DIR="astrago-logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p $LOG_DIR

echo "로그 수집 중..."

# 클러스터 정보
kubectl cluster-info > $LOG_DIR/cluster-info.txt
kubectl get nodes -o wide > $LOG_DIR/nodes.txt

# Pod 로그
kubectl get pods -n astrago -o wide > $LOG_DIR/pods.txt
for pod in $(kubectl get pods -n astrago -o name); do
    kubectl logs $pod -n astrago > $LOG_DIR/${pod#*/}.log 2>&1
done

# 시스템 로그
sudo journalctl -u kubelet --since "1 hour ago" > $LOG_DIR/kubelet.log
sudo journalctl -u docker --since "1 hour ago" > $LOG_DIR/docker.log

# 설정 파일
kubectl get configmap -n astrago -o yaml > $LOG_DIR/configmaps.yaml
kubectl get secret -n astrago -o yaml > $LOG_DIR/secrets.yaml

tar -czf $LOG_DIR.tar.gz $LOG_DIR
echo "로그 수집 완료: $LOG_DIR.tar.gz"
```

### 3. 네트워크 연결 테스트

```bash
#!/bin/bash
# network-test.sh

echo "=== 네트워크 연결 테스트 ==="

# DNS 테스트
echo "1. DNS 테스트:"
nslookup kubernetes.default

# 서비스 연결 테스트
echo "2. 서비스 연결 테스트:"
EXTERNAL_IP=$(kubectl get svc astrago-frontend -n astrago -o jsonpath='{.spec.clusterIP}')
curl -I http://$EXTERNAL_IP:8080 || echo "Frontend 서비스 연결 실패"

# 외부 연결 테스트
echo "3. 외부 연결 테스트:"
curl -I http://google.com || echo "외부 인터넷 연결 실패"
```

## 🔧 성능 최적화

### 1. 리소스 모니터링

```bash
# 실시간 리소스 모니터링
watch -n 1 "kubectl top nodes && echo && kubectl top pods -n astrago"

# 리소스 사용량 히스토리
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods
```

### 2. 데이터베이스 최적화

```sql
-- MariaDB 성능 튜닝
SHOW VARIABLES LIKE 'innodb%';
SHOW STATUS LIKE 'Threads%';

-- 느린 쿼리 확인
SHOW VARIABLES LIKE 'slow_query%';
SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;
```

### 3. 스토리지 최적화

```bash
# NFS 성능 확인
nfsstat -c

# 디스크 I/O 모니터링
iostat -x 1

# 파일 시스템 최적화
sudo tune2fs -l /dev/sda1
```

## 📊 모니터링 설정

### 1. Prometheus 알림 규칙

```yaml
# prometheus-alerts.yaml
groups:
- name: astrago-alerts
  rules:
  - alert: AstragoPodDown
    expr: up{job="astrago"} == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Astrago Pod is down"
      
  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.9
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage detected"
```

### 2. 로그 분석

```bash
# 에러 로그 분석
kubectl logs -f deployment/astrago-core -n astrago | grep -i error

# 성능 관련 로그
kubectl logs deployment/astrago-core -n astrago | grep -E "(slow|timeout|performance)"

# 로그 집계
kubectl logs deployment/astrago-core -n astrago --since=1h | \
  awk '{print $1, $2}' | sort | uniq -c | sort -nr
```

## 🚨 긴급 복구 절차

### 1. 서비스 롤백

```bash
# Helm 릴리스 히스토리 확인
helm history astrago -n astrago

# 이전 버전으로 롤백
helm rollback astrago 1 -n astrago

# 또는 kubectl을 사용한 롤백
kubectl rollout undo deployment/astrago-core -n astrago
```

### 2. 데이터 백업 및 복구

```bash
# MariaDB 백업
kubectl exec deployment/mariadb -n astrago -- \
  mysqldump -u root -p$MYSQL_ROOT_PASSWORD astrago > astrago-backup.sql

# 백업 복구
kubectl exec -i deployment/mariadb -n astrago -- \
  mysql -u root -p$MYSQL_ROOT_PASSWORD astrago < astrago-backup.sql

# PVC 데이터 백업
kubectl exec deployment/astrago-core -n astrago -- \
  tar -czf /tmp/data-backup.tar.gz /app/data
```

### 3. 클러스터 재시작

```bash
# 전체 클러스터 재시작 (주의!)
sudo systemctl restart kubelet
sudo systemctl restart docker

# 특정 노드 재시작
kubectl drain node1 --ignore-daemonsets
# 노드 재부팅 후
kubectl uncordon node1
```

## 📞 지원 요청 시 준비사항

### 필수 정보 수집

1. **시스템 환경 정보**

```bash
kubectl version
docker version
cat /etc/os-release
```

2. **오류 로그**

```bash
# 수집 스크립트 실행
./collect-logs.sh
```

3. **설정 정보**

```bash
# values.yaml 파일
cat environments/astrago/values.yaml

# 현재 설정
kubectl get cm,secret -n astrago
```

4. **타임라인**

- 문제 발생 시간
- 최근 변경사항
- 재현 단계

### 지원 연락처

- 📧 **이메일**: <support@astrago.io>
- 💬 **Slack**: #astrago-support
- 🐛 **GitHub Issues**: [Issues 페이지](https://github.com/your-org/astrago-deployment/issues)
- 📞 **긴급 지원**: +82-2-xxxx-xxxx (업무시간 내)

---

## 🔍 추가 참고 자료

- [Kubernetes 공식 문제 해결 가이드](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- [Helm 문제 해결](https://helm.sh/docs/faq/)
- [Docker 문제 해결](https://docs.docker.com/config/daemon/)
- [Prometheus 모니터링 가이드](https://prometheus.io/docs/guides/)
