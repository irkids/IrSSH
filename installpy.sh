#!/bin/bash

# Installing prerequisites
sudo apt update
sudo apt install -y python3 python3-pip mysql-server

# Link to the Python script from GitHub
PYTHON_SCRIPT_URL="https://raw.githubusercontent.com/irkids/IrSSH/main/install.py"

# Downloading Python script
wget $PYTHON_SCRIPT_URL -O /tmp/install.py

# Running the Python script
python3 /tmp/install.py
