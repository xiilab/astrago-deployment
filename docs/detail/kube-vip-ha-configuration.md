# Kube-VIP를 이용한 Control Plane HA 구성 가이드

## 📋 목차

- [개요](#개요)
- [왜 HA 구성이 필요한가?](#왜-ha-구성이-필요한가)
- [Kube-VIP란?](#kube-vip란)
- [설정 방법](#설정-방법)
- [설정 항목 상세 설명](#설정-항목-상세-설명)
- [설정 확인 방법](#설정-확인-방법)
- [문제 해결](#문제-해결)
- [LoadBalancer Service 기능 (선택사항)](#loadbalancer-service-기능-선택사항)

---

## 개요

Kubernetes Control Plane의 고가용성(High Availability, HA)을 구성하기 위해 Kube-VIP를 사용하여 **Virtual IP(VIP)**를 설정합니다. 이를 통해 여러 Control Plane 노드 중 하나가 장애 발생 시에도 API 서버에 중단 없이 접근할 수 있습니다.

---

## 왜 HA 구성이 필요한가?

### 문제 상황: Single Control Plane

```
API 클라이언트 → Master Node (10.61.3.83:6443)
                      ↓
                   장애 발생!
                      ↓
                  ❌ 클러스터 접근 불가
```

**문제점:**
- Master 노드 장애 시 전체 클러스터 관리 불가
- API 서버 접근 불가 → `kubectl` 명령 실패
- 운영 중단 (Downtime 발생)

### 해결책: HA with Kube-VIP

```
API 클라이언트 → VIP (10.61.3.82:6443)
                      ↓
            ┌─────────┼─────────┐
            ↓         ↓         ↓
        Master-1  Master-2  Master-3
        (Leader)  (Standby) (Standby)
            ↓
        Master-1 장애 발생!
            ↓
        Master-2가 즉시 VIP 인수
            ↓
        ✅ 중단 없이 계속 서비스
```

**장점:**
- ✅ **무중단 서비스**: 노드 장애 시에도 자동 페일오버
- ✅ **단일 접근점**: 고정된 VIP로 항상 접근 가능
- ✅ **자동 복구**: Leader Election으로 자동 전환
- ✅ **운영 안정성**: 유지보수 시 무중단 작업 가능

---

## Kube-VIP란?

**Kube-VIP**는 Kubernetes를 위한 가상 IP 및 로드 밸런싱 솔루션입니다.

### 주요 기능

1. **Control Plane HA (고가용성)**
   - 여러 Control Plane 노드에 단일 VIP 제공
   - Leader Election을 통한 자동 페일오버
   - ARP/BGP를 통한 네트워크 광고

2. **LoadBalancer Service (선택사항)**
   - `type: LoadBalancer` Service에 External IP 자동 할당
   - 온프레미스 환경에서 클라우드와 동일한 경험 제공

### 동작 방식

```
1. Kube-VIP Pod가 각 Control Plane 노드에서 실행 (Static Pod)
2. Leader Election을 통해 하나의 노드가 Leader로 선출
3. Leader 노드가 VIP를 자신의 네트워크 인터페이스에 할당
4. ARP 브로드캐스트로 네트워크에 VIP 위치 알림
5. Leader 노드 장애 시, 다른 노드가 즉시 VIP 인수
```

---

## 설정 방법

### 필수 파일 수정

Kube-VIP HA 구성을 위해 다음 2개 파일을 수정해야 합니다.

#### 1️⃣ `/kubespray/inventory/mycluster/group_vars/k8s_cluster/addons.yml`

```yaml
# Kube VIP
kube_vip_enabled: true
kube_vip_arp_enabled: true
kube_vip_controlplane_enabled: true
kube_vip_address: 10.61.3.82  # ← 고객사별 부여받은 VIP (변경 필요!)
kube_vip_port: 6443
kube_vip_version: 0.8.2
loadbalancer_apiserver:
  address: "{{ kube_vip_address }}"
  port: 6443
kube_vip_interface: ""
kube_vip_services_enabled: false  # LoadBalancer Service 기능 (기본: 비활성화)
```

#### 2️⃣ `/kubespray/inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`

```yaml
# Kube-proxy proxyMode configuration.
# Can be ipvs, iptables
kube_proxy_mode: ipvs

# configure arp_ignore and arp_announce to avoid answering ARP queries from kube-ipvs0 interface
# must be set to true for MetalLB, kube-vip(ARP enabled) to work
kube_proxy_strict_arp: true  # ← false에서 true로 변경 (필수!)
```

---

## 설정 항목 상세 설명

### addons.yml 설정 항목

| 설정 항목 | 설명 | 기본값 | 변경 필요 여부 |
|----------|------|--------|--------------|
| `kube_vip_enabled` | Kube-VIP 기능 전체 활성화/비활성화 | `false` | ✅ **`true`로 변경** |
| `kube_vip_arp_enabled` | ARP 모드 활성화 (L2 네트워크) | `false` | ✅ **`true`로 변경** |
| `kube_vip_controlplane_enabled` | Control Plane HA 기능 활성화 | `false` | ✅ **`true`로 변경** |
| `kube_vip_address` | API 서버 접근용 Virtual IP | - | ✅ **고객사 환경에 맞게 설정** |
| `kube_vip_port` | API 서버 포트 | `6443` | ⚪ 변경 불필요 (표준 포트) |
| `kube_vip_version` | Kube-VIP 버전 | `0.8.2` | ⚪ 변경 불필요 |
| `loadbalancer_apiserver.address` | kubectl이 사용할 API 서버 주소 | - | ✅ **VIP 주소와 동일하게** |
| `loadbalancer_apiserver.port` | API 서버 포트 | `6443` | ⚪ 변경 불필요 |
| `kube_vip_interface` | VIP를 할당할 네트워크 인터페이스 | `""` (자동 감지) | ⚪ 대부분 비워둠 |
| `kube_vip_services_enabled` | LoadBalancer Service 기능 | `false` | ⚪ 필요 시 `true` |

### 주요 설정 설명

#### `kube_vip_address` (가장 중요!)

**설명:** Control Plane에 접근하기 위한 가상 IP 주소입니다.

**설정 기준:**
- ✅ Control Plane 노드들과 **동일한 서브넷**에 있어야 함
- ✅ **사용되지 않는 IP**여야 함 (다른 장비와 충돌 방지)
- ✅ Control Plane 노드 IP와 **다른 IP**여야 함
- ✅ 네트워크 정책상 허용된 IP여야 함

**예시:**
```yaml
# 환경 예시
Control Plane Nodes:
  - Master-1: 10.61.3.83
  - Master-2: 10.61.3.84
  - Master-3: 10.61.3.85

# VIP 설정
kube_vip_address: 10.61.3.82  # ← 같은 대역, 미사용 IP
```


## 설정 확인 방법

### 1. 클러스터 설치/재설치

```bash
쿠버네티스 재설치
```

### 2. VIP 네트워크 연결 확인

```bash
# VIP Ping 테스트
ping -c 3 10.61.3.82

# 예상 출력
64 bytes from 10.61.3.82: icmp_seq=1 ttl=64 time=1.5 ms
```

### 3. API 서버 VIP 접근 테스트

```bash
# VIP를 통한 API 서버 버전 조회
curl -k https://10.61.3.82:6443/version

# 예상 출력
{
  "major": "1",
  "minor": "28",
  "gitVersion": "v1.28.6",
  "gitCommit": "be3af46a4654bdf05b4838fe94e95ec8c165660c",
  "gitTreeState": "clean",
  "buildDate": "2024-01-17T13:39:00Z",
  "goVersion": "go1.20.13",
  "compiler": "gc",
  "platform": "linux/amd64"
}

# VIP를 통한 노드 목록 조회
kubectl get nodes --server=https://10.61.3.82:6443 --insecure-skip-tls-verify

# 예상 출력
NAME       STATUS   ROLES           AGE     VERSION
master-1   Ready    control-plane   3d18h   v1.28.6
master-2   Ready    control-plane   3d18h   v1.28.6
master-3   Ready    control-plane   3d18h   v1.28.6
```

### 5. kubectl config 확인

```bash
# kubectl이 사용하는 API 서버 주소 확인
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'

# 예상 출력 (둘 중 하나)
https://lb-apiserver.kubernetes.local:6443  # ← 도메인 (권장)
# 또는
https://10.61.3.82:6443  # ← 직접 VIP
```

```bash
# 도메인이 VIP로 해석되는지 확인
nslookup lb-apiserver.kubernetes.local

# 예상 출력
Name:    lb-apiserver.kubernetes.local
Address: 10.61.3.82  # ← VIP와 일치해야 함!
```

### 6. VIP 할당 노드 확인 (Leader 확인)

```bash
# Control Plane 노드에 SSH 접속
ssh <control-plane-node>

# VIP가 할당된 인터페이스 확인
ip addr show | grep 10.61.3.82

# 예상 출력 (Leader 노드에서만)
inet 10.61.3.82/32 scope global eth0
```

### 7. Kube-VIP 로그 확인

```bash
# Kube-VIP Pod 이름 확인
kubectl get pods -n kube-system | grep kube-vip

# 로그 확인
kubectl logs -n kube-system kube-vip-master-1

# 정상 로그 예시
[INFO] Starting kube-vip
[INFO] VIP address: 10.61.3.82
[INFO] Elected as leader
[INFO] Broadcasting ARP for 10.61.3.82
[INFO] VIP assigned to interface ens192
```
