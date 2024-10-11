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

# Function to check and install general prerequisites
check_general_prerequisites() {
    install_package "wget"
    install_package "git"
    install_package "curl"
}

# Function to download and set up a script
setup_script() {
    local repo_url="$1"
    local filename="$2"
    local filepath="$INSTALL_DIR/$filename"

    if [ -f "$filepath" ]; then
        echo "$filename already exists. Skipping download."
    else
        echo "Downloading $filename..."
        wget "$repo_url" -O "$filepath"
        chmod +x "$filepath"
        echo "$filename downloaded and made executable."
    fi
}

# Function to check and install Docker and Docker Compose
check_docker_prerequisites() {
    install_package "apt-transport-https"
    install_package "ca-certificates"
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
if ! sudo docker-compose -f Docker.yml config > /dev/null 2>&1; then
    echo "Error: Docker.yml file is not a valid Docker Compose configuration."
    echo "Please check the contents of $INSTALL_DIR/Docker.yml for any syntax errors."
    echo "Common issues include missing colons after keys or incorrect indentation."
    exit 1
fi

sudo docker-compose -f Docker.yml up -d

# Run the other scripts
echo "Running menu script..."
sudo bash "$INSTALL_DIR/menu.sh"

echo "Running web UI installation script..."
sudo bash "$INSTALL_DIR/installIu.sh"

echo "Installation and setup complete!"

exit 0
