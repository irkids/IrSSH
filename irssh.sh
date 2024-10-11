#!/bin/bash

# Set up error handling
set -e

# Define the installation directory
INSTALL_DIR="/opt/vpn-management-system"

# Create the installation directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

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

# Main installation process
echo "Starting VPN Management System installation..."

# Install Docker script
setup_script "https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/Docker.yml" "Docker.yml"

# Install menu script
setup_script "https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/menu.sh" "menu.sh"

# Install web UI script
setup_script "https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installIu.sh" "installIu.sh"

echo "All scripts have been downloaded and set up in $INSTALL_DIR"
echo "Installation complete!"

# Optionally, you can add code here to run the scripts in the desired order
# For example:
# bash "$INSTALL_DIR/Docker.yml"
# bash "$INSTALL_DIR/menu.sh"
# bash "$INSTALL_DIR/installIu.sh"

exit 0
