#!/bin/bash

set -euo pipefail

# ShadowSocks VPN Protocol Installation Script
# This script installs and configures ShadowSocks with advanced optimizations,
# PostgreSQL database integration, and enhanced monitoring capabilities.

# --- Variables ---
SS_VERSION="3.3.5"
SS_CONFIG="/etc/shadowsocks-libev/config.json"
SS_SERVICE="/etc/systemd/system/shadowsocks-libev.service"
POSTGRES_VERSION="13"
DB_NAME="shadowsocks_vpn"
DB_USER=""
DB_PASSWORD=""
SS_PASSWORD=""
WORKERS=$(nproc)
BACKUP_DIR="/var/backups/postgres"
LOG_FILE="/var/log/shadowsocks_install.log"

# --- Functions ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
}

prompt_user() {
    read -p "Enter PostgreSQL username: " DB_USER
    DB_PASSWORD=$(openssl rand -base64 32)
    SS_PASSWORD=$(openssl rand -base64 32)
    
    echo "Generated passwords:"
    echo "PostgreSQL password: $DB_PASSWORD"
    echo "ShadowSocks password: $SS_PASSWORD"
    echo "Please save these passwords securely and press Enter to continue..."
    read
}

install_dependencies() {
    log "Installing dependencies..."
    apt-get update || error_exit "Failed to update package lists"
    apt-get install -y \
        build-essential \
        autoconf \
        libtool \
        libssl-dev \
        libpcre3-dev \
        libev-dev \
        asciidoc \
        xmlto \
        automake \
        git \
        curl \
        postgresql \
        postgresql-contrib \
        libpq-dev \
        python3-pip \
        prometheus \
        node-exporter \
        grafana \
        ufw \
        pgbouncer \
        fail2ban \
        gnupg \
        || error_exit "Failed to install dependencies"

    pip3 install psycopg2-binary || error_exit "Failed to install psycopg2-binary"
}

install_shadowsocks() {
    log "Installing ShadowSocks..."
    git clone https://github.com/shadowsocks/shadowsocks-libev.git || error_exit "Failed to clone ShadowSocks repository"
    cd shadowsocks-libev
    git checkout "v${SS_VERSION}" || error_exit "Failed to checkout ShadowSocks version ${SS_VERSION}"
    ./autogen.sh && ./configure && make && make install || error_exit "Failed to compile and install ShadowSocks"
    cd ..
    rm -rf shadowsocks-libev

    log "Installing simple-obfs plugin..."
    git clone https://github.com/shadowsocks/simple-obfs.git || error_exit "Failed to clone simple-obfs repository"
    cd simple-obfs
    git submodule update --init --recursive
    ./autogen.sh && ./configure && make && make install || error_exit "Failed to compile and install simple-obfs"
    cd ..
    rm -rf simple-obfs
}

configure_shadowsocks() {
    log "Configuring ShadowSocks..."
    mkdir -p /etc/shadowsocks-libev
    cat > $SS_CONFIG <<EOL
{
    "server":"0.0.0.0",
    "server_port":8388,
    "password":"${SS_PASSWORD}",
    "timeout":300,
    "method":"xchacha20-ietf-poly1305",
    "fast_open":true,
    "workers":${WORKERS},
    "prefer_ipv6":false,
    "no_delay":true,
    "reuse_port":true,
    "mode":"tcp_and_udp",
    "plugin":"obfs-server",
    "plugin_opts":"obfs=http;obfs-host=www.example.com"
}
EOL

    cat > $SS_SERVICE <<EOL
[Unit]
Description=Shadowsocks-libev Server
After=network.target

[Service]
Type=simple
User=nobody
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/ss-server -c $SS_CONFIG
Restart=on-failure
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable shadowsocks-libev || error_exit "Failed to enable ShadowSocks service"
    systemctl start shadowsocks-libev || error_exit "Failed to start ShadowSocks service"
}

optimize_kernel() {
    log "Optimizing kernel parameters..."
    cat >> /etc/sysctl.conf <<EOL

# Shadowsocks Optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 200000
net.ipv4.tcp_mtu_probing = 1
net.core.default_qdisc = fq
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOL

    # Check if BBR is supported
    if modprobe tcp_bbr &> /dev/null; then
        echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    else
        log "BBR not supported by the kernel. Skipping BBR configuration."
    fi

    sysctl -p || error_exit "Failed to apply sysctl changes"
}

