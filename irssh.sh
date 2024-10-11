#!/bin/bash

# Function to check and install Docker if it's not installed
install_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker..."
    apt-get update
    apt-get install -y docker.io
  else
    echo "Docker is already installed."
  fi
}

# Function to check and install Docker Compose if it's not installed
install_docker_compose() {
  if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose not found. Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  else
    echo "Docker Compose is already installed."
  fi
}

# Download necessary files
echo "Downloading /opt/vpn-management-system/Docker.yml..."
repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/Docker.yml"
wget $repo_url -O /opt/vpn-management-system/Docker.yml

echo "Downloading /opt/vpn-management-system/menu.sh..."
repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/menu.sh"
wget $repo_url -O /opt/vpn-management-system/menu.sh
chmod +x /opt/vpn-management-system/menu.sh

echo "Downloading /opt/vpn-management-system/installIu.sh..."
repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installIu.sh"
wget $repo_url -O /opt/vpn-management-system/installIu.sh
chmod +x /opt/vpn-management-system/installIu.sh

# Install Docker and Docker Compose
install_docker
install_docker_compose

# Run Docker Compose using the Docker.yml file
echo "Running Docker Compose setup..."
docker-compose -f /opt/vpn-management-system/Docker.yml up -d

# Continue with the rest of your setup...
echo "Running menu setup..."
/opt/vpn-management-system/menu.sh

echo "Running UI installer..."
/opt/vpn-management-system/installIu.sh

echo "Setup complete."
