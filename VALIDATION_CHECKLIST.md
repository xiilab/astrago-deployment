# 🔍 Astrago 배포 스크립트 검증 체크리스트

## 📋 개선사항 요약

### 🚀 주요 개선점

1. **Python 버전 호환성 강화**
   - 동적 Python 버전 감지 (3.12, 3.11, 3.10, 3.9 지원)
   - 가상 환경 자동 생성 및 관리
   - OS별 Python 버전 자동 선택

2. **시스템 요구사항 검증**
   - OS 자동 감지 및 지원 여부 확인
   - 필수 명령어 존재 여부 확인
   - 디스크 공간 검사
   - 의존성 자동 설치

3. **입력 검증 강화**
   - IP 주소 형식 검증
   - URL 형식 검증
   - 노드 이름 Kubernetes 표준 준수 검증
   - 빈 값 입력 방지

4. **에러 핸들링 개선**
   - 모든 명령어에 에러 체크 추가
   - 명확한 에러 메시지 출력
   - 파일 권한 검사 강화
   - Graceful failure 처리

5. **사용자 경험 개선**
   - 컬러 출력으로 가독성 향상
   - 진행 상황 실시간 표시
   - 명확한 성공/실패 메시지
   - 상세한 상태 정보 제공

## 🧪 테스트 시나리오

### 1. 환경 설정 테스트

#### 온라인 모드
```bash
# 1. 환경 설정
./deploy_astrago_unified.sh env

# 입력값 예시:
# External IP: 192.168.1.100
# NFS Server IP: 192.168.1.101
# NFS Base Path: /mnt/nfs
```

#### 오프라인 모드
```bash
# 1. 환경 설정
./deploy_astrago_unified.sh --mode offline env

# 추가 입력값:
# Offline Registry: 192.168.1.102:35000
# HTTP Server: http://192.168.1.102
```

### 2. 클러스터 배포 테스트

#### 온라인 모드
```bash
# 1. 클러스터 배포
./deploy_astrago_unified.sh --mode online cluster

# 노드 정보 입력:
# Node Name: master-01
# IP Address: 192.168.1.100
# Roles: kube-master,kube-node
# Include in etcd: Y

# SSH 정보:
# SSH Username: ubuntu
# SSH Password: ****
```

#### 오프라인 모드
```bash
# 1. 오프라인 패키지 준비
./deploy_astrago_unified.sh --mode offline prepare

# 2. 클러스터 배포
./deploy_astrago_unified.sh --mode offline cluster
```

### 3. 애플리케이션 배포 테스트

```bash
# 모든 애플리케이션 배포
./deploy_astrago_unified.sh sync

# 특정 애플리케이션 배포
./deploy_astrago_unified.sh sync --app keycloak

# 상태 확인
./deploy_astrago_unified.sh status
```

## ✅ 사전 요구사항 체크리스트

### 시스템 요구사항
- [ ] Ubuntu 20.04/22.04/24.04 또는 RHEL/CentOS 8/9
- [ ] Python 3.9 이상 설치됨
- [ ] 최소 10GB 여유 디스크 공간
- [ ] Git, curl, wget 설치됨
- [ ] sudo 권한 보유

### 네트워크 요구사항
- [ ] 모든 노드 간 SSH 연결 가능
- [ ] 온라인 모드: 인터넷 연결 가능
- [ ] 오프라인 모드: 로컬 레지스트리 및 HTTP 서버 준비됨

### 파일 권한
- [ ] 스크립트 실행 권한 (`chmod +x deploy_astrago_unified.sh`)
- [ ] tools/linux/ 디렉토리의 바이너리 파일들 존재
- [ ] 환경 설정 파일 쓰기 권한

## 🔧 테스트 환경 구성

### 최소 테스트 환경
```
Master Node: 192.168.1.100 (4GB RAM, 2CPU)
Worker Node: 192.168.1.101 (4GB RAM, 2CPU)
NFS Server: 192.168.1.102 (Storage)
```

### 오프라인 테스트 추가 요구사항
```
Registry Server: 192.168.1.102:35000
HTTP Server: http://192.168.1.102
```

## 🎯 핵심 검증 포인트

### 1. 스크립트 실행 검증
- [ ] `./deploy_astrago_unified.sh --help` 도움말 표시
- [ ] `./deploy_astrago_unified.sh status` 상태 확인
- [ ] 컬러 출력 정상 작동
- [ ] 에러 메시지 명확성

### 2. Python 환경 검증
- [ ] 자동 Python 버전 감지
- [ ] 가상환경 자동 생성
- [ ] pip 의존성 설치
- [ ] ansible 명령어 실행 가능

