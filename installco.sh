#!/bin/bash

# Enhanced Cisco AnyConnect VPN Configuration Script
# This script sets up and optimizes a server for use with Cisco AnyConnect VPN
# and integrates it with PostgreSQL for user management and logging.

# Error handling
set -e

# Variables (using environment variables with defaults)
OCSERV_VERSION=${OCSERV_VERSION:-"1.3.0"}
OCSERV_CONFIG=${OCSERV_CONFIG:-"/etc/ocserv/ocserv.conf"}
OCPASSWD_FILE=${OCPASSWD_FILE:-"/etc/ocserv/ocpasswd"}
LOG_FILE=${LOG_FILE:-"/var/log/ocserv.log"}
PID_FILE=${PID_FILE:-"/var/run/ocserv.pid"}
SETUP_LOG=${SETUP_LOG:-"/var/log/vpn_setup.log"}
PG_PASSWORD=${PG_PASSWORD:-""}
DOMAIN=${DOMAIN:-""}
VPN_TCP_PORT=${VPN_TCP_PORT:-443}
VPN_UDP_PORT=${VPN_UDP_PORT:-4443}

# Function to log messages
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$SETUP_LOG"
}

# Error handling function
error_exit() {
    log_message "Error on line $1"
    exit 1
}

trap 'error_exit $LINENO' ERR

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_message "This script must be run as root"
   exit 1
fi

