#!/bin/bash

sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
# Install cri-tools
# Ensure the script is run with root privileges

VERSION="latest"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
sudo rm -f crictl-$VERSION-linux-amd64.tar.gz
# Install kubeadm, kubelet, kubectl

sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo sh -c 'echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list'
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
# Enable br_netfilter
sudo modprobe br_netfilter
echo "1" | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables
echo "1" | sudo tee /proc/sys/net/bridge/bridge-nf-call-ip6tables
echo "1" | sudo tee /proc/sys/net/ipv4/ip_forward
echo "1" | sudo tee /proc/sys/net/ipv6/conf/all/forwarding
# Set sysctl parameters
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
# Apply sysctl settings
sudo sysctl --system
# Install containerd
sudo apt-get install -y containerd
# Configure containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
# Restart containerd
sudo systemctl restart containerd
# Enable and start kubelet
sudo systemctl enable kubelet
sudo systemctl start kubelet
# Check kubelet status
if systemctl is-active --quiet kubelet; then
    echo "Kubelet is running."
else
    echo "Kubelet is not running. Please check the logs for more details."
fi
# Check kubeadm version
KUBEADM_VERSION=$(kubeadm version -o short)
if [ $? -eq 0 ]; then
    echo "Kubeadm version: $KUBEADM_VERSION"
else
    echo "Kubeadm is not installed or not functioning correctly."
fi
# Check kubectl version
KUBECTL_VERSION=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
if [ $? -eq 0 ]; then
    echo "Kubectl version: $KUBECTL_VERSION"
else
    echo "Kubectl is not installed or not functioning correctly."
fi
# Check crictl version
CRICTL_VERSION=$(crictl --version | awk '{print $3}')
if [ $? -eq 0 ]; then
    echo "Crictl version: $CRICTL_VERSION"
else
    echo "Crictl is not installed or not functioning correctly."
fi
# Check containerd version
CONTAINERD_VERSION=$(containerd --version | awk '{print $3}')
if [ $? -eq 0 ]; then
    echo "Containerd version: $CONTAINERD_VERSION"
else
    echo "Containerd is not installed or not functioning correctly."
fi
# Check Docker version
DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
if [ $? -eq 0 ]; then
    echo "Docker version: $DOCKER_VERSION"
else
    echo "Docker is not installed or not functioning correctly."
fi
# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo' or switch to the root user."
    exit 1
fi
# Check if the system is Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        echo "This script is designed for Ubuntu. Please run it on an Ubuntu system."
        exit 1
    fi
else
    echo "Unable to determine the operating system. Please ensure this script is run on an Ubuntu system."
    exit 1
fi
# Check if the required commands are available
for cmd in docker kubeadm kubelet kubectl crictl containerd; do
    if ! command -v $cmd &> /dev/null; then
        echo "$cmd is not installed. Please install it before running this script."
        exit 1
    fi
done
# Check if the system has enough memory
REQUIRED_MEMORY=2048 # in MB
AVAILABLE_MEMORY=$(free -m | awk '/^Mem:/{print $2}')
if [ "$AVAILABLE_MEMORY" -lt "$REQUIRED_MEMORY" ]; then
    echo "This system does not have enough memory. At least $REQUIRED_MEMORY MB is required."
    exit 1
