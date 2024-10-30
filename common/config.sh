#!/bin/bash

###########################################
# System Core Configuration
###########################################

# Base directories
export BASE_DIR="/opt/automation"
export CONFIG_DIR="${BASE_DIR}/config"
export LOG_DIR="${BASE_DIR}/logs"
export TEMP_DIR="${BASE_DIR}/tmp"
export BACKUP_DIR="${BASE_DIR}/backups"
export DATA_DIR="${BASE_DIR}/data"
export CERT_DIR="${BASE_DIR}/certificates"
export KEY_DIR="${BASE_DIR}/keys"
export SCRIPT_DIR="${BASE_DIR}/scripts"

# Application directories
export FRONTEND_DIR="${BASE_DIR}/frontend"
export BACKEND_DIR="${BASE_DIR}/backend"
export ANSIBLE_DIR="${BASE_DIR}/ansible"
export MONITORING_DIR="${BASE_DIR}/monitoring"
export VPN_DIR="${BASE_DIR}/vpn"

# Configuration files
export MAIN_CONFIG="${CONFIG_DIR}/main.conf"
export CLAUDE_CONFIG="${CONFIG_DIR}/claude.conf"
export ANSIBLE_CONFIG="${CONFIG_DIR}/ansible.cfg"
export DOCKER_COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
export NGINX_CONFIG="${CONFIG_DIR}/nginx/nginx.conf"
export PROMETHEUS_CONFIG="${CONFIG_DIR}/prometheus/prometheus.yml"
export GRAFANA_CONFIG="${CONFIG_DIR}/grafana/grafana.ini"

###########################################
# VPN Protocols Configuration
###########################################

# SSH Tunnel Configuration
export SSH_TUNNEL_PORT=22
export SSH_CONFIG_DIR="${VPN_DIR}/ssh"
export SSH_KEY_TYPE="ed25519"
export SSH_KEY_BITS=4096
export SSH_ALLOW_TCP_FORWARDING="yes"
export SSH_PERMIT_TUNNEL="yes"
export SSH_COMPRESSION="yes"
export SSH_MAX_SESSIONS=10
export SSH_MAX_STARTUPS="10:30:100"
export SSH_LOGIN_GRACE_TIME=120
export SSH_STRICT_MODES="yes"
export SSH_MAX_AUTH_TRIES=3
export SSH_ALLOW_AGENT_FORWARDING="yes"
export SSH_X11_FORWARDING="no"

# L2TPv3/IPSec Configuration
export L2TP_CONFIG_DIR="${VPN_DIR}/l2tp"
export L2TP_PORT=1701
export L2TP_LOCAL_IP="10.10.0.1"
export L2TP_REMOTE_IP="10.10.0.2"
export L2TP_TUNNEL_NAME="l2tpv3_tunnel"
export L2TP_SESSION_NAME="l2tpv3_session"
export L2TP_COOKIE_SECRET=$(random_string 32)
export L2TP_ENCAP_TYPE="udp"
export L2TP_MTU=1460
export L2TP_TIMEOUT=30
export L2TP_HELLO_INTERVAL=60
export L2TP_MAX_RETRIES=5
export L2TP_SUBNET="10.10.0.0/24"

# IPSec Common Settings
export IPSEC_CONFIG_DIR="${VPN_DIR}/ipsec"
export IPSEC_SECRETS_FILE="${IPSEC_CONFIG_DIR}/ipsec.secrets"
export IPSEC_CERT_DIR="${CERT_DIR}/ipsec"
export IPSEC_DH_GROUP="modp2048"
export IPSEC_IKE="aes256-sha2_256-modp2048"
export IPSEC_ESP="aes256-sha2_256-modp2048"
export IPSEC_IKELIFETIME="24h"
export IPSEC_KEYLIFE="8h"
export IPSEC_REKEYMARGIN="3m"
export IPSEC_DPD_DELAY="30s"
export IPSEC_DPD_TIMEOUT="120s"

# IKEv2/IPsec Specific Configuration
export IKEV2_PORT=500
export IKEV2_NAT_PORT=4500
export IKEV2_SUBNET="10.11.0.0/24"
export IKEV2_DNS="8.8.8.8,8.8.4.4"
export IKEV2_SPLIT_TUNNEL="yes"
export IKEV2_MOBIKE="yes"
export IKEV2_CERT_PROFILE="rsa-4096"
export IKEV2_PROPOSALS="aes256-sha2_256-modp2048"
export IKEV2_REKEY_TIME="4h"
export IKEV2_REAUTH_TIME="24h"
export IKEV2_POOL_START="10.11.0.10"
export IKEV2_POOL_END="10.11.0.200"

