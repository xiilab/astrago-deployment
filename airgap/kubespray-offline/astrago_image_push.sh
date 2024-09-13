#!/bin/bash

REGISTRY_IMAGE=registry:2.8.2
REGISTRY_DIR=$(pwd)/outputs/registry-volume
REGISTRY_PORT=35000
LOCAL_REGISTRY=localhost:${REGISTRY_PORT}
# 스크립트 실행 시 에러 발생 시 종료
set -e

# containerd와 nerdctl 설치 함수
install_containerd_and_nerdctl() {
    # containerd 설치 여부 확인
    if command -v containerd &> /dev/null; then
        echo "containerd가 이미 설치되어 있습니다. 설치를 스킵합니다."
    else
        echo "containerd 설치를 시작합니다..."

        # 필요한 패키지 업데이트 및 설치
        sudo apt-get update
        # Add Docker's official GPG key:
        sudo apt-get install ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update        
        sudo apt-get install -y containerd.io

        # 기본 설정 파일 생성
        sudo mkdir -p /etc/containerd
        sudo containerd config default | sudo tee /etc/containerd/config.toml

        # containerd 서비스 시작 및 부팅 시 자동 시작 설정
        sudo systemctl restart containerd
        sudo systemctl enable containerd

        echo "containerd가 성공적으로 설치 및 설정되었습니다."
    fi

    # nerdctl 설치 여부 확인
    if command -v nerdctl &> /dev/null; then
        echo "nerdctl이 이미 설치되어 있습니다. 설치를 스킵합니다."
    else
        echo "nerdctl 설치를 시작합니다..."
        NERDCTL_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
        curl -LO https://github.com/containerd/nerdctl/releases/download/${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION#v}-linux-amd64.tar.gz
        sudo tar Cxzvf /usr/local/bin nerdctl-${NERDCTL_VERSION#v}-linux-amd64.tar.gz
        rm nerdctl-${NERDCTL_VERSION#v}-linux-amd64.tar.gz

        echo "nerdctl가 성공적으로 설치되었습니다."
    fi
}

# 프라이빗 Docker 레지스트리 실행 함수
run_private_registry() {
    echo "프라이빗 Docker 레지스트리를 실행합니다..."

    # Registry가 이미 실행 중인지 확인
    if nerdctl ps --format '{{.Names}}' | grep -q '^registry$'; then
        echo "Registry가 이미 실행 중입니다. 스킵합니다."
        return
    fi

    # nerdctl을 사용하여 프라이빗 레지스트리 실행
    sudo nerdctl run -d \
        --name registry \
        -p $REGISTRY_PORT:5000 \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Origin="[http://registry.example.com]" \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Methods="[HEAD,GET,OPTIONS,DELETE]" \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Credentials="[true]" \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Headers="[Authorization,Accept,Cache-Control]" \
        -e REGISTRY_HTTP_HEADERS_Access-Control-Expose-Headers="[Docker-Content-Digest]" \
        -e REGISTRY_STORAGE_DELETE_ENABLED=true \
        -v $REGISTRY_DIR:/var/lib/registry \
        $REGISTRY_IMAGE

    echo "프라이빗 Docker 레지스트리가 성공적으로 실행되었습니다."
    echo "레지스트리는 localhost에서 접근 가능합니다."
}

pull_and_push_images() {
    images=$(cat outputs/images/*.list)
    for image in $images; do

        # Removes specific repo parts from each image for kubespray
        newImage=$image
	
        for repo in registry.k8s.io k8s.gcr.io gcr.io docker.io quay.io "nvcr.io/nvidia/cloud-native" "nvcr.io/nvidia/k8s" "nvcr.io/nvidia"; do
            newImage=$(echo ${newImage} | sed s@^${repo}/@@)
        done

        newImage=${LOCAL_REGISTRY}/${newImage}	

        echo "===> Pull ${image}"
        sudo nerdctl pull ${image} || exit 1

        echo "===> Tag ${image} -> ${newImage}"
        sudo nerdctl tag ${image} ${newImage} || exit 1

        echo "===> Push ${newImage}"
        sudo nerdctl push ${newImage} || exit 1	

        if [[ $image != $REGISTRY_IMAGE ]]; then
            echo "===> Remove ${image} and ${newImage}"	  
            sudo nerdctl rmi ${image} ${newImage}
	fi
    done
}

# 함수 호출
install_containerd_and_nerdctl
run_private_registry
pull_and_push_images
