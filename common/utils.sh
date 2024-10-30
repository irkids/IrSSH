#!/bin/bash

# Complete utility functions for VPN Management System
# Version: 2.0.0
# This script provides comprehensive utility functions for the entire system

# ================== Constants & Global Variables ==================

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Logging levels with numeric values
declare -A LOG_LEVELS=(
    ["TRACE"]=0
    ["DEBUG"]=1
    ["INFO"]=2
    ["WARN"]=3
    ["ERROR"]=4
    ["FATAL"]=5
)
CURRENT_LOG_LEVEL=${LOG_LEVELS["INFO"]}

# System requirements
readonly MIN_RAM_GB=4
readonly MIN_CPU_CORES=2
readonly MIN_DISK_GB=20
readonly MIN_NETWORK_SPEED=10 # Mbps
readonly REQUIRED_PORTS=(22 80 443 500 4500 51820 8080 5432 9090 3000 8000)

# Temporary directory for script operations
readonly TEMP_DIR="/tmp/vpn-manager"
readonly LOG_DIR="/var/log/vpn-manager"
readonly BACKUP_DIR="/var/backups/vpn-manager"

# ================== Core Utility Functions ==================

function create_directories() {
    local dirs=("$TEMP_DIR" "$LOG_DIR" "$BACKUP_DIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || {
                echo "Failed to create directory: $dir"
                return 1
            }
            chmod 750 "$dir"
        fi
    done
}

function initialize_logging() {
    local log_file="$LOG_DIR/vpn-manager-$(date +%Y%m%d).log"
    touch "$log_file" || return 1
    chmod 640 "$log_file"
    
    # Create log rotation configuration
    cat > /etc/logrotate.d/vpn-manager << EOF
$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF
}

# ================== Enhanced Logging System ==================

function log() {
    local level=$1
    shift
    local message=$@
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    local script_name=$(basename "$0")
    local line_number="${BASH_LINENO[0]}"
    local function_name="${FUNCNAME[1]:-main}"
    
    # Check if level is valid
    if [[ ! ${LOG_LEVELS[$level]} ]]; then
        level="INFO"
    fi
    
    # Only log if level is high enough
    if [[ ${LOG_LEVELS[$level]} -ge $CURRENT_LOG_LEVEL ]]; then
        # Format the log message
        local log_message="$timestamp [$level] [$script_name:$line_number] [$function_name] $message"
        
        # Color the output based on level
        case $level in
            "FATAL") echo -e "${RED}${log_message}${NC}" ;;
            "ERROR") echo -e "${RED}${log_message}${NC}" ;;
            "WARN")  echo -e "${YELLOW}${log_message}${NC}" ;;
            "INFO")  echo -e "${GREEN}${log_message}${NC}" ;;
            "DEBUG") echo -e "${BLUE}${log_message}${NC}" ;;
            "TRACE") echo -e "${PURPLE}${log_message}${NC}" ;;
        esac
        
        # Write to log file
        echo "$log_message" >> "$LOG_DIR/vpn-manager-$(date +%Y%m%d).log"
        
        # Special handling for FATAL level
        if [[ $level == "FATAL" ]]; then
            echo -e "${RED}Fatal error occurred. Check logs for details.${NC}"
            cleanup
            exit 1
        fi
    fi
}

# ================== System Check Functions ==================

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "FATAL" "This script must be run as root"
        return 1
    fi
    return 0
}

function check_system_requirements() {
    log "INFO" "Performing comprehensive system requirements check..."
    
    # Check RAM
    local total_ram_gb=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
    if (( $(echo "$total_ram_gb < $MIN_RAM_GB" | bc -l) )); then
        log "ERROR" "Insufficient RAM. Required: ${MIN_RAM_GB}GB, Found: ${total_ram_gb}GB"
        return 1
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt $MIN_CPU_CORES ]]; then
        log "ERROR" "Insufficient CPU cores. Required: ${MIN_CPU_CORES}, Found: ${cpu_cores}"
        return 1
    fi
    
    # Check disk space
    local disk_space_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $disk_space_gb -lt $MIN_DISK_GB ]]; then
        log "ERROR" "Insufficient disk space. Required: ${MIN_DISK_GB}GB, Found: ${disk_space_gb}GB"
        return 1
    fi
    
    # Check network speed
    check_network_speed || return 1
    
    # Check required ports
    check_required_ports || return 1
    
    # Check system architecture
    check_architecture || return 1
    
    log "INFO" "System requirements check passed successfully"
    return 0
}

