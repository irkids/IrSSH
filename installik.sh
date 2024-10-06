#!/bin/bash

# Advanced IKEv2/IPsec VPN Server Setup Script
# This script sets up a high-performance IKEv2/IPsec VPN server with PostgreSQL integration

set -e

# Global variables
VPN_DOMAIN=""
POSTGRES_PASSWORD="your_secure_password"  # This should match the password in the original script
VPN_IP_RANGE="10.10.10.0/24"  # This should match the IP range in the original script
VPN_DNS_SERVERS="8.8.8.8,8.8.4.4"  # This should match the DNS servers in the original script

# Function to prompt for VPN domain
prompt_vpn_domain() {
    while [[ -z "$VPN_DOMAIN" ]]; do
        read -p "Please enter the real address of your VPN domain or subdomain: " VPN_DOMAIN
        if [[ -z "$VPN_DOMAIN" ]]; then
            echo "VPN domain cannot be empty. Please try again."
        fi
    done
    echo "VPN domain set to: $VPN_DOMAIN"
}

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

# Function to install necessary dependencies
install_dependencies() {
    apt install -y strongswan libcharon-extra-plugins libstrongswan-extra-plugins postgresql postgresql-contrib fail2ban ufw
}

# Function to tune kernel for IPsec
tune_kernel() {
    cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
EOF
    sysctl -p
}

# Function to configure StrongSwan
configure_strongswan() {
    cat > /etc/strongswan.conf <<EOF
charon {
    threads = 16
    ikesa_table_size = 4096
    install_routes = yes
    install_virtual_ip = yes
    ignore_routing_tables = 1
    load_modular = yes
}

log {
    default = 2
    filelog {
        /var/log/ipsec.log {
            time_format = %b %e %T
            append = no
            default = 2
        }
    }
}
EOF
}

# Function to generate certificates
generate_certificates() {
    mkdir -p /etc/ipsec.d/private /etc/ipsec.d/cacerts /etc/ipsec.d/certs

    ipsec pki --gen --outform pem > /etc/ipsec.d/private/caKey.pem
    chmod 600 /etc/ipsec.d/private/caKey.pem
    ipsec pki --self --in /etc/ipsec.d/private/caKey.pem --dn "CN=IKEv2 VPN CA" --ca --outform pem > /etc/ipsec.d/cacerts/caCert.pem

    ipsec pki --gen --outform pem > /etc/ipsec.d/private/serverKey.pem
    chmod 600 /etc/ipsec.d/private/serverKey.pem
    ipsec pki --pub --in /etc/ipsec.d/private/serverKey.pem | ipsec pki --issue --cacert /etc/ipsec.d/cacerts/caCert.pem --cakey /etc/ipsec.d/private/caKey.pem --dn "CN=$VPN_DOMAIN" --san "$VPN_DOMAIN" --flag serverAuth --flag ikeIntermediate --outform pem > /etc/ipsec.d/certs/serverCert.pem
}

# Function to configure ipsec.conf
configure_ipsec() {
    cat > /etc/ipsec.conf <<EOF
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    keyexchange=ikev2
    ike=aes256-sha256-ecp384!
    esp=aes256gcm16-sha256!

conn ikev2-vpn
    left=%any
    leftid=@$VPN_DOMAIN
    leftcert=serverCert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=$VPN_IP_RANGE
    rightdns=$VPN_DNS_SERVERS
    authby=secret
    eap_identity=%identity
    auto=add
EOF
}

# Function to configure ipsec.secrets
configure_secrets() {
    echo ': RSA "serverKey.pem"' > /etc/ipsec.secrets
    echo 'your_username : EAP "your_password"' >> /etc/ipsec.secrets
    chmod 600 /etc/ipsec.secrets
}

# Function to configure PostgreSQL
configure_postgresql() {
    sudo -u postgres psql -c "CREATE DATABASE vpn_db;"
    sudo -u postgres psql -c "CREATE USER vpn_user WITH ENCRYPTED PASSWORD '$POSTGRES_PASSWORD';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpn_db TO vpn_user;"

    sudo -u postgres psql vpn_db <<EOF
CREATE TABLE vpn_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    connection_status BOOLEAN DEFAULT FALSE,
    last_login TIMESTAMP
);

