#!/bin/bash

# Set up error handling
set -e

# Define the installation directory
INSTALL_DIR="/opt/vpn-management-system"

# ... [previous parts of the script remain unchanged] ...

# Function to check and install Docker and Docker Compose
check_docker_prerequisites() {
    install_package "apt-transport-https"
    install_package "ca-certificates"
    install_package "curl"
    install_package "software-properties-common"

    if ! command_exists docker; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
    else
        echo "Docker is already installed."
    fi

    if ! command_exists docker-compose; then
        echo "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        echo "Docker Compose is already installed."
    fi
}

# ... [other functions remain unchanged] ...

# Main installation process
echo "Starting VPN Management System installation..."

# Check and install general prerequisites
check_general_prerequisites

# Install Docker script
setup_script "https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/Docker.yml" "Docker.yml"

# Install menu script
setup_script "https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/menu.sh" "menu.sh"

# Install web UI script
setup_script "https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installIu.sh" "installIu.sh"

echo "All scripts have been downloaded and set up in $INSTALL_DIR"

# Check and install Docker prerequisites
check_docker_prerequisites

# Run Docker Compose
echo "Setting up Docker containers..."
cd "$INSTALL_DIR"
sudo docker-compose -f Docker.yml up -d

# Run the other scripts
echo "Running menu script..."
sudo bash "$INSTALL_DIR/menu.sh"

echo "Running web UI installation script..."
sudo bash "$INSTALL_DIR/installIu.sh"

echo "Installation and setup complete!"

exit 0
