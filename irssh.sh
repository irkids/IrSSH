#!/bin/bash

# Define installation directory
INSTALL_DIR="/opt/vpn-management-system"

# Create the installation directory if it doesn't exist
mkdir -p $INSTALL_DIR

# Function to download scripts
download_script() {
    local repo_url=$1
    local output_file=$2
    echo "Downloading $output_file..."
    wget $repo_url -O $output_file
    if [[ $? -ne 0 ]]; then
        echo "Error downloading $output_file. Please check the repository link."
        exit 1
    fi
    chmod +x $output_file
    echo "$output_file downloaded and made executable."
}

# 1. Download Docker script
docker_repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/Docker.yml"
download_script $docker_repo_url "$INSTALL_DIR/Docker.yml"

# 2. Download VPN protocol installation menu script
menu_repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/menu.sh"
download_script $menu_repo_url "$INSTALL_DIR/menu.sh"

# 3. Download Web-based UI management script
ui_repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installIu.sh"
download_script $ui_repo_url "$INSTALL_DIR/installIu.sh"

# Run Docker setup (if Docker.yml script is executable)
echo "Running Docker setup..."
cd $INSTALL_DIR
./Docker.yml
if [[ $? -ne 0 ]]; then
    echo "Error running Docker setup. Please check the Docker.yml script."
    exit 1
fi

# Run VPN protocol installation menu script
echo "Running VPN protocol installation menu..."
./menu.sh
if [[ $? -ne 0 ]]; then
    echo "Error running VPN installation menu script."
    exit 1
fi

# Run web-based UI management script
echo "Running Web-based UI setup..."
./installIu.sh
if [[ $? -ne 0 ]]; then
    echo "Error running Web-based UI setup."
    exit 1
fi

echo "All scripts have been successfully installed and executed."

# Provide final instructions or messages
echo "VPN Management System and Web-based UI are successfully installed."
echo "Please navigate to your server's IP address to access the Web-based UI."

exit 0
