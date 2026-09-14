#!/bin/bash
# check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo' or switch to the root user."
    exit 1
fi 
read -p "This script will set a static IP address. Do you want to continue? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

read -p "Enter the interface name (e.g., eth0, enp0s3): " interface
read -p "Enter the static IP address (e.g., 192.168.9): " static_ip
read -p "Enter the subnet mask (e.g., 255.255.255.0): " subnet_mask
read -p "Enter the gateway (e.g., 192.168.9.1): " gateway
read -p "Enter the DNS server (e.g., 8.8.8. 8): " dns_server    
# check if the interface exists
if ! ip link show "$interface" > /dev/null 2>&1; then
    echo "Interface '$interface' does not exist. Please check the interface name and try again."
    exit 1
elif [[ -z "$static_ip" || -z "$subnet_mask" || -z "$gateway" || -z "$dns_server" ]]; then
    echo "All fields are required. Please provide valid inputs."
    exit 1
fi

# Set the static IP address
if [ -f /etc/netplan/50-cloud-init.yaml ]; then
    # For systems using netplan (e.g., Ubuntu)
    echo "Setting static IP for Ubuntu..."
    cat <<EOF > /etc/netplan/50-cloud-init.yaml
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
    netplan apply
    echo "Static IP set successfully for Ubuntu."
elif [ -f /etc/network/interfaces ]; then
    # For Debian-based systems
    echo "Setting static IP for Debian..."
    cat <<EOF > /etc/network/interfaces
auto $interface
iface $interface inet static
    address $static_ip
    netmask $subnet_mask
    gateway $gateway
    dns-nameservers $dns_server
EOF
    systemctl restart networking
    echo "Static IP set successfully for Debian."
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
    systemctl restart network
    echo "Static IP set successfully for Red Hat-based system."
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
    systemctl restart systemd-networkd
    echo "Static IP set successfully for Arch Linux."
elif [ -f /etc/NetworkManager/system-connections/$interface ]; then
    # For systems using NetworkManager
    echo "Setting static IP for NetworkManager-managed system..."
    nmcli con modify "$interface" ipv4.addresses "$static_ip/24"
    nmcli con modify "$interface" ipv4.gateway "$gateway"
    nmcli con modify "$interface" ipv4.dns "$dns_server"
    nmcli con modify "$interface" ipv4.method manual
    nmcli con up "$interface"
    echo "Static IP set successfully for NetworkManager-managed system."
else
    echo "Unsupported operating system or network configuration."
    exit 1
fi  
