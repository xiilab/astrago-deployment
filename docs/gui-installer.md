# 🖥️ Astrago GUI 인스톨러 가이드

## 📋 개요

Astrago GUI 인스톨러는 **터미널 기반의 대화형 인터페이스**를 제공하여 Astrago 플랫폼을 쉽게 설치하고 관리할 수 있도록 도와주는 도구입니다. Python curses 라이브러리를 사용하여 직관적인 사용자 경험을 제공합니다.

## 🎯 주요 기능

- 🖱️ **대화형 메뉴**: 마우스 없이 키보드로 조작 가능한 TUI
- 🏗️ **Kubernetes 클러스터 설치**: Kubespray를 통한 자동 설치
- 📦 **NFS 서버 설정**: 공유 스토리지 자동 구성
- 🖥️ **GPU 드라이버 설치**: GPU 리소스 활용을 위한 드라이버 설치
- 🚀 **Astrago 배포**: 전체 애플리케이션 스택 배포
- 📊 **실시간 로그**: 설치 과정의 실시간 모니터링

## 🚀 시작하기

### 실행 방법

```bash
# GUI 인스톨러 실행
python3 astrago_gui_installer.py

# 또는 스크립트를 통한 실행
./run_gui_installer.sh
```

### 시스템 요구사항

- **Python**: 3.8 이상
- **OS**: Linux (CentOS/RHEL 7/8, Ubuntu 18.04/20.04)
- **터미널**: 최소 80x24 크기 권장
- **권한**: sudo 권한 필요

## 🖥️ 인터페이스 구성

### 메인 메뉴

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              🚀 Astrago Installer v1.0                                 │
│                         AI/ML Platform Deployment Tool                                  │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   ► 1. 노드 설정 관리                                                                     │
│     2. NFS 서버 설정                                                                      │
│     3. Kubernetes 설치 관리                                                               │
│     4. Astrago 설치 관리                                                                  │
│     5. 시스템 종료                                                                        │
│                                                                                         │
│   ↑↓: 선택   Enter: 실행   ESC: 종료                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 화면 구성 요소

1. **헤더 영역**: 로고 및 제목 표시
2. **메뉴 영역**: 선택 가능한 메뉴 목록
3. **상태 영역**: 현재 설정 상태 표시
4. **도움말 영역**: 키보드 단축키 안내

## 🔧 세부 기능 가이드

### 1. 노드 설정 관리

#### 노드 추가
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    노드 추가                                             │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   노드 이름: [worker-1        ]                                                          │
│   IP 주소  : [192.168.1.101   ]                                                          │
│   역할     : [kube-master     ] ▼                                                        │
│   ETCD     : [Y] Y/N                                                                     │
│                                                                                         │
│   [ 추가 ]  [ 취소 ]                                                                     │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

**노드 역할 옵션:**
- `kube-master`: Kubernetes 마스터 노드
- `kube-node`: Kubernetes 워커 노드
- `kube-master,kube-node`: 마스터/워커 역할 겸용

#### 노드 목록 관리
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    노드 목록                                             │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   ┌─────────────────┬────────────────┬──────────────────┬──────────┐                   │
│   │ 노드 이름       │ IP 주소        │ 역할             │ ETCD     │                   │
│   ├─────────────────┼────────────────┼──────────────────┼──────────┤                   │
│ ► │ master-1        │ 192.168.1.100  │ kube-master      │ Y        │                   │
│   │ worker-1        │ 192.168.1.101  │ kube-node        │ N        │                   │
│   │ worker-2        │ 192.168.1.102  │ kube-node        │ N        │                   │
│   └─────────────────┴────────────────┴──────────────────┴──────────┘                   │
│                                                                                         │
│   Enter: 편집   Delete: 삭제   Insert: 추가   ESC: 뒤로                                  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2. NFS 서버 설정

