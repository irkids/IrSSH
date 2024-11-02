#!/bin/bash

# Advanced L2TPv3/IPSec VPN Installation Script with Multi-Protocol Support
# Version: 2.0.0
# Features:
# - Full L2TPv3 support with IPv6
# - Dynamic port switching (49152-65152)
# - PostgreSQL integration with monitoring
# - Ansible automation for problem resolution
# - React.js/Material-UI web dashboard
# - Multi-protocol compatibility
# - Docker containerization
# - Comprehensive logging and monitoring

set -e

# Script Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONFIG_DIR="/etc/vpn_manager"
LOG_DIR="/var/log/vpn_manager"
BACKUP_DIR="/var/backup/vpn_manager"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment variables
if [[ -f "${CONFIG_DIR}/.env" ]]; then
    source "${CONFIG_DIR}/.env"
fi

# Logging configuration
setup_logging() {
    mkdir -p "${LOG_DIR}"
    exec 1> >(tee -a "${LOG_DIR}/install_${TIMESTAMP}.log")
    exec 2> >(tee -a "${LOG_DIR}/install_${TIMESTAMP}.error.log")
}

# Function to log messages with timestamp and level
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
}

# Function to check system requirements
check_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        exit 1
    }
    
    # Check minimum system resources
    local min_ram=1024  # 1GB RAM minimum
    local min_cpu=1     # 1 CPU core minimum
    local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local cpu_cores=$(nproc)
    
    if [[ $ram_kb -lt $((min_ram * 1024)) ]]; then
        log "WARNING" "System has less than recommended RAM (1GB)"
    }
    
    if [[ $cpu_cores -lt $min_cpu ]]; then
        log "ERROR" "System requires at least 1 CPU core"
        exit 1
    }
    
    # Check for required commands
    local required_commands=(curl wget git docker docker-compose ansible python3 pip3)
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Required command '$cmd' not found"
            install_dependencies
        fi
    done
}

# Function to install dependencies
install_dependencies() {
    log "INFO" "Installing system dependencies..."
    
    # Update package lists
    apt-get update
    
    # Install required packages
    apt-get install -y \
        strongswan \
        xl2tpd \
        python3 \
        python3-pip \
        docker.io \
        docker-compose \
        ansible \
        postgresql \
        postgresql-contrib \
        libpq-dev \
        nginx \
        certbot \
        python3-certbot-nginx \
        iptables-persistent \
        net-tools \
        curl \
        wget \
        git \
        ruby \
        ruby-dev \
        openjdk-11-jdk \
        nodejs \
        npm
        
    # Install Python packages
    pip3 install \
        psycopg2-binary \
        fastapi \
        uvicorn \
        python-dotenv \
        sqlalchemy \
        alembic \
        pydantic \
        python-jose[cryptography] \
        passlib[bcrypt] \
        docker \
        ansible \
        prisma \
        requests
        
    # Install Ruby gems
    gem install \
        bundler \
        rake \
        sinatra \
        activerecord \
        pg
        
    # Install Node.js packages globally
    npm install -g \
        pm2 \
        @prisma/cli \
        typescript \
        ts-node
}

# PostgreSQL Database Setup
setup_database() {
    log "INFO" "Setting up PostgreSQL database..."
    
    # Generate secure database password
    DB_PASSWORD=$(openssl rand -base64 32)
    
    # Create database and user
    sudo -u postgres psql <<EOF
CREATE DATABASE vpn_manager;
CREATE USER vpn_admin WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE vpn_manager TO vpn_admin;
\c vpn_manager

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create tables for VPN management
CREATE TABLE IF NOT EXISTS vpn_servers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    protocol VARCHAR(50) NOT NULL,
    primary_port INTEGER NOT NULL,
    backup_ports INTEGER[],
    ipv4_address INET,
    ipv6_address INET,
    status VARCHAR(20) DEFAULT 'active',
    last_checked TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vpn_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    psk VARCHAR(255),
    active BOOLEAN DEFAULT true,
    ipv4_address INET,
    ipv6_address INET,
    max_connections INTEGER DEFAULT 1,
    bandwidth_limit BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vpn_connections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES vpn_users(id),
    server_id UUID REFERENCES vpn_servers(id),
    protocol VARCHAR(50) NOT NULL,
    port INTEGER NOT NULL,
    ipv4_address INET,
    ipv6_address INET,
    bytes_sent BIGINT DEFAULT 0,
    bytes_received BIGINT DEFAULT 0,
    connected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    disconnected_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS port_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    port INTEGER NOT NULL,
    protocol VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'active',
    last_checked TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(port, protocol)
);

CREATE TABLE IF NOT EXISTS system_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    message TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create necessary indexes
CREATE INDEX idx_vpn_users_username ON vpn_users(username);
CREATE INDEX idx_vpn_connections_user_id ON vpn_connections(user_id);
CREATE INDEX idx_vpn_connections_server_id ON vpn_connections(server_id);
CREATE INDEX idx_system_events_type_severity ON system_events(event_type, severity);
CREATE INDEX idx_port_assignments_status ON port_assignments(status);

