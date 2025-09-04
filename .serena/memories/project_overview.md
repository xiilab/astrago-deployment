# Astrago Deployment 프로젝트 개요

## 프로젝트 구성
1. **Kubespray**: Kubernetes 클러스터 설치
2. **Airgap**: 오프라인 환경에서의 Kubernetes 준비 및 설치  
3. **Helmfile**: Astrago 및 관련 플랫폼 설치 (현재 리팩토링 대상)

## 기술 스택
- Helm 3.x
- Helmfile 0.150+
- Kubernetes 1.25+
- Flux CD (GitOps)
- Kustomize (패치 관리)

## 주요 애플리케이션
- Astrago (Core)
- GPU Operator (NVIDIA)
- CSI Driver NFS
- Prometheus & Loki (모니터링)
- Keycloak (인증)
- Harbor (레지스트리)
- MPI Operator (분산 컴퓨팅)

## 환경
- dev, dev2 (개발)
- stage (스테이징)
- prod (프로덕션)
- astrago (특수 환경)

## 코드 스타일
- YAML 파일 사용
- Go Template 문법 (gotmpl)
- 2 space 들여쓰기
- kebab-case 네이밍

## 주요 명령어
```bash
# Helmfile 적용
helmfile -e dev apply

# 차이점 확인
helmfile -e dev diff

# 린트
helmfile -e dev lint

# 동기화
helmfile -e dev sync
```

## 프로젝트 특징
- 설치형 솔루션 (On-premise)
- 고객 커스터마이징 요구 많음
- 멀티 환경 지원 필요