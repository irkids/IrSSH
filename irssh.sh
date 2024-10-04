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
log "Cloning the VPN Management System repository..."
read -p "Enter the GitHub repository URL for the VPN Management System: " repo_url
git clone $repo_url /opt/vpn-management-system
cd /opt/vpn-management-system

# Setup environment variables
log "Setting up environment variables..."
cp .env.example .env
# Prompt for necessary environment variables
read -p "Enter the database name: " db_name
read -p "Enter the database user: " db_user
read -sp "Enter the database password: " db_password
echo
sed -i "s/DB_DATABASE=.*/DB_DATABASE=$db_name/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$db_user/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_password/" .env

# Build and start Docker containers
log "Building and starting Docker containers..."
docker-compose up -d --build

# Setup Nginx reverse proxy
log "Setting up Nginx reverse proxy..."
read -p "Enter your domain name: " domain_name
cat > /etc/nginx/sites-available/vpn-management << EOF
server {
    listen 80;
    server_name $domain_name;

    location / {
        proxy_pass http://localhost:3000;
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
    certbot --nginx -d $domain_name
else
    log "SSL setup skipped. You can set it up later using: certbot --nginx -d $domain_name"
fi

# Setup firewall
log "Configuring firewall..."
ufw allow 22
ufw allow 80
ufw allow 443
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
    
    # Install core components
    # ... (previous steps remain the same)

    # VPN protocol installation
    install_vpn_protocols

    log "VPN Management System installation complete!"
    log "Access the web interface at https://$domain_name"
    log "Default login: admin / password"
    warning "Please change the default password immediately after logging in."
}

# Run the main installation process
main

exit 0