-- Create functions and triggers for automatic updates
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_vpn_servers_timestamp
    BEFORE UPDATE ON vpn_servers
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_vpn_users_timestamp
    BEFORE UPDATE ON vpn_users
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- Create views for monitoring
CREATE OR REPLACE VIEW active_connections AS
SELECT 
    vc.id,
    vu.username,
    vs.name as server_name,
    vc.protocol,
    vc.port,
    vc.ipv4_address,
    vc.ipv6_address,
    vc.bytes_sent,
    vc.bytes_received,
    vc.connected_at,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - vc.connected_at))::INTEGER as connection_duration_seconds
FROM vpn_connections vc
JOIN vpn_users vu ON vc.user_id = vu.id
JOIN vpn_servers vs ON vc.server_id = vs.id
WHERE vc.status = 'active';

-- Create function for port allocation
CREATE OR REPLACE FUNCTION allocate_dynamic_port(
    p_protocol VARCHAR(50),
    p_min_port INTEGER DEFAULT 49152,
    p_max_port INTEGER DEFAULT 65152
) RETURNS INTEGER AS $$
DECLARE
    v_port INTEGER;
BEGIN
    -- Find the first available port in the range
    SELECT port INTO v_port
    FROM generate_series(p_min_port, p_max_port) AS p(port)
    WHERE NOT EXISTS (
        SELECT 1 
        FROM port_assignments 
        WHERE port = p.port 
        AND protocol = p_protocol 
        AND status = 'active'
    )
    LIMIT 1;

    IF v_port IS NULL THEN
        RAISE EXCEPTION 'No available ports in the specified range';
    END IF;

    -- Insert the allocated port
    INSERT INTO port_assignments (port, protocol, status)
    VALUES (v_port, p_protocol, 'active');

    RETURN v_port;
END;
$$ LANGUAGE plpgsql;
EOF

    # Save database credentials
    cat > "${CONFIG_DIR}/.env" <<EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=vpn_manager
DB_USER=vpn_admin
DB_PASSWORD=${DB_PASSWORD}
EOF

    chmod 600 "${CONFIG_DIR}/.env"
}

