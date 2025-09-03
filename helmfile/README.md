# Helmfile 구조

이 디렉토리는 Astrago 배포를 위한 통합 Helmfile 구조를 포함합니다.

## 📁 디렉토리 구조

```
helmfile/
├── helmfile.yaml           # 단일 통합 Helmfile 설정
├── charts/
│   ├── external/          # 오프라인용 다운로드된 외부 차트
│   ├── custom/            # 커스텀 Helm 차트
│   └── patches/           # Kustomize 패치 파일
├── values/
│   ├── common/            # 환경 간 공유되는 공통 values
│   └── templates/         # Go 템플릿 파일
└── environments/
    ├── dev/               # 개발 환경 설정
    ├── stage/             # 스테이징 환경 설정
    └── prod/              # 프로덕션 환경 설정
```

## 🎯 특징

- **단일 파일 관리**: 모든 releases를 `helmfile.yaml`에서 관리
- **오프라인 지원**: 모든 외부 차트가 `charts/external/`에 로컬 저장
- **Tier 기반 배포**: Infrastructure → Monitoring → Security → Applications 순서
- **환경별 분리**: 환경별 설정이 독립적으로 관리됨

## 🚀 사용법

### 배포
```bash
# 개발 환경
helmfile -e dev apply

# 스테이징 환경  
helmfile -e stage apply

# 프로덕션 환경
helmfile -e prod apply
```

### 검증
```bash
# 변경 사항 미리보기
helmfile -e dev diff

# 차트 검증
helmfile -e dev lint
```

## 📋 요구사항

- Helm 3.8+
- Helmfile 0.150+
- 오프라인 환경 지원을 위한 로컬 차트 저장

## ⚠️ 주의사항

- 모든 외부 차트는 `charts/external/`에 로컬 저장되어야 함
- 환경별 secrets는 암호화하여 저장
- 배포 전 반드시 `diff` 명령으로 변경사항 확인

---

**리팩토링 완료**: BE-385 Helmfile 구조 리팩토링의 일환으로 생성됨