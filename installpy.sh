#!/bin/bash

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo or su to switch to root."
    exit 1
fi

# Update the package list
apt-get update

# Install necessary dependencies
apt-get install -y python3 python3-pip curl

# Download and run the Python script
curl -Ls https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/install.py -o install.py
sudo python3 install.py

# Clean up
rm install.py
