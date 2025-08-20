# 두산 AstraGo 환경 가이드

## 📋 개요

이 디렉토리는 **두산 고객사 전용 AstraGo 환경**을 위한 설정 파일입니다.

## 🎯 주요 특징

### **HTTPS 도메인 접근 지원**
- 인그레스 컨트롤러를 통한 도메인 기반 접근
- 자동 TLS 인증서 발급 (Let's Encrypt)
- 표준 HTTP/HTTPS 포트 (80/443) 사용

### **두산 전용 설정**
- 고유 이미지 태그 (`-doosan-latest`)
- 두산 특화 네트워크/스토리지 설정
- 강화된 보안 설정

## 🚀 배포 방법

### **1단계: 사전 설치**
```bash
# 인그레스 컨트롤러 및 cert-manager 설치
./scripts/install-ingress-controller.sh
```

### **2단계: 환경 설정 수정**
```bash
# environments/doosan/values.yaml 파일 수정
vi environments/doosan/values.yaml
```

**주요 수정 항목:**
- `externalIP`: 두산 클러스터 IP
- `ingress.hostname`: 두산 도메인 (예: astrago.doosan.com)
- `nfs.server`: 두산 NFS 서버 IP
- 각종 비밀번호들

### **3단계: DNS 설정**
```bash
# 두산 DNS 서버 또는 hosts 파일에서
astrago.doosan.com → 클러스터_노드_IP
```

### **4단계: 배포**
```bash
# 두산 환경으로 배포
./deploy_astrago.sh -e doosan sync
```

## 🔧 접근 방법

### **HTTPS 도메인 접근 (권장)**
```
https://astrago.doosan.com
```

### **직접 IP 접근 (fallback)**
```
http://클러스터_IP:30080
```

## 📊 환경 비교

| 구분 | dev/stage 환경 | 두산 환경 |
|------|----------------|-----------|
| **접근 방식** | NodePort (IP:30080) | 인그레스 (도메인) |
| **HTTPS** | 수동 설정 | 자동 인증서 |
| **이미지 태그** | 일반 태그 | doosan 전용 태그 |
| **보안** | 기본 설정 | 강화된 설정 |

## ⚠️ 주의사항

### **배포 전 확인사항**
1. **DNS 설정**: 도메인이 클러스터를 가리키는지 확인
2. **방화벽**: 80, 443 포트 오픈 확인
3. **인증서 이메일**: Let's Encrypt 이메일 주소 확인
4. **NFS 서버**: NFS 서버 접근 가능 여부 확인

### **보안 관련**
- 모든 기본 비밀번호는 두산 요구사항에 맞춰 변경
- 프로덕션 환경에서는 시크릿 관리 도구 사용 권장
- 정기적인 보안 업데이트 필요

### **이미지 관리**
- 두산 전용 이미지 태그 사용
- 이미지 업데이트 시 두산 승인 후 진행
- 태그 버전 관리 체계 준수

## 🛠 문제 해결

### **인그레스 문제**
```bash
# 인그레스 상태 확인
kubectl get ingress -n astrago

# 인그레스 컨트롤러 확인
kubectl get pods -n ingress-nginx
```

### **TLS 인증서 문제**
```bash
# 인증서 상태 확인
kubectl get certificates -n astrago

# cert-manager 로그 확인
kubectl logs -n cert-manager deployment/cert-manager
```

### **DNS 문제**
```bash
# 도메인 해석 확인
nslookup astrago.doosan.com

# 클러스터 내부에서 확인
kubectl run test --image=busybox -it --rm -- nslookup astrago.doosan.com
```

## 📞 지원

문제 발생 시 다음 정보와 함께 문의:
- 배포 환경 (두산)
- 오류 메시지
- kubectl 명령어 결과
- 로그 파일