function check_network_speed() {
    log "INFO" "Checking network speed..."
    
    # Install speedtest-cli if not present
    if ! command -v speedtest-cli &> /dev/null; then
        apt-get update && apt-get install -y speedtest-cli || {
            log "ERROR" "Failed to install speedtest-cli"
            return 1
        }
    }
    
    # Run speed test
    local speed_result=$(speedtest-cli --simple)
    local download_speed=$(echo "$speed_result" | awk '/Download/ {print $2}')
    
    if (( $(echo "$download_speed < $MIN_NETWORK_SPEED" | bc -l) )); then
        log "ERROR" "Insufficient network speed. Required: ${MIN_NETWORK_SPEED}Mbps, Found: ${download_speed}Mbps"
        return 1
    }
    
    log "INFO" "Network speed check passed: ${download_speed}Mbps"
    return 0
}

function check_required_ports() {
    log "INFO" "Checking required ports availability..."
    
    local busy_ports=()
    for port in "${REQUIRED_PORTS[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            busy_ports+=($port)
        fi
    done
    
    if [[ ${#busy_ports[@]} -gt 0 ]]; then
        log "ERROR" "Following ports are already in use: ${busy_ports[*]}"
        return 1
    fi
    
    log "INFO" "All required ports are available"
    return 0
}

function check_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            log "INFO" "Architecture check passed: $arch"
            return 0
            ;;
        *)
            log "ERROR" "Unsupported architecture: $arch. Only x86_64 is supported."
            return 1
            ;;
    esac
}

# ================== Package Management Functions ==================

function update_package_lists() {
    log "INFO" "Updating package lists..."
    apt-get update || {
        log "ERROR" "Failed to update package lists"
        return 1
    }
    return 0
}

function install_required_packages() {
    log "INFO" "Installing required packages..."
    
    local packages=(
        curl
        wget
        git
        python3
        python3-pip
        python3-venv
        nodejs
        npm
        postgresql
        docker.io
        docker-compose
        nginx
        certbot
        python3-certbot-nginx
        net-tools
        speedtest-cli
        jq
        unzip
    )
    
    apt-get install -y "${packages[@]}" || {
        log "ERROR" "Failed to install required packages"
        return 1
    }
    
    # Verify installations
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            log "ERROR" "Package $package was not installed properly"
            return 1
        fi
    done
    
    log "INFO" "Required packages installed successfully"
    return 0
}

# ================== VPN Management Functions ==================

function setup_vpn_dependencies() {
    log "INFO" "Setting up VPN dependencies..."
    
    local packages=(
        strongswan
        xl2tpd
        ocserv
        wireguard
        iptables
        fail2ban
        ufw
    )
    
    apt-get install -y "${packages[@]}" || {
        log "ERROR" "Failed to install VPN dependencies"
        return 1
    }
    
    # Enable IP forwarding
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-vpn-forward.conf
    sysctl -p /etc/sysctl.d/99-vpn-forward.conf
    
    log "INFO" "VPN dependencies setup completed"
    return 0
}

function configure_vpn_protocols() {
    local protocols=("SSH" "L2TPv3/IPSec" "IKEv2/IPsec" "Cisco-AnyConnect" "WireGuard" "SingBox")
    
    for protocol in "${protocols[@]}"; do
        log "INFO" "Configuring $protocol..."
        case $protocol in
            "SSH")
                configure_ssh || return 1
                ;;
            "L2TPv3/IPSec")
                configure_l2tp || return 1
                ;;
            "IKEv2/IPsec")
                configure_ikev2 || return 1
                ;;
            "Cisco-AnyConnect")
                configure_anyconnect || return 1
                ;;
            "WireGuard")
                configure_wireguard || return 1
                ;;
            "SingBox")
                configure_singbox || return 1
                ;;
        esac
    done
    
    log "INFO" "All VPN protocols configured successfully"
    return 0
}

function configure_ssh() {
    log "INFO" "Configuring SSH VPN..."
    
    # Backup original SSH config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Configure SSH for VPN use
    cat > /etc/ssh/sshd_config << EOF
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
UsePrivilegeSeparation yes
KeyRegenerationInterval 3600
ServerKeyBits 2048
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 120
PermitRootLogin no
StrictModes yes
RSAAuthentication yes
PubkeyAuthentication yes
IgnoreRhosts yes
RhostsRSAAuthentication no
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PasswordAuthentication yes
X11Forwarding yes
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
UsePAM yes
AllowTcpForwarding yes
GatewayPorts yes
EOF
    
    # Restart SSH service
    systemctl restart sshd || {
        log "ERROR" "Failed to restart SSH service"
        return 1
    }
    
    log "INFO" "SSH VPN configuration completed"
    return 0
}