#### NFS 설정 화면
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                  NFS 서버 설정                                           │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   NFS 서버 IP: [192.168.1.200 ]                                                         │
│   공유 경로  : [/nfs-data      ]                                                         │
│                                                                                         │
│   현재 설정:                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │ IP: 192.168.1.200                                                              │   │
│   │ Path: /nfs-data                                                                │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│   [ 저장 ]  [ 취소 ]                                                                     │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3. Kubernetes 설치 관리

#### Kubernetes 설치 메뉴
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                               Kubernetes 관리                                           │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   ► 1. Kubernetes 클러스터 설치                                                           │
│     2. Kubernetes 클러스터 초기화                                                         │
│     3. NFS 서버 설치                                                                      │
│     4. GPU 드라이버 설치                                                                  │
│     5. 뒤로 가기                                                                          │
│                                                                                         │
│   상태: 클러스터 미설치                                                                    │
│                                                                                         │
│   ↑↓: 선택   Enter: 실행   ESC: 뒤로                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

#### 실시간 설치 로그
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                            Kubernetes 설치 진행중                                        │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│ TASK [kubernetes/kubeadm : kubeadm | Initialize first master]                           │
│ ok: [master-1]                                                                          │
│                                                                                         │
│ TASK [kubernetes/kubeadm : slurp kubeconfig]                                             │
│ ok: [master-1]                                                                          │
│                                                                                         │
│ TASK [kubernetes/node : install | Copy kubectl binary from download dir]                │
│ changed: [worker-1]                                                                     │
│ changed: [worker-2]                                                                     │
│                                                                                         │
│ ● 진행률: [████████████████████████████████████████████████] 85%                        │
│                                                                                         │
│   ESC: 취소   Ctrl+C: 강제 종료                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4. Astrago 설치 관리

#### Astrago 설치 메뉴
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                Astrago 관리                                             │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   ► 1. Astrago 설치                                                                      │
│     2. Astrago 제거                                                                      │
│     3. 뒤로 가기                                                                          │
│                                                                                         │
│   상태: 미설치                                                                            │
│   외부 URL: http://192.168.1.100:30080                                                  │
│                                                                                         │
│   ↑↓: 선택   Enter: 실행   ESC: 뒤로                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## ⌨️ 키보드 단축키

### 기본 조작
- **↑/↓**: 메뉴 선택 이동
- **Enter**: 선택 실행
- **ESC**: 이전 메뉴로 돌아가기
- **Tab**: 입력 필드 간 이동

### 목록 관리
- **Insert**: 새 항목 추가
- **Delete**: 선택된 항목 삭제
- **F2**: 편집 모드
- **F5**: 새로고침

### 설치 중 조작
- **Ctrl+C**: 강제 종료
- **Space**: 일시 정지/재개
- **Page Up/Down**: 로그 스크롤

## 🔧 고급 설정

### 환경 변수 설정

```bash
# 기본 사용자명 설정
export ANSIBLE_USER="admin"

# 기본 비밀번호 설정 (보안상 권장하지 않음)
export ANSIBLE_PASSWORD="password"

# SSH 타임아웃 설정
export ANSIBLE_SSH_TIMEOUT="60"

# GUI 인스톨러 실행
python3 astrago_gui_installer.py
```

### 설정 파일 커스터마이징

#### nodes.yaml 예시
```yaml
- name: master-1
  ip: 192.168.1.100
  role: kube-master
  etcd: Y
- name: worker-1
  ip: 192.168.1.101
  role: kube-node
  etcd: N
- name: worker-2
  ip: 192.168.1.102
  role: kube-node
  etcd: N
```

#### nfs-servers.yaml 예시
```yaml
ip: 192.168.1.200
path: /nfs-data/astrago
```

## 🚨 문제 해결

### 일반적인 문제들

#### 1. 터미널 크기 문제
```
오류: 터미널 크기가 너무 작습니다 (최소 80x24 필요)
해결: 터미널 창 크기를 조정하거나 글꼴 크기를 줄이세요
```

