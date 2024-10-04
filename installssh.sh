#!/bin/bash

set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/advanced_ssh_install.log
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install packages
install_package() {
    if command_exists apt-get; then
        apt-get install -y "$@"
    elif command_exists yum; then
        yum install -y "$@"
    else
        log "Error: Unsupported package manager"
        exit 1
    fi
}

# Update and upgrade system
log "Updating and upgrading system..."
if command_exists apt-get; then
    apt-get update && apt-get upgrade -y
elif command_exists yum; then
    yum update -y
else
    log "Error: Unsupported package manager"
    exit 1
fi

# Install prerequisites
log "Installing prerequisites..."
install_package curl wget git build-essential libssl-dev zlib1g-dev libncurses5-dev libncursesw5-dev libreadline-dev libsqlite3-dev libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev liblzma-dev libffi-dev libc6-dev postgresql-client openssh-server dropbear stunnel4 python3 python3-pip nginx

# Install WebSocket support
pip3 install websockets

# Backup original SSH configuration
log "Backing up original SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Get port numbers from user
read -p "Enter SSH port (default 22): " ssh_port
ssh_port=${ssh_port:-22}
read -p "Enter SSH-TLS port (default 444): " ssh_tls_port
ssh_tls_port=${ssh_tls_port:-444}
read -p "Enter Dropbear port (default 22222): " dropbear_port
dropbear_port=${dropbear_port:-22222}

# Configure SSH
log "Configuring SSH..."
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
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/C=US/ST=State/L=City/O=Organization/CN=example.com" -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem

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
    }
}
EOF

ln -s /etc/nginx/sites-available/ssh-websocket /etc/nginx/sites-enabled/

# Create WebSocket to SSH proxy script
log "Creating WebSocket to SSH proxy script..."
cat << 'EOF' > /usr/local/bin/websocket_to_ssh.py
import asyncio
import websockets
import socket

async def handle_connection(websocket, path):
    ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ssh_socket.connect(('127.0.0.1', 22))  # Connect to SSH server

    async def forward_ws_to_ssh():
        while True:
            data = await websocket.recv()
            ssh_socket.sendall(data)

    async def forward_ssh_to_ws():
        while True:
            data = ssh_socket.recv(4096)
            if not data:
                break
            await websocket.send(data)

    await asyncio.gather(
        forward_ws_to_ssh(),
        forward_ssh_to_ws()
    )

start_server = websockets.serve(handle_connection, '127.0.0.1', 8080)

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

# Install fail2ban
log "Installing and configuring fail2ban..."
install_package fail2ban
cat << EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[dropbear]
enabled = true
port = $dropbear_port
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
systemctl restart fail2ban

# Configure firewall (assuming UFW)
log "Configuring firewall..."
install_package ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow $ssh_port/tcp
ufw allow $ssh_tls_port/tcp
ufw allow $dropbear_port/tcp
ufw allow 80/tcp
ufw enable

# Update PostgreSQL with new port information
log "Updating PostgreSQL with new port information..."
sudo -u postgres psql -c "CREATE TABLE IF NOT EXISTS ssh_ports (id SERIAL PRIMARY KEY, port_type VARCHAR(50), port_number INTEGER);"
sudo -u postgres psql -c "INSERT INTO ssh_ports (port_type, port_number) VALUES ('SSH', $ssh_port), ('SSH-TLS', $ssh_tls_port), ('Dropbear', $dropbear_port) ON CONFLICT (port_type) DO UPDATE SET port_number = EXCLUDED.port_number;"

# Final setup
log "Installation and configuration completed successfully."
log "SSH port: $ssh_port"
log "SSH-TLS port: $ssh_tls_port"
log "Dropbear port: $dropbear_port"
log "WebSocket SSH available at: ws://your-server-ip/ssh-ws"
log "Please remember to:"
log "1. Set up a strong password for the PostgreSQL 'vpnuser'"
log "2. Configure your SSH clients to use the new ports"
log "3. Regularly update and maintain your system"
log "4. Monitor logs and system performance"

exit 0
