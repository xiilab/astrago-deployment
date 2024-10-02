FILES_DIR=outputs/gpu-driver

decide_relative_dir() {
    local url=$1
    local rdir
    rdir=$url
    rdir=$(echo $url | sed 's@https://kr.download.nvidia.com/\([^/]*\)/.*@\1@')
    if [ "$url" != "$rdir" ]; then
        echo $rdir
        return
    fi
}

get_url() {
    url=$1
    filename="${url##*/}"

    rdir=$(decide_relative_dir $url)

    if [ -n "$rdir" ]; then
        if [ ! -d $FILES_DIR/$rdir ]; then
            mkdir -p $FILES_DIR/$rdir
        fi
    else
        rdir="."
    fi

    if [ ! -e $FILES_DIR/$rdir/$filename ]; then
        echo "==> Download $url"
        for i in {1..3}; do
            curl --location --show-error --fail --output $FILES_DIR/$rdir/$filename $url && return
            echo "curl failed. Attempt=$i"
        done
        echo "Download failed, exit : $url"
        exit 1
    else
        echo "==> Skip $url"
    fi
}

# https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html
# 550.54.15(CUDA 12.4)
# 535.161.08(CUDA 12.2)
# 470.239.06(CUDA 11.4)
# Data Center / Tesla
#get_url https://kr.download.nvidia.com/tesla/550.54.15/NVIDIA-Linux-x86_64-550.54.15.run
get_url https://kr.download.nvidia.com/tesla/535.161.08/NVIDIA-Linux-x86_64-535.161.08.run
#get_url https://kr.download.nvidia.com/tesla/470.239.06/NVIDIA-Linux-x86_64-470.239.06.run
