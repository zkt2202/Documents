: '
menu.sh - Custom Linux Menu Script

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
'
#!/bin/bash
# menu.sh
# This script provides a menu for managing Kubernetes and other system configurations.
# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo' or switch to the root user."
    exit 1
fi  
# Function to display the menu
display_menu() {
    echo "=============================="
    echo "   Custom Linux Menu"
    echo "=============================="
    echo "1) Change Hostname, enable no passwd sudoer and Set IP Static"
    echo "2) Change Ip"
    echo "3) Disable SELinux, Firewalld & Enable IP Forwarding, disable swap"
    echo "4) Install docker"
    echo "5) No Config"
    echo "6) No Config"
    echo "7) No Config"
    echo "8) Install kubernetes  "
    echo "9) Initialize Kubernetes and addon Calico for Master after install Kubelet, for master"
    echo "0) Exit"
    echo "------------------------------"
}

# Default: use sudo unless --no-sudo is specified
usesudo="${usesudo:-true}"

# Check if sudo is available and wanted
run_sudo(){
    if [ [ "$usesudo" == "true" ] ]; then
        if command -v sudo &>/dev/null; then
            SUDO="sudo"
            echo "sudo detected and will be used."
        else
            echo "sudo not found. Switching to no-sudo mode."
            SUDO=""
            echo "Some installation steps may fail if run without root privileges."
        fi
    else
        SUDO=""
        echo "Running in no-sudo mode."
        echo "Some installation steps may fail if run without root privileges."
    fi
}


# Get Username
uname=$(whoami)
gname=$(id -gn ${uname})
admintoken=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)

ARCH=$(uname -m)

# identify OS
if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
        UPSTREAM_ID="$(echo ${ID_LIKE,,} | sed s/\"//g | cut -d' ' -f1)"
    fi
elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    OS=SuSE
    VER=$(cat /etc/SuSe-release)
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi


# output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]; then
    echo "OS: $OS"
    echo "VER: $VER"
    echo "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi


# Check interfaces
get_interfaces() {
 ip -o link show up | awk -F': ' '{print $2}' | grep -v "lo"   
}

# Reboot VM 
rb(){
  read -p "Reboot ! (Y/N) : " ok
  if  [ ! "$ok" =~ ^[Yy]$ ]; then
    echo "Not reboot."
    return $1
  else
    sudo systemctl reboot
  fi
}

get_o() {
  if [ [ -f /etc/os-release ] ]; then
    # On Linux, source the file and return the ID (e.g., ubuntu, fedora, alpine)
    source /etc/os-release
    echo "$ID"
  else
    # On macOS or BSD, use uname to get the OS name
    uname
  fi
}

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



# Usage
#os=$(get_os)
#echo "Operating System: $os"

# Enable no password sudoer
dis_pw(){
  sudo bash -c 'echo "$(logname) ALL=(ALL:ALL) NOPASSWD: ALL" | (EDITOR="tee -a" visudo)'
  echo "Sudoer no password has been enabled."
}

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

