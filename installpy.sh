#!/bin/bash

# Installing prerequisites
sudo apt update
sudo apt install -y python3 python3-pip mysql-server

# Link to the Python script from GitHub (replace this with your actual link)
https://raw.githubusercontent.com/irkids/IrSSH/main/install.py="https://raw.githubusercontent.com/irkids/IrSSH/main/install.py"

# Downloading Python script
wget $https://raw.githubusercontent.com/irkids/IrSSH/main/install.py -O /tmp/install.py

# Running the Python script
python3 /tmp/install.py