# L2TPv3 Configuration
configure_l2tpv3() {
    log "INFO" "Configuring L2TPv3..."
    
    # Create configuration directories
    mkdir -p /etc/xl2tpd/l2tpv3.d
    
    # Generate L2TPv3 configuration
    cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701
access control = no
debug network = yes
debug state = yes
debug tunnel = yes
debug avp = yes

[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require authentication = yes
name = l2tpv3-vpn
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    # Configure PPP options
    cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
ms-dns 2001:4860:4860::8888
ms-dns 2001:4860:4860::8844
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

    # Configure IPSec
    cat > /etc/ipsec.conf <<EOF
config setup
    charondebug="ike 2, knl 2, cfg 2"
    uniqueids=no

conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    keyexchange=ikev2
    authby=secret
    
conn L2TPv3-PSK
    left=%defaultroute
    leftprotoport=17/1701
    rightprotoport=17/1701
    leftauth=psk
    rightauth=psk
    rightsubnet=vhost:%priv
    also=L2TP-PSK-NAT
    
conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-common
    
conn L2TP-PSK-common
    type=transport
    auto=add
    keyexchange=ikev2
    leftid=@vpn.example.com
    left=%defaultroute
    leftprotoport=17/1701
    rightprotoport=17/1701
    right=%any
    rightsubnet=vhost:%priv
    forceencaps=yes
    authby=secret
    pfs=no
    rekey=no
    keyingtries=5
    dpddelay=30
    dpdtimeout=120
    dpdaction=clear
    ike=aes256-sha2_256-modp2048,aes128-sha2_256-modp2048!
    esp=aes256-sha2_256,aes128-sha2_256!
EOF

    # Generate IPSec secrets
    PSK=$(openssl rand -base64 32)
    echo ": PSK \"${PSK}\"" > /etc/ipsec.secrets
    chmod 600 /etc/ipsec.secrets
}

# Create Python monitoring service
create_monitoring_service() {
    log "INFO" "Creating monitoring service..."
    
    cat > /usr/local/bin/vpn_monitor.py <<EOF
#!/usr/bin/env python3

import os
import sys
import time
import signal
import logging
import psycopg2
import subprocess
from datetime import datetime
from typing import List, Dict, Optional
import json

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/vpn_manager/monitor.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger('VPNMonitor')

class VPNMonitor:
    def __init__(self):
        self.db_config = {
            'dbname': os.getenv('DB_NAME', 'vpn_manager'),
            'user': os.getenv('DB_USER', 'vpn_admin'),
            'password': os.getenv('DB_PASSWORD'),
            'host': os.getenv('DB_HOST', 'localhost')
        }
        self.port_range = range(49152, 65152)
        self.current_port = 1701

    def connect_db(self):
        """Establish database connection with retry mechanism"""
        max_retries = 3
        retry_delay = 5
        
        for attempt in range(max_retries):
            try:
                return psycopg2.connect(**self.db_config)
            except psycopg2.Error as e:
                logger.error(f"Database connection attempt {attempt + 1} failed: {e}")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                else:
                    raise

    def check_port_status(self, port):
        """Verify if a port is available and operational"""
        try:
            # Check IPv4 port status
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.bind(('0.0.0.0', port))
            sock.close()

            # Check IPv6 port status
            sock_v6 = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
            sock_v6.bind(('::', port))
            sock_v6.close()
            
            return True
        except socket.error:
            return False

    def find_available_port(self):
        """Find an available port in the specified range"""
        random_ports = list(self.port_range)
        random.shuffle(random_ports)
        
        for port in random_ports:
            if self.check_port_status(port):
                return port
        return None

    def update_vpn_configuration(self, new_port):
        """Update VPN configuration with new port"""
        try:
            # Update database
            with self.connect_db() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        UPDATE vpn_servers 
                        SET port = %s, 
                            last_updated = NOW(),
                            status = 'port_changed'
                        WHERE is_active = true
                    """, (new_port,))
                    
                    # Log the change
                    cur.execute("""
                        INSERT INTO system_events 
                        (event_type, message, details) 
                        VALUES (%s, %s, %s)
                    """, (
                        'port_change',
                        f'VPN port changed from {self.current_port} to {new_port}',
                        json.dumps({'old_port': self.current_port, 'new_port': new_port})
                    ))
                    conn.commit()

            # Trigger Ansible playbook
            self.trigger_ansible_update(new_port)
            
            self.current_port = new_port
            logger.info(f"Successfully updated VPN configuration to use port {new_port}")
            
        except Exception as e:
            logger.error(f"Failed to update VPN configuration: {e}")
            raise

    def trigger_ansible_update(self, new_port):
        """Execute Ansible playbook for configuration update"""
        try:
            playbook_path = '/etc/ansible/playbooks/update_vpn_port.yml'
            extra_vars = {
                'vpn_port': new_port,
                'ipv6_enabled': True,
                'protocols': ['l2tpv3', 'ipsec']
            }
            
            # Execute ansible-playbook command
            result = subprocess.run([
                'ansible-playbook',
                playbook_path,
                '-e', json.dumps(extra_vars)
            ], capture_output=True, text=True)
            
            if result.returncode != 0:
                raise Exception(f"Ansible playbook failed: {result.stderr}")
                
            logger.info("Successfully executed Ansible playbook for port update")
            
        except Exception as e:
            logger.error(f"Failed to execute Ansible playbook: {e}")
            raise

    def monitor_vpn_service(self):
        """Main monitoring loop"""
        while True:
            try:
                # Check current port status
                if not self.check_port_status(self.current_port):
                    logger.warning(f"Port {self.current_port} is not available")
                    
                    # Find new port
                    new_port = self.find_available_port()
                    if new_port:
                        logger.info(f"Found new available port: {new_port}")
                        self.update_vpn_configuration(new_port)
                    else:
                        logger.error("No available ports found in specified range")
                        
                # Check L2TPv3 service status
                service_status = subprocess.run(
                    ['systemctl', 'is-active', 'xl2tpd'],
                    capture_output=True,
                    text=True
                )
                
                if service_status.stdout.strip() != 'active':
                    logger.error("L2TPv3 service is not active")
                    self.handle_service_failure()
                    
            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}")
                
            time.sleep(60)  # Check every minute

    def handle_service_failure(self):
        """Handle L2TPv3 service failures"""
        try:
            # Log the failure
            with self.connect_db() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO system_events 
                        (event_type, severity, message) 
                        VALUES (%s, %s, %s)
                    """, ('service_failure', 'critical', 'L2TPv3 service failure detected'))
                    conn.commit()
            
            # Attempt service restart
            subprocess.run(['systemctl', 'restart', 'xl2tpd'])
            
            # Check if restart was successful
            time.sleep(5)
            status = subprocess.run(
                ['systemctl', 'is-active', 'xl2tpd'],
                capture_output=True,
                text=True
            )
            
            if status.stdout.strip() != 'active':
                logger.error("Failed to restart L2TPv3 service")
                self.trigger_ansible_update(self.current_port)
            
        except Exception as e:
            logger.error(f"Error handling service failure: {e}")

def main():
    """Main function to start the VPN monitoring service"""
    try:
        monitor = VPNMonitor()
        logger.info("Starting VPN monitoring service")
        monitor.monitor_vpn_service()
    except Exception as e:
        logger.error(f"Critical error in main function: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