#### 2. Python 의존성 문제
```bash
# 필요한 Python 패키지 설치
pip3 install pyyaml curses

# CentOS/RHEL에서
yum install -y python3-pyyaml ncurses-devel
```

#### 3. SSH 연결 실패
```
오류: SSH 연결 실패 - 호스트에 연결할 수 없습니다
해결 방법:
1. 네트워크 연결 확인
2. SSH 서비스 상태 확인
3. 방화벽 설정 확인
4. SSH 키 또는 패스워드 확인
```

#### 4. 권한 부족 오류
```bash
# sudo 권한 확인
sudo -l

# passwordless sudo 설정 (선택사항)
echo "username ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers
```

### 로그 파일 위치

```bash
# GUI 인스톨러 로그
tail -f /tmp/astrago-installer.log

# Ansible 실행 로그
tail -f /tmp/ansible-playbook.log

# Kubernetes 설치 로그
tail -f /var/log/kubespray-install.log
```

## 🎨 인터페이스 커스터마이징

### 색상 테마 변경

```python
# astrago_gui_installer.py 파일에서
COLORS = {
    'header': curses.color_pair(1),      # 파란색
    'menu': curses.color_pair(2),        # 흰색
    'selected': curses.color_pair(3),    # 노란색
    'error': curses.color_pair(4),       # 빨간색
    'success': curses.color_pair(5)      # 초록색
}
```

### 화면 레이아웃 수정

```python
# 메뉴 위치 조정
MENU_START_Y = 8
MENU_START_X = 4
MENU_WIDTH = 60
MENU_HEIGHT = 15

# 상태 표시 영역
STATUS_Y = 20
STATUS_X = 4
```

## 📊 모니터링 및 로깅

### 설치 진행 상황 모니터링

```bash
# 별도 터미널에서 실시간 모니터링
watch -n 1 "kubectl get pods -A"

# 로그 실시간 확인
tail -f /var/log/astrago-installer.log | grep -E "(ERROR|WARN|INFO)"
```

### 성능 메트릭 수집

```python
# 설치 시간 측정
import time

start_time = time.time()
# 설치 과정 실행
end_time = time.time()
installation_time = end_time - start_time

print(f"설치 완료 시간: {installation_time:.2f}초")
```

## 🔒 보안 고려사항

### 자격 증명 보호

```bash
# SSH 키 기반 인증 사용 (권장)
ssh-keygen -t rsa -b 4096
ssh-copy-id user@target-host

# 패스워드 기반 인증시 안전한 입력
# (GUI에서 별표로 마스킹 처리됨)
```

### 네트워크 보안

```bash
# 방화벽 설정 확인
firewall-cmd --list-all

# 필요한 포트만 개방
firewall-cmd --add-port=22/tcp --permanent  # SSH
firewall-cmd --add-port=6443/tcp --permanent  # Kubernetes API
firewall-cmd --reload
```

## 📚 참고 자료

### 관련 문서
- [설치 가이드](installation-guide.md)
- [문제 해결 가이드](troubleshooting.md)
- [Kubespray 공식 문서](https://kubespray.io/)

### 유용한 명령어

```bash
# 클러스터 상태 확인
kubectl cluster-info
kubectl get nodes

# 애플리케이션 상태 확인
helmfile -e astrago status

# 로그 수집
kubectl logs -f deployment/astrago-core -n astrago
```

## 🆘 지원 및 문의

GUI 인스톨러 사용 중 문제가 발생하면:

1. **로그 파일 확인**: `/tmp/astrago-installer.log`
2. **스크린샷 캡처**: 오류 화면 스크린샷
3. **시스템 정보 수집**: OS, Python 버전 등
4. **GitHub Issues 생성**: 상세한 오류 정보와 함께 이슈 등록

**연락처:**
- 📧 이메일: support@astrago.io
- 💬 Slack: #astrago-support
- 🐛 GitHub: [Issues](https://github.com/your-org/astrago-deployment/issues) 