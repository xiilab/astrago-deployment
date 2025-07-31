#!/bin/bash

echo "=========================================="
echo "Astrago Keycloak SPI 빌드 및 푸시"
echo "=========================================="

# 1. Maven 빌드
echo "1. Maven 빌드 중..."
mvn clean package -DskipTests

if [ $? -ne 0 ]; then
    echo "Maven 빌드 실패!"
    exit 1
fi

# 2. Docker 이미지 빌드
echo "2. Docker 이미지 빌드 중..."
docker build -t xiilab/astrago-keycloak-spi-userattribute:latest .

if [ $? -ne 0 ]; then
    echo "Docker 빌드 실패!"
    exit 1
fi

# 3. Docker Hub 푸시
echo "3. Docker Hub 푸시 중..."
docker push xiilab/astrago-keycloak-spi-userattribute:latest

if [ $? -ne 0 ]; then
    echo "Docker Hub 푸시 실패!"
    exit 1
fi

echo "=========================================="
echo "빌드 및 푸시 완료!"
echo "=========================================="
echo "이미지: xiilab/astrago-keycloak-spi-userattribute:latest"
echo ""
echo "배포하려면:"
echo "cd ../applications/keycloak"
echo "helmfile apply" 