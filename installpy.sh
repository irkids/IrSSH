#!/bin/bash

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Update the package list
apt-get update

# Install Python and pip
apt-get install -y python3 python3-pip

# Install MySQL server
debconf-set-selections <<< 'mysql-server mysql-server/root_password password rootpassword'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password rootpassword'
apt-get install -y mysql-server

# Install mysql-connector-python library
pip3 install mysql-connector-python

# Install subprocess module
pip3 install subprocess32

# Download the Python script from the repository
wget -O /opt/python_script.py https://raw.githubusercontent.com/irkids/IrSSH/main/install.py

# Run the Python script
python3 /opt/python_script.py
