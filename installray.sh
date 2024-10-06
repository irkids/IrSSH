#!/bin/bash

set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."
    apt-get update
    apt-get install -y curl wget unzip jq postgresql postgresql-contrib nginx certbot python3-certbot-nginx pgbouncer fail2ban prometheus grafana
}

# Function to install V2Ray
install_v2ray() {
    log "Installing V2Ray..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
}

# Function to generate V2Ray configuration
generate_v2ray_config() {
    log "Generating V2Ray configuration..."
    cat > /usr/local/etc/v2ray/config.json <<EOL
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$(uuid)",
            "level": 0,
            "email": "user@example.com"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
            }
          ]
        },
        "wsSettings": {
          "path": "/v2ray"
        }
      },
      "concurrency": 10
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOL
}

# Function to configure Nginx with HTTP/3 support
configure_nginx() {
    log "Configuring Nginx with HTTP/3 support..."
    cat > /etc/nginx/sites-available/v2ray <<EOL
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    listen 443 quic;
    listen [::]:443 quic;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    http2_max_field_size 16k;
    http2_max_header_size 32k;

    location /v2ray {
        proxy_pass http://127.0.0.1:443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
}
EOL

    ln -s /etc/nginx/sites-available/v2ray /etc/nginx/sites-enabled/
    sed -i 's/worker_processes auto;/worker_processes 4;/g' /etc/nginx/nginx.conf
    nginx -s reload
}

# Function to set up PostgreSQL with advanced optimizations
setup_postgresql() {
    log "Setting up PostgreSQL with advanced optimizations..."
    sudo -u postgres psql -c "CREATE DATABASE v2ray_db;" || { log "Failed to create database"; exit 1; }
    sudo -u postgres psql -c "CREATE USER v2ray_user WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';" || { log "Failed to create user"; exit 1; }
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE v2ray_db TO v2ray_user;" || { log "Failed to grant privileges"; exit 1; }

    cat > /etc/v2ray/db_schema.sql <<EOL
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    uuid UUID NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE
);
CREATE INDEX idx_users_uuid ON users(uuid);

CREATE TABLE traffic_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    upload BIGINT,
    download BIGINT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_traffic_logs_user_id ON traffic_logs(user_id);
EOL

    sudo -u postgres psql v2ray_db < /etc/v2ray/db_schema.sql

    PG_VERSION=$(psql --version | awk '{print $3}' | cut -d. -f1)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    SHARED_BUFFERS=$((TOTAL_MEM / 4))
    EFFECTIVE_CACHE_SIZE=$((TOTAL_MEM * 3 / 4))

    cat >> /etc/postgresql/${PG_VERSION}/main/postgresql.conf <<EOL
max_connections = 500
shared_buffers = ${SHARED_BUFFERS}MB
effective_cache_size = ${EFFECTIVE_CACHE_SIZE}MB
maintenance_work_mem = 1GB
work_mem = 256MB
checkpoint_completion_target = 0.9
synchronous_commit = off
wal_buffers = 32MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 300
min_wal_size = 4GB
max_wal_size = 8GB
max_parallel_workers_per_gather = 4
parallel_setup_cost = 1000
parallel_tuple_cost = 0.1
log_min_duration_statement = 500
log_connections = on
log_disconnections = on
log_lock_waits = on
autovacuum_max_workers = 6
autovacuum_naptime = 5s
autovacuum_vacuum_cost_delay = 10ms
wal_compression = on
EOL

    echo "host    v2ray_db    v2ray_user    127.0.0.1/32    scram-sha-256" >> /etc/postgresql/${PG_VERSION}/main/pg_hba.conf

    systemctl restart postgresql
}

