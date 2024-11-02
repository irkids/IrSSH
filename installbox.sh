#!/bin/bash

# SingBox Comprehensive Installation and Configuration Script
# Version: 3.0.0

set -eE

###################
# Global Variables #
###################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SINGBOX_VERSION="1.3.0"
SINGBOX_PATH="/usr/local/bin/sing-box"
SINGBOX_CONFIG_DIR="/etc/singbox"
SINGBOX_CONFIG_PATH="${SINGBOX_CONFIG_DIR}/config.json"
SINGBOX_LOG_DIR="/var/log/singbox"
SINGBOX_WEB_DIR="/var/www/singbox"
TEMP_DIR="/tmp/singbox-install"
SSL_DIR="/etc/singbox/ssl"
BACKUP_DIR="${SINGBOX_CONFIG_DIR}/backups"
UPDATE_CHECK_URL="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
MIRROR_URLS=(
    "https://github.com/SagerNet/sing-box/releases/download"
    "https://mirror1.example.com/sing-box"
    "https://mirror2.example.com/sing-box"
)

# Default ports (configurable via web UI)
declare -A DEFAULT_PORTS=(
    ["shadowsocks"]="8388"
    ["tuic"]="49513"
    ["vless"]="8443"
    ["hysteria2"]="10080"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

###################
# Logging Functions #
###################
setup_logging() {
    local log_file="${SINGBOX_LOG_DIR}/install.log"
    mkdir -p "${SINGBOX_LOG_DIR}"
    exec &> >(tee -a "$log_file")
    chmod 640 "$log_file"
    
    # Setup log rotation
    cat > /etc/logrotate.d/singbox <<EOF
${SINGBOX_LOG_DIR}/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
    postrotate
        systemctl reload singbox >/dev/null 2>&1 || true
    endscript
}
EOF
}

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}INFO${NC}: $1"
}

log_warning() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}WARNING${NC}: $1" >&2
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERROR${NC}: $1" >&2
}

###################
# Error Handling #
###################
cleanup() {
    local exit_code=$?
    log "Performing cleanup..."
    
    # Remove temporary files
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Stop services on failure
    if [ $exit_code -ne 0 ]; then
        log_warning "Installation failed. Stopping services..."
        systemctl stop singbox 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
        
        # Restore from last backup if available
        if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR")" ]; then
            local latest_backup=$(ls -t "$BACKUP_DIR" | head -n1)
            log "Attempting to restore from backup: $latest_backup"
            restore_backup "${BACKUP_DIR}/${latest_backup}"
        fi
    fi
    
    exit $exit_code
}

error_handler() {
    local line_no=$1
    local error_code=$2
    log_error "Error on line $line_no (Error code: $error_code)"
    
    # Additional error context
    local error_context=$(tail -n 5 "${SINGBOX_LOG_DIR}/install.log")
    log_error "Last 5 log entries:\n$error_context"
}

trap 'error_handler ${LINENO} $?' ERR
trap cleanup EXIT