function configure_l2tp() {
    log "INFO" "Configuring L2TPv3/IPSec..."
    
    # Install required packages if not already installed
    apt-get install -y xl2tpd strongswan || return 1
    
    # Configure strongSwan
    cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"
    uniqueids=never

conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    keyexchange=ikev1
    authby=secret
    ike=aes256-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,3des-sha1!

conn L2TP-PSK
    keyexchange=ikev1
    left=%defaultroute
    auto=add
    authby=secret
    type=transport
    leftprotoport=17/1701
    rightprotoport=17/1701
    right=%any
    rekey=no
EOF
    
    # Generate IPSec secret
    local IPSEC_SECRET=$(openssl rand -hex 16)
    echo ": PSK \"$IPSEC_SECRET\"" > /etc/ipsec.secrets
    chmod 600 /etc/ipsec.secrets
    
    # Configure xl2tpd
    cat > /etc/xl2tpd/xl2tpd.conf << EOF
[global]
port = 1701
auth file = /etc/ppp/chap-secrets
debug avp = yes
debug network = yes
debug state = yes
debug tunnel = yes

[lns default]
ip range = 172.16.1.100-172.16.1.199
local ip = 172.16.1.1
require chap = yes
refuse pap = yes
require authentication = yes
name = L2TPv3-VPN
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF
    
    # Configure PPP options
    cat > /etc/ppp/options.xl2tpd << EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
crtscts
idle 1800
mtu 1460
mru 1460
nodefaultroute
debug
lock
proxyarp
connect-delay 5000
EOF
    
    # Restart services
    systemctl restart strongswan xl2tpd || {
        log "ERROR" "Failed to restart L2TPv3/IPSec services"
        return 1
    }
    
    log "INFO" "L2TPv3/IPSec configuration completed"
    return 0
}

function configure_ikev2() {
    log "INFO" "Configuring IKEv2/IPsec..."
    
    # Generate certificates
    local CERT_DIR="/etc/ipsec.d/certs"
    local KEY_DIR="/etc/ipsec.d/private"
    local CA_DIR="/etc/ipsec.d/cacerts"
    
    mkdir -p "$CERT_DIR" "$KEY_DIR" "$CA_DIR"
    
    # Generate CA key and certificate
    ipsec pki --gen --type rsa --size 4096 --outform pem > "$KEY_DIR/cakey.pem"
    chmod 600 "$KEY_DIR/cakey.pem"
    
    ipsec pki --self --ca --lifetime 3650 \
        --in "$KEY_DIR/cakey.pem" \
        --type rsa --dn "CN=VPN Root CA" \
        --outform pem > "$CA_DIR/cacert.pem"
    
    # Generate server key and certificate
    ipsec pki --gen --type rsa --size 4096 --outform pem > "$KEY_DIR/server.pem"
    chmod 600 "$KEY_DIR/server.pem"
    
    ipsec pki --pub --in "$KEY_DIR/server.pem" \
        --type rsa | ipsec pki --issue --lifetime 1825 \
        --cacert "$CA_DIR/cacert.pem" \
        --cakey "$KEY_DIR/cakey.pem" \
        --dn "CN=$(hostname)" \
        --san "@$(hostname)" \
        --san "$(hostname)" \
        --flag serverAuth \
        --flag ikeIntermediate \
        --outform pem > "$CERT_DIR/server.pem"
    
    # Configure strongSwan for IKEv2
    cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"
    uniqueids=never

conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    keyexchange=ikev2
    ike=aes256-sha256-modp2048,aes128-sha1-modp2048,3des-sha1-modp2048!
    esp=aes256-sha256,aes128-sha1,3des-sha1!

conn IKEv2-VPN
    left=%any
    leftauth=pubkey
    leftcert=server.pem
    leftid=@$(hostname)
    leftsubnet=0.0.0.0/0
    right=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightdns=8.8.8.8,8.8.4.4
    rightsendcert=never
    eap_identity=%identity
    auto=add
EOF
    
    # Restart strongSwan
    systemctl restart strongswan || {
        log "ERROR" "Failed to restart IKEv2/IPsec service"
        return 1
    }
    
    log "INFO" "IKEv2/IPsec configuration completed"
    return 0
}