# Cisco AnyConnect Configuration
export ANYCONNECT_PORT=443
export ANYCONNECT_CONFIG_DIR="${VPN_DIR}/anyconnect"
export ANYCONNECT_PROFILE_DIR="${ANYCONNECT_CONFIG_DIR}/profiles"
export ANYCONNECT_IMAGE_DIR="${ANYCONNECT_CONFIG_DIR}/images"
export ANYCONNECT_SUBNET="10.12.0.0/24"
export ANYCONNECT_DNS="8.8.8.8,8.8.4.4"
export ANYCONNECT_DTLS_PORT=443
export ANYCONNECT_KEEPALIVE=30
export ANYCONNECT_IDLE_TIMEOUT=1800
export ANYCONNECT_SESSION_TIMEOUT=86400
export ANYCONNECT_MAX_CLIENTS=250
export ANYCONNECT_SPLIT_TUNNEL="yes"
export ANYCONNECT_MOBILE_BYPASS="yes"

# WireGuard Configuration
export WIREGUARD_CONFIG_DIR="${VPN_DIR}/wireguard"
export WIREGUARD_PORT=51820
export WIREGUARD_SUBNET="10.13.0.0/24"
export WIREGUARD_MTU=1420
export WIREGUARD_KEEPALIVE=25
export WIREGUARD_PRIVATE_KEY="${KEY_DIR}/wireguard/server_private.key"
export WIREGUARD_PUBLIC_KEY="${KEY_DIR}/wireguard/server_public.key"
export WIREGUARD_PRESHARED_KEY="${KEY_DIR}/wireguard/preshared.key"
export WIREGUARD_DNS="1.1.1.1,1.0.0.1"
export WIREGUARD_ALLOWED_IPS="0.0.0.0/0"
export WIREGUARD_PERSISTENT_KEEPALIVE=25
export WIREGUARD_SAVE_CONFIG="true"

# SingBox Configuration
export SINGBOX_CONFIG_DIR="${VPN_DIR}/singbox"
export SINGBOX_PORT=2080
export SINGBOX_CONTROL_PORT=2081
export SINGBOX_API_PORT=9090
export SINGBOX_DNS_PORT=53
export SINGBOX_TUN_DEVICE="tun0"
export SINGBOX_SUBNET="10.14.0.0/24"
export SINGBOX_MTU=1500
export SINGBOX_TIMEOUT=300
export SINGBOX_DIAL_TIMEOUT=30
export SINGBOX_UDP_TIMEOUT=60
export SINGBOX_TCP_FAST_OPEN="true"
export SINGBOX_TCP_MULTI_PATH="true"
export SINGBOX_SNIFF_TIMEOUT=300
export SINGBOX_DOMAIN_STRATEGY="prefer-ipv4"

###########################################
# Database Configuration
###########################################

# PostgreSQL settings
export DB_HOST="localhost"
export DB_PORT="5432"
export DB_NAME="automation"
export DB_USER="automation_user"
export DB_PASSWORD=$(random_string 32)
export DB_MAX_CONNECTIONS=200
export DB_SHARED_BUFFERS="1GB"
export DB_EFFECTIVE_CACHE_SIZE="3GB"
export DB_MAINTENANCE_WORK_MEM="256MB"
export DB_CHECKPOINT_COMPLETION_TARGET=0.9
export DB_WAL_BUFFERS="16MB"
export DB_DEFAULT_STATISTICS_TARGET=100
export DB_RANDOM_PAGE_COST=1.1
export DB_EFFECTIVE_IO_CONCURRENCY=200
export DB_WORK_MEM="64MB"
export DB_MIN_WAL_SIZE="1GB"
export DB_MAX_WAL_SIZE="4GB"
export DB_MAX_WORKER_PROCESSES=8
export DB_MAX_PARALLEL_WORKERS_PER_GATHER=4
export DB_MAX_PARALLEL_WORKERS=8
export DB_MAX_PARALLEL_MAINTENANCE_WORKERS=4

# Redis settings
export REDIS_HOST="localhost"
export REDIS_PORT="6379"
export REDIS_PASSWORD=$(random_string 32)
export REDIS_DB_VPN=0
export REDIS_DB_SESSIONS=1
export REDIS_DB_CACHE=2
export REDIS_MAX_MEMORY="2gb"
export REDIS_MAX_MEMORY_POLICY="allkeys-lru"
export REDIS_AOF_ENABLED="yes"
export REDIS_SAVE_INTERVALS="900 1 300 10 60 10000"

###########################################
# Security Configuration
###########################################