###################
# Utility Functions #
###################
get_latest_version() {
    local api_response
    local latest_version
    
    api_response=$(curl -s "$UPDATE_CHECK_URL")
    if [ $? -eq 0 ]; then
        latest_version=$(echo "$api_response" | grep -oP '"tag_name": "v\K[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"')
        echo "$latest_version"
        return 0
    fi
    
    for mirror in "${MIRROR_URLS[@]}"; do
        latest_version=$(curl -s "${mirror}/latest" | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+')
        if [[ -n "$latest_version" ]]; then
            echo "$latest_version"
            return 0
        fi
    done
    
    return 1
}

download_singbox() {
    local version=$1
    local arch=$(uname -m)
    local success=false
    local download_url
    
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    log "Downloading SingBox version ${version} for ${arch}..."
    
    for mirror in "${MIRROR_URLS[@]}"; do
        download_url="${mirror}/v${version}/sing-box-${version}-linux-${arch}.tar.gz"
        if curl -sL --connect-timeout 10 "$download_url" -o singbox.tar.gz; then
            success=true
            break
        fi
    done
    
    if ! $success; then
        log_error "Failed to download SingBox from all mirrors"
        return 1
    fi
    
    # Verify download
    if ! sha256sum -c --status <(curl -sL "${download_url}.sha256"); then
        log_error "Checksum verification failed"
        return 1
    fi
    
    return 0
}

###################
# Installation Functions #
###################
install_dependencies() {
    log "Installing dependencies..."
    
    apt-get update
    apt-get install -y curl wget ufw fail2ban net-tools certbot software-properties-common jq nginx php-fpm iptables-persistent postgresql
    
    # Install Node.js and npm for web UI
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
    apt-get install -y nodejs
    
    # Install additional PHP extensions
    apt-get install -y php-pgsql php-mbstring php-xml php-curl
}

install_singbox() {
    local version=$(get_latest_version)
    if [ $? -ne 0 ]; then
        log_error "Failed to determine latest SingBox version"
        return 1
    fi
    
    log "Installing SingBox version $version..."
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    if ! download_singbox "$version"; then
        log_error "Failed to download SingBox"
        return 1
    fi
    
    tar -xzf singbox.tar.gz
    mv "sing-box-${version}-linux-amd64/sing-box" "$SINGBOX_PATH"
    chmod +x "$SINGBOX_PATH"
    
    # Create necessary directories
    mkdir -p "$SINGBOX_CONFIG_DIR" "$SINGBOX_LOG_DIR" "$SSL_DIR"
    
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_DIR"
    
    log "SingBox installed successfully"
}

###################
# Configuration Functions #
###################
generate_singbox_config() {
    log "Generating SingBox configuration..."
    
    # Generate random UUIDs for each protocol
    local ss_password=$(openssl rand -base64 16)
    local tuic_uuid=$(uuidgen)
    local vless_uuid=$(uuidgen)
    local hysteria2_password=$(openssl rand -base64 16)
    
    cat > "$SINGBOX_CONFIG_PATH" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${DEFAULT_PORTS["shadowsocks"]},
      "method": "chacha20-ietf-poly1305",
      "password": "$ss_password"
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": ${DEFAULT_PORTS["tuic"]},
      "users": [
        {
          "uuid": "$tuic_uuid",
          "password": "$(openssl rand -base64 16)"
        }
      ],
      "congestion_control": "bbr",
      "zero_rtt_handshake": true
    },
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${DEFAULT_PORTS["vless"]},
      "users": [
        {
          "uuid": "$vless_uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "example.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "example.com",
            "server_port": 443
          },
          "private_key": "$(sing-box generate reality-keypair | jq -r .PrivateKey)",
          "short_id": ["$(openssl rand -hex 8)"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "::",
      "listen_port": ${DEFAULT_PORTS["hysteria2"]},
      "up_mbps": 100,
      "down_mbps": 100,
      "obfs": {
        "type": "salamander",
        "password": "$hysteria2_password"
      },
      "users": [
        {
          "password": "$(openssl rand -base64 16)"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "geoip": "private",
        "outbound": "block"
      }
    ],
    "final": "direct"
  }
}
EOF

    log "SingBox configuration generated"
}

