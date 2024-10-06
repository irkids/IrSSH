#!/bin/bash

set -euo pipefail

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This script must be run as root"
        exit 1
    fi
}

# Function to generate a secure random password
generate_password() {
    openssl rand -base64 24
}

# Function to install dependencies
install_dependencies() {
    log "Updating system and installing dependencies"
    apt-get update && apt-get upgrade -y
    apt-get install -y wireguard wireguard-tools iptables postgresql-13 postgresql-contrib python3 python3-pip ufw pgbouncer prometheus-node-exporter prometheus postgresql-exporter fail2ban
    pip3 install psycopg2-binary
}

# Function to set up PostgreSQL
setup_postgresql() {
    log "Setting up PostgreSQL"
    systemctl start postgresql
    systemctl enable postgresql
    
    # Generate secure passwords
    DB_PASSWORD=$(generate_password)
    PGBOUNCER_PASSWORD=$(generate_password)
    
    # Create database and user
    sudo -u postgres psql -c "CREATE DATABASE wireguard_vpn;"
    sudo -u postgres psql -c "CREATE USER wireguard_admin WITH ENCRYPTED PASSWORD '$DB_PASSWORD';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE wireguard_vpn TO wireguard_admin;"
    
    # Create tables with improved schema
    sudo -u postgres psql -d wireguard_vpn -c "
    CREATE TABLE wireguard_users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(100) UNIQUE NOT NULL,
        private_key TEXT UNIQUE NOT NULL,
        public_key TEXT UNIQUE NOT NULL,
        allowed_ips INET NOT NULL,
        connection_time TIMESTAMP DEFAULT NOW(),
        connection_status BOOLEAN DEFAULT FALSE,
        last_handshake TIMESTAMP
    );
    
    CREATE TABLE server_config (
        id SERIAL PRIMARY KEY,
        public_key TEXT UNIQUE NOT NULL,
        private_key TEXT UNIQUE NOT NULL,
        endpoint VARCHAR(100) NOT NULL,
        port INT NOT NULL,
        dns VARCHAR(100),
        mtu INT,
        persistent_keepalive INT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE INDEX idx_username ON wireguard_users(username);
    CREATE INDEX idx_connection_time ON wireguard_users(connection_time);
    CREATE INDEX idx_last_handshake ON wireguard_users(last_handshake);"
    
    # Optimize PostgreSQL configuration
    sed -i "s/^shared_buffers.*/shared_buffers = $(awk '/MemTotal/ {printf "%dMB", $2/1024/4}' /proc/meminfo)/" /etc/postgresql/13/main/postgresql.conf
    sed -i "s/^#work_mem.*/work_mem = 16MB/" /etc/postgresql/13/main/postgresql.conf
    sed -i "s/^#maintenance_work_mem.*/maintenance_work_mem = 256MB/" /etc/postgresql/13/main/postgresql.conf
    sed -i "s/^#effective_cache_size.*/effective_cache_size = $(awk '/MemTotal/ {printf "%dMB", $2/1024*3/4}' /proc/meminfo)/" /etc/postgresql/13/main/postgresql.conf
    
    # Enable SSL for PostgreSQL
    sed -i "s/^#ssl = off/ssl = on/" /etc/postgresql/13/main/postgresql.conf
    
    # Configure pg_hba.conf for enhanced security
    echo "hostssl all all 127.0.0.1/32 scram-sha-256" > /etc/postgresql/13/main/pg_hba.conf
    
    # Set connection limits
    echo "max_connections = 100" >> /etc/postgresql/13/main/postgresql.conf
    echo "superuser_reserved_connections = 3" >> /etc/postgresql/13/main/postgresql.conf
    
    # Restart PostgreSQL to apply changes
    systemctl restart postgresql
    
    # Schedule regular VACUUM ANALYZE
    (crontab -l 2>/dev/null; echo "0 3 * * * sudo -u postgres psql -d wireguard_vpn -c 'VACUUM ANALYZE;'") | crontab -
}

# Function to generate WireGuard keys
generate_keys() {
    log "Generating WireGuard keys"
    private_key=$(wg genkey)
    public_key=$(echo "$private_key" | wg pubkey)
    
    # Store keys in the database
    sudo -u postgres psql -d wireguard_vpn -c "
    INSERT INTO server_config (public_key, private_key, endpoint, port, mtu, persistent_keepalive)
    VALUES ('$public_key', '$private_key', '$(curl -s ifconfig.me)', 51820, 1420, 25)
    ON CONFLICT (id) DO UPDATE
    SET public_key = EXCLUDED.public_key,
        private_key = EXCLUDED.private_key,
        endpoint = EXCLUDED.endpoint,
        mtu = EXCLUDED.mtu,
        persistent_keepalive = EXCLUDED.persistent_keepalive,
        updated_at = CURRENT_TIMESTAMP;"
}

