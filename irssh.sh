#!/bin/bash

# Set up error handling
set -e

# Define the installation directory
INSTALL_DIR="/opt/vpn-management-system"

# Create the installation directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install a package
install_package() {
    if ! command_exists "$1"; then
        echo "Installing $1..."
        sudo apt-get update
        sudo apt-get install -y "$1"
    else
        echo "$1 is already installed."
    fi
}

# Function to download and set up a script
setup_script() {
    local repo_url="$1"
    local filename="$2"
    local filepath="$INSTALL_DIR/$filename"

    echo "Downloading $filename..."
    wget "$repo_url" -O "$filepath"
    chmod +x "$filepath"
    echo "$filename downloaded and made executable."
}

# Function to check and install Docker prerequisites
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
}

# Function to check and install general prerequisites
check_general_prerequisites() {
    install_package "wget"
    install_package "git"
}

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

# Run the scripts in order
echo "Running Docker setup script..."
sudo bash "$INSTALL_DIR/Docker.yml"

echo "Running menu script..."
sudo bash "$INSTALL_DIR/menu.sh"

echo "Running web UI installation script..."
sudo bash "$INSTALL_DIR/installIu.sh"

echo "Installation and setup complete!"

exit 0
