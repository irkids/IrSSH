#!/bin/bash

# Advanced L2TP/IPSec VPN Installation Script
# This script installs and configures a L2TP/IPSec VPN server with PostgreSQL integration

# Exit immediately if a command exits with a non-zero status
set -e

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This script must be run as root"
        exit 1
    fi
}

# Function to install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."
    apt-get update
    apt-get install -y \
        strongswan \
        xl2tpd \
        ppp \
        lsof \
        iptables-persistent \
        postgresql \
        postgresql-contrib \
        libpq-dev \
        python3-pip
    pip3 install psycopg2-binary
}

# Function to configure IPSec
configure_ipsec() {
    log "Configuring IPSec..."
    cat > /etc/ipsec.conf <<EOF
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    keyexchange=ikev1
    authby=secret
    ike=aes256-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,3des-sha1!

conn L2TP-PSK-NAT
    leftfirewall=yes
    leftsubnet=0.0.0.0/0
    right=%any
    rightsubnet=10.0.0.0/24
    narrowing=yes
    type=transport
    auto=add
    dpddelay=30
    dpdtimeout=120
    dpdaction=clear
EOF

    # Generate a random PSK
    PSK=$(openssl rand -base64 32)
    echo ": PSK \"$PSK\"" > /etc/ipsec.secrets
    chmod 600 /etc/ipsec.secrets
}

# Function to configure xl2tpd
configure_xl2tpd() {
    log "Configuring xl2tpd..."
    cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

[lns default]
ip range = 10.0.0.2-10.0.0.254
local ip = 10.0.0.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
mtu 1280
mru 1280
proxyarp
lcp-echo-failure 4
lcp-echo-interval 30
connect-delay 5000
EOF
}

# Function to configure iptables
configure_iptables() {
    log "Configuring iptables..."
    iptables -t nat -A POSTROUTING -j SNAT --to-source $(curl -s ifconfig.me) -o eth0
    iptables -A INPUT -p udp --dport 1701 -j ACCEPT
    iptables -A INPUT -p udp --dport 500 -j ACCEPT
    iptables -A INPUT -p udp --dport 4500 -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
}

# Function to enable IP forwarding
enable_ip_forwarding() {
    log "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    echo "net.ipv4.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
    echo "net.ipv4.conf.all.send_redirects = 0" >> /etc/sysctl.conf
    echo "net.ipv4.conf.default.rp_filter = 0" >> /etc/sysctl.conf
    echo "net.ipv4.conf.default.accept_source_route = 0" >> /etc/sysctl.conf
    echo "net.ipv4.conf.default.send_redirects = 0" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_ignore_bogus_error_responses = 1" >> /etc/sysctl.conf
    sysctl -p
}

# Function to setup PostgreSQL
setup_postgresql() {
    log "Setting up PostgreSQL..."
    sudo -u postgres psql -c "CREATE DATABASE vpn_users;"
    sudo -u postgres psql -c "CREATE USER vpn_admin WITH PASSWORD 'strong_password';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpn_users TO vpn_admin;"
    
    sudo -u postgres psql vpn_users <<EOF
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(100) NOT NULL,
    ip_address VARCHAR(15),
    connected_since TIMESTAMP,
    bytes_sent BIGINT DEFAULT 0,
    bytes_received BIGINT DEFAULT 0
);

CREATE INDEX idx_username ON users(username);
EOF
}

# Function to create a Python script for user management
create_user_management_script() {
    log "Creating user management script..."
    cat > /usr/local/bin/vpn_user_manager.py <<EOF
#!/usr/bin/env python3

import psycopg2
import argparse
import subprocess

DB_NAME = "vpn_users"
DB_USER = "vpn_admin"
DB_PASSWORD = "strong_password"
DB_HOST = "localhost"

def connect_db():
    return psycopg2.connect(dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD, host=DB_HOST)

def add_user(username, password):
    with connect_db() as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO users (username, password) VALUES (%s, %s)", (username, password))
    subprocess.run(["chap-secrets", "add", username, password])

def remove_user(username):
    with connect_db() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM users WHERE username = %s", (username,))
    subprocess.run(["chap-secrets", "remove", username])

def list_users():
    with connect_db() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT username, ip_address, connected_since, bytes_sent, bytes_received FROM users")
            users = cur.fetchall()
    for user in users:
        print(f"Username: {user[0]}, IP: {user[1]}, Connected since: {user[2]}, Bytes sent: {user[3]}, Bytes received: {user[4]}")

def main():
    parser = argparse.ArgumentParser(description="Manage VPN users")
    parser.add_argument("action", choices=["add", "remove", "list"])
    parser.add_argument("--username", help="Username for add/remove actions")
    parser.add_argument("--password", help="Password for add action")
    args = parser.parse_args()

    if args.action == "add":
        if not args.username or not args.password:
            print("Username and password are required for add action")
            return
        add_user(args.username, args.password)
    elif args.action == "remove":
        if not args.username:
            print("Username is required for remove action")
            return
        remove_user(args.username)
    elif args.action == "list":
        list_users()

if __name__ == "__main__":
    main()
EOF
    chmod +x /usr/local/bin/vpn_user_manager.py
}

# Function to optimize VPN performance
optimize_vpn() {
    log "Optimizing VPN performance..."
    # Increase maximum number of open files
    echo "* soft nofile 51200" >> /etc/security/limits.conf
    echo "* hard nofile 51200" >> /etc/security/limits.conf
    
    # Optimize kernel parameters
    cat >> /etc/sysctl.conf <<EOF
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF
    sysctl -p
}

# Main function to run the installation
main() {
    check_root
    install_prerequisites
    configure_ipsec
    configure_xl2tpd
    configure_iptables
    enable_ip_forwarding
    setup_postgresql
    create_user_management_script
    optimize_vpn
    
    log "L2TP/IPSec VPN installation completed successfully!"
    log "Use the vpn_user_manager.py script to manage users."
    log "Example: /usr/local/bin/vpn_user_manager.py add --username johndoe --password secretpass"
}

# Run the main function
main
