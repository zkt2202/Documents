# customlinux
Set ip, hostname, repair seting OS , kube ...

This script provides an interactive menu for managing Kubernetes and various system configurations on Linux-based systems. It supports multiple distributions and adapts its actions based on the detected operating system and network configuration tools.

Features:
- Change system hostname
- Set or change static IP address for network interfaces (supports Netplan, NetworkManager, systemd-networkd, traditional scripts, BSD rc.conf)
- Enable root SSH login and configure passwordless sudo for the current user
- Disable SELinux and firewalld, enable IPv4 forwarding
- Disable swap (required for Kubernetes)
- Install Docker (supports apt, yum, dnf)
- Install Kubernetes (supports apt, yum, dnf, and manual installation)
- Initialize Kubernetes master node and export join command

Usage:
- Run the script as root for full functionality.
- Follow the interactive prompts to select and configure system options.

Notes:
- The script attempts to detect the operating system and network configuration method automatically.
- Some actions may overwrite existing configuration files (e.g., network settings).
- Always review changes before applying in production environments.

Author: zkt2202
Date: 22/07/2025

## Set up load balancer node
##### Install Haproxy
```
apt update && apt install -y haproxy
```
##### Configure haproxy
Append the below lines to **/etc/haproxy/haproxy.cfg**
```
frontend kubernetes-frontend
    bind 10.0.1.84:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    option tcp-check
    balance roundrobin
    server kmaster1 10.0.1.24:6443 check fall 3 rise 2
    server kmaster2 10.0.1.100:6443 check fall 3 rise 2
```
##### Restart haproxy service
```
systemctl restart haproxy## Set up load balancer node
##### Install Haproxy
```
apt update && apt install -y haproxy
```
##### Configure haproxy
Append the below lines to **/etc/haproxy/haproxy.cfg**
```
frontend kubernetes-frontend
    bind 10.0.1.84:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    option tcp-check
    balance roundrobin
    server kmaster1 10.0.1.24:6443 check fall 3 rise 2
    server kmaster2 10.0.1.100:6443 check fall 3 rise 2
```
##### Restart haproxy service
```
systemctl restart haproxy

## On any one of the Kubernetes master node (Eg: kmaster1)
##### Initialize Kubernetes Cluster
```
kubeadm init --control-plane-endpoint="<Ip server proxy>:6443" --upload-certs --apiserver-advertise-address=<ip master> --pod-network-cidr=192.168.0.0/16
```
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
Copy the commands to join other master nodes and worker nodes.
##### Deploy Calico network
```
kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://docs.projectcalico.org/manifests/calico.yaml
```

## Join other nodes to the cluster (kmaster2 & kworker1, kworker2)
> Use the respective kubeadm join commands you copied from the output of kubeadm init command on the first master.

> IMPORTANT: You also need to pass --apiserver-advertise-address to the join command when you join the other master node.

## Downloading kube config to your local machine
On your host machine
```
mkdir ~/.kube
scp root@192.168.9.100:/etc/kubernetes/admin.conf ~/.kube/config
```

## Verifying the cluster
```
kubectl cluster-info
kubectl get nodes
kubectl get cs
```

Have Fun!!