# Function to handle user input
handle_choice() {
    case $1 in
        1)
        # Change hostname ...
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
            setip = $(set_ip)
            echo "$setip"
            # Reboot
            read -p "Reboot apply setting IP. (y): " cb
            if [ "$cb" =~ ^[Yy]$ ] ; then
                rb2=$(rb)
                echo "$rb2"
            fi
            ;;
        2)
        # Change new IP address 
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
            # Reboot 
            rb3=$(rb)
            echo "$rb3"
            ;;
        3)
        # Check and install policycoreutils if getenforce or setenforce is missing for setup k8s.
            if ! command -v getenforce &> /dev/null || ! command -v setenforce &> /dev/null; then
                echo "Installing policycoreutils to manage SELinux..."
                if command -v yum &> /dev/null; then
                    sudo yum install -y policycoreutils || sudo apt-get install -y policycoreutils || sudo dnf install -y policycoreutils
                else
                    echo "Package manager not found. Please install policycoreutils manually."
                    exit 1
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
                echo "IPv4 IP forwarding is disabled. Enabling it..."
                sudo sysctl -w net.ipv4.ip_forward=1
                sudo sed -i 's/^net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
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
            ;;
        4)
        # Docker
            echo "Checking Docker installation..."
            if command -v docker &> /dev/null; then
                # Docker installed , remove and install new versions , not skip 
                read -p "Docker is already installed. Do you want to continue? (y/n) and remove Docker old and reinstall: " cfd
                if [[ "$cfd" =~ ^[Yy]$ ]]; then
                    # Remove versions old and reboot.
                    echo "Removing old Docker installation and reboot ..."
                    if [ "$OS" = "Ubuntu" ]; then
                        sudo systemctl stop docker
                        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
                            sudo apt-get remove -y $pkg
                        done
                        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
                        sudo rm -f /etc/apt/sources.list.d/docker.list
                        sudo rm -f /etc/apt/keyrings/docker.asc

                    elif [ "$OS" = "Debian" ]; then
                        sudo systemctl stop docker
                        for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
                            sudo apt-get remove -y $pkg
                        done
                        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
                        sudo rm -f /etc/apt/sources.list.d/docker.list
                        sudo rm -f /etc/apt/keyrings/docker.asc

                    elif [ "$OS" = "RedHat" ]; then
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

                    elif [ "$OS" = "Fedora" ]; then
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

                    elif [ "$OS" = "CentOS" ]; then
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

                    elif [ "$OS" = "Raspbian" ]; then
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
                    sudo rm  -rf /usr/local/bin/com.docker.cli
                    echo "Docker removed successfully. Rebooting..."
                    # Reboot
                    rb1=$(rb)
                    echo "$rb1"
                fi
            else
                echo "Docker not found. Installing Docker..."
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update
                    sudo apt-get install -y ca-certificates curl gnupg
                    sudo install -m 0755 -d /etc/apt/keyrings
                    curl -fsSL https://download.docker.com/linux/$(./etc/os-release; echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(./etc/os-release; echo "$ID") $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
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
            fi
            ;;
        5)
           
            ;;
        6)
        # No config
            ;;
        7)
        # No config
            ;;

        8)
        # Install Kubernetes
            echo "Installing Kubernetes..."
            KUBERNETES_VERSION="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
            echo "Install Kubernetes version : $KUBERNETES_VERSION"
            
            # Check containerd (docker) installed
            if ! command -v containerd &> /dev/null; then
                echo " Containerd not install, install now."
                if command apt-get &> /dev/null; then
                    sudo apt-get update
                    sudo apt-get install -y containerd
                else 
                    echo "Detected Red Hat-based system. Installing Kubernetes..."
                    if command -v yum &> /dev/null; then
                        PKG_MGR="yum"
                    else
                        PKG_MGR="dnf"
                    fi
                    sudo yum install -y containerd
                fi
                sudo containerd config default | sudo tee /etc/containerd/config.toml
                sudo systemctl start containerd
                sudo systemctl enable containerd
                sudo systemctl status containerd
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
                echo "Kubernet not install, OS not support"
                exit 0
            fi
            echo " Run 9: with master node."
            ;;
        
        9) 
        # For Master Kube
            echo "Initializing Kubernetes master node..."
            # Check kubeadm run on master 
            if systemctl is-active --quiet kubelet; then
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
                sudo kubeadm init --config kubeadm-config.yaml

                # Config, Install a Pod Network Add-on
                if [ [$? -eq 0] || [-f /etc/kubernetes/admin.conf] ]; then
                    mkdir -p $HOME/.kube
                    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
                    sudo chown $(id -u):$(id -g) $HOME/.kube/config
                    sudo "Kubernetes master node initialized successfully."
                    sudo "You can now install a pod network add-on, e.g.:"
                    sudo "kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
                    sudo "kube get nodes -o wide"
                fi
            else
                echo "Kubelet not install or not run, check system."
            fi      
            ;;

        0)
            echo "Thank you for using the Custom Linux Menu!"
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