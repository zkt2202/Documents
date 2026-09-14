#!/bin/bash
# This script installs Docker on a Debian or Red Hat-based system.
# It checks the architecture and operating system, installs necessary packages,
# and sets up Docker to run as a service.
# Ensure the script is run as root
# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo' or switch to the root user."
    exit 1
fi

# Update the package list
sudo apt-get update -y
# check arch 
ARCH=$(uname -m)
# check os
OS=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
# Install required packages based on architecture
if [ "$OS" != "debian" ]; then
    sudo yum install -y apt-transport-https ca-certificates curl gnupg lsb-release || sudo dnf install -y apt-transport-https ca-certificates curl gnupg lsb-release
else
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
fi

# isntall docker
# check installed docker
if command -v docker &> /dev/null; then
    echo "Docker is already installed."
    else
        if [ "$OS" == "debian" ]; then
            sudo apt-get install -y docker.io
        else
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/$(echo $OS | tr '[:lower:]' '[:upper:]')/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            # Add Docker's stable repository
            echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(echo $OS | tr '[:lower:]' '[:upper:') $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            # Update the package list again
            sudo apt-get update -y
            # Install Docker redhat
            sudo yum install -y docker-ce docker-ce-cli containerd.io || sudo dnf install -y docker-ce docker-ce-cli containerd.io
            # Install Docker on Red Hat-based systems
            # Check if yum or dnf is available
            sudo yum install -y yum-utils || sudo dnf install -y yum-utils
            # Set up the stable repository
            sudo yum-config-manager --add-repo https://download.docker.com/linux/$(echo $OS | tr '[:lower:]' '[:upper:]')/docker-ce.repo || sudo dnf config-manager --add-repo https://download.docker.com/linux/$(echo $OS | tr '[:lower:]' '[:upper:]')/docker-ce.repo
            # Install Docker
            # Check if yum or dnf is available
            sudo yum install -y docker || sudo dnf install -y docker
            # Start and enable Docker service
            sudo systemctl start docker
            sudo systemctl enable docker
            # Add the current user to the Docker group
            sudo usermod -aG docker $USER
            echo "Docker installed successfully."
        fi

fi