### 3. 입력 검증
- [ ] 잘못된 IP 주소 거부
- [ ] 중복 노드 이름/IP 감지
- [ ] 빈 값 입력 거부
- [ ] 파일 권한 에러 감지

### 4. 클러스터 배포 검증
- [ ] kubespray 인벤토리 생성
- [ ] SSH 연결 테스트
- [ ] ansible playbook 실행
- [ ] kubeconfig 설정
- [ ] 클러스터 상태 확인

### 5. 애플리케이션 배포 검증
- [ ] helmfile 설정 로드
- [ ] 헬름 차트 배포
- [ ] 애플리케이션 상태 확인
- [ ] 서비스 접근 가능성

## 🚨 알려진 제한사항 및 해결방안

### 1. Python 3.9 미만 버전
**문제**: Ansible 호환성
**해결**: 시스템 패키지 매니저로 Python 3.9+ 설치

### 2. SELinux 활성화 (RHEL/CentOS)
**문제**: 권한 에러 발생 가능
**해결**: `setenforce 0` 또는 SELinux 정책 조정

### 3. 방화벽 설정
**문제**: 포트 차단으로 인한 연결 실패
**해결**: 필요 포트 개방 (6443, 2379-2380, 10250-10252)

### 4. 메모리 부족
**문제**: 설치 중 OOM 에러
**해결**: 최소 4GB RAM 권장, swap 활성화

## 📊 성능 벤치마크

### 예상 설치 시간
- **환경 설정**: 5-10분
- **오프라인 패키지 다운로드**: 30-60분
- **클러스터 배포**: 15-30분
- **애플리케이션 배포**: 10-20분

### 리소스 사용량
- **디스크**: 10-20GB
- **메모리**: 2-4GB (설치 중)
- **네트워크**: 5-10GB (온라인 모드)

## 🔒 보안 고려사항

### SSH 보안
- [ ] SSH 키 기반 인증 권장
- [ ] 강력한 패스워드 사용
- [ ] SSH 포트 기본값 변경 고려

### 네트워크 보안
- [ ] 방화벽 규칙 최소화
- [ ] 내부 네트워크 사용 권장
- [ ] TLS 인증서 검증

## 📞 문제 해결 가이드

### 일반적인 오류와 해결방법

1. **"Python 3.9+ not found"**
   ```bash
   # Ubuntu
   sudo apt update && sudo apt install python3.11 python3.11-venv
   
   # RHEL/CentOS
   sudo dnf install python3.11
   ```

2. **"Cannot create virtual environment"**
   ```bash
   # 디스크 공간 확인
   df -h
   # 권한 확인
   ls -la ~/.venv/
   ```

3. **"SSH connection failed"**
   ```bash
   # SSH 연결 테스트
   ssh user@target-host
   # SSH 서비스 상태 확인
   systemctl status ssh
   ```

4. **"Kubernetes cluster not accessible"**
   ```bash
   # kubeconfig 확인
   ls -la ~/.kube/config
   # 클러스터 상태 확인
   kubectl get nodes
   ```

## 🎯 테스트 완료 기준

### 성공 기준
- [ ] 모든 노드가 Ready 상태
- [ ] 모든 시스템 파드 Running 상태
- [ ] 애플리케이션 정상 배포
- [ ] 웹 UI 접근 가능
- [ ] 로그 수집 정상 작동

### 최종 검증 명령어
```bash
# 클러스터 상태
kubectl get nodes -o wide
kubectl get pods -A

# 애플리케이션 상태
./deploy_astrago_unified.sh status

# 서비스 접근성 테스트
curl http://<external-ip>:30080  # Astrago UI
curl http://<external-ip>:30001  # Keycloak
curl http://<external-ip>:30002  # Harbor
```

## 📈 다음 주 설치 준비사항

### 사전 준비 (금요일까지)
1. [ ] 대상 서버 OS 설치 및 기본 설정
2. [ ] 네트워크 구성 및 방화벽 설정
3. [ ] SSH 키 배포 및 접근 권한 설정
4. [ ] 오프라인 모드인 경우 패키지 다운로드 실행

### 설치 당일
1. [ ] 최종 시스템 요구사항 확인
2. [ ] 네트워크 연결성 테스트
3. [ ] 스크립트 실행 및 단계별 진행
4. [ ] 설치 완료 후 검증 테스트

### 백업 계획
1. [ ] 설치 로그 수집 및 보관
2. [ ] 설정 파일 백업
3. [ ] 문제 발생 시 롤백 절차 준비

---

**⚠️ 중요**: 프로덕션 환경 설치 전 반드시 테스트 환경에서 전체 시나리오를 검증하세요.
**📞 지원**: 설치 중 문제 발생 시 즉시 기술 지원팀에 연락하세요.