# Function to configure WireGuard
configure_wireguard() {
    log "Configuring WireGuard"
    
    # Fetch server configuration from the database
    server_config=$(sudo -u postgres psql -d wireguard_vpn -tAc "SELECT private_key, endpoint, port, mtu FROM server_config LIMIT 1;")
    IFS='|' read -r private_key endpoint port mtu <<< "$server_config"
    
    # Create WireGuard configuration file
    cat > /etc/wireguard/wg0.conf <<EOL
[Interface]
PrivateKey = $private_key
Address = 10.0.0.1/24
ListenPort = $port
MTU = $mtu
SaveConfig = true
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Client configurations will be added dynamically
EOL

    # Set correct permissions
    chmod 600 /etc/wireguard/wg0.conf
}

# Function to optimize WireGuard performance
optimize_wireguard() {
    log "Optimizing WireGuard performance"
    
    # Calculate optimal MTU
    optimal_mtu=$(( $(cat /sys/class/net/eth0/mtu) - 80 ))
    ip link set mtu $optimal_mtu dev wg0
    
    # Enable IP forwarding
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    
    # Optimize UDP and TCP buffers
    cat >> /etc/sysctl.conf <<EOL
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 87380 4194304
EOL
    
    # Enable BBR congestion control
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    
    # Adjust flow control for network optimization
    echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf
    
    # Apply sysctl changes
    sysctl -p
    
    # Enable Receive Packet Steering (RPS) and Receive Flow Steering (RFS)
    echo f > /sys/class/net/eth0/queues/rx-0/rps_cpus
    echo 32768 > /proc/sys/net/core/rps_sock_flow_entries
    echo 32768 > /sys/class/net/eth0/queues/rx-0/rps_flow_cnt
    
    # Update database with optimizations
    sudo -u postgres psql -d wireguard_vpn -c "
    UPDATE server_config
    SET mtu = $optimal_mtu, persistent_keepalive = 25
    WHERE id = 1;"
}

# Function to set up firewall rules
setup_firewall() {
    log "Setting up firewall rules"
    
    # Allow WireGuard traffic
    ufw allow 51820/udp
    
    # Allow SSH (adjust if your SSH port is different)
    ufw allow 22/tcp
    
    # Allow forwarding
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    
    # Enable NAT
    echo "net.ipv4.ip_forward=1" >> /etc/ufw/sysctl.conf
    
    # Configure iptables for WireGuard
    iptables -A FORWARD -i wg0 -j ACCEPT
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    
    # Limit connections per client
    iptables -A INPUT -p udp --dport 51820 -m connlimit --connlimit-above 5 -j REJECT
    
    # Enable IPv6 support
    ip6tables -A FORWARD -i wg0 -j ACCEPT
    ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    
    # Save iptables rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    
    # Apply rules
    ufw --force enable
    
    # Configure fail2ban
    cat > /etc/fail2ban/jail.local <<EOL
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[wireguard]
enabled = true
port = 51820
filter = wireguard
logpath = /var/log/syslog
maxretry = 3
bantime = 3600
EOL

    # Create WireGuard filter for fail2ban
    cat > /etc/fail2ban/filter.d/wireguard.conf <<EOL
[Definition]
failregex = Failed to authenticate peer \(tried \d+ keys\)
ignoreregex =
EOL

    # Restart fail2ban
    systemctl restart fail2ban
}

# Function to create a new client
create_client() {
    log "Creating a new client"
    
    read -p "Enter client name: " client_name
    
    # Generate client keys
    client_private_key=$(wg genkey)
    client_public_key=$(echo "$client_private_key" | wg pubkey)
    
    # Assign IP address
    client_ip="10.0.0.$(( $(sudo -u postgres psql -d wireguard_vpn -tAc "SELECT COUNT(*) FROM wireguard_users;") + 2 ))/32"
    
    # Insert client into database
    sudo -u postgres psql -d wireguard_vpn -c "
    INSERT INTO wireguard_users (username, private_key, public_key, allowed_ips)
    VALUES ('$client_name', '$client_private_key', '$client_public_key', '$client_ip');"
    
    # Fetch server public key and endpoint
    server_info=$(sudo -u postgres psql -d wireguard_vpn -tAc "SELECT public_key, endpoint, port, dns, mtu FROM server_config LIMIT 1;")
    IFS='|' read -r server_public_key server_endpoint server_port server_dns server_mtu <<< "$server_info"
    
    # Generate client configuration
    client_config="
[Interface]
PrivateKey = $client_private_key
Address = $client_ip
DNS = ${server_dns:-1.1.1.1}
MTU = $server_mtu

[Peer]
PublicKey = $server_public_key
Endpoint = $server_endpoint:$server_port
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"
    
    # Save client configuration
    mkdir -p /etc/wireguard/clients
    echo "$client_config" > "/etc/wireguard/clients/$client_name.conf"
    
    # Add client to server configuration
    wg set wg0 peer "$client_public_key" allowed-ips "${client_ip%/*}"
    
    log "Client $client_name created successfully"
}

