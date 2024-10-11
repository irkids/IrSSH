#!/bin/bash

# VPN Management Script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${!1}%s${NC}\n" "$2"
}

# Function to check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "RED" "This script must be run as root"
        exit 1
    fi
}

# Function to install prerequisites
install_prerequisites() {
    print_color "YELLOW" "Installing prerequisites..."
    apt update
    apt install -y wget curl
}

# Function to change Ubuntu 22.04 to VPN server
change_to_vpn_server() {
    print_color "YELLOW" "Changing Ubuntu 22.04 to VPN server..."
    repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installvpn.sh"
    wget $repo_url -O /opt/vpn-management-system/installvpn.sh
    chmod +x /opt/vpn-management-system/installvpn.sh
    /opt/vpn-management-system/installvpn.sh
}

# Function to install SSH protocol
install_ssh() {
    print_color "YELLOW" "Installing SSH protocol..."
    repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/inssh.sh"
    wget $repo_url -O /opt/vpn-management-system/inssh.sh
    chmod +x /opt/vpn-management-system/inssh.sh
    /opt/vpn-management-system/inssh.sh
}

# Function to install IKEv2/IPsec protocol
install_ikev2() {
    print_color "YELLOW" "Installing IKEv2/IPsec protocol..."
    repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installik.sh"
    wget $repo_url -O /opt/vpn-management-system/installik.sh
    chmod +x /opt/vpn-management-system/installik.sh
    /opt/vpn-management-system/installik.sh
}

# Function to install L2TP/IPSec protocol
install_l2tp() {
    print_color "YELLOW" "Installing L2TP/IPSec protocol..."
    repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installl2.sh"
    wget $repo_url -O /opt/vpn-management-system/installl2.sh
    chmod +x /opt/vpn-management-system/installl2.sh
    /opt/vpn-management-system/installl2.sh
}

# Function to install Cisco AnyConnect protocol
install_anyconnect() {
    print_color "YELLOW" "Installing Cisco AnyConnect protocol..."
    repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installco.sh"
    wget $repo_url -O /opt/vpn-management-system/installco.sh
    chmod +x /opt/vpn-management-system/installco.sh
    /opt/vpn-management-system/installco.sh
}

# Function to install WireGuard protocol
install_wireguard() {
    print_color "YELLOW" "Installing WireGuard protocol..."
    repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installwi.sh"
    wget $repo_url -O /opt/vpn-management-system/installwi.sh
    chmod +x /opt/vpn-management-system/installwi.sh
    /opt/vpn-management-system/installwi.sh
}

# Function to install ShadowSocks protocol
install_shadowsocks() {
    print_color "YELLOW" "Installing ShadowSocks protocol..."
    repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installsw.sh"
    wget $repo_url -O /opt/vpn-management-system/installsw.sh
    chmod +x /opt/vpn-management-system/installsw.sh
    /opt/vpn-management-system/installsw.sh
}

# Function to install V2Ray protocol
install_v2ray() {
    print_color "YELLOW" "Installing V2Ray protocol..."
    repo_url="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main/installray.sh"
    wget $repo_url -O /opt/vpn-management-system/installray.sh
    chmod +x /opt/vpn-management-system/installray.sh
    /opt/vpn-management-system/installray.sh
}

# Function to display menu
display_menu() {
    clear
    print_color "GREEN" "=== VPN Management System ==="
    echo "1. Install SSH protocol"
    echo "2. Install IKEv2/IPsec protocol"
    echo "3. Install L2TP/IPSec protocol"
    echo "4. Install Cisco AnyConnect protocol"
    echo "5. Install WireGuard protocol"
    echo "6. Install ShadowSocks protocol"
    echo "7. Install V2Ray protocol"
    echo "8. Exit"
    echo
    read -p "Enter your choice [1-8]: " choice
}

# Main function
main() {
    check_root
    install_prerequisites
    change_to_vpn_server

    while true; do
        display_menu

        case $choice in
            1) install_ssh ;;
            2) install_ikev2 ;;
            3) install_l2tp ;;
            4) install_anyconnect ;;
            5) install_wireguard ;;
            6) install_shadowsocks ;;
            7) install_v2ray ;;
            8) print_color "GREEN" "Exiting. Goodbye!"; exit 0 ;;
            *) print_color "RED" "Invalid option. Please try again." ;;
        esac

        echo
        read -p "Press Enter to continue..."
    done
}

# Run the main function
main