CREATE TABLE vpn_sessions (
    session_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES vpn_users(id),
    ip_address VARCHAR(255),
    login_time TIMESTAMP,
    logout_time TIMESTAMP
);
EOF

    # Optimize PostgreSQL
    sed -i 's/^max_connections =.*/max_connections = 500/' /etc/postgresql/*/main/postgresql.conf
    sed -i 's/^shared_buffers =.*/shared_buffers = 4GB/' /etc/postgresql/*/main/postgresql.conf
    sed -i 's/^#work_mem =.*/work_mem = 64MB/' /etc/postgresql/*/main/postgresql.conf
    sed -i 's/^#maintenance_work_mem =.*/maintenance_work_mem = 256MB/' /etc/postgresql/*/main/postgresql.conf
    sed -i 's/^#wal_buffers =.*/wal_buffers = 16MB/' /etc/postgresql/*/main/postgresql.conf

    # Enable SSL for PostgreSQL
    sed -i 's/^#ssl =.*/ssl = on/' /etc/postgresql/*/main/postgresql.conf
    sed -i "s|^#ssl_cert_file =.*|ssl_cert_file = '/etc/ssl/certs/ssl-cert.pem'|" /etc/postgresql/*/main/postgresql.conf
    sed -i "s|^#ssl_key_file =.*|ssl_key_file = '/etc/ssl/private/ssl-cert.key'|" /etc/postgresql/*/main/postgresql.conf

    systemctl restart postgresql
}

# Function to configure firewall
configure_firewall() {
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 500,4500/udp
    ufw enable
}

# Function to configure fail2ban
configure_fail2ban() {
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sed -i 's/bantime  = 10m/bantime  = 1h/' /etc/fail2ban/jail.local
    sed -i 's/findtime  = 10m/findtime  = 20m/' /etc/fail2ban/jail.local
    sed -i 's/maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local
    systemctl restart fail2ban
}

# Function to set up monitoring (Prometheus exporter for IPsec)
setup_monitoring() {
    wget https://github.com/pakerin/ipsec_exporter/releases/download/v0.3.1/ipsec_exporter-0.3.1.linux-amd64.tar.gz
    tar xvzf ipsec_exporter-0.3.1.linux-amd64.tar.gz
    mv ipsec_exporter-0.3.1.linux-amd64/ipsec_exporter /usr/local/bin/
    chmod +x /usr/local/bin/ipsec_exporter

    cat > /etc/systemd/system/ipsec_exporter.service <<EOF
[Unit]
Description=IPsec Exporter
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ipsec_exporter

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ipsec_exporter
    systemctl start ipsec_exporter
}

# Function to set up backup
setup_backup() {
    apt install -y borgbackup

    mkdir /backup
    borg init --encryption=repokey /backup

    cat > /root/backup.sh <<EOF
#!/bin/bash
borg create --stats --progress /backup::{now:%Y-%m-%d} /etc/ipsec.* /etc/strongswan.conf
pg_dump vpn_db | borg create --stats --progress /backup::vpn_db-{now:%Y-%m-%d}
EOF

    chmod +x /root/backup.sh

    echo "0 2 * * * /root/backup.sh" | crontab -
}

# Main function to run all setup steps
main() {
    check_root
    prompt_vpn_domain
    update_system
    install_dependencies
    tune_kernel
    configure_strongswan
    generate_certificates
    configure_ipsec
    configure_secrets
    configure_postgresql
    configure_firewall
    configure_fail2ban
    setup_monitoring
    setup_backup

    # Restart services
    systemctl restart strongswan-starter
    systemctl restart postgresql

    echo "IKEv2/IPsec VPN server setup complete!"
    echo "VPN Domain: $VPN_DOMAIN"
    echo "VPN IP Range: $VPN_IP_RANGE"
    echo "VPN DNS Servers: $VPN_DNS_SERVERS"
    echo "Please ensure to update the VPN user credentials in /etc/ipsec.secrets"
}

# Run the main function
main