# Function to remove inactive clients
remove_inactive_clients() {
    log "Removing inactive clients"
    
    # Get list of inactive clients (no handshake in the last 30 days)
    inactive_clients=$(sudo -u postgres psql -d wireguard_vpn -tAc "
    SELECT username, public_key FROM wireguard_users
    WHERE last_handshake < NOW() - INTERVAL '30 days' OR last_handshake IS NULL;")
    
    while IFS='|' read -r username public_key; do
        # Remove client from WireGuard configuration
        wg set wg0 peer "$public_key" remove
        
        # Remove client from database
        sudo -u postgres psql -d wireguard_vpn -c "DELETE FROM wireguard_users WHERE username = '$username';"
        
        # Remove client configuration file
        rm -f "/etc/wireguard/clients/$username.conf"
        
        log "Removed inactive client: $username"
    done <<< "$inactive_clients"
}

# Function to start WireGuard
start_wireguard() {
    log "Starting WireGuard"
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
}

# Function to set up monitoring
setup_monitoring() {
    log "Setting up monitoring with Prometheus and node_exporter"
    
    # Configure Prometheus
    cat > /etc/prometheus/prometheus.yml <<EOL
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'postgres'
static_configs:
      - targets: ['localhost:9187']
  - job_name: 'wireguard'
    static_configs:
      - targets: ['localhost:9586']
EOL

    # Start and enable Prometheus services
    systemctl enable prometheus
    systemctl start prometheus
    systemctl enable prometheus-node-exporter
    systemctl start prometheus-node-exporter
    systemctl enable postgresql-exporter
    systemctl start postgresql-exporter

    # Set up WireGuard exporter
    wget https://github.com/MindFlavor/prometheus_wireguard_exporter/releases/download/3.6.5/prometheus_wireguard_exporter_3.6.5_amd64.deb
    dpkg -i prometheus_wireguard_exporter_3.6.5_amd64.deb
    systemctl enable prometheus-wireguard-exporter
    systemctl start prometheus-wireguard-exporter
}

# Function to set up PgBouncer
setup_pgbouncer() {
    log "Setting up PgBouncer for connection pooling"
    
    # Generate PgBouncer password
    PGBOUNCER_PASSWORD=$(generate_password)
    
    # Configure PgBouncer
    cat > /etc/pgbouncer/pgbouncer.ini <<EOL
[databases]
wireguard_vpn = host=127.0.0.1 port=5432 dbname=wireguard_vpn

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
min_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 5
max_db_connections = 50
max_user_connections = 50
EOL

    # Create userlist for PgBouncer
    echo '"wireguard_admin" "'$PGBOUNCER_PASSWORD'"' > /etc/pgbouncer/userlist.txt
    
    # Secure PgBouncer configuration
    chown postgres:postgres /etc/pgbouncer/userlist.txt
    chmod 600 /etc/pgbouncer/userlist.txt
    
    # Start and enable PgBouncer
    systemctl enable pgbouncer
    systemctl start pgbouncer
}

# Function to set up automatic updates
setup_automatic_updates() {
    log "Setting up automatic updates"
    
    apt-get install -y unattended-upgrades
    
    # Configure unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOL
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOL

    # Enable automatic updates
    echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
    echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
}

# Function to set up backups
setup_backups() {
    log "Setting up automated backups"
    
    # Install required packages
    apt-get install -y postgresql-client awscli

    # Create backup script
    cat > /usr/local/bin/backup_wireguard.sh <<EOL
#!/bin/bash
BACKUP_DIR="/var/backups/wireguard"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/wireguard_vpn_\$TIMESTAMP.sql"

# Ensure backup directory exists
mkdir -p \$BACKUP_DIR

# Perform database backup
sudo -u postgres pg_dump wireguard_vpn > \$BACKUP_FILE

# Compress the backup
gzip \$BACKUP_FILE

# Upload to S3 (uncomment and configure if using S3)
# aws s3 cp \$BACKUP_FILE.gz s3://your-bucket-name/wireguard-backups/

# Remove backups older than 7 days
find \$BACKUP_DIR -type f -mtime +7 -delete
EOL

    chmod +x /usr/local/bin/backup_wireguard.sh

    # Set up daily cron job for backups
    echo "0 2 * * * root /usr/local/bin/backup_wireguard.sh" > /etc/cron.d/wireguard-backup
}

# Main execution
main() {
    check_root
    install_dependencies
    setup_postgresql
    generate_keys
    configure_wireguard
    optimize_wireguard
    setup_firewall
    setup_monitoring
    setup_pgbouncer
    setup_automatic_updates
    setup_backups
    start_wireguard
    
    log "WireGuard VPN server installation and configuration completed successfully"
    log "Use the create_client function to add new clients"
    log "Monitoring is set up with Prometheus and node_exporter"
    log "Connection pooling is configured with PgBouncer"
    log "Automatic updates and backups are configured"
}

main "$@"