# Function to detect OS
detect_os() {
    if [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        log_message "Unsupported OS"
        exit 1
    fi
    log_message "Detected OS: $OS"
}

# Function to install dependencies
install_dependencies() {
    log_message "Installing dependencies"
    if [ "$OS" == "debian" ]; then
        apt-get update
        for pkg in postgresql postgresql-contrib nginx fail2ban ufw gnutls-bin libgnutls28-dev libwrap0-dev liblz4-dev libseccomp-dev libreadline-dev libnl-nf-3-dev libev-dev iptables-persistent pgtune certbot; do
            if ! dpkg -l | grep -q $pkg; then
                apt-get install -y $pkg || { log_message "Failed to install $pkg"; exit 1; }
            fi
        done
    elif [ "$OS" == "centos" ]; then
        yum install -y epel-release
        for pkg in postgresql postgresql-server nginx fail2ban firewalld gnutls gnutls-devel tcp_wrappers-devel lz4-devel libseccomp-devel readline-devel libnl3-devel libev-devel pgtune certbot; do
            if ! rpm -q $pkg &>/dev/null; then
                yum install -y $pkg || { log_message "Failed to install $pkg"; exit 1; }
            fi
        done
    fi
    log_message "Dependencies installed successfully"
}

# Optimize kernel parameters
optimize_kernel() {
    log_message "Optimizing kernel parameters"
    cat << EOF > /etc/sysctl.d/99-vpn.conf
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_syncookies=1
net.core.netdev_max_backlog=2500
net.ipv4.ip_local_port_range=1024 65000
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_max_tw_buckets=400000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_window_scaling=1
net.ipv4.ip_forward=1
EOF
    sysctl --system || { log_message "Failed to apply sysctl settings"; exit 1; }
    log_message "Kernel parameters optimized successfully"
}

# Configure PostgreSQL
configure_postgresql() {
    log_message "Configuring PostgreSQL"
    if [ "$OS" == "centos" ]; then
        postgresql-setup initdb || { log_message "Failed to initialize PostgreSQL database"; exit 1; }
        systemctl start postgresql || { log_message "Failed to start PostgreSQL service"; exit 1; }
    fi

    # Use environment variable for password if set, otherwise prompt
    if [ -z "$PG_PASSWORD" ]; then
        read -s -p "Enter PostgreSQL password for vpn_user: " PG_PASSWORD
        echo
    fi

    # Check if database and user already exist
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='vpn_db'" | grep -q 1; then
        sudo -u postgres psql -c "CREATE DATABASE vpn_db;" || { log_message "Failed to create vpn_db"; exit 1; }
    fi

    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='vpn_user'" | grep -q 1; then
        sudo -u postgres psql -c "CREATE USER vpn_user WITH ENCRYPTED PASSWORD '$PG_PASSWORD';" || { log_message "Failed to create vpn_user"; exit 1; }
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpn_db TO vpn_user;" || { log_message "Failed to grant privileges to vpn_user"; exit 1; }
    fi

    # Dynamically set PostgreSQL version
    PG_VERSION=$(psql --version | awk '{print $3}' | cut -d '.' -f1,2)
    POSTGRES_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"

    # Use pgtune for optimal PostgreSQL settings
    pgtune -i $POSTGRES_CONF -o ${POSTGRES_CONF}.new || { log_message "Failed to optimize PostgreSQL configuration"; exit 1; }
    mv ${POSTGRES_CONF}.new $POSTGRES_CONF

    systemctl restart postgresql || { log_message "Failed to restart PostgreSQL service"; exit 1; }
    log_message "PostgreSQL configuration complete"
}

# Install and configure ocserv
install_ocserv() {
    log_message "Installing ocserv"
    if ! command -v ocserv &> /dev/null; then
        if [ "$OS" == "debian" ]; then
            apt-get install -y ocserv || {
                wget "ftp://ftp.infradead.org/pub/ocserv/ocserv-${OCSERV_VERSION}.tar.xz"
                tar -xf "ocserv-${OCSERV_VERSION}.tar.xz"
                cd "ocserv-${OCSERV_VERSION}"
                ./configure || { log_message "Configure failed"; exit 1; }
                make || { log_message "Make failed"; exit 1; }
                make install || { log_message "Make install failed"; exit 1; }
                cd ..
                rm -rf "ocserv-${OCSERV_VERSION}" "ocserv-${OCSERV_VERSION}.tar.xz"
            }
        elif [ "$OS" == "centos" ]; then
            yum install -y ocserv || {
                wget "ftp://ftp.infradead.org/pub/ocserv/ocserv-${OCSERV_VERSION}.tar.xz"
                tar -xf "ocserv-${OCSERV_VERSION}.tar.xz"
                cd "ocserv-${OCSERV_VERSION}"
                ./configure || { log_message "Configure failed"; exit 1; }
                make || { log_message "Make failed"; exit 1; }
                make install || { log_message "Make install failed"; exit 1; }
                cd ..
                rm -rf "ocserv-${OCSERV_VERSION}" "ocserv-${OCSERV_VERSION}.tar.xz"
            }
        fi
    fi
    log_message "ocserv installation complete"
}

# Configure ocserv
configure_ocserv() {
    log_message "Configuring ocserv"
    mkdir -p /etc/ocserv
    wget -O ${OCSERV_CONFIG} "https://raw.githubusercontent.com/sfc9982/AnyConnect-Server/main/ocserv.conf" || { log_message "Failed to download ocserv config"; exit 1; }

    # Generate SSL certificate using Let's Encrypt
    if [ -z "$DOMAIN" ]; then
        read -p "Enter domain for SSL certificate: " DOMAIN
    fi

    # Check if domain is properly configured
    if ! host $DOMAIN > /dev/null 2>&1; then
        log_message "Domain $DOMAIN is not properly configured. Falling back to self-signed certificate."
        mkdir -p /etc/ocserv/ssl
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -keyout /etc/ocserv/ssl/server-key.pem -out /etc/ocserv/ssl/server-cert.pem -subj "/C=US/ST=YourState/L=YourCity/O=YourOrg/CN=${DOMAIN}" || { log_message "Failed to create self-signed certificate"; exit 1; }
    else
        certbot certonly --standalone -d $DOMAIN --agree-tos --email admin@$DOMAIN --non-interactive || {
            log_message "Certbot failed, falling back to self-signed certificate"
            mkdir -p /etc/ocserv/ssl
            openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -keyout /etc/ocserv/ssl/server-key.pem -out /etc/ocserv/ssl/server-cert.pem -subj "/C=US/ST=YourState/L=YourCity/O=YourOrg/CN=${DOMAIN}" || { log_message "Failed to create self-signed certificate"; exit 1; }
        }
        # Add renewal configuration
        echo "0 0,12 * * * root certbot renew --quiet --post-hook 'systemctl reload ocserv'" > /etc/cron.d/certbot-renew
    fi

    # Set up ocserv service with enhanced security
    cat << EOF > /etc/systemd/system/ocserv.service
[Unit]
Description=OpenConnect SSL VPN server
After=network.target

[Service]
ExecStart=/usr/local/sbin/ocserv --foreground --pid-file ${PID_FILE} --config ${OCSERV_CONFIG}
PIDFile=${PID_FILE}
Restart=on-failure
RestartSec=10
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ocserv
    log_message "ocserv configuration complete"
}

# Configure firewall
configure_firewall() {
    log_message "Configuring firewall"
    if [ "$OS" == "debian" ]; then
        ufw allow 22/tcp
        ufw allow ${VPN_TCP_PORT}/tcp
        ufw allow ${VPN_UDP_PORT}/udp
        ufw limit ssh/tcp
        ufw logging on
        ufw enable
    elif [ "$OS" == "centos" ]; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-port=${VPN_TCP_PORT}/tcp
        firewall-cmd --permanent --add-port=${VPN_UDP_PORT}/udp
        firewall-cmd --permanent --add-rich-rule='rule service name="ssh" limit value="5/m" accept'
        firewall-cmd --reload
    fi

    # Set up NAT
    INTERFACE=$(ip route | grep default | awk '{print $5}')
    iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4
    fi
    log_message "Firewall configuration complete"
}

# Configure SELinux (for CentOS)
configure_selinux() {
    if [ "$OS" == "centos" ]; then
        if sestatus | grep -q "SELinux status:\s*enabled"; then
            log_message "Configuring SELinux policies"
            setsebool -P httpd_can_network_connect 1
            semanage port -a -t http_port_t -p tcp ${VPN_TCP_PORT}
            semanage port -a -t http_port_t -p udp ${VPN_UDP_PORT}
        fi
    fi
}

# Configure fail2ban
configure_fail2ban() {
    log_message "Configuring fail2ban"
    cat << EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[ocserv]
enabled = true
port = ${VPN_TCP_PORT},${VPN_UDP_PORT}
filter = ocserv
logpath = /var/log/ocserv.log
maxretry = 3
bantime = 3600
EOF

    systemctl restart fail2ban
    log_message "fail2ban configuration complete"
}

# Verify services
verify_services() {
    log_message "Verifying services"
    services=("postgresql" "ocserv" "fail2ban")
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet $service; then
            log_message "$service is not running. Attempting to start..."
            systemctl start $service || { log_message "Failed to start $service"; exit 1; }
        fi
    done
    log_message "All services are running"
}

# Main installation process
main() {
    detect_os
    install_dependencies
    optimize_kernel
    configure_postgresql
    install_ocserv
    configure_ocserv
    configure_firewall
    configure_selinux
    configure_fail2ban
    verify_services

    log_message "VPN server setup complete"
    echo "VPN server setup complete. Please review and adjust configurations as needed."
}

main
