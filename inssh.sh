#!/bin/bash

# Enable strict error handling and debugging
set -euo pipefail
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Global configurations
readonly LOG_FILE="/var/log/enhanced_ssh_server.log"
readonly METRICS_DIR="/var/lib/node_exporter"
readonly BACKUP_DIR="/var/backups/ssh_server"
readonly CONFIG_DIR="/etc/ssh_server"
readonly VAULT_ADDR="http://localhost:8200"
readonly DB_POOL_MIN=5
readonly DB_POOL_MAX=20

# Function to log messages with enhanced formatting
log() {
    local level=$1
    local message=$2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Error handling function
error_handler() {
    local exit_code=$1
    local line_number=$2
    local last_command=$4
    
    log "ERROR" "Command '$last_command' failed with exit code $exit_code at line $line_number"
    
    # Attempt recovery
    if [[ "$exit_code" == "1" ]]; then
        log "INFO" "Attempting automatic recovery..."
        systemctl restart sshd dropbear stunnel4 nginx
    fi
    
    send_alert "ERROR: SSH Server failure at line $line_number"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install packages with error handling
install_package() {
    log "INFO" "Installing packages: $*"
    if command_exists apt-get; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    elif command_exists yum; then
        yum install -y "$@"
    else
        log "ERROR" "Unsupported package manager"
        exit 1
    fi
}

# Generate secure random password
generate_secure_password() {
    openssl rand -base64 32
}

# Enhanced certificate generation with proper attributes
generate_certificate() {
    local CERT_DIR="/etc/ssl/private"
    local DOMAIN="$1"
    
    log "INFO" "Generating certificates for domain: $DOMAIN"
    
    # Generate strong DH parameters
    openssl dhparam -out "$CERT_DIR/dhparams.pem" 4096
    
    # Generate private key with modern encryption
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
        -out "$CERT_DIR/server.key"
    
    # Generate CSR with proper attributes
    openssl req -new -key "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.csr" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN" \
        -config <(cat /etc/ssl/openssl.cnf \
            <(printf "[SAN]\nsubjectAltName=DNS:%s" "$DOMAIN"))
            
    # Self-sign certificate with proper extensions
    openssl x509 -req -days 365 -in "$CERT_DIR/server.csr" \
        -signkey "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" \
        -extensions v3_ca -extfile /etc/ssl/openssl.cnf
        
    # Set proper permissions
    chmod 600 "$CERT_DIR/server.key"
    chmod 644 "$CERT_DIR/server.crt"
}

# Enhanced fail2ban configuration
configure_fail2ban() {
    log "INFO" "Configuring fail2ban..."
    
    cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 86400  # 24 hours
findtime = 600   # 10 minutes
maxretry = 3
banaction = ufw
protocol = all
chain = INPUT

[sshd]
enabled = true
port = ssh,${ssh_port},${ssh_tls_port}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[dropbear]
enabled = true
port = ${dropbear_port}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
EOF

    systemctl restart fail2ban
}

# Database connection management with enhanced security
init_db_connection() {
    log "INFO" "Initializing database connection..."
    
    # Create database connection pool
    cat << EOF > /etc/pgbouncer/pgbouncer.ini
[databases]
* = host=localhost port=5432

[pgbouncer]
pool_mode = transaction
max_client_conn = $DB_POOL_MAX
default_pool_size = $DB_POOL_MIN
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = 50
max_user_connections = 25
server_reset_query = DISCARD ALL
server_check_delay = 30
server_check_query = select 1
server_lifetime = 3600
server_idle_timeout = 600
EOF

    systemctl restart pgbouncer
}

# Configure enhanced monitoring
setup_monitoring() {
    log "INFO" "Setting up monitoring system..."
    
    # Install Prometheus Node Exporter
    install_package prometheus-node-exporter
    
    # Configure custom metrics
    mkdir -p "$METRICS_DIR"
    
    # Create metrics collection script
    cat << 'EOF' > /usr/local/bin/collect_ssh_metrics.sh
#!/bin/bash

while true; do
    # Collect SSH metrics
    active_connections=$(ss -tnp | grep -c sshd)
    failed_auths=$(grep -c "Failed password" /var/log/auth.log)
    successful_auths=$(grep -c "Accepted" /var/log/auth.log)
    
    # Write to node exporter directory
    cat << METRICS > "$METRICS_DIR/ssh_metrics.prom"
ssh_active_connections $active_connections
ssh_failed_auth_attempts $failed_auths
ssh_successful_auth_attempts $successful_auths
METRICS

    sleep 60
done
EOF

    chmod +x /usr/local/bin/collect_ssh_metrics.sh
    
    # Create systemd service for metrics collection
    cat << EOF > /etc/systemd/system/ssh-metrics.service
[Unit]
Description=SSH Metrics Collector
After=network.target

[Service]
ExecStart=/usr/local/bin/collect_ssh_metrics.sh
Restart=always
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable --now ssh-metrics
}

# Configure WebSocket proxy with enhanced security
setup_websocket_proxy() {
    log "INFO" "Setting up WebSocket proxy..."
    
    cat << 'EOF' > /usr/local/bin/websocket_proxy.py
import asyncio
import websockets
import ssl
import jwt
from datetime import datetime, timedelta
import socket
import logging
import prometheus_client as prom

# Set up metrics
ACTIVE_CONNECTIONS = prom.Gauge('ws_active_connections', 'Number of active WebSocket connections')
CONNECTION_ERRORS = prom.Counter('ws_connection_errors', 'Number of WebSocket connection errors')
BYTES_TRANSFERRED = prom.Counter('ws_bytes_transferred', 'Number of bytes transferred')

class SecureWebSocketServer:
    def __init__(self, host='127.0.0.1', port=8080):
        self.host = host
        self.port = port
        self.clients = set()
        self.ssl_context = self._create_ssl_context()
        self.rate_limiter = {}
        
    def _create_ssl_context(self):
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain('/etc/ssl/private/server.crt',
                                  '/etc/ssl/private/server.key')
        ssl_context.set_ciphers('ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384')
        return ssl_context
    
    async def authenticate(self, websocket):
        try:
            token = await websocket.recv()
            payload = jwt.decode(token, 'your-secret-key', algorithms=['HS256'])
            return payload['user_id']
        except Exception as e:
            logging.error(f"Authentication failed: {e}")
            CONNECTION_ERRORS.inc()
            await websocket.close(1008, 'Authentication failed')
            return None
            
    async def handle_connection(self, websocket, path):
        user_id = await self.authenticate(websocket)
        if not user_id:
            return
            
        # Rate limiting check
        client_ip = websocket.remote_address[0]
        current_time = datetime.now()
        if client_ip in self.rate_limiter:
            if (current_time - self.rate_limiter[client_ip]).seconds < 60:
                await websocket.close(1008, 'Rate limit exceeded')
                return
        self.rate_limiter[client_ip] = current_time
        
        ssh_socket = None
        try:
            ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            ssh_socket.connect(('127.0.0.1', 22))
            self.clients.add(websocket)
            ACTIVE_CONNECTIONS.inc()
            
            async def forward_ws_to_ssh():
                try:
                    while True:
                        data = await websocket.recv()
                        ssh_socket.sendall(data)
                        BYTES_TRANSFERRED.inc(len(data))
                except Exception as e:
                    logging.error(f"WS->SSH forwarding error: {e}")
                    CONNECTION_ERRORS.inc()
                    
            async def forward_ssh_to_ws():
                try:
                    while True:
                        data = ssh_socket.recv(4096)
                        if not data:
                            break
                        await websocket.send(data)
                        BYTES_TRANSFERRED.inc(len(data))
                except Exception as e:
                    logging.error(f"SSH->WS forwarding error: {e}")
                    CONNECTION_ERRORS.inc()
                    
            await asyncio.gather(
                forward_ws_to_ssh(),
                forward_ssh_to_ws()
            )
            
        except Exception as e:
            logging.error(f"Connection error: {e}")
            CONNECTION_ERRORS.inc()
        finally:
            if ssh_socket:
                ssh_socket.close()
            self.clients.remove(websocket)
            ACTIVE_CONNECTIONS.dec()
            
    async def start(self):
        async with websockets.serve(
            self.handle_connection,
            self.host,
            self.port,
            ssl=self.ssl_context
        ):
            await asyncio.Future()  # run forever
            
    def run(self):
        asyncio.run(self.start())

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    prom.start_http_server(8000)
    server = SecureWebSocketServer()
    server.run()
EOF

    # Create systemd service for WebSocket proxy
    cat << EOF > /etc/systemd/system/websocket-proxy.service
[Unit]
Description=SSH WebSocket Proxy
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/websocket_proxy.py
Restart=always
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable --now websocket-proxy
}

# Configure backup system
setup_backup_system() {
    log "INFO" "Setting up backup system..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Create backup script
    cat << 'EOF' > /usr/local/bin/backup_ssh_server.sh
#!/bin/bash

timestamp=$(date +%Y%m%d_%H%M%S)
backup_file="$BACKUP_DIR/ssh_server_$timestamp.tar.gz"

# Backup configuration and certificates
tar czf "$backup_file" \
    /etc/ssh \
    /etc/ssl/private \
    /etc/stunnel \
    /etc/nginx/sites-available \
    /var/log/ssh_server.log

# Encrypt backup
gpg --encrypt --recipient admin@example.com "$backup_file"

# Rotate old backups
find "$BACKUP_DIR" -type f -mtime +7 -delete
EOF

    chmod +x /usr/local/bin/backup_ssh_server.sh
    
    # Set up daily backup
    cat << EOF > /etc/cron.d/ssh_server_backup
0 2 * * * root /usr/local/bin/backup_ssh_server.sh
EOF
}

# Main setup function
main() {
    log "INFO" "Starting enhanced SSH server setup..."
    
    # Update and upgrade system
    if command_exists apt-get; then
        apt-get update && apt-get upgrade -y
    elif command_exists yum; then
        yum update -y
    fi
    
    # Install required packages
    install_package \
        curl wget git build-essential libssl-dev \
        zlib1g-dev libncurses5-dev libncursesw5-dev \
        libreadline-dev libsqlite3-dev libgdbm-dev \
        libdb5.3-dev libbz2-dev libexpat1-dev \
        liblzma-dev libffi-dev libc6-dev postgresql-client \
        openssh-server dropbear stunnel4 python3 python3-pip \
        nginx fail2ban prometheus-node-exporter pgbouncer
        
    # Install Python packages
    pip3 install websockets prometheus_client jwt
    
    # Get port numbers
    read -p "Enter SSH port (default 22): " ssh_port
    ssh_port=${ssh_port:-22}
    read -p "Enter SSH-TLS port (default 444): " ssh_tls_port
    ssh_tls_port=${ssh_tls_port:-444}
    read -p "Enter Dropbear port (default 22222): " dropbear_port
    dropbear_port=${dropbear_port:-22222}
    
    # Generate certificates
    generate_certificate "$(hostname -f)"
    
    # Configure components
    configure_fail2ban
    init_db_connection
    setup_monitoring
    setup_websocket_proxy
    setup_backup_system
    
    # Configure SSH
    log "INFO" "Configuring SSH..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    cat << EOF > /etc/ssh/sshd_config
# SSH Server Configuration
Port $ssh_port
AddressFamily inet
ListenAddress 0.0.0.0
Protocol 2

# Authentication
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security
X11Forwarding no
AllowTcpForwarding yes
AllowAgentForwarding yes
PermitUserEnvironment no
Compression delayed

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Idle timeout
ClientAliveInterval 300
ClientAliveCountMax 2

# Max auth tries and sessions
MaxAuthTries 3
MaxSessions 10

# Allow only specific users (replace with your users)
AllowUsers vpnuser

# Use strong ciphers and algorithms
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256

# Banner
Banner /etc/ssh/banner
EOF

# Create SSH banner
log "Creating SSH banner..."
cat << EOF > /etc/ssh/banner
*******************************************************************
*                   Authorized access only!                       *
* Disconnect IMMEDIATELY if you are not an authorized user!       *
*       All actions are logged and monitored                      *
*******************************************************************
EOF

# Set correct permissions for SSH files
log "Setting correct permissions for SSH files..."
chmod 600 /etc/ssh/ssh_host_*_key
chmod 644 /etc/ssh/ssh_host_*_key.pub
chmod 644 /etc/ssh/sshd_config
chmod 644 /etc/ssh/banner

# Generate strong SSH keys
log "Generating strong SSH keys..."
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""

# Configure Dropbear
log "Configuring Dropbear..."
cat << EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=$dropbear_port
DROPBEAR_EXTRA_ARGS="-w -g"
DROPBEAR_BANNER="/etc/ssh/banner"
EOF

# Configure SSH-TLS (stunnel)
log "Configuring SSH-TLS..."
cat << EOF > /etc/stunnel/stunnel.conf
[ssh]
accept = $ssh_tls_port
connect = 127.0.0.1:$ssh_port
cert = /etc/stunnel/stunnel.pem
EOF

# Generate self-signed certificate for stunnel
log "Generating self-signed certificate for stunnel..."
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=US/ST=State/L=City/O=Organization/CN=example.com" -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem

# Configure SSH WebSocket
log "Configuring SSH WebSocket..."
cat << EOF > /etc/nginx/sites-available/ssh-websocket
server {
    listen 80;
    server_name _;

    location /ssh-ws {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -s /etc/nginx/sites-available/ssh-websocket /etc/nginx/sites-enabled/

# Create WebSocket to SSH proxy script with enhanced security and monitoring
log "Creating WebSocket to SSH proxy script..."
cat << 'EOF' > /usr/local/bin/websocket_to_ssh.py
import asyncio
import websockets
import socket
import ssl
import logging
from datetime import datetime

logging.basicConfig(filename='/var/log/ssh_websocket.log', level=logging.INFO)

class RateLimiter:
    def __init__(self, max_calls, time_frame):
        self.max_calls = max_calls
        self.time_frame = time_frame
        self.calls = []

    def __call__(self):
        now = datetime.now()
        self.calls = [call for call in self.calls if (now - call).total_seconds() < self.time_frame]
        if len(self.calls) >= self.max_calls:
            return False
        self.calls.append(now)
        return True

rate_limiter = RateLimiter(max_calls=5, time_frame=60)  # 5 calls per minute

async def handle_connection(websocket, path):
    if not rate_limiter():
        logging.warning(f"Rate limit exceeded for {websocket.remote_address}")
        await websocket.close(1008, "Rate limit exceeded")
        return

    try:
        ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_socket.settimeout(10)  # Set a timeout for the connection
        ssh_socket.connect(('127.0.0.1', 22))  # Connect to SSH server
        logging.info(f"New connection from {websocket.remote_address}")

        async def forward_ws_to_ssh():
            try:
                while True:
                    data = await asyncio.wait_for(websocket.recv(), timeout=300)  # 5 minutes timeout
                    if not data:
                        break
                    ssh_socket.sendall(data)
            except asyncio.TimeoutError:
                logging.info(f"WebSocket to SSH forward timeout for {websocket.remote_address}")
            except Exception as e:
                logging.error(f"Error in WebSocket to SSH forward for {websocket.remote_address}: {str(e)}")

        async def forward_ssh_to_ws():
            try:
                while True:
                    data = await asyncio.get_event_loop().run_in_executor(None, ssh_socket.recv, 4096)
                    if not data:
                        break
                    await websocket.send(data)
            except Exception as e:
                logging.error(f"Error in SSH to WebSocket forward for {websocket.remote_address}: {str(e)}")

        await asyncio.gather(
            forward_ws_to_ssh(),
            forward_ssh_to_ws()
        )
    except Exception as e:
        logging.error(f"Connection error for {websocket.remote_address}: {str(e)}")
    finally:
        ssh_socket.close()
        logging.info(f"Connection closed for {websocket.remote_address}")

ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ssl_context.load_cert_chain('/etc/stunnel/stunnel.pem')

start_server = websockets.serve(
    handle_connection, 
    '127.0.0.1', 
    8080, 
    ssl=ssl_context,
    max_size=10 * 1024 * 1024,  # 10 MB max message size
    max_queue=32,  # Max 32 pending connections
    compression=None  # Disable compression for better performance
)

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

# Create systemd service for WebSocket proxy
log "Creating systemd service for WebSocket proxy..."
cat << EOF > /etc/systemd/system/ssh-websocket.service
[Unit]
Description=SSH WebSocket Proxy
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/websocket_to_ssh.py
Restart=always
User=nobody
Group=nogroup
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
log "Enabling and starting services..."
systemctl enable ssh
systemctl enable dropbear
systemctl enable stunnel4
systemctl enable nginx
systemctl enable ssh-websocket

systemctl restart ssh
systemctl restart dropbear
systemctl restart stunnel4
systemctl restart nginx
systemctl start ssh-websocket

# Install and configure fail2ban with additional jails
log "Installing and configuring fail2ban..."
install_package fail2ban
cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log

[dropbear]
enabled = true
port = $dropbear_port
filter = sshd
logpath = /var/log/auth.log

[stunnel]
enabled = true
port = $ssh_tls_port
filter = stunnel
logpath = /var/log/stunnel4/stunnel.log

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log

[nginx-badbots]
enabled = true
filter = nginx-badbots
port = http,https
logpath = /var/log/nginx/access.log
EOF
systemctl restart fail2ban

# Configure firewall (using UFW)
log "Configuring firewall..."
install_package ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow $ssh_port/tcp comment "SSH"
ufw allow $ssh_tls_port/tcp comment "SSH-TLS"
ufw allow $dropbear_port/tcp comment "Dropbear"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable

# Install and configure auditd for system auditing
log "Installing and configuring auditd..."
install_package auditd

cat << EOF > /etc/audit/rules.d/audit.rules
# Log all unauthorized accesses
-a exit,always -F arch=b64 -S open -F dir=/etc -F success=0
-a exit,always -F arch=b32 -S open -F dir=/etc -F success=0

# Monitor changes to system files
-w /etc/passwd -p wa
-w /etc/shadow -p wa
-w /etc/group -p wa
-w /etc/ssh/sshd_config -p wa

# Monitor privileged commands
-a exit,always -F path=/usr/bin/sudo -F perm=x
-a exit,always -F path=/usr/bin/su -F perm=x

# Monitor unsuccessful unauthorized access attempts
-a always,exit -F arch=b64 -S open -F dir=/home -F success=0
-a always,exit -F arch=b32 -S open -F dir=/home -F success=0

# Monitor changes to user and group information
-w /etc/passwd -p wa
-w /etc/group -p wa
-w /etc/shadow -p wa
-w /etc/sudoers -p wa
EOF

systemctl restart auditd

# Install and configure Prometheus for monitoring
log "Installing and configuring Prometheus..."
install_package prometheus

cat << EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'ssh'
    static_configs:
      - targets: ['localhost:9256']
EOF

systemctl restart prometheus

# Install and configure node_exporter for system metrics
log "Installing and configuring node_exporter..."
wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.3.1.linux-amd64.tar.gz
mv node_exporter-1.3.1.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.3.1.linux-amd64*

cat << EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Install and configure Grafana for visualization
log "Installing and configuring Grafana..."
install_package grafana
systemctl enable grafana-server
systemctl start grafana-server

# Update PostgreSQL with new port information and add connection pooling
log "Updating PostgreSQL with new port information and adding connection pooling..."
install_package postgresql pgbouncer

sudo -u postgres psql -c "CREATE DATABASE sshmanager;"
sudo -u postgres psql -c "CREATE USER sshmanager WITH ENCRYPTED PASSWORD 'strongpassword';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sshmanager TO sshmanager;"

sudo -u postgres psql sshmanager << EOF
CREATE TABLE IF NOT EXISTS ssh_ports (
    id SERIAL PRIMARY KEY,
    port_type VARCHAR(50) UNIQUE,
    port_number INTEGER,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ssh_connections (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    connection_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    disconnect_time TIMESTAMP,
    source_ip VARCHAR(50),
    port_used INTEGER
);

INSERT INTO ssh_ports (port_type, port_number) 
VALUES ('SSH', $ssh_port), ('SSH-TLS', $ssh_tls_port), ('Dropbear', $dropbear_port) 
ON CONFLICT (port_type) DO UPDATE SET 
    port_number = EXCLUDED.port_number,
    last_updated = CURRENT_TIMESTAMP;
EOF

# Configure PgBouncer for connection pooling
cat << EOF > /etc/pgbouncer/pgbouncer.ini
[databases]
sshmanager = host=127.0.0.1 port=5432 dbname=sshmanager

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = session
max_client_conn = 1000
default_pool_size = 20
EOF

echo '"sshmanager" "strongpassword"' > /etc/pgbouncer/userlist.txt
chmod 600 /etc/pgbouncer/userlist.txt

systemctl enable pgbouncer
systemctl start pgbouncer

# Create a script to periodically clean up old connection logs
cat << 'EOF' > /usr/local/bin/cleanup_ssh_logs.sh
#!/bin/bash
psql -h 127.0.0.1 -p 6432 -U sshmanager -d sshmanager << EOQ
DELETE FROM ssh_connections WHERE connection_time < NOW() - INTERVAL '30 days';
VACUUM FULL ssh_connections;
EOQ
EOF

chmod +x /usr/local/bin/cleanup_ssh_logs.sh

# Add a cron job to run the cleanup script weekly
(crontab -l 2>/dev/null; echo "0 0 * * 0 /usr/local/bin/cleanup_ssh_logs.sh") | crontab -

# Create a script for monitoring SSH connections
cat << 'EOF' > /usr/local/bin/monitor_ssh_connections.sh
#!/bin/bash
CONNECTIONS=$(netstat -tnpa | grep 'ESTABLISHED.*sshd')

# Log connections to a file
echo "$(date): $CONNECTIONS" >> /var/log/ssh_connections.log

# Check for suspicious activity (e.g., multiple connections from the same IP)
SUSPICIOUS=$(echo "$CONNECTIONS" | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | awk '$1 > 5 {print $2}')

if [ ! -z "$SUSPICIOUS" ]; then
    echo "Suspicious activity detected from IP(s): $SUSPICIOUS" | mail -s "SSH Alert" admin@example.com
fi

# Update Prometheus metrics
echo "ssh_active_connections $(echo "$CONNECTIONS" | wc -l)" > /var/lib/node_exporter/ssh_metrics.prom
EOF

chmod +x /usr/local/bin/monitor_ssh_connections.sh

# Add a cron job to run the monitoring script every 5 minutes
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/monitor_ssh_connections.sh") | crontab -

# Implement secret management with HashiCorp Vault
install_package vault

# Initialize Vault (this should be done manually in a production environment)
vault server -dev &
export VAULT_ADDR='http://127.0.0.1:8200'
vault operator init > /root/vault_keys.txt

# Store SSH configuration in Vault
vault kv put secret/ssh-config ssh_port="$ssh_port" ssh_tls_port="$ssh_tls_port" dropbear_port="$dropbear_port"

# Function to retrieve secrets from Vault
get_secret() {
    vault kv get -field="$2" secret/"$1"
}

# Implement CI/CD pipeline (example using GitLab CI)
cat << EOF > .gitlab-ci.yml
stages:
  - test
  - deploy

test:
  stage: test
  script:
    - bash -n advanced_ssh_install.sh
    - shellcheck advanced_ssh_install.sh

deploy:
  stage: deploy
  script:
    - scp advanced_ssh_install.sh user@remote-server:/tmp/
    - ssh user@remote-server 'bash /tmp/advanced_ssh_install.sh'
  only:
    - main
EOF

# Implement automated security scanning
install_package lynis

cat << EOF > /usr/local/bin/security_scan.sh
#!/bin/bash
lynis audit system --quick
EOF

chmod +x /usr/local/bin/security_scan.sh

# Add a cron job to run the security scan weekly
(crontab -l 2>/dev/null; echo "0 0 * * 0 /usr/local/bin/security_scan.sh") | crontab -

# Implement backup and disaster recovery
install_package restic

# Initialize restic repository (replace with your preferred backup destination)
restic init --repo /path/to/backup/repository

# Create backup script
cat << EOF > /usr/local/bin/backup_ssh_config.sh
#!/bin/bash
restic -r /path/to/backup/repository backup /etc/ssh /etc/dropbear /etc/stunnel
restic -r /path/to/backup/repository forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6
EOF

chmod +x /usr/local/bin/backup_ssh_config.sh

# Add a cron job to run the backup script daily
(crontab -l 2>/dev/null; echo "0 1 * * * /usr/local/bin/backup_ssh_config.sh") | crontab -

# Implement proper monitoring and alerting
install_package prometheus alertmanager

# Configure Prometheus
cat << EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'ssh'
    static_configs:
      - targets: ['localhost:9100']
    metrics_path: '/metrics/ssh'

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - localhost:9093
EOF

# Configure Alertmanager
cat << EOF > /etc/alertmanager/alertmanager.yml
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
    from: 'alertmanager@example.com'
    smarthost: 'smtp.example.com:587'
    auth_username: 'alertmanager@example.com'
    auth_password: 'your-smtp-password'
EOF

# Restart Prometheus and Alertmanager
systemctl restart prometheus alertmanager

# Implement proper access control
install_package freeipa-server

# Set up FreeIPA (this should be customized for your environment)
ipa-server-install --setup-dns --no-forwarders

# Configure SSH to use FreeIPA for authentication
authconfig --enablesssd --enablesssdauth --enablemkhomedir --update

# Implement proper error handling
set -euo pipefail
trap 'echo "Error on line $LINENO: $BASH_COMMAND"' ERR

# Function for centralized error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    echo "Error on line $line_number: Command exited with status $exit_code"
    # You can add more sophisticated error handling here, like sending alerts
}
trap 'handle_error $? $LINENO' ERR

# Optimize database queries
cat << EOF > /etc/postgresql/13/main/postgresql.conf
max_connections = 100
shared_buffers = 256MB
effective_cache_size = 768MB
work_mem = 6553kB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 7864kB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
autovacuum = on
EOF

# Restart PostgreSQL to apply changes
systemctl restart postgresql

# Implement connection pooling
install_package pgbouncer

cat << EOF > /etc/pgbouncer/pgbouncer.ini
[databases]
* = host=127.0.0.1 port=5432

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = session
max_client_conn = 100
default_pool_size = 20
EOF

# Create user list for PgBouncer
echo '"postgres" "your-postgres-password"' > /etc/pgbouncer/userlist.txt

# Start PgBouncer
systemctl start pgbouncer

# Optimize WebSocket connections
cat << EOF > /usr/local/bin/websocket_to_ssh.py
import asyncio
import websockets
import socket
import ssl

async def handle_connection(websocket, path):
    ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ssh_socket.connect(('127.0.0.1', $(get_secret ssh-config ssh_port)))
    
    async def forward_ws_to_ssh():
        try:
            while True:
                data = await websocket.recv()
                ssh_socket.sendall(data)
        except websockets.exceptions.ConnectionClosed:
            ssh_socket.close()

    async def forward_ssh_to_ws():
        try:
            while True:
                data = ssh_socket.recv(4096)
                if not data:
                    break
                await websocket.send(data)
        except (BrokenPipeError, ConnectionResetError):
            await websocket.close()

    await asyncio.gather(
        forward_ws_to_ssh(),
        forward_ssh_to_ws()
    )

ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ssl_context.load_cert_chain('/etc/letsencrypt/live/your-domain.com/fullchain.pem', 
                            '/etc/letsencrypt/live/your-domain.com/privkey.pem')

start_server = websockets.serve(handle_connection, '0.0.0.0', 8080, ssl=ssl_context)

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

# Update systemd service for WebSocket proxy
cat << EOF > /etc/systemd/system/ssh-websocket.service
[Unit]
Description=SSH WebSocket Proxy
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/websocket_to_ssh.py
Restart=always
User=nobody
Group=nogroup
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and restart the WebSocket service
systemctl daemon-reload
systemctl restart ssh-websocket

# Implement rate limiting for SSH connections
cat << EOF > /etc/security/limits.conf
*               hard    nofile          65535
*               soft    nofile          65535
root            hard    nofile          65535
root            soft    nofile          65535
EOF

# Update SSH configuration for performance
cat << EOF >> /etc/ssh/sshd_config
MaxStartups 10:30:100
MaxSessions 10
TCPKeepAlive yes
ClientAliveInterval 120
ClientAliveCountMax 3
EOF

# Restart SSH service to apply changes
systemctl restart ssh

# Final setup and cleanup
log "Advanced SSH server setup completed successfully."
log "SSH port: $(get_secret ssh-config ssh_port)"
log "SSH-TLS port: $(get_secret ssh-config ssh_tls_port)"
log "Dropbear port: $(get_secret ssh-config dropbear_port)"
log "WebSocket SSH available at: wss://your-domain.com:8080"

# Remove temporary files and clear bash history
rm -rf /tmp/*
history -c

log "Please remember to:"
log "1. Regularly update and maintain your system"
log "2. Monitor logs and system performance"
log "3. Rotate encryption keys and update passwords periodically"
log "4. Keep backups in a secure, off-site location"
log "5. Conduct regular security audits"

exit 0
