#!/bin/bash

# IRSSH VPN Management System Installation Script
# Designed and compiled by MeHrSaM

# Error handling
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Error function
error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

# Warning function
warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root" 
fi

# Check if running on Ubuntu 22.04
if [[ $(lsb_release -rs) != "22.04" ]]; then
    error "This script is designed for Ubuntu 22.04. Your system is running $(lsb_release -ds)"
fi

# Collect initial configuration information
log "Collecting initial configuration information..."
read -p "Enter the administrator username: " admin_username
read -sp "Enter the administrator password: " admin_password
echo
read -p "Enter the server IP address: " server_ip
read -p "Enter the 4-digit web port: " web_port

# Update system
log "Updating system..."
apt update && apt upgrade -y

# Install dependencies
log "Installing dependencies..."
apt install -y curl wget git unzip nginx postgresql nodejs npm

# Install Docker
log "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker $USER

# Install Docker Compose
log "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Clone the repository
log "Downloading the VPN Management System installation script..."
repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installvpn.sh"
mkdir -p /opt/vpn-management-system
wget $repo_url -O /opt/vpn-management-system/install.sh
chmod +x /opt/vpn-management-system/install.sh

# Change to the installation directory
cd /opt/vpn-management-system

# Setup database
log "Setting up database..."
db_name="vpn_management"
db_user="vpnuser"
db_password=$(openssl rand -base64 12)

# Check if database exists
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
    warning "Database '$db_name' already exists."
    read -p "Do you want to use the existing database? (y/n): " use_existing_db
    if [[ $use_existing_db == "n" ]]; then
        read -p "Enter a new database name: " db_name
    fi
fi

# Create database if it doesn't exist
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
    sudo -u postgres psql -c "CREATE DATABASE $db_name;"
    log "Database '$db_name' created."
else
    log "Using existing database '$db_name'."
fi

# Create user if it doesn't exist
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$db_user'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE USER $db_user WITH PASSWORD '$db_password';"
    log "Database user '$db_user' created."
else
    log "Database user '$db_user' already exists. Using existing user."
fi

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;"

# Create a default .env file
log "Creating default .env file..."
cat > .env << EOF
ADMIN_USERNAME=$admin_username
ADMIN_PASSWORD=$admin_password
SERVER_IP=$server_ip
WEB_PORT=$web_port
DB_DATABASE=$db_name
DB_USERNAME=$db_user
DB_PASSWORD=$db_password
EOF

# Create a basic docker-compose.yml file
log "Creating docker-compose.yml file..."
cat > docker-compose.yml << EOF
version: '3'
services:
  app:
    image: node:14
    working_dir: /app
    volumes:
      - ./:/app
    ports:
      - "${web_port}:3000"
    environment:
      - NODE_ENV=production
    command: npm start
    depends_on:
      - db
  db:
    image: postgres:13
    environment:
      POSTGRES_DB: $db_name
      POSTGRES_USER: $db_user
      POSTGRES_PASSWORD: $db_password
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
EOF

# Build and start Docker containers
log "Building and starting Docker containers..."
docker-compose up -d --build

# Setup Nginx reverse proxy
log "Setting up Nginx reverse proxy..."
cat > /etc/nginx/sites-available/vpn-management << EOF
server {
    listen 80;
    server_name $server_ip;

    location / {
        proxy_pass http://localhost:$web_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

ln -s /etc/nginx/sites-available/vpn-management /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# Setup SSL with Let's Encrypt
log "Setting up SSL with Let's Encrypt..."
apt install -y certbot python3-certbot-nginx
read -p "Do you want to set up SSL now? (y/n): " setup_ssl
if [[ $setup_ssl == "y" ]]; then
    certbot --nginx -d $server_ip
else
    log "SSL setup skipped. You can set it up later using: certbot --nginx -d $server_ip"
fi

# Setup firewall
log "Configuring firewall..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow $web_port
ufw enable

# VPN protocol installation function
install_vpn_protocol() {
    local protocol=$1
    log "Installing $protocol..."
    case $protocol in
        "SSH")
            # Install and configure SSH
            apt install -y openssh-server
            # TODO: Add SSH-specific configuration
            ;;
        "IKEv2/IPsec")
            # Install and configure IKEv2/IPsec
            apt install -y strongswan libstrongswan-standard-plugins libcharon-extra-plugins
            # TODO: Add IKEv2/IPsec-specific configuration
            ;;
        "L2TP/IPSec")
            # Install and configure L2TP/IPSec
            apt install -y xl2tpd
            # TODO: Add L2TP/IPSec-specific configuration
            ;;
        "Cisco AnyConnect")
            # Install and configure Cisco AnyConnect
            # TODO: Add Cisco AnyConnect-specific installation and configuration
            ;;
        "WireGuard")
            # Install and configure WireGuard
            apt install -y wireguard
            # TODO: Add WireGuard-specific configuration
            ;;
        "ShadowSocks")
            # Install and configure ShadowSocks
            apt install -y shadowsocks-libev
            # TODO: Add ShadowSocks-specific configuration
            ;;
        "V2Ray")
            # Install and configure V2Ray
            bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
            # TODO: Add V2Ray-specific configuration
            ;;
        *)
            warning "Unknown protocol: $protocol"
            ;;
    esac
}

# VPN protocol installation menu
install_vpn_protocols() {
    while true; do
        echo "Select VPN protocols to install:"
        echo "1) SSH"
        echo "2) IKEv2/IPsec"
        echo "3) L2TP/IPSec"
        echo "4) Cisco AnyConnect"
        echo "5) WireGuard"
        echo "6) ShadowSocks"
        echo "7) V2Ray"
        echo "8) Finish installation"
        read -p "Enter your choice: " choice
        case $choice in
            1) install_vpn_protocol "SSH" ;;
            2) install_vpn_protocol "IKEv2/IPsec" ;;
            3) install_vpn_protocol "L2TP/IPSec" ;;
            4) install_vpn_protocol "Cisco AnyConnect" ;;
            5) install_vpn_protocol "WireGuard" ;;
            6) install_vpn_protocol "ShadowSocks" ;;
            7) install_vpn_protocol "V2Ray" ;;
            8) break ;;
            *) echo "Invalid option. Please try again." ;;
        esac
    done
}

# Main installation process
main() {
    log "Starting VPN Management System installation..."
    
    # Run the downloaded installation script
    log "Running the VPN Management System installation script..."
    bash /opt/vpn-management-system/install.sh

    # VPN protocol installation
    install_vpn_protocols

    log "VPN Management System installation complete!"
    log "Access the web interface at http://$server_ip:$web_port"
    log "Admin login: $admin_username / $admin_password"
    warning "Please change the default password immediately after logging in."
}

# Run the main installation process
main

exit 0
