#!/bin/bash

# ---- Initial setup: Check directories and permissions ----

# Check if the directory exists, if not, create it
if [ ! -d "/var/www/html/app/Scripts" ]; then
  echo "Directory /var/www/html/app/Scripts not found. Creating it..."
  sudo mkdir -p /var/www/html/app/Scripts
fi

# Check if get_network_stats.php file exists, if not, create a placeholder
if [ ! -f "/var/www/html/app/Scripts/get_network_stats.php" ]; then
  echo "File get_network_stats.php not found. Creating a placeholder..."
  sudo touch /var/www/html/app/Scripts/get_network_stats.php
  echo "<?php // Placeholder for get_network_stats.php ?>" | sudo tee /var/www/html/app/Scripts/get_network_stats.php > /dev/null
fi

# Set ownership and permissions for the files
echo "Setting ownership and permissions for /var/www/html/..."
sudo chown -R www-data:www-data /var/www/html/
sudo chmod -R 755 /var/www/html/

# ---- Install and Configure Nethogs ----

# Install nethogs if not already installed
if ! command -v nethogs &> /dev/null
then
    echo "Nethogs could not be found. Installing Nethogs..."
    sudo apt-get update && sudo apt-get install -y nethogs
else
    echo "Nethogs is already installed."
fi

# ---- Upgrade Node.js to the required version ----
echo "Upgrading Node.js to version 16..."
curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt-get install -y nodejs

# Ensure npm is installed
if ! command -v npm &> /dev/null
then
    echo "npm is not installed. Installing npm..."
    sudo apt-get install -y npm
fi

# ---- Build and Refresh Frontend (React) ----
cd /var/www/html/app

# Install dependencies and build the project
echo "Installing npm dependencies and building frontend..."
npm install
npm run build

# ---- Test the API endpoint ----
echo "Testing API endpoint to check network stats..."
curl http://localhost/api/network-stats

# Final message
echo "Setup complete. The network statistics will be displayed in the Online User section."