# Function to configure PgBouncer with advanced settings
configure_pgbouncer() {
    log "Configuring PgBouncer with advanced settings..."
    cat > /etc/pgbouncer/pgbouncer.ini <<EOL
[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = session
max_client_conn = 1000
default_pool_size = 200
reserve_pool_size = 50
reserve_pool_timeout = 10
client_idle_timeout = 60
server_idle_timeout = 300
log_connections = 1
log_disconnections = 1

[databases]
v2ray_db = host=127.0.0.1 dbname=v2ray_db user=v2ray_user
EOL

    echo '"v2ray_user" "'"${DB_PASSWORD}"'"' > /etc/pgbouncer/userlist.txt
    systemctl restart pgbouncer
}

# Function to optimize system settings
optimize_system() {
    log "Optimizing system settings..."
    cat >> /etc/sysctl.conf <<EOL
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 16384 4194304
net.ipv4.tcp_tw_reuse = 1
EOL
    sysctl -p
}

# Function to set up firewall rules with rate limiting
setup_firewall() {
    log "Setting up firewall rules with rate limiting..."
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw limit 22/tcp
    ufw limit 80/tcp
    ufw limit 443/tcp
    ufw enable
}

# Function to create a systemd service for V2Ray
create_v2ray_service() {
    log "Creating V2Ray systemd service..."
    cat > /etc/systemd/system/v2ray.service <<EOL
[Unit]
Description=V2Ray Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray -config /usr/local/etc/v2ray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable v2ray
    systemctl start v2ray
}

# Function to set up Fail2Ban with enhanced rules
setup_fail2ban() {
    log "Setting up Fail2Ban with enhanced rules..."
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    cat >> /etc/fail2ban/jail.local <<EOL

[v2ray]
enabled  = true
port     = 443
filter   = v2ray
logpath  = /var/log/v2ray/access.log
maxretry = 3
bantime  = 86400

[nginx-http-auth]
enabled = true
port    = http,https

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = %(nginx_error_log)s

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOL

    cat > /etc/fail2ban/filter.d/v2ray.conf <<EOL
[Definition]
failregex = ^.* rejected tcp connection from .* \(client <HOST>\)$
ignoreregex =
EOL

    systemctl restart fail2ban
}

# Function to set up automated backups
setup_backups() {
    log "Setting up automated backups..."
    mkdir -p /backups
    cat > /etc/cron.daily/v2ray_backup <<EOL
#!/bin/bash
pg_dump -U v2ray_user v2ray_db | gzip > /backups/v2ray_db_$(date +\%F).sql.gz
find /backups -type f -name "v2ray_db_*.sql.gz" -mtime +7 -delete
EOL
    chmod +x /etc/cron.daily/v2ray_backup
}

# Function to set up monitoring with Prometheus and Grafana
setup_monitoring() {
    log "Setting up monitoring with Prometheus and Grafana..."
    
    # Configure Prometheus
    cat > /etc/prometheus/prometheus.yml <<EOL
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'v2ray'
    static_configs:
      - targets: ['localhost:9101']
EOL

    systemctl restart prometheus

    # Configure Grafana (basic setup, you may want to customize further)
    systemctl enable grafana-server
    systemctl start grafana-server

    # Install and configure pg_stat_statements
    sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" v2ray_db
    echo "shared_preload_libraries = 'pg_stat_statements'" >> /etc/postgresql/${PG_VERSION}/main/postgresql.conf
    systemctl restart postgresql
}

# Main installation function
main() {
    log "Starting optimized V2Ray VPN installation..."

    # Check if DOMAIN and DB_PASSWORD are set
    if [ -z "${DOMAIN}" ] || [ -z "${DB_PASSWORD}" ]; then
        log "Error: DOMAIN and DB_PASSWORD must be set before running this script."
        exit 1
    }

    install_prerequisites
    install_v2ray
    generate_v2ray_config
    configure_nginx
    setup_postgresql
    configure_pgbouncer
    optimize_system
    setup_firewall
    create_v2ray_service
    setup_fail2ban
    setup_backups
    setup_monitoring

    log "V2Ray VPN installation completed successfully with optimized settings!"
    log "Please ensure SSL certificates are set up for your domain using Certbot or a similar tool."
    log "Access Grafana at http://${DOMAIN}:3000 to configure your monitoring dashboards."
}

# Run the main installation function
main
