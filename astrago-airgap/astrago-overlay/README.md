# Astrago Overlay for kubespray-offline

이 디렉토리는 kubespray-offline 위에 Astrago 특화 기능을 추가하는 오버레이입니다.

## 구조

- `configs/`: Astrago 전용 설정 파일들
- `images/`: Helmfile 연동 이미지 관리
- `scripts/`: 4단계 배포 자동화 스크립트

## 사용법

```bash
# 1. kubespray-offline 업데이트 (필요시)
make update-kubespray

# 2. Astrago 오프라인 패키지 생성
make build

# 3. 오프라인 환경에 배포
make deploy
```

## kubespray-offline 업데이트

```bash
# 최신 버전으로 업데이트
./update-kubespray.sh

# 특정 태그로 업데이트
./update-kubespray.sh v1.2.3
```