fi
# Check if the system has enough disk space
REQUIRED_DISK_SPACE=20480 # in MB
AVAILABLE_DISK_SPACE=$(df / | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_DISK_SPACE" -lt "$REQUIRED_DISK_SPACE" ]; then
    echo "This system does not have enough disk space. At least $REQUIRED_DISK_SPACE MB is required."
    exit 1
fi
# Check if the system has a compatible kernel version
REQUIRED_KERNEL_VERSION="4.15.0"
CURRENT_KERNEL_VERSION=$(uname -r | awk -F '-' '{print $1}')
if [ "$(printf '%s\n' "$REQUIRED_KERNEL_VERSION" "$CURRENT_KERNEL_VERSION" | sort -V | head -n1)" != "$REQUIRED_KERNEL_VERSION" ]; then
    echo "This system does not have a compatible kernel version. At least $REQUIRED_KERNEL_VERSION is required."
    exit 1
fi
# Check if the system has the required network configuration
REQUIRED_NETWORK_CONFIG="br_netfilter"
if ! lsmod | grep -q "$REQUIRED_NETWORK_CONFIG"; then
    echo "The required network configuration '$REQUIRED_NETWORK_CONFIG' is not enabled. Please enable it before running this script."
    exit 1
fi
# Check if the system has the required sysctl settings
REQUIRED_SYSCTL_SETTINGS=(
    "net.bridge.bridge-nf-call-iptables=1"
    "net.bridge.bridge-nf-call-ip6tables=1"
    "net.ipv4.ip_forward=1"
    "net.ipv6.conf.all.forwarding=1"
)
for setting in "${REQUIRED_SYSCTL_SETTINGS[@]}"; do
    if ! sysctl -n "$setting" | grep -q "1"; then
        echo "The required sysctl setting '$setting' is not enabled. Please enable it before running this script."
        exit 1
    fi
done
# Check if the system has the required firewall configuration
REQUIRED_FIREWALL_CONFIG="iptables"
if ! iptables -L | grep -q "$REQUIRED_FIREWALL_CONFIG"; then
    echo "The required firewall configuration '$REQUIRED_FIREWALL_CONFIG' is not enabled. Please enable it before running this script."
    exit 1
fi
# Check if the system has the required SELinux configuration
REQUIRED_SELINUX_CONFIG="disabled"
if [ -f /etc/selinux/config ]; then
    SELINUX_STATUS=$(grep "^SELINUX=" /etc/selinux/config | cut -d '=' -f2)
    if [ "$SELINUX_STATUS" != "$REQUIRED_SELINUX_CONFIG" ]; then
        echo "The required SELinux configuration '$REQUIRED_SELINUX_CONFIG' is not set. Please set it before running this script."
        exit 1
    fi
else
    echo "SELinux configuration file not found. Please ensure SELinux is configured correctly."
    exit 1
fi

# Check if the system has the required swap configuration
REQUIRED_SWAP_CONFIG="0"
if grep -q "swap" /etc/fstab; then
    SWAP_STATUS=$(grep "swap" /etc/fstab | awk '{print $4}')
    if [ "$SWAP_STATUS" != "$REQUIRED_SWAP_CONFIG" ]; then
        echo "The required swap configuration '$REQUIRED_SWAP_CONFIG' is not set. Please disable swap before running this script."
        exit 1
    fi
else
    echo "Swap configuration not found. Please ensure swap is disabled."
    exit 1
fi
# Check if the system has the required Docker configuration
REQUIRED_DOCKER_CONFIG="overlay2"
if ! docker info | grep -q "$REQUIRED_DOCKER_CONFIG"; then
    echo "The required Docker configuration '$REQUIRED_DOCKER_CONFIG' is not set. Please configure Docker correctly before running this script."
    exit 1
fi
# Check if the system has the required kubelet configuration
REQUIRED_KUBELET_CONFIG="cgroupfs"
if ! kubelet --version | grep -q "$REQUIRED_KUBELET_CONFIG"; then
    echo "The required kubelet configuration '$REQUIRED_KUBELET_CONFIG' is not set. Please configure kubelet correctly before running this script."
    exit 1
fi
# Check if the system has the required kubeadm configuration
REQUIRED_KUBEADM_CONFIG="kubelet"
if ! kubeadm config view | grep -q "$REQUIRED_KUBEADM_CONFIG"; then
    echo "The required kubeadm configuration '$REQUIRED_KUBEADM_CONFIG' is not set. Please configure kubeadm correctly before running this script."
    exit 1
fi
# Check if the system has the required kubectl configuration
REQUIRED_KUBECTL_CONFIG="kubeconfig"
if ! kubectl config view | grep -q "$REQUIRED_KUBECTL_CONFIG"; then
    echo "The required kubectl configuration '$REQUIRED_KUBECTL_CONFIG' is not set. Please configure kubectl correctly before running this script."
    exit 1
fi
# Check if the system has the required crictl configuration
REQUIRED_CRICTL_CONFIG="runtime-endpoint"
if ! crictl info | grep -q "$REQUIRED_CRICTL_CONFIG"; then
    echo "The required crictl configuration '$REQUIRED_CRICTL_CONFIG' is not set. Please configure crictl correctly before running this script."
    exit 1
fi
# Check if the system has the required containerd configuration
REQUIRED_CONTAINERD_CONFIG="containerd"
if ! containerd config dump | grep -q "$REQUIRED_CONTAINERD_CONFIG"; then
    echo "The required containerd configuration '$REQUIRED_CONTAINERD_CONFIG' is not set. Please configure containerd correctly before running this script."
    exit 1
fi
# Check if the system has the required network configuration
REQUIRED_NETWORK_CONFIG="cni"
if ! ls /opt/cni/bin | grep -q "$REQUIRED_NETWORK_CONFIG"; then
    echo "The required network configuration '$REQUIRED_NETWORK_CONFIG' is not set. Please configure CNI correctly before running this script."
    exit 1
fi
# Check if the system has the required CNI plugins
REQUIRED_CNI_PLUGINS=("bridge" "flannel" "calico" "weave")
for plugin in "${REQUIRED_CNI_PLUGINS[@]}"; do
    if ! ls /opt/cni/bin | grep -q "$plugin"; then
        echo "The required CNI plugin '$plugin' is not installed. Please install it before running this script."
        exit 1
    fi
done
# Check if the system has the required kubelet service file
REQUIRED_KUBELET_SERVICE="/usr/lib/systemd/system/kubelet.service"
if [ ! -f "$REQUIRED_KUBELET_SERVICE" ]; then
    echo "The required kubelet service file '$REQUIRED_KUBELET_SERVICE' is not found. Please ensure it is created before running this script."
    exit 1
fi
# Check if the system has the required kubelet configuration file
REQUIRED_KUBELET_CONFIG_FILE="/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf"
if [ ! -f "$REQUIRED_KUBELET_CONFIG_FILE" ]; then
    echo "The required kubelet configuration file '$REQUIRED_KUBELET_CONFIG_FILE' is not found. Please ensure it is created before running this script."
    exit 1
fi
# Check if the system has the required kubelet service directory
REQUIRED_KUBELET_SERVICE_DIR="/usr/lib/systemd/system/kubelet.service.d"
if [ ! -d "$REQUIRED_KUBELET_SERVICE_DIR" ]; then
    echo "The required kubelet service directory '$REQUIRED_KUBELET_SERVICE_DIR' is not found. Please ensure it is created before running this script."
    exit 1
fi
# Check if the system has the required kubelet service file
REQUIRED_KUBELET_SERVICE_FILE="/usr/lib/systemd/system/kubelet.service"
if [ ! -f "$REQUIRED_KUBELET_SERVICE_FILE" ]; then
    echo "The required kubelet service file '$REQUIRED_KUBELET_SERVICE_FILE' is not found. Please ensure it is created before running this script."
    exit 1
fi
# Check if the system has the required kubelet configuration file
REQUIRED_KUBELET_CONFIG_FILE="/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf"
if [ ! -f "$REQUIRED_KUBELET_CONFIG_FILE" ]; then
    echo "The required kubelet configuration file '$REQUIRED_KUBELET_CONFIG_FILE' is not found. Please ensure it is created before running this script."
    exit 1
fi
# Check if the system has the required kubelet service directory
REQUIRED_KUBELET_SERVICE_DIR="/usr/lib/systemd/system/kubelet.service.d"
if [ ! -d "$REQUIRED_KUBELET_SERVICE_DIR" ]; then
    echo "The required kubelet service directory '$REQUIRED_KUBELET_SERVICE_DIR' is not found. Please ensure it is created before running this script."
    exit 1
fi
# Reload systemd to recognize the new kubelet service
sudo systemctl daemon-reload
# Enable and start kubelet
sudo systemctl enable --now kubelet
# Check if kubelet is running
if systemctl is-active --quiet kubelet; then
    echo "Kubelet is running."
else
    echo "Kubelet is not running. Please check the logs for more details."
fi
# Check if kubeadm is installed
KUBEADM_VERSION=$(kubeadm version -o short)
if [ $? -eq 0 ]; then
    echo "Kubeadm version: $KUBEADM_VERSION"
else
    echo "Kubeadm is not installed or not functioning correctly."
fi
# Check if kubectl is installed
KUBECTL_VERSION=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
if [ $? -eq 0 ]; then
    echo "Kubectl version: $KUBECTL_VERSION"
else
    echo "Kubectl is not installed or not functioning correctly."
fi
# Check if crictl is installed
CRICTL_VERSION=$(crictl --version | awk '{print $3}')
if [ $? -eq 0 ]; then
    echo "Crictl version: $CRICTL_VERSION"
else
    echo "Crictl is not installed or not functioning correctly."
fi
# Check if containerd is installed
CONTAINERD_VERSION=$(containerd --version | awk '{print $3}')
if [ $? -eq 0 ]; then
    echo "Containerd version: $CONTAINERD_VERSION"
else
    echo "Containerd is not installed or not functioning correctly."
fi
# Check if Docker is installed
DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
if [ $? -eq 0 ]; then
    echo "Docker version: $DOCKER_VERSION"
else
    echo "Docker is not installed or not functioning correctly."
fi
# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo' or switch to the root user."
    exit 1
fi