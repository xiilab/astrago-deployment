# Keycloak SPI (Service Provider Interface) 매뉴얼

## 개요

Astrago Keycloak SPI는 LDAP 사용자 로그인 시 자동으로 3가지 기본 속성을 추가하는 커스텀 Event Listener SPI입니다.

## 주요 구성 요소

### 1. uyuni-login-theme과 SPI 통합 (Dockerfile)

Keycloak SPI 이미지에서 **SPI JAR과 Theme JAR을 모두 함께 처리**합니다.

- **SPI JAR**: Maven 빌드 결과물을 복사
- **Theme JAR**: wget으로 GitHub에서 다운로드
- **최종 위치**: 둘 다 `/opt/bitnami/keycloak/providers/`에 위치

```dockerfile
# SPI JAR 복사
COPY target/keycloak-astrago-spi-1.0.0.jar /opt/bitnami/keycloak/providers/

# Theme JAR 다운로드
RUN wget -O /opt/bitnami/keycloak/providers/keycloak-theme.jar \
    https://github.com/xiilab/uyuni-login-theme/releases/download/v1.1.16/keycloak-theme.jar

# 전체 디렉토리 권한 설정
RUN chown -R 1001:1001 /opt/bitnami/keycloak/providers/
```

### 2. SPI와 Theme 경로

**SPI JAR 파일과 Theme JAR 파일은 모두 같은 경로에 위치합니다:**

```
/opt/bitnami/keycloak/providers/
├── keycloak-astrago-spi-1.0.0.jar     # SPI JAR 파일 (Dockerfile에서 복사)
└── keycloak-theme.jar                   # Theme JAR 파일 (Dockerfile에서 wget 다운로드)
```

- **SPI JAR**: keycloak-spi Dockerfile에서 복사
- **Theme JAR**: keycloak-spi Dockerfile에서 wget으로 다운로드

**모두 한 번에 처리되어 별도 설정이 불필요합니다.**

### 3. Event Listener 등록 (Keycloak Admin Console)

SPI JAR 파일이 복사되는 것은 내부 로직이지만, **외부(웹)에서 동작하려면 Keycloak Admin Console에서 Event Listener를 수동으로 등록해야 합니다.**

#### 등록 경로:
1. Keycloak Admin Console 접속 (`http://your-keycloak-url/auth/admin/`)
2. **Events** → **Config** 탭
3. **Event Listeners** 섹션에서 `astrago-event-listener` 추가
4. **Save** 버튼 클릭

#### Event Listener ID:
```
astrago-event-listener
```

### 4. 빌드 및 배포 방법

#### Java 파일 재빌드 시:
```bash
cd keycloak-spi

# 1. Maven 빌드
mvn clean package -DskipTests

# 2. Docker 이미지 빌드 및 푸시
./build.sh
```

#### Dockerfile만 빌드 시:
```bash
cd keycloak-spi

# Docker 이미지 빌드 및 푸시
docker build -t xiilab/astrago-keycloak-spi-userattribute:latest .
docker push xiilab/astrago-keycloak-spi-userattribute:latest
```

#### 배포:
```bash
cd ../applications/keycloak
helmfile apply
```

## SPI가 필요한 이유

### 목적
LDAP 연동 사용자가 Keycloak에 로그인할 때, Astrago 시스템에서 필요한 기본 속성들을 자동으로 추가하기 위함입니다.

### 동작 원리
- 사용자 LOGIN 또는 REGISTER 이벤트 발생 시
- LDAP 사용자인지 확인 (federationLink 존재 여부)
- LDAP 사용자인 경우 3가지 속성을 자동 추가

## 추가되는 3가지 속성

### 1. workspaceCreateLimit
- **값**: `"2"`
- **목적**: 사용자가 생성할 수 있는 워크스페이스 수 제한

### 2. signUpPath  
- **값**: `"ASTRAGO"`
- **목적**: 사용자 가입 경로 식별

### 3. approvalYN
- **값**: `"true"` (최신 버전)
- **목적**: 사용자 승인 여부 상태

## 이미지 정보

- **Docker Hub 이미지**: `xiilab/astrago-keycloak-spi-userattribute:latest`
- **기반 이미지**: `bitnami/keycloak:22.0.5`

## 테스트 계정

- **admin** / admin123
- **user1** / user123

## 주의 사항

1. **빌드 순서 중요**: Docker 이미지 빌드 전에 반드시 `mvn clean package -DskipTests`로 JAR 파일을 먼저 생성해야 합니다.

2. **Event Listener 등록**: SPI가 제대로 동작하려면 Keycloak Admin Console에서 Event Listener를 수동으로 등록해야 합니다.

3. **LDAP 사용자만 대상**: 로컬 사용자가 아닌 LDAP 연동 사용자에게만 속성이 추가됩니다.

4. **중복 방지**: 이미 속성이 존재하는 경우 중복으로 추가하지 않습니다.