setup_database() {
    log "Setting up PostgreSQL database..."
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" || error_exit "Failed to create database"
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';" || error_exit "Failed to create database user"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" || error_exit "Failed to grant privileges to database user"

    # Enable SSL for PostgreSQL
    log "Configuring PostgreSQL SSL..."
    PG_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
    PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"
    
    # Generate self-signed certificate (replace with proper certificates in production)
    sudo -u postgres openssl req -new -x509 -days 365 -nodes -text -out /etc/postgresql/$POSTGRES_VERSION/main/server.crt -keyout /etc/postgresql/$POSTGRES_VERSION/main/server.key -subj "/CN=localhost" || error_exit "Failed to generate SSL certificate"
    chmod 600 /etc/postgresql/$POSTGRES_VERSION/main/server.key
    chown postgres:postgres /etc/postgresql/$POSTGRES_VERSION/main/server.{crt,key}
    
    sed -i "s/#ssl = off/ssl = on/" $PG_CONF
    sed -i "s/#ssl_cert_file = '/ssl_cert_file = '\/etc\/postgresql\/$POSTGRES_VERSION\/main\/server.crt/" $PG_CONF
    sed -i "s/#ssl_key_file = '/ssl_key_file = '\/etc\/postgresql\/$POSTGRES_VERSION\/main\/server.key/" $PG_CONF
    
    # Update pg_hba.conf to use SSL
    sed -i 's/host all all all md5/hostssl all all all md5/' $PG_HBA
    
    systemctl restart postgresql || error_exit "Failed to restart PostgreSQL after SSL configuration"

    # Configure pgbouncer with SSL
    log "Configuring pgbouncer..."
    cat > /etc/pgbouncer/pgbouncer.ini <<EOL
[databases]
$DB_NAME = host=127.0.0.1 port=5432 dbname=$DB_NAME

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
admin_users = $DB_USER
client_tls_sslmode = require
client_tls_key_file = /etc/postgresql/$POSTGRES_VERSION/main/server.key
client_tls_cert_file = /etc/postgresql/$POSTGRES_VERSION/main/server.crt
EOL

    echo "\"$DB_USER\" \"$(echo -n "$DB_PASSWORD$DB_USER" | md5sum | cut -d' ' -f1)\"" > /etc/pgbouncer/userlist.txt
    chown postgres:postgres /etc/pgbouncer/userlist.txt
    chmod 600 /etc/pgbouncer/userlist.txt

    systemctl enable pgbouncer || error_exit "Failed to enable pgbouncer service"
    systemctl start pgbouncer || error_exit "Failed to start pgbouncer service"

    # Create tables
    log "Creating database tables..."
    PGPASSWORD=$DB_PASSWORD psql -h 127.0.0.1 -p 6432 -U $DB_USER -d $DB_NAME <<EOL || error_exit "Failed to create database tables"
    CREATE TABLE users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(100) NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        last_login TIMESTAMP WITH TIME ZONE
    );

    CREATE TABLE connections (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id),
        ip_address INET NOT NULL,
        connected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        disconnected_at TIMESTAMP WITH TIME ZONE,
        bytes_sent BIGINT DEFAULT 0,
        bytes_received BIGINT DEFAULT 0
    );

    CREATE INDEX idx_connections_user_id ON connections(user_id);
    CREATE INDEX idx_connections_ip_address ON connections(ip_address);
EOL
}

setup_monitoring() {
    log "Setting up monitoring..."
    # Configure Prometheus
    cat > /etc/prometheus/prometheus.yml <<EOL
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  
  - job_name: 'postgresql'
    static_configs:
      - targets: ['localhost:9187']
EOL

    systemctl restart prometheus || error_exit "Failed to restart Prometheus"

    # Configure Grafana (basic setup, dashboard should be imported manually)
    systemctl enable grafana-server || error_exit "Failed to enable Grafana service"
    systemctl start grafana-server || error_exit "Failed to start Grafana service"

    # Install and configure PostgreSQL exporter
    log "Setting up PostgreSQL exporter..."
    wget https://github.com/wrouesnel/postgres_exporter/releases/download/v0.8.0/postgres_exporter_v0.8.0_linux-amd64.tar.gz || error_exit "Failed to download PostgreSQL exporter"
    tar xvf postgres_exporter_v0.8.0_linux-amd64.tar.gz
    cp postgres_exporter_v0.8.0_linux-amd64/postgres_exporter /usr/local/bin/

    cat > /etc/systemd/system/postgres_exporter.service <<EOL
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target

[Service]
Type=simple
User=postgres
Environment="DATA_SOURCE_NAME=user=$DB_USER password=$DB_PASSWORD host=/var/run/postgresql/ sslmode=require"
ExecStart=/usr/local/bin/postgres_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable postgres_exporter || error_exit "Failed to enable PostgreSQL exporter service"
    systemctl start postgres_exporter || error_exit "Failed to start PostgreSQL exporter service"
}

setup_firewall() {
    log "Configuring firewall..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 8388/tcp
    ufw allow 8388/udp
    ufw allow 9100/tcp  # Node Exporter
    ufw allow 9187/tcp  # PostgreSQL Exporter
    ufw allow 3000/tcp  # Grafana
    ufw --force enable || error_exit "Failed to enable UFW"

    # Configure fail2ban
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sed -i 's/bantime  = 10m/bantime  = 1h/' /etc/fail2ban/jail.local
    sed -i 's/maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local

    # Add jail for SSH
    cat >> /etc/fail2ban/jail.local <<EOL

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOL

    systemctl enable fail2ban || error_exit "Failed to enable fail2ban service"
    systemctl start fail2ban || error_exit "Failed to start fail2ban service"
}