# Certificate Authority
export CA_DIR="${CERT_DIR}/ca"
export CA_KEY="${CA_DIR}/ca.key"
export CA_CERT="${CA_DIR}/ca.crt"
export CA_CHAIN="${CA_DIR}/ca-chain.crt"
export CA_KEY_TYPE="rsa"
export CA_KEY_SIZE=4096
export CA_DIGEST="sha512"
export CA_DAYS=3650
export CA_CRL_DAYS=30

# JWT settings
export JWT_SECRET=$(random_string 64)
export JWT_ALGORITHM="HS512"
export JWT_ACCESS_TOKEN_EXPIRE=3600
export JWT_REFRESH_TOKEN_EXPIRE=604800
export JWT_BLACKLIST_ENABLED="true"
export JWT_BLACKLIST_TOKEN_CHECKS="access,refresh"

# Encryption settings
export ENCRYPTION_KEY=$(random_string 32)
export ENCRYPTION_ALGORITHM="aes-256-gcm"
export ENCRYPTION_KEY_DERIVATION="pbkdf2"
export ENCRYPTION_ITERATIONS=100000

# Rate limiting
export RATE_LIMIT_WINDOW="15m"
export RATE_LIMIT_MAX_REQUESTS=100
export RATE_LIMIT_BLOCK_TIME="1h"

###########################################
# Monitoring Configuration
###########################################

# Prometheus settings
export PROMETHEUS_PORT=9090
export PROMETHEUS_RETENTION_TIME="30d"
export PROMETHEUS_RETENTION_SIZE="50GB"
export PROMETHEUS_WAL_RETENTION="5d"
export PROMETHEUS_SCRAPE_INTERVAL="15s"
export PROMETHEUS_EVALUATION_INTERVAL="15s"
export PROMETHEUS_MAX_SAMPLES=5000000
export PROMETHEUS_QUERY_TIMEOUT="2m"

# Grafana settings
export GRAFANA_PORT=3000
export GRAFANA_DOMAIN="grafana.automation.local"
export GRAFANA_ADMIN_USER="admin"
export GRAFANA_ADMIN_PASSWORD=$(random_string 32)
export GRAFANA_SECRET_KEY=$(random_string 32)
export GRAFANA_COOKIE_NAME="grafana_session"
export GRAFANA_COOKIE_SECURE="true"
export GRAFANA_DISABLE_GRAVATAR="true"
export GRAFANA_DEFAULT_THEME="dark"

# Alert Manager
export ALERTMANAGER_PORT=9093
export ALERTMANAGER_CLUSTER_PORT=9094
export ALERTMANAGER_MESH_PORT=9095
export ALERTMANAGER_RESOLVE_TIMEOUT="5m"
export ALERTMANAGER_SMTP_HOST="smtp.example.com"
export ALERTMANAGER_SMTP_PORT=587
export ALERTMANAGER_SMTP_FROM="alerts@automation.local"
export ALERTMANAGER_SLACK_API_URL=""
export ALERTMANAGER_SLACK_CHANNEL="#alerts"

###########################################
# Resource Management
###########################################

# System resource limits
export MAX_FILE_DESCRIPTORS=65535
export MAX_PROCESSES=4096
export MAX_MEMORY_PERCENT=80
export MAX_CPU_PERCENT=90
export MAX_DISK_PERCENT=85
export SWAP_PERCENT_THRESHOLD=20

# Container resource limits
export CONTAINER_CPU_LIMIT="0.5"
export CONTAINER_MEMORY_LIMIT="512M"
export CONTAINER_SWAP_LIMIT="1G"
export CONTAINER_PIDS_LIMIT=100
export CONTAINER_ULIMITS_NOFILE=65535
export CONTAINER_ULIMITS_NPROC=4096

# Load balancing thresholds
export LOAD_THRESHOLD_WARNING=2.0
export LOAD_THRESHOLD_CRITICAL=4.0
export LOAD_BALANCE_INTERVAL="1m"
export LOAD_BALANCE_MIN_NODES=2
export LOAD_BALANCE_MAX_NODES=10

###########################################
# Backup Configuration
###########################################

# Backup settings
export BACKUP_RETENTION_DAYS=30
export BACKUP_COMPRESS_LEVEL=9
export BACKUP_MAX_SIZE="50G"
export BACKUP_SCHEDULE="0 2 * * *"
export BACKUP_TYPE="incremental"
export BACKUP_ENCRYPTION="yes"
export BACKUP_ENCRYPTION_KEY=$(random_string 32)
export BACKUP_VERIFY="yes"
export BACKUP_NOTIFY="yes"
export BACKUP_NOTIFY_EMAIL="admin@automation.local"

# Export all environment variables
export PATH="${BASE_DIR}/bin:${PATH}"