function configure_anyconnect() {
    log "INFO" "Configuring Cisco AnyConnect (ocserv)..."
    
    # Install ocserv if not present
    apt-get install -y ocserv || return 1
    
    # Generate self-signed certificate for ocserv
    local OCSERV_DIR="/etc/ocserv"
    mkdir -p "$OCSERV_DIR/certs"
    
    # Generate CA key and certificate
    certtool --generate-privkey --outfile "$OCSERV_DIR/certs/ca-key.pem"
    
    cat > "$OCSERV_DIR/certs/ca.tmpl" << EOF
cn = "VPN CA"
organization = "VPN System"
serial = 1
expiration_days = 3650
ca
signing_key
cert_signing_key
crl_signing_key
EOF
    
    certtool --generate-self-signed --load-privkey "$OCSERV_DIR/certs/ca-key.pem" \
        --template "$OCSERV_DIR/certs/ca.tmpl" --outfile "$OCSERV_DIR/certs/ca-cert.pem"
    
    # Generate server key and certificate
    certtool --generate-privkey --outfile "$OCSERV_DIR/certs/server-key.pem"
    
    cat > "$OCSERV_DIR/certs/server.tmpl" << EOF
cn = "$(hostname)"
organization = "VPN System"
expiration_days = 3650
signing_key
encryption_key
tls_www_server
EOF
    
    certtool --generate-certificate --load-privkey "$OCSERV_DIR/certs/server-key.pem" \
        --load-ca-certificate "$OCSERV_DIR/certs/ca-cert.pem" \
        --load-ca-privkey "$OCSERV_DIR/certs/ca-key.pem" \
        --template "$OCSERV_DIR/certs/server.tmpl" --outfile "$OCSERV_DIR/certs/server-cert.pem"
    
    # Configure ocserv
    cat > /etc/ocserv/ocserv.conf << EOF
auth = "plain[passwd=/etc/ocserv/ocpasswd]"
tcp-port = 443
udp-port = 443
run-as-user = nobody
run-as-group = daemon
socket-file = /var/run/ocserv-socket
server-cert = /etc/ocserv/certs/server-cert.pem
server-key = /etc/ocserv/certs/server-key.pem
ca-cert = /etc/ocserv/certs/ca-cert.pem
isolate-workers = true
max-clients = 128
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
use-utmp = true
pid-file = /var/run/ocserv.pid
device = vpns
predictable-ips = true
ipv4-network = 192.168.1.0
ipv4-netmask = 255.255.255.0
dns = 8.8.8.8
dns = 8.8.4.4
ping-leases = false
route = default
no-route = 192.168.0.0/255.255.0.0
no-route = 10.0.0.0/255.0.0.0
no-route = 172.16.0.0/255.240.0.0
no-route = 127.0.0.0/255.0.0.0
cisco-client-compat = true
dtls-legacy = true
EOF
    
    # Create initial password file
    touch /etc/ocserv/ocpasswd
    
    # Start service
    systemctl restart ocserv || {
        log "ERROR" "Failed to restart ocserv service"
        return 1
    }
    
    log "INFO" "Cisco AnyConnect configuration completed"
    return 0
}

function configure_wireguard() {
    log "INFO" "Configuring WireGuard..."
    
    # Install WireGuard
    apt-get install -y wireguard || return 1
    
    # Generate server keys
    local WG_DIR="/etc/wireguard"
    mkdir -p "$WG_DIR"
    chmod 700 "$WG_DIR"
    
    wg genkey | tee "$WG_DIR/server.key" | wg pubkey > "$WG_DIR/server.pub"
    chmod 600 "$WG_DIR/server.key"
    
    # Configure WireGuard interface
    local SERVER_PRIVATE_KEY=$(cat "$WG_DIR/server.key")
    
    cat > "$WG_DIR/wg0.conf" << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.8.0.1/24
ListenPort = 51820
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF
    
    # Enable and start WireGuard
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0 || {
        log "ERROR" "Failed to start WireGuard service"
        return 1
    }
    
    log "INFO" "WireGuard configuration completed"
    return 0
}

