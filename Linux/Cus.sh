#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo' or switch to the root user."
    exit 1
fi


# get info OS 
get_os() { 
    if command -v lsb_release &> /dev/null; then
        # Get the OS ID using lsb_release
        lsb_release -i | awk -F: '{print $2}' | xargs
    else
        echo "lsb_release is not available. Trying alternative methods."
        if [ -f /etc/os-release ]; then
            # Get the ID from /etc/os-release
            grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"'
        else
            echo "No OS information available."
            exit 1
        fi
    fi
}

# Call the function to display the OS ID
#os_id=$(get_os_id)
#echo "Operating System ID: $os_id"


# Edit hostname machine, set ip, enable no password sudoer
change_hostname(){
  local new_hostname=$2
  read -p "Enter new hostname: " new_hostname
  if [ -z "$new_hostname" ]; then
    echo "Hostname connot be empty."
  return $2
  fi
  sudo hostnamectl set-hostname "$new_hostname"
  sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/g" /etc/hosts
  echo "Change Hostname: $new_hostname"
  read -p "Enabale sudoer no password, (y,n): " yes
  if [[ "$yes" =~ ^[Yy]$ ]]; then
    # Disbale Password sudo
    pw=$(dis_pw)
    echo "$pw"
  fi
  # Set IP
  read -p "Setting IP Static VM. Do you want to continue? (y/n): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    return $1
  else
    # Set ip
    setip=$(set_ip)
    echo "$setip"
  fi
  read -p "Reboot now. (y/n): " cb
  if [[ ! "$cb" =~ ^[Yy]$ ]]; then
    return $1
  else
    rb2=$(rb)
    echo "$rb2"
  fi
}

