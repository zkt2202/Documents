#!/bin/bash
# This script installs Kubernetes on a Debian or Red Hat-based system, or with packages linux.
# It checks the architecture and operating system, installs necessary packages,
# and sets up Kubernetes to run as a service.
# Ensure the script is run as root
# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo' or switch to the root user."
    exit 1
fi
# Install required packages based on architecture and check install Docker
echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl enable --now docker
    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
        PKG_MGR="yum"
        if command -v dnf &> /dev/null; then
            PKG_MGR="dnf"
        fi
        sudo $PKG_MGR install -y yum-utils
        sudo $PKG_MGR config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo $PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl enable --now docker
    else
        echo "Unsupported OS or package manager. Please install Docker manually."
        exit 1
    fi
    echo "Docker installation completed."
else
    echo "Docker is already installed."
fi

intstall_kube() {
# Install Kubernetes
# Check if Kubernetes is already installed
if command -v kubectl &> /dev/null; then
    echo "Kubernetes is already installed."
else
    if command -v apt-get &> /dev/null; then
        sudo apt-get install -y kubelet kubeadm kubectl
    elif command -v yum &> /dev/null; then
        # Add Kubernetes's official GPG key
        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
        # Add Kubernetes's stable repository
        echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
        # Update the package list again
        sudo apt-get update -y
        # Install Kubernetes on Red Hat-based systems
        sudo yum install -y kubelet kubeadm kubectl || sudo dnf install -y kubelet kubeadm kubectl
    else
        VERSION="latest"
        wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
        sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
        sudo rm -f crictl-$VERSION-linux-amd64.tar.gz
        CNI_PLUGINS_VERSION="v1.3.0"
        ARCH="amd64"
        DEST="/opt/cni/bin"
        sudo mkdir -p "$DEST"
        curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" | sudo tar -C "$DEST" -xz
        DOWNLOAD_DIR="/usr/local/bin"
        sudo mkdir -p "$DOWNLOAD_DIR"
        RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
        cd $DOWNLOAD_DIR
        sudo curl -L --remote-name-all https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet}
        sudo chmod +x {kubeadm,kubelet}
        RELEASE_VERSION="v0.16.2"
        curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /usr/lib/systemd/system/kubelet.service
        sudo mkdir -p /usr/lib/systemd/system/kubelet.service.d
        curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
        sudo systemctl enable --now kubelet
        sudo systemctl start --now kubelet
        echo "Kubernetes installed successfully."
    fi
fi
}

# Check kubelet on master
 # Check kubeadm run on master 
if systemctl is-active --quiet kubelet; then
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16
else
    echo "Kubelet not install or not run"
    get_install=$(intstall_kube)
    echo "$get_install"
    if sysconfig is-active --quiet kubelet; then
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16 
    fi
fi

