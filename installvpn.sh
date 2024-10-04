#!/bin/bash

# Comprehensive Ubuntu 22.04 VPN Server Setup Script
# This script sets up a VPN server with SSH, IKEv2/IPsec, L2TP/IPSec, WireGuard, and Cisco AnyConnect (OpenConnect) protocols

# Exit on any error
set -e

# Function to check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" 
        exit 1
    fi
}

# Function to update and upgrade system
update_system() {
    apt update && apt upgrade -y
}

# Function to install common prerequisites
install_prerequisites() {
    apt install -y build-essential git curl wget unzip ufw
}

# Function to set up UFW (Uncomplicated Firewall)
setup_ufw() {
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 500,4500/udp # For IPsec
    ufw allow 1701/udp # For L2TP
    ufw allow 51820/udp # For WireGuard
    ufw allow 443/tcp # For OpenConnect
    ufw enable
}

# Function to optimize system for VPN performance
optimize_system() {
    # Enable IP forwarding
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    
    # Increase max open files
    echo "* soft nofile 51200" >> /etc/security/limits.conf
    echo "* hard nofile 51200" >> /etc/security/limits.conf
    
    # Optimize network settings
    cat << EOF >> /etc/sysctl.conf
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p
}

# Function to set up SSH server
setup_ssh() {
    # Harden SSH configuration
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart ssh
}

# Function to set up IPsec/IKEv2
setup_ikev2() {
    # Install StrongSwan
    apt install -y strongswan strongswan-pki libcharon-extra-plugins libcharon-extauth-plugins libstrongswan-extra-plugins
    
    # Generate certificates
    mkdir -p ~/pki/{cacerts,certs,private}
    chmod 700 ~/pki
    ipsec pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/ca-key.pem
    ipsec pki --self --ca --lifetime 3650 --in ~/pki/private/ca-key.pem --type rsa --dn "CN=VPN root CA" --outform pem > ~/pki/cacerts/ca-cert.pem
    ipsec pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/server-key.pem
    ipsec pki --pub --in ~/pki/private/server-key.pem --type rsa | ipsec pki --issue --lifetime 1825 --cacert ~/pki/cacerts/ca-cert.pem --cakey ~/pki/private/ca-key.pem --dn "CN=$(hostname)" --san "$(hostname)" --flag serverAuth --flag ikeIntermediate --outform pem > ~/pki/certs/server-cert.pem

    # Copy certificates
    cp -r ~/pki/* /etc/ipsec.d/

    # Configure StrongSwan
    cat << EOF > /etc/ipsec.conf
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    keyexchange=ikev2
    authby=secret

conn ikev2-vpn
    left=%any
    leftid=$(hostname)
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightdns=8.8.8.8,8.8.4.4
    rightsendcert=never
    eap_identity=%identity
    auto=add
EOF

    # Set up secrets
    echo ": RSA server-key.pem" > /etc/ipsec.secrets
    echo "your_username : EAP \"your_password\"" >> /etc/ipsec.secrets

    # Restart StrongSwan
    systemctl restart strongswan-starter
}

# Function to set up L2TP/IPsec
setup_l2tp() {
    # Install necessary packages
    apt install -y xl2tpd

    # Configure xl2tpd
    cat << EOF > /etc/xl2tpd/xl2tpd.conf
[global]
ipsec saref = yes
saref refinfo = 30

[lns default]
ip range = 10.20.20.100-10.20.20.250
local ip = 10.20.20.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    # Configure PPP
    cat << EOF > /etc/ppp/options.xl2tpd
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
crtscts
idle 1800
mtu 1280
mru 1280
lock
lcp-echo-failure 10
lcp-echo-interval 60
connect-delay 5000
EOF

    # Set up secrets
    echo "your_username * your_password *" > /etc/ppp/chap-secrets

    # Restart xl2tpd
    systemctl restart xl2tpd
}

# Function to set up WireGuard
setup_wireguard() {
    # Install WireGuard
    apt install -y wireguard

    # Generate keys
    wg genkey | tee /etc/wireguard/server_private_key | wg pubkey > /etc/wireguard/server_public_key
    
    # Configure WireGuard
    cat << EOF > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $(cat /etc/wireguard/server_private_key)
Address = 10.30.30.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = CLIENT_PUBLIC_KEY
AllowedIPs = 10.30.30.2/32
EOF

    # Enable and start WireGuard
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
}

# Function to set up OpenConnect (Cisco AnyConnect)
setup_openconnect() {
    # Install OpenConnect
    apt install -y ocserv

    # Generate certificates
    mkdir -p /etc/ocserv/ssl
    cd /etc/ocserv/ssl
    certtool --generate-privkey --outfile server-key.pem
    cat << EOF > server.tmpl
cn = "VPN Server"
organization = "Your Organization"
expiration_days = 3650
signing_key
encryption_key
tls_www_server
EOF
    certtool --generate-self-signed --load-privkey server-key.pem --template server.tmpl --outfile server-cert.pem

    # Configure OpenConnect
    cat << EOF > /etc/ocserv/ocserv.conf
auth = "plain[passwd=/etc/ocserv/ocpasswd]"
tcp-port = 443
udp-port = 443
run-as-user = nobody
run-as-group = daemon
socket-file = /var/run/ocserv-socket
server-cert = /etc/ocserv/ssl/server-cert.pem
server-key = /etc/ocserv/ssl/server-key.pem
ca-cert = /etc/ocserv/ssl/server-cert.pem
isolate-workers = true
max-clients = 0
max-same-clients = 2
server-stats-reset-time = 604800
keepalive = 32400
dpd = 90
mobile-dpd = 1800
switch-to-tcp-timeout = 25
try-mtu-discovery = true
cert-user-oid = 0.9.2342.19200300.100.1.1
tls-priorities = "NORMAL:%SERVER_PRECEDENCE:%COMPAT:-VERS-SSL3.0"
auth-timeout = 240
min-reauth-time = 300
max-ban-score = 50
ban-reset-time = 300
cookie-timeout = 300
deny-roaming = false
rekey-time = 172800
rekey-method = ssl
use-occtl = true
pid-file = /var/run/ocserv.pid
device = vpns
predictable-ips = true
ipv4-network = 10.40.40.0
ipv4-netmask = 255.255.255.0
dns = 8.8.8.8
dns = 8.8.4.4
ping-leases = false
route = default
no-route = 192.168.0.0/255.255.0.0
no-route = 10.0.0.0/255.0.0.0
no-route = 172.16.0.0/255.240.0.0
no-route = 127.0.0.0/255.0.0.0
EOF

    # Create user
    echo "your_username" | ocpasswd -c /etc/ocserv/ocpasswd your_username

    # Enable and start OpenConnect
    systemctl enable ocserv
    systemctl start ocserv
}

# Main function to run all setup functions
main() {
    check_root
    update_system
    install_prerequisites
    setup_ufw
    optimize_system
    setup_ssh
    setup_ikev2
    setup_l2tp
    setup_wireguard
    setup_openconnect
    
    echo "VPN server setup complete!"
}

# Run the main function
main