setup_postgresql() {
    log "Setting up PostgreSQL..."
    
    # Generate a secure password for the singbox user
    local db_password=$(openssl rand -base64 16)
    
    # Create singbox user and database
    sudo -u postgres psql -c "CREATE USER singbox WITH PASSWORD '$db_password';"
    sudo -u postgres psql -c "CREATE DATABASE singbox_db OWNER singbox;"
    
    # Create necessary tables
    sudo -u postgres psql -d singbox_db <<EOF
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE configurations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    protocol VARCHAR(20) NOT NULL,
    settings JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE usage_stats (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    protocol VARCHAR(20) NOT NULL,
    bytes_sent BIGINT DEFAULT 0,
    bytes_received BIGINT DEFAULT 0,
    last_used TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

    # Save database credentials securely
    echo "DB_USER=singbox" > "${SINGBOX_CONFIG_DIR}/.env"
    echo "DB_PASSWORD=$db_password" >> "${SINGBOX_CONFIG_DIR}/.env"
    echo "DB_NAME=singbox_db" >> "${SINGBOX_CONFIG_DIR}/.env"
    chmod 600 "${SINGBOX_CONFIG_DIR}/.env"
    
    log "PostgreSQL setup completed"
}

setup_web_interface() {
    log "Setting up web interface..."
    
    # Clone the web interface repository (assuming it exists)
    git clone https://github.com/yourusername/singbox-web-ui.git "$SINGBOX_WEB_DIR"
    
    # Install dependencies
    cd "$SINGBOX_WEB_DIR"
    npm install
    
    # Build the web interface
    npm run build
    
    # Configure Nginx
    cat > /etc/nginx/sites-available/singbox <<EOF
server {
    listen 80;
    server_name your_domain.com;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your_domain.com;

    ssl_certificate /etc/letsencrypt/live/your_domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your_domain.com/privkey.pem;
    
    root $SINGBOX_WEB_DIR/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    # Enable the Nginx configuration
    ln -s /etc/nginx/sites-available/singbox /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
    
    log "Web interface setup completed"
}

optimize_system() {
    log "Optimizing system settings..."
    
    # Backup original sysctl configuration
    if [ -f /etc/sysctl.conf ]; then
        cp /etc/sysctl.conf "/etc/sysctl.conf.backup-$(date +%Y%m%d)"
    fi
    
    # Create sysctl config file
    cat > /etc/sysctl.d/99-singbox-optimizations.conf <<EOF
# TCP optimization
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_syncookies = 1

# UDP optimization
net.core.netdev_max_backlog = 16384
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# General network security
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Performance optimization
net.core.somaxconn = 65535
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2

# Connection tracking limits
net.netfilter.nf_conntrack_max = 2000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7440
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
EOF

    # Apply sysctl settings
    if ! sysctl -p /etc/sysctl.d/98-singbox.conf; then
        log_error "Failed to apply system optimizations"
        return 1
    fi
    
    # Enable BBR if available
    if grep -q "tcp_bbr" /proc/modules; then
        log "BBR already enabled"
    else
        modprobe tcp_bbr
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/98-singbox.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/98-singbox.conf
        sysctl -p /etc/sysctl.d/98-singbox.conf
    fi
}

setup_firewall() {
    log "Configuring UFW firewall..."
    
    # Ensure UFW is installed
    apt-get install -y ufw || log_error "Failed to install UFW"
    
    # Backup existing rules
    if [ -f /etc/ufw/user.rules ]; then
        cp /etc/ufw/user.rules "/etc/ufw/user.rules.backup-$(date +%Y%m%d)"
    fi
    
    # Reset UFW
    ufw --force reset
    
    # Configure UFW
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (before enabling UFW)
    ufw allow ssh comment 'SSH access'
    
    # Allow HTTPS for web panel
    ufw allow https comment 'HTTPS/TLS'
    
    # Allow SingBox ports
    for port_config in "${DEFAULT_PORTS[@]}"; do
        protocol=${port_config%:*}
        port=${port_config#*:}
        
        case $protocol in
            shadowsocks)
                ufw allow "$port"/tcp comment 'Shadowsocks'
                ;;
            tuic)
                ufw allow "$port"/udp comment 'TUIC'
                ;;
            vless)
                ufw allow "$port"/tcp comment 'VLess Reality'
                ;;
            hysteria2)
                ufw allow "$port"/udp comment 'Hysteria2'
                ;;
        esac
    done
    
    # Enable UFW
    ufw logging on
    echo "y" | ufw enable
    
    # Verify firewall status
    if ! ufw status numbered | grep -qE "$(echo "${DEFAULT_PORTS[@]}" | tr ' ' '|')"; then
        log_error "Failed to configure firewall rules"
        return 1
    fi
}