setup_backups() {
    log "Setting up database backups..."
    mkdir -p $BACKUP_DIR
    chown postgres:postgres $BACKUP_DIR

    cat > /etc/cron.daily/backup-postgres <<EOL
#!/bin/bash
BACKUP_DIR="$BACKUP_DIR"
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="\$BACKUP_DIR/\$DB_NAME_\$TIMESTAMP.sql.gz"
export PGPASSWORD='$DB_PASSWORD'

pg_dump -h localhost -U $DB_USER $DB_NAME | gzip > "\$BACKUP_FILE"

if [ \$? -eq 0 ]; then
    echo "Backup completed successfully: \$BACKUP_FILE" | mail -s "PostgreSQL Backup Success" root@localhost
    find \$BACKUP_DIR -type f -mtime +7 -delete
else
    echo "Backup failed" | mail -s "PostgreSQL Backup Failure" root@localhost
fi

unset PGPASSWORD
EOL

chmod +x /etc/cron.daily/backup-postgres
}

setup_logging() {
    log "Setting up logging..."
    mkdir -p /var/log/shadowsocks
    chown nobody:nogroup /var/log/shadowsocks

    # Add log rotation configuration
    cat > /etc/logrotate.d/shadowsocks <<EOL
/var/log/shadowsocks/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 nobody nogroup
}
EOL
}

setup_monitoring_alerts() {
    log "Setting up monitoring alerts..."
    
    # Install Alertmanager
    wget https://github.com/prometheus/alertmanager/releases/download/v0.23.0/alertmanager-0.23.0.linux-amd64.tar.gz
    tar xvf alertmanager-0.23.0.linux-amd64.tar.gz
    cp alertmanager-0.23.0.linux-amd64/alertmanager /usr/local/bin/
    
    # Configure Alertmanager
    mkdir -p /etc/alertmanager
    cat > /etc/alertmanager/alertmanager.yml <<EOL
global:
  smtp_smarthost: 'localhost:25'
  smtp_from: 'alertmanager@example.com'
  smtp_auth_username: ''
  smtp_auth_password: ''

route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'email-notifications'

receivers:
- name: 'email-notifications'
  email_configs:
  - to: 'admin@example.com'
EOL

    # Create Alertmanager service
    cat > /etc/systemd/system/alertmanager.service <<EOL
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable alertmanager
    systemctl start alertmanager

    # Add alert rules to Prometheus
    cat > /etc/prometheus/alert.rules.yml <<EOL
groups:
- name: ShadowsocksAlerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High CPU usage detected
      description: CPU usage is above 80% for more than 5 minutes.

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High memory usage detected
      description: Memory usage is above 80% for more than 5 minutes.

  - alert: ShadowsocksDown
    expr: up{job="shadowsocks"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: Shadowsocks server is down
      description: Shadowsocks server has been down for more than 1 minute.
EOL

    # Update Prometheus configuration to include alert rules
    sed -i '/scrape_configs:/i\rule_files:\n  - "alert.rules.yml"' /etc/prometheus/prometheus.yml
    systemctl restart prometheus
}

setup_security_hardening() {
    log "Setting up additional security measures..."

    # Disable root login via SSH
    sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    
    # Use strong SSH ciphers
    echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
    
    # Enable SSH key-based authentication and disable password authentication
    sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    
    systemctl restart ssh

    # Install and configure auditd
    apt-get install -y auditd

    # Set up basic audit rules
    cat > /etc/audit/rules.d/audit.rules <<EOL
# Log all sudo commands
-a exit,always -F arch=b64 -F euid=0 -S execve -k sudo_log

# Log changes to system files
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/gshadow -p wa -k gshadow_changes

# Log unsuccessful unauthorized access attempts
-a always,exit -F arch=b64 -S open -F dir=/etc -F success=0 -k access
-a always,exit -F arch=b64 -S open -F dir=/usr -F success=0 -k access
EOL

    systemctl enable auditd
    systemctl start auditd
}

main() {
    log "Starting ShadowSocks VPN installation..."
    check_root
    install_dependencies
    install_shadowsocks
    configure_shadowsocks
    optimize_kernel
    setup_database
    setup_monitoring
    setup_firewall
    setup_backups
    setup_logging
    setup_monitoring_alerts
    setup_security_hardening

    log "ShadowSocks VPN installation completed successfully!"
    log "PostgreSQL Database: $DB_NAME"
    log "Database User: $DB_USER"
    log "Database and ShadowSocks Password: $DB_PASSWORD"
    log "Please save these credentials securely and change them immediately."
    log "Remember to set up Grafana dashboards manually and configure email settings for alerts."
    log "It is highly recommended to change the default passwords and further secure your system."
}

main
