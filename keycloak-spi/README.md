# Astrago Keycloak SPI

간단한 Keycloak SPI로 기본 attribute 3개를 추가합니다.

## 기능

- 기본 사용자 인증 (admin/admin123, user1/user123)
- **고정된 3개 attribute 추가**:
  - `workspaceCreateLimit`: "2"
  - `signUpPath`: "ASTRAGO"
  - `approvalYN`: "true"

## 빌드 및 배포

> **중요:**
> Docker 이미지를 빌드할 때는 항상 `mvn clean package -DskipTests`로 JAR 파일(`target/keycloak-astrago-spi-1.0.0-shaded.jar`)을 먼저 생성해야 합니다.

```bash
# 1. JAR 빌드 및 Docker Hub 푸시
cd keycloak-spi
mvn clean package -DskipTests
./build.sh

# 2. 배포
cd ../applications/keycloak
helmfile apply
```

## Docker Hub

이미지: `xiilab/astrago-keycloak-spi-userattribute:latest`

## 테스트

- **admin** / admin123
- **user1** / user123

## Attribute

모든 사용자에게 다음 attribute가 자동으로 추가됩니다:

- `workspaceCreateLimit`: "2"
- `signUpPath`: "ASTRAGO" 
- `approvalYN`: "true"

매우 간단하고 깔끔합니다! 