setup_fail2ban() {
    log "Configuring Fail2Ban..."
    
    # Install fail2ban if not present
    apt-get install -y fail2ban || log_error "Failed to install fail2ban"
    
    # Backup existing config
    if [ -f /etc/fail2ban/jail.local ]; then
        cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.backup-$(date +%Y%m%d)"
    fi
    
    # Create custom jail configuration
    cat > /etc/fail2ban/jail.d/singbox.conf <<EOF
[singbox-auth]
enabled = true
filter = singbox
logpath = /var/log/singbox/singbox.log
maxretry = 3
findtime = 300
bantime = 3600
action = iptables-multiport[name=singbox, port="${DEFAULT_PORTS[@]//[^0-9 ]/}", protocol=tcp]

[singbox-ddos]
enabled = true
filter = singbox-ddos
logpath = /var/log/singbox/singbox.log
maxretry = 100
findtime = 60
bantime = 7200
action = iptables-multiport[name=singbox-ddos, port="${DEFAULT_PORTS[@]//[^0-9 ]/}", protocol=tcp]

[singbox-probe]
enabled = true
filter = singbox-probe
logpath = /var/log/singbox/singbox.log
maxretry = 2
findtime = 3600
bantime = 86400
action = iptables-multiport[name=singbox-probe, port="${DEFAULT_PORTS[@]//[^0-9 ]/}", protocol=all]
EOF
    
    # Create custom filter for authentication failures
    cat > /etc/fail2ban/filter.d/singbox.conf <<EOF
[Definition]
failregex = ^.*(Failed authentication|Invalid credentials|Authentication failed).*from <HOST>
ignoreregex =
EOF
    
    # Create custom filter for DDoS protection
    cat > /etc/fail2ban/filter.d/singbox-ddos.conf <<EOF
[Definition]
failregex = ^.*Possible DDoS attack detected from <HOST>.*$
            ^.*Too many concurrent connections from <HOST>.*$
            ^.*Connection flood detected from <HOST>.*$
ignoreregex =
EOF

    # Create custom filter for port scanning and probing
    cat > /etc/fail2ban/filter.d/singbox-probe.conf <<EOF
[Definition]
failregex = ^.*Port scan detected from <HOST>.*$
            ^.*Probe attempt detected from <HOST>.*$
            ^.*Suspicious activity from <HOST>.*$
ignoreregex =
EOF

    # Setup rate limiting with advanced rules
    cat > /etc/fail2ban/jail.d/singbox-ratelimit.conf <<EOF
[singbox-ratelimit]
enabled = true
filter = singbox-ratelimit
logpath = ${SINGBOX_LOG_DIR}/singbox.log
maxretry = 60
findtime = 60
bantime = 3600
action = iptables-multiport[name=singbox-ratelimit, port="${DEFAULT_PORTS[@]}", protocol=all]
EOF

    # Create rate limiting filter
    cat > /etc/fail2ban/filter.d/singbox-ratelimit.conf <<EOF
[Definition]
failregex = ^.*Rate limit exceeded.*from <HOST>.*$
            ^.*Too many requests.*from <HOST>.*$
ignoreregex =
EOF

    # Restart fail2ban to apply changes
    systemctl restart fail2ban || log_error "Failed to restart fail2ban"

    # Setup advanced rate limiting with iptables
    log "Configuring advanced rate limiting..."

    # Create iptables rules for connection rate limiting
    iptables -N SINGBOX_RATELIMIT
    iptables -A SINGBOX_RATELIMIT -m state --state NEW -m hashlimit \
        --hashlimit-above 30/minute \
        --hashlimit-burst 10 \
        --hashlimit-mode srcip \
        --hashlimit-name conn_rate_limit \
        -j DROP

    # Apply rate limiting to each port
    for port in "${DEFAULT_PORTS[@]}"; do
        iptables -A INPUT -p tcp --dport ${port} -j SINGBOX_RATELIMIT
        iptables -A INPUT -p udp --dport ${port} -j SINGBOX_RATELIMIT
    done

    # Setup Nginx rate limiting
    cat > /etc/nginx/conf.d/singbox-ratelimit.conf <<EOF
limit_req_zone \$binary_remote_addr zone=singbox_limit:10m rate=10r/s;
limit_conn_zone \$binary_remote_addr zone=singbox_conn:10m;

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

    # Create API endpoint configuration
    cat > /etc/nginx/conf.d/singbox-api.conf <<EOF
server {
    listen 9090;
    server_name localhost;

    location /api/ {
        limit_req zone=singbox_limit burst=20 nodelay;
        limit_conn singbox_conn 10;
        
        proxy_pass http://127.0.0.1:8080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

    # Reload Nginx configuration
    nginx -t && systemctl reload nginx || log_error "Failed to reload Nginx configuration"
}

setup_backup() {
    log "Setting up automatic backups..."

    # Setup automatic backup scheduling
    cat > /etc/systemd/system/singbox-backup.timer <<EOF
[Unit]
Description=SingBox Daily Backup Timer

[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

    cat > /etc/systemd/system/singbox-backup.service <<EOF
[Unit]
Description=SingBox Backup Service
After=singbox.service

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/backup.sh
EOF

    # Create backup rotation script
    cat > ${SCRIPT_DIR}/backup.sh <<'EOF'
#!/bin/bash

BACKUP_DIR="${SINGBOX_CONFIG_DIR}/backups"
MAX_BACKUPS=7

# Create backup
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/singbox_${timestamp}.tar.gz"

    tar -czf "$backup_file" \
        -C / \
        "${SINGBOX_CONFIG_DIR#/}" \
        "${SINGBOX_LOG_DIR#/}" \
        "etc/systemd/system/singbox.service" \
        "etc/systemd/system/singbox-monitor.service" \
        "etc/fail2ban/jail.d/singbox.conf" \
        "etc/nginx/conf.d/singbox-api.conf"

    echo "$backup_file"
}

# Rotate old backups
rotate_backups() {
    local backup_count=$(ls -1 "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l)
    
    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        ls -1t "${BACKUP_DIR}"/*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
    fi
}

# Main backup process
mkdir -p "$BACKUP_DIR"
backup_file=$(create_backup)
rotate_backups

# Verify backup
if [ -f "$backup_file" ] && tar -tzf "$backup_file" >/dev/null 2>&1; then
    echo "Backup created successfully: $backup_file"
    exit 0
else
    echo "Backup failed: $backup_file"
    exit 1
fi
EOF

    chmod +x ${SCRIPT_DIR}/backup.sh

    # Enable and start backup timer
    systemctl daemon-reload
    systemctl enable singbox-backup.timer
    systemctl start singbox-backup.timer
}

setup_monitoring() {
    log "Setting up monitoring..."

    # Setup monitoring with resource tracking
    cat > ${SCRIPT_DIR}/monitor.sh <<'EOF'
#!/bin/bash

# Configuration
ALERT_CPU_THRESHOLD=80
ALERT_MEM_THRESHOLD=80
ALERT_DISK_THRESHOLD=90
CHECK_INTERVAL=60
RECOVERY_ATTEMPTS=3

# Monitoring function
monitor_resources() {
    # CPU usage monitoring
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    if (( $(echo "$cpu_usage > $ALERT_CPU_THRESHOLD" | bc -l) )); then
        log "ALERT: High CPU usage: ${cpu_usage}%"
        send_alert "High CPU Usage" "CPU usage is at ${cpu_usage}%"
    fi

    # Memory usage monitoring
    mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    if (( $(echo "$mem_usage > $ALERT_MEM_THRESHOLD" | bc -l) )); then
        log "ALERT: High memory usage: ${mem_usage}%"
        send_alert "High Memory Usage" "Memory usage is at ${mem_usage}%"
    fi

    # Disk usage monitoring
    disk_usage=$(df -h | awk '$NF=="/"{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt "$ALERT_DISK_THRESHOLD" ]; then
        log "ALERT: High disk usage: ${disk_usage}%"
        send_alert "High Disk Usage" "Disk usage is at ${disk_usage}%"
    fi
}

# Service monitoring function
monitor_service() {
    if ! systemctl is-active --quiet singbox; then
        log "ALERT: SingBox service is down, attempting recovery..."
        
        for ((i=1; i<=RECOVERY_ATTEMPTS; i++)); do
            systemctl restart singbox
            sleep 5
            
            if systemctl is-active --quiet singbox; then
                log "Service recovered after attempt $i"
                send_alert "Service Recovery" "SingBox service was recovered after $i attempts"
                return 0
            fi
        done
        
        log "CRITICAL: Service recovery failed after $RECOVERY_ATTEMPTS attempts"
        send_alert "Critical Service Failure" "SingBox service could not be recovered after $RECOVERY_ATTEMPTS attempts"
    return 1
}

# Port monitoring function
monitor_ports() {
    for port_config in "${DEFAULT_PORTS[@]}"; do
        protocol=${port_config%:*}
        port=${port_config#*:}
        if ! netstat -tuln | grep -q ":$port "; then
            log "ALERT: Port $port ($protocol) is not listening"
            send_alert "Port Down" "Port $port ($protocol) is not responding"
            return 1
        fi
    done
}

# Main monitoring loop
while true; do
    monitor_resources
    monitor_service
    monitor_ports
    sleep "$CHECK_INTERVAL"
done
EOF

chmod +x "${SCRIPT_DIR}/monitor.sh"

# Create monitoring service
cat > /etc/systemd/system/singbox-monitor.service <<EOF
[Unit]
Description=SingBox Monitoring Service
After=singbox.service

[Service]
Type=simple
ExecStart=${SCRIPT_DIR}/monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start monitoring service
systemctl daemon-reload
systemctl enable singbox-monitor
systemctl start singbox-monitor

log "SingBox installation and configuration completed successfully"
log "Web interface is accessible at https://your_domain.com"
log "Please update your domain in the Nginx configuration at /etc/nginx/sites-available/singbox"
log "Remember to secure your PostgreSQL database and update the .env file with proper credentials"
log "Monitoring service is active. Check logs at ${SINGBOX_LOG_DIR}/monitor.log for any alerts"

# Final security reminder
log "IMPORTANT: Remember to change all default passwords, including database and web interface credentials"
log "Regularly update your system and SingBox for the latest security patches"

# Cleanup
cleanup

exit 0