# Set IP static 
set_ip(){
  read -p "Enter the interface name (e.g., eth0, enp0s3): " interface
    if ! ip -o link show up | awk -F': ' '{print $2}' | grep -i "$interface" > /dev/null 2>&1; then
    echo "Interface '$interface' does not exist. Please check the interface name and try again."
    exit $1
    fi
  read -p "Enter the static IP address (e.g., 192.168.9.100): " static_ip
  read -p "Enter the subnet mask (e.g., 255.255.255.0): " subnet_mask
  read -p "Enter the gateway (e.g., 192.168.9.1): " gateway
  read -p "Enter the DNS server (e.g., 8.8.8.8): " dns_server 
  if [[ -z "$interface" || -z "$static_ip" || -z "$subnet_mask" || -z "$gateway" || -z "$dns_server" ]]; then
    echo "All fields are required. Please provide valid inputs."
    exit $1
  fi
  # set ip with nmcli 
  if command -v nmcli &> /dev/null; then
    # Set the static IP address NetworkManager
    #nmcli con add type ethernet ifname "$interface" con-name "$interface" autoconnect yes \
    #  ip4 "$static_ip" gw4 "$gateway" \
    #  ipv4.dns "$dns_server" ipv4.method manual
    #nmcli con up "$interface"
    sudo nmcli connection modify "$interface" ipv4.addresses $static_ip/24
    sudo nmcli connection modify "$interface" ipv4.gateway $gateway
    sudo nmcli connection modify "$interface" ipv4.dns $dns_server
    sudo nmcli connection modify "$interface" ipv4.method manual
    sudo nmcli connection up "$interface"
    echo "Static IP set successfully for interface '$interface'." 
    rb4=$(rb)
    echo "$rb4"
  else
    if [ -f /etc/netplan/*.yaml ]; then
    # For systems using netplan (e.g., Ubuntu)
    echo "Setting static IP for Ubuntu..."
    cat <<EOF > /etc/netplan/*.yaml
network:
version: 2
ethernets:
  $interface: 
    dhcp4: no
    addresses:
      - $static_ip/24
    gateway4: $gateway
    nameservers:
      addresses:
        - $dns_server
EOF
    echo "Static IP set successfully for Ubuntu."
    rb5 = $(rb)
    echo "$rb5"
    elif [ -f /etc/network/interfaces ]; then
        # For Debian-based systems
        echo "Setting static IP for Debian..."
        cat <<EOF > /etc/network/interfaces
auto $interface
iface $interface inet static
    address $static_ip/24
    gateway $gateway
    dns-nameservers $dns_server
EOF
        echo "Static IP set successfully for Debian."
        rb6=$(rb)
        echo "$rb6"
    elif [ -f /etc/sysconfig/network-scripts/ifcfg-$interface ]; then
        # For Red Hat-based systems (CentOS, Fedora, etc.)
        echo "Setting static IP for Red Hat-based system..."
        cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$interface
DEVICE=$interface
BOOTPROTO=none
ONBOOT=yes
IPADDR=$static_ip
NETMASK=$subnet_mask
GATEWAY=$gateway
DNS1=$dns_server
EOF
        echo "Static IP set successfully for Red Hat-based system."
        rb7 = $(rb)
        echo "$rb7"
    elif [ -f /etc/systemd/network/10-$interface.network ]; then
        # For systems using systemd-networkd (e.g., Arch Linux)
        echo "Setting static IP for Arch Linux..."
        cat <<EOF > /etc/systemd/network/10-$interface.network
[Match]
Name=$interface
[Network]
Address=$static_ip/24
Gateway=$gateway
DNS=$dns_server
EOF
        echo "Static IP set successfully for Arch Linux."
        rb8=$(rb)
        echo "$rb8"
    else
        echo "Unsupported operating system or network configuration."
        exit $1
    fi  
  fi
}

# Change IP
change_ip(){
  read -p "Enter interfaces connected: " interface
    if ! ip -o link show up | awk -F': ' '{print $2}' | grep -i "$interface" > /dev/null 2>&1; then
    echo "Interface '$interface' does not exist. Please check the interface name and try again."
    exit $1
    fi 
  read -p "Enter the new static IP address (e.g., 192.168.9.100): " NEW_IP
  if [ -f /etc/network/interfaces ]; then
      sudo sed -i "s|^ *address .*|    address $NEW_IP/24|" /etc/network/interfaces
      echo "Static IP set successfully and reboot."
  elif [ -f /etc/netplan/*.yaml ]; then
      sudo sed -i "s|[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}|$NEW_IP/24|g" /etc/netplan/*.yaml
      echo "Static IP set successfully and reboot."
  elif [ -d /etc/NetworkManager/system-connections ]; then
      sudo sed -i "s/^address1=.*/address1=$NEW_IP/" /etc/NetworkManager/system-connections/$interface || true
      echo "Static IP set successfully and reboot."
  elif [ -f /etc/sysconfig/network-scripts/ifcfg-$interface]; then
      sudo sed -i "s/IPADDR=.*/IPADDR=$NEW_IP/" /etc/sysconfig/network-scripts/ifcfg-"$interface"
      echo "Static IP set successfully and reboot."
  elif [ -f /etc/rc.conf ]; then
      sudo sed -i "s/inet [0-9]\.[0-9]\.[0-9]\.[0-9]/inet $NEW_IP/" /etc/rc.conf
      echo "Static IP set successfully and reboot."
  elif [ -f /etc/systemd/network/10-$interface.network ]; then
      sudo sed -i "s/Address=*\+/24/Address=$NEW_IP/24|g" /etc/systemd/network/10-$interface.network 
      echo "Static IP set successfully and reboot."
  elif [-f /etc/con.d/net]; then
      sudo sed -i "s/^config_$interface=.*/config_$interface=$NEW_IP/24|g" /etc/con.d/net
      echo "Static IP set successfully and reboot."
  else
      echo "Unsupported operating system or network configuration."
  fi
  rb3=$(rb)
  echo "$rb3"
}

# Enable sudoer without password
dis_pw(){
  sudo bash -c 'echo "$(logname) ALL=(ALL:ALL) NOPASSWD: ALL" | (EDITOR="tee -a" visudo)'
  echo "Sudoer no password has been enabled."
}

# Check and install policycoreutils if getenforce or setenforce is missing
set_os(){
  # Check and install policycoreutils if getenforce or setenforce is missing
  if ! command -v getenforce &> /dev/null || ! command -v setenforce &> /dev/null; then
    echo "Installing policycoreutils to manage SELinux..."
    if command -v yum &> /dev/null || command -v dnf &> /dev/null; then
      PKG_MGR="yum"
      if command -v dnf &> /dev/null; then
          PKG_MGR="dnf"
      fi
      sudo $PKG_MGR install -y policycoreutils 
    else
      sudo apt-get install -y policycoreutils
    fi
  fi
  # Check and disable SELinux
  echo "Checking SELinux status..."
  SELINUX_STATUS=$(getenforce)
  if [ "$SELINUX_STATUS" != "Disabled" ]; then
    echo "SELinux is currently $SELINUX_STATUS. Disabling SELinux..."
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    echo "SELinux has been disabled."
  else
    echo "SELinux is already disabled."
  fi
  # Check and disable firewalld (if it exists)
  if systemctl list-unit-files | grep -q "^firewalld.service"; then
    echo "Checking firewalld status..."
    FIREWALLD_STATUS=$(sudo systemctl is-active firewalld)
    if [ "$FIREWALLD_STATUS" = "active" ]; then
        echo "firewalld is active. Disabling firewalld..."
        sudo systemctl stop firewalld
        sudo systemctl disable firewalld
        echo "firewalld has been disabled."
    else
        echo "firewalld is already disabled."
    fi
  else
    echo "firewalld service does not exist on this system." 
  fi
  # Check and enable IPv4 IP forwarding
  echo "Checking IPv4 IP forwarding status..."
  IP_FORWARD_STATUS=$(sysctl net.ipv4.ip_forward | awk '{print $3}')
  if [ "$IP_FORWARD_STATUS" = "0" ]; then
    #echo "IPv4 IP forwarding is disabled. Enabling it..."
    #sudo sysctl -w net.ipv4.ip_forward=1
    #sudo sed -i 's/^net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sudo modprobe br_netfilter
    echo "1" | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables
    echo "1" | sudo tee /proc/sys/net/bridge/bridge-nf-call-ip6tables
    echo "1" | sudo tee /proc/sys/net/ipv4/ip_forward
    echo "1" | sudo tee /proc/sys/net/ipv6/conf/all/forwarding
    echo "IPv4 IP forwarding has been enabled."
  else
    echo "IPv4 IP forwarding is already enabled."
  fi
  # Disable swap
  echo "Disabling swap..."
  sudo swapoff -a
  sudo sed -i '/\sswap\s/d' /etc/fstab
  echo "Swap has been disabled and removed from /etc/fstab."
  # Ensure swap remains disabled after reboot by adding to /etc/rc.local
  if [ -f /etc/rc.local ]; then
    if ! grep -q "swapoff -a" /etc/rc.local; then
      echo "swapoff -a" | sudo tee -a /etc/rc.local > /dev/null
      sudo chmod +x /etc/rc.local
      echo "Added 'swapoff -a' to /etc/rc.local to disable swap on boot."
    else
      echo "'swapoff -a' is already present in /etc/rc.local."
    fi
  else
    echo "#!/bin/bash
swapoff -a
exit 0" | sudo tee /etc/rc.local > /dev/null
    sudo chmod +x /etc/rc.local
    echo "Created /etc/rc.local and added 'swapoff -a' to disable swap on boot."
  fi
  echo "All tasks completed."
}

# Install Docker
i_docker(){
  if command -v docker &> /dev/null; then
    read -p "Docker is already installed. Do you want to continue? (y/n) and remove Docker old and reinstall: " cfd
    if [[ ! "$cfd" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        echo "Docker is already installed."
        exit 0
    else
        echo "Removing old Docker installation and reboot ..."
        removedocker=$(r_d)
        echo "$removedocker"
        if [[ $? -ne 0 ]]; then
            echo "Failed to remove Docker: $removedocker"
            exit 1
        fi
        
        echo "Installing Docker..."
        installdocker=$(i_d)
        echo "$installdocker"
        if [[ $? -ne 0 ]]; then
            echo "Failed to install Docker: $installdocker"
            exit 1
        fi
        
        echo "Docker has been reinstalled successfully."
    fi
  else
    echo "Installing Docker..."
    idocker=$(i_d)
    echo "$idocker"
    if [[ $? -ne 0 ]]; then
        echo "Failed to install Docker: $idocker"
        exit 1
    fi
    sudo usermod -aG docker $USER
    echo "Docker has been installed successfully."
  fi


}

# Docker , test in debian , ubuntu , fedora, RHEL 8,9
i_d(){
os=$(get_os)
if [ "$os" = "Ubuntu" ]; then
    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

elif [ "$os" = "Debian" ]; then
    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo service docker start

elif [ "$os" = "RHEL" ]; then
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker

elif [ "$os" = "Fedora" ]; then
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker

elif [ "$os" = "CentOS" ]; then
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker

elif [ "$os" = "Raspbian" ]; then
    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/raspbian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/raspbian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index and install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker

else
    echo "System not supported, check OS"
fi

}

# Remove Docker 
r_d(){
os=$(get_os)

if [ "$os" = "Ubuntu" ]; then
    sudo systemctl stop docker
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get remove -y $pkg
    done
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.asc

elif [ "$os" = "Debian" ]; then
    sudo systemctl stop docker
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo apt-get remove -y $pkg
    done
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.asc

elif [ "$os" = "RHEL" ]; then
    sudo systemctl stop docker
    sudo dnf remove -y docker \
                        docker-client \
                        docker-client-latest \
                        docker-common \
                        docker-latest \
                        docker-latest-logrotate \
                        docker-logrotate \
                        docker-engine
    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

elif [ "$os" = "Fedora" ]; then
    sudo systemctl stop docker
    sudo dnf remove -y docker \
                        docker-client \
                        docker-client-latest \
                        docker-common \
                        docker-latest \
                        docker-latest-logrotate \
                        docker-logrotate \
                        docker-selinux \
                        docker-engine-selinux \
                        docker-engine
    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

elif [ "$os" = "CentOS" ]; then
    sudo systemctl stop docker
    sudo dnf remove -y docker \
                        docker-client \
                        docker-client-latest \
                        docker-common \
                        docker-latest \
                        docker-latest-logrotate \
                        docker-logrotate \
                        docker-engine
    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
    docker-compose-plugin docker-ce-rootless-extras

elif [ "$os" = "Raspbian" ]; then
    sudo systemctl stop docker
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo apt-get remove -y $pkg
    done
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.asc

else
    echo "System not supported, check OS"
    exit 1
fi  

# Final cleanup
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd

echo "Docker removed successfully. Rebooting..."
rb1=$(rb)
echo "$rb1"

}


# Install Cri-o
in_cri(){
    # Add the CRI-O repository  if not exit.
    CRIO_VERSION="v1.33"
    # Check repo for debian based
      if [ -f /etc/apt/sources.list.d/cri-o.list ] || [ -f /etc/apt/sources.list.d/cri-o.list ]; then
        sudo rm /etc/apt/sources.list.d/cri-o.list 
        sudo rm /etc/apt/keyrings/cri-o-apt-keyring.gpg
      fi

    if command -v apt-get &> /dev/null; then
      curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
      gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
      echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] \
      https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" \
      |sudo tee /etc/apt/sources.list.d/cri-o.list
      sudo apt-get update
      sudo apt-get install -y cri-o 
      sudo systemctl start crio.service
    else
      if command -v yum &> /dev/null; then
        PKG_MGR="yum"
      else
        PKG_MGR="dnf"
      fi

       if [ -f /etc/yum.repos.d/cri-o.repo ]; then
        sudo rm /etc/yum.repos.d/cri-o.repo
      fi

      # add repo
      cat <<EOF | sudo tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/rpm/repodata/repomd.xml.key
EOF

      sudo $PKG_MGR install -y cri-o 
      sudo mv /etc/cni/net.d/10-crio-bridge.conflist.disabled /etc/cni/net.d/10-crio-bridge.conflist
      sudo systemctl start crio.service 
    fi
}


 # Intall Kubernetes
in_kube(){
  echo "Installing Kubernetes..."
  KUBERNETES_VERSION="v1.33"
  # Check containerd (docker) installed

  if ! command -v containerd &> /dev/null; then
    echo " Containerd not install or not run"
    read -p "Do you install docker now :" ye
    if [[ ! "$ye" =~ ^[Yy]$ ]]; then
      exit 0
    else
      iddock = $(i_docker)
      echo "$iddock"
    fi
  fi

  # Check the operating system and install Kubernetes accordingly
  # Install using native package management
  # Check if the system is Debian-based (e.g., Ubuntu)
  if command -v apt-get &> /dev/null; then
      # Update package list and install necessary packages
    sudo apt-get update -y
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg software-properties-common

    # Check if /etc/apt/keyrings exists, create if not
    if [ ! -d /etc/apt/keyrings ]; then
        sudo mkdir -p -m 755 /etc/apt/keyrings
    fi
    curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg    sudo chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg  # Allow unprivileged APT programs to read this keyring
    # Add the Kubernetes repository
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    # Update package list again to include the new Kubernetes repository
    sudo apt-get update
    # Install Kubernetes components
    sudo apt-get install -y kubelet kubeadm kubectl 
    sudo apt-mark hold kubelet kubeadm kubectl  # Prevent these packages from being upgraded
    # Enable and start kubelet service
    sudo systemctl enable --now kubelet
    echo "Kubernetes installation completed successfully."

  # Check if the system is Redhat-based 
  elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
      echo "Detected Red Hat-based system. Installing Kubernetes..."
      if command -v yum &> /dev/null; then
        PKG_MGR="yum"
      else
        PKG_MGR="dnf"
      fi
      # Set SELinux in permissive mode (effectively disabling it)
      sudo setenforce 0
      sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
      # This overwrites any existing configuration in /etc/yum.repos.d/kubernetes.repo and delete file old
      if [ -f /etc/yum.repos.d/kubernetes.repo ] ; then
        sudo rm /etc/yum.repos.d/kubernetes.repo
      fi
    # create file repo
      cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
      
      sudo $PKG_MGR install -y curl 
      sudo $PKG_MGR install -y kubelet kubeadm kubectl --disabclleexcludes=kubernetes
      sudo systemctl enable --now kubelet


  # Without a package manager
  # Install CNI plugins (required for most pod network):      
  else
    CNI_PLUGINS_VERSION="v1.3.0"
    ARCH=$(dpkg --print-architecture)
    DEST="/opt/cni/bin"
    sudo mkdir -p "$DEST"
    sudo curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" | sudo tar -C "$DEST" -xz
    DOWNLOAD_DIR="/usr/local/bin"
    sudo mkdir -p "$DOWNLOAD_DIR"
    RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
    cd $DOWNLOAD_DIR
    sudo curl -L --remote-name-all https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet}
    sudo chmod +x {kubeadm,kubelet}
    RELEASE_VERSION="v0.16.2"
    sudo curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /usr/lib/systemd/system/kubelet.service
    sudo mkdir -p /usr/lib/systemd/system/kubelet.service.d
    curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
    sudo systemctl enable --now kubelet
    sudo systemctl start --now kubelet
  fi
}

# Check kubeadm run on master 
k8s_master() {
  i_crio=$(in_cri)  # Function to check if CRI-O is in use
  read -p "You use cri-o. Do you want to continue? (y/n): " confirm
  
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "$i_crio"
    sock_api="crio.sock" 
  else
    sock_api="containerd.sock" 
  fi

  # Create kubeadm-config.yaml 
  cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
networking:
  podSubnet: "10.244.0.0/16"
apiServer:
  extraArgs:
    criSocket: "unix:///var/run/containerd/$sock_api"  # containerd.sock or crio.sock
EOF

  # Check if kubelet is active
  if systemctl is-active --quiet kubelet; then
    sudo kubeadm init --config kubeadm-config.yaml  # Use --config flag for kubeadm
  else
    echo "Kubelet is not installed or not running. Please check your system."
    get_install=$(in_kube)  # Function to check kubelet installation
    echo "$get_install"
    
    # Check if kubelet is active using the correct command
    if systemctl is-active --quiet kubelet; then
      sudo kubeadm init --config kubeadm-config.yaml  # Use --config flag for kubeadm
    else
      echo "Kubelet is still not active. Please install and start kubelet."
    fi
  fi
  # Install Pod add-on
  ipa=$(i_pod_addon)
  echo "$ipa"
  
}


# Config, Install a Pod Network Add-on
i_pod_addon(){
  if systemctl is-active --quiet kubelet; then
    if [ [$? -eq 0] || [-f /etc/kubernetes/admin.conf]]; then
      mkdir -p $HOME/.kube
      sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
      sudo chown $(id -u):$(id -g) $HOME/.kube/config
      echo "Kubernetes master node initialized successfully."
      echo "You can now install a pod network add-on, e.g.:"
      echo "kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
      # Generate join command as root and export to a text file in $HOME
      #JOIN_CMD=$(kubeadm token create --print-join-command)
      #echo "$JOIN_CMD" > "$HOME/kubeadm-join-command.txt"
      #echo "$JOIN_CMD" | tee kubeadm-join-command.txt
      #echo "Join command exported to kubeadm-join-command.txt"
      echo "kube get nodes -o wide"
    else
      echo "Kubernetes master node initialization failed."
    fi
  else
    echo "Kubelet not install or not run"
  fi 
}
# Check interfaces
get_interfaces() {
 ip -o link show up | awk -F': ' '{print $2}' | grep -v "lo"   
}

# Reboot VM 
rb(){
  read -p "Reboot ! (Y/N) : " ok
  if [[ ! "$ok" =~ ^[Yy]$ ]]; then
    echo "Not reboot."
    return $1
  else
    sudo systemctl reboot
  fi
}




# Function to display the menu
display_menu() {
    echo "=============================="
    echo "   Custom Linux Menu"
    echo "=============================="
    echo "1) Change Hostname, enable no passwd sudoer and Set IP Static"
    echo "2) No Setting"
    echo "3) Change Static IP Address"
    echo "4) No Setting"
    echo "5) Disable SELinux, Firewalld & Enable IP Forwarding, disable swap"
    echo "6) Install Docker"
    echo "7) Install Kubernetes"
    echo "8) Initialize Kubernetes and addon Calico for Master after install Kubelet "
    echo "9) No Setting"
    echo "0) Exit"
    echo "------------------------------"
}

# Function to handle user input
handle_choice() {
  case $1 in
    1)
    hs=$(change_hostname)
    echo "$hs"
      ;;
    2)
    
      ;;
    3)
    # Change IP
    cip=$(change_ip)
    echo "$cip"
      ;;
    4)
    
      ;;
    5)
    # Set up OS for create
    setos=$(set_os)
    echo "$setos"
      ;;
    6)
    # Install docker
    idk=$(i_docker)
    echo "$idk"
      ;;
    7)
    # Install kube
    kube=$(in_kube)
    echo "$kube"
      ;;
    8)
    # Master
    ms=$(k8s_master)
    echo "$ms"
      ;;
    9)
    
      ;;
    0)
      echo "Thank you for using the Custom Linux!" 
      echo "Goodbye!"
      exit 0
      ;;
    *)
      echo "Invalid choice. Please try again."
      ;;
  esac
}

# Main loop to display the menu and handle user input
while true; do
    display_menu
    read -p "Enter your choice: " choice
    handle_choice "$choice"
    echo
done
# 