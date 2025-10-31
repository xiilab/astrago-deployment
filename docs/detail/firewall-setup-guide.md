# Kubernetes 클러스터 방화벽 설정 가이드

## 📋 개요

이 가이드는 Astrago Kubernetes 클러스터에서 방화벽을 활성화하면서도 모든 서비스가 정상적으로 작동할 수 있도록 하는 설정 방법을 제공합니다.

## 🔍 분석된 애플리케이션 포트

### 외부 노출 서비스 (NodePort)
| 포트 | 서비스 | 네임스페이스 | 설명 |
|------|--------|-------------|------|
| 30080 | nginx-service | astrago | Astrago 메인 웹 UI |
| 30081 | astrago-backend-core | astrago | Core API 서버 |
| 30082 | astrago-backend-batch | astrago | Batch API 서버 |
| 30083 | astrago-backend-monitor | astrago | Monitor API 서버 |
| 30005 | astrago-time-prediction | astrago | Time Prediction API |
| 30010 | astrago-mariadb | astrago | MariaDB 데이터베이스 |
| 30001 | keycloak | keycloak | 인증 서버 |
| 32145 | prometheus-grafana | prometheus | Grafana 대시보드 |
| 30903 | prometheus-alertmanager | prometheus | Alertmanager |
| 31481 | prometheus-alertmanager-web | prometheus | Alertmanager 웹UI |
| 30090 | prometheus | prometheus | Prometheus 메트릭 |
| 32127 | prometheus-web | prometheus | Prometheus 웹UI |

### 내부 서비스 (ClusterIP)
| 포트 | 서비스 | 설명 |
|------|--------|------|
| 3100 | loki-stack-loki | 로그 수집 서버 |
| 9400 | nvidia-dcgm-exporter | GPU 메트릭 수집 |
| 5555 | nvidia-dcgm | GPU 관리 서비스 |
| 8080 | 각종 백엔드 | 애플리케이션 서버들 |
| 3000 | astrago-frontend | 프론트엔드 서버 |
| 3306 | MariaDB | 데이터베이스 |
| 8000 | Time Prediction | AI 모델 서버 |

## 🚀 설정 방법

### 방법 1: 통합 스크립트 사용 (권장)

```bash
# 1. 통합 스크립트 실행
./scripts/setup-k8s-firewall.sh

# 2. 설정 방법 선택
# - 1: Ansible 기반 설정 (권장)
# - 2: 동적 스크립트 설정
# - 3: 둘 다 실행
# - 4: 설정 확인만
```

### 방법 2: Ansible 기반 설정

```bash
# 1. Ansible 설치 (필요한 경우)
yum install -y ansible

# 2. 인벤토리 파일 확인/수정
vim ansible/k8s-hosts.ini

# 3. 플레이북 실행
ansible-playbook -i ansible/k8s-hosts.ini ansible/k8s-firewall-playbook.yml -v
```

### 방법 3: 동적 스크립트 설정

```bash
# 1. 동적 스크립트 실행
./scripts/dynamic-firewall-setup.sh

# 2. 로컬 노드만 설정하려면
./scripts/dynamic-firewall-setup.sh --local-only
```

## 🔧 필수 포트 목록

### Kubernetes 기본 포트
- **6443/tcp** - API Server
- **2379-2380/tcp** - etcd
- **10250/tcp** - kubelet
- **10257/tcp** - controller-manager
- **10259/tcp** - scheduler
- **10256/tcp** - kubelet health

### CNI 네트워크 (Calico)
- **179/tcp** - BGP
- **4789/udp** - VXLAN

### DNS 서비스
- **53/tcp** - DNS TCP
- **53/udp** - DNS UDP
- **9153/tcp** - CoreDNS metrics

### 웹 서비스
- **80/tcp** - HTTP
- **443/tcp** - HTTPS

### 모니터링
- **9100/tcp** - Node Exporter
- **9400/tcp** - DCGM Exporter

