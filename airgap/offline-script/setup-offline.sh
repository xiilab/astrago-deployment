#!/bin/bash

# Check if first argument is provided and is a valid IP address or hostname
if [ -n "$1" ]; then
    REPO_SERVER="$1"
else
    REPO_SERVER="localhost"
fi

# setup yum repository
setup_yum_repos() {
    sudo /bin/rm /etc/yum.repos.d/offline.repo

    echo "===> Disable all yum repositories"
    for repo in /etc/yum.repos.d/*.repo; do
        #sudo sed -i "s/^enabled=.*/enabled=0/" $repo
        sudo mv "${repo}" "${repo}.original"
    done

    echo "===> Setup local yum repository"
    cat <<EOF | sudo tee /etc/yum.repos.d/offline.repo
[offline-repo]
name=Offline repo
baseurl=http://$REPO_SERVER/rpms/local/
enabled=1
gpgcheck=0
EOF
}

# setup deb repository
setup_deb_repos() {
    echo "===> Setup deb offline repository"
    cat <<EOF | sudo tee /etc/apt/apt.conf.d/99offline
APT::Get::AllowUnauthenticated "true";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF

    cat <<EOF | sudo tee /etc/apt/sources.list.d/offline.list
deb [trusted=yes] http://$REPO_SERVER/debs/local/ ./
EOF

    echo "===> Disable default repositories"
    if [ ! -e /etc/apt/sources.list.original ]; then
        sudo cp /etc/apt/sources.list /etc/apt/sources.list.original
    fi
    sudo sed -i "s/^deb /# deb /" /etc/apt/sources.list
}

setup_pypi_mirror() {
    # PyPI mirror
    echo "===> Setup PyPI mirror"
    mkdir -p ~/.config/pip/
    cat <<EOF >~/.config/pip/pip.conf
[global]
index = http://$REPO_SERVER/pypi/
index-url = http://$REPO_SERVER/pypi/
trusted-host = $REPO_SERVER
EOF
}

if [ -e /etc/redhat-release ]; then
    setup_yum_repos
else
    setup_deb_repos
fi
setup_pypi_mirror