function configure_openvpn() {
    log "INFO" "Configuring OpenVPN..."
    
    # Install OpenVPN
    apt-get install -y openvpn easy-rsa || return 1
    
    # Set up PKI
    local EASYRSA_DIR="/etc/openvpn/easy-rsa"
    cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR"
    cd "$EASYRSA_DIR"
    
    # Initialize PKI
    ./easyrsa init-pki
    
    # Generate CA
    EASYRSA_BATCH=1 ./easyrsa build-ca nopass
    
    # Generate server certificate
    EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass
    
    # Generate DH parameters
    ./easyrsa gen-dh
    
    # Generate TLS auth key
    openvpn --genkey secret /etc/openvpn/ta.key
    
    # Configure OpenVPN server
    cat > /etc/openvpn/server.conf << EOF
port 1194
proto udp
dev tun
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
tls-auth /etc/openvpn/ta.key 0
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
explicit-exit-notify 1
EOF
    
    # Enable and start OpenVPN
    systemctl enable openvpn@server
    systemctl start openvpn@server || {
        log "ERROR" "Failed to start OpenVPN service"
        return 1
    }
    
    log "INFO" "OpenVPN configuration completed"
    return 0
}

function configure_singbox() {
    log "INFO" "Configuring SingBox..."
    
    # Create directory structure
    local SINGBOX_DIR="/etc/singbox"
    mkdir -p "$SINGBOX_DIR"
    
    # Download latest SingBox binary
    local LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    wget "https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-amd64.tar.gz" -O /tmp/singbox.tar.gz
    
    tar xzf /tmp/singbox.tar.gz -C "$SINGBOX_DIR"
    mv "$SINGBOX_DIR"/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    
    # Generate certificates
    local CERT_DIR="$SINGBOX_DIR/certs"
    mkdir -p "$CERT_DIR"
    
    openssl req -x509 -newkey rsa:4096 -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" \
        -days 365 -nodes -subj "/CN=$(hostname)"
    
    # Configure SingBox
    cat > "$SINGBOX_DIR/config.json" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "::",
      "listen_port": 443,
      "sniff": true,
      "sniff_override_destination": false,
      "domain_strategy": "prefer_ipv4",
      "set_system_proxy": false,
      "users": []
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
    
    # Create systemd service
    cat > /etc/systemd/system/singbox.service << EOF
[Unit]
Description=SingBox Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/singbox/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start SingBox
    systemctl daemon-reload
    systemctl enable singbox
    systemctl start singbox || {
        log "ERROR" "Failed to start SingBox service"
        return 1
    }
    
    log "INFO" "SingBox configuration completed"
    return 0
}

# ================== Monitoring Functions ==================

function setup_monitoring() {
    log "INFO" "Setting up monitoring system..."
    
    # Install monitoring tools
    apt-get install -y prometheus grafana || return 1
    
    # Configure Prometheus
    cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'vpn_system'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF
    
    # Configure Grafana
    cat > /etc/grafana/provisioning/dashboards/vpn-dashboard.yml << EOF
apiVersion: 1

providers:
  - name: 'VPN Dashboard'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards
EOF
    
    # Start monitoring services
    systemctl restart prometheus grafana-server || {
        log "ERROR" "Failed to start monitoring services"
        return 1
    }
    
    log "INFO" "Monitoring system setup completed"
    return 0
}

# ================== Backup Functions ==================

function create_backup() {
    local backup_dir="$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    log "INFO" "Creating system backup in $backup_dir..."
    
    # Backup configurations
    cp -r /etc/ssh "$backup_dir/"
    cp -r /etc/ipsec.d "$backup_dir/"
    cp -r /etc/xl2tpd "$backup_dir/"
    cp -r /etc/ocserv "$backup_dir/"
    cp -r /etc/wireguard "$backup_dir/"
    cp -r /etc/openvpn "$backup_dir/"
    cp -r /etc/singbox "$backup_dir/"
    
    # Backup databases
    pg_dump vpn_db > "$backup_dir/vpn_db.sql"
    
    # Create archive
    tar -czf "$backup_dir.tar.gz" "$backup_dir"
    rm -rf "$backup_dir"
    
    log "INFO" "Backup completed: $backup_dir.tar.gz"
    return 0
}

# ================== Cleanup Function ==================

function cleanup() {
    log "INFO" "Performing cleanup..."
    
    # Remove temporary files
    rm -rf "$TEMP_DIR"/*
    
    # Stop services gracefully
    local services=(
        "ssh"
        "xl2tpd"
        "ipsec"
        "ocserv"
        "wg-quick@wg0"
        "openvpn@server"
        "singbox"
        "prometheus"
        "grafana-server"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            systemctl stop "$service"
        fi
    done
    
    log "INFO" "Cleanup completed"
    return 0
}

# Initialize system
create_directories
initialize_logging