### 스토리지
- **35000/tcp** - Docker Registry
- **NFS 서비스** - nfs, rpc-bind, mountd

### NodePort 범위
- **30000-32767/tcp** - NodePort 서비스들

## 🌐 네트워크 설정

### 신뢰 네트워크
- **노드 네트워크**: 10.61.3.0/24
- **Pod 네트워크**: 10.233.0.0/16

### 마스커레이드
- **활성화 필수**: Kubernetes 네트워킹을 위해 필수

## ✅ 설정 확인

### 1. 방화벽 상태 확인
```bash
# 모든 노드에서 확인
./scripts/setup-k8s-firewall.sh verify

# 개별 노드 확인
firewall-cmd --list-all
```

### 2. 서비스 접근성 테스트
```bash
# API Server
curl -k https://localhost:6443/healthz

# Astrago UI
curl http://localhost:30080

# Prometheus
curl http://localhost:30090/-/healthy
```

### 3. 클러스터 상태 확인
```bash
# Pod 상태
kubectl get pods --all-namespaces

# 서비스 상태
kubectl get svc --all-namespaces

# 노드 상태
kubectl get nodes
```

## 🔧 문제 해결

### 1. 방화벽 설정 후 서비스 접근 불가
```bash
# 방화벽 로그 확인
journalctl -u firewalld -f

# 포트 확인
firewall-cmd --list-ports

# 임시로 특정 포트 열기
firewall-cmd --add-port=PORT/tcp
firewall-cmd --permanent --add-port=PORT/tcp
firewall-cmd --reload
```

### 2. Pod 간 통신 문제
```bash
# 마스커레이드 확인
firewall-cmd --query-masquerade

# 신뢰 네트워크 확인
firewall-cmd --list-rich-rules

# 임시 해결
firewall-cmd --add-masquerade
firewall-cmd --permanent --add-masquerade
```

### 3. 노드 간 통신 문제
```bash
# 노드 네트워크 신뢰 추가
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='10.61.3.0/24' accept"
firewall-cmd --reload
```

## 📊 성능 영향

### 방화벽 활성화 시 예상 영향
- **CPU 사용률**: 1-3% 증가
- **네트워크 지연**: 0.1-0.5ms 증가
- **메모리 사용**: 10-50MB 증가

### 최적화 권장사항
1. **Rich Rules 최소화**: 필요한 규칙만 사용
2. **포트 범위 사용**: 개별 포트보다 범위 사용
3. **로깅 최소화**: 필요한 경우만 로깅 활성화

## 🔄 자동화 옵션

### 1. Cron 기반 자동 점검
```bash
# 매일 자정에 방화벽 상태 점검
0 0 * * * /root/astrago-deployment-2/scripts/setup-k8s-firewall.sh verify
```

### 2. 서비스 변경 시 자동 업데이트
```bash
# kubectl 이벤트 모니터링
kubectl get events --watch | while read event; do
    if [[ $event == *"Service"* ]]; then
        ./scripts/dynamic-firewall-setup.sh --local-only
    fi
done
```

## 📝 주의사항

1. **백업**: 방화벽 설정 전 현재 설정 백업
2. **테스트**: 프로덕션 환경 적용 전 테스트 환경에서 검증
3. **모니터링**: 설정 후 24시간 동안 모니터링
4. **롤백 계획**: 문제 발생 시 즉시 롤백할 수 있는 계획 수립

## 🆘 응급 복구

### 방화벽 완전 비활성화
```bash
# 모든 노드에서 실행
systemctl stop firewalld
systemctl disable firewalld

# 또는 모든 트래픽 허용
firewall-cmd --set-default-zone=trusted
```

### 기본 설정 복원
```bash
# 방화벽 설정 초기화
firewall-cmd --complete-reload
firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='10.61.3.0/24' accept"
firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='10.233.0.0/16' accept"
``` 