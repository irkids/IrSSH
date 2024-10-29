#!/bin/bash

# Define color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define log file
LOG_FILE="/var/log/system-setup.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Initialize logging
init_logging() {
    mkdir -p "$(dirname $LOG_FILE)"
    touch "$LOG_FILE"
    echo "[$TIMESTAMP] Installation script started" >> "$LOG_FILE"
}

# Log function
log() {
    local level=$1
    local message=$2
    echo "[$TIMESTAMP] [$level] $message" >> "$LOG_FILE"
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
}

# Error handling function
handle_error() {
    local exit_code=$?
    local command=$1
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Command '$command' failed with exit code $exit_code"
        exit $exit_code
    fi
}

# Check system requirements
check_system_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check minimum RAM (8GB)
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_ram -lt 8000 ]; then
        log "ERROR" "Insufficient RAM. Minimum 8GB required."
        exit 1
    fi

    # Check minimum CPU cores (2)
    local cpu_cores=$(nproc)
    if [ $cpu_cores -lt 2 ]; then
        log "ERROR" "Insufficient CPU cores. Minimum 2 cores required."
        exit 1
    fi

    # Check disk space (minimum 20GB free)
    local free_space=$(df -BG / | awk '/^\//{print $4}' | tr -d 'G')
    if [ $free_space -lt 20 ]; then
        log "ERROR" "Insufficient disk space. Minimum 20GB free space required."
        exit 1
    }

    log "INFO" "System requirements check passed"
}

# Update system packages
update_system() {
    log "INFO" "Updating system packages..."
    
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get upgrade -y
        handle_error "apt-get update/upgrade"
    elif [ -f /etc/redhat-release ]; then
        dnf update -y
        handle_error "dnf update"
    else
        log "ERROR" "Unsupported distribution"
        exit 1
    fi

    log "INFO" "System packages updated successfully"
}

# Install Python and required packages
install_python() {
    log "INFO" "Installing Python and dependencies..."
    
    if [ -f /etc/debian_version ]; then
        apt-get install -y python3 python3-pip python3-venv
        handle_error "Python installation"
    elif [ -f /etc/redhat-release ]; then
        dnf install -y python3 python3-pip python3-virtualenv
        handle_error "Python installation"
    fi

    # Upgrade pip
    python3 -m pip install --upgrade pip
    handle_error "pip upgrade"

    # Install required Python packages
    python3 -m pip install ansible-core requests psycopg2-binary docker-compose
    handle_error "Python packages installation"

    log "INFO" "Python installation completed"
}

# Install and configure PostgreSQL
install_postgresql() {
    log "INFO" "Installing PostgreSQL..."
    
    if [ -f /etc/debian_version ]; then
        apt-get install -y postgresql postgresql-contrib
        handle_error "PostgreSQL installation"
    elif [ -f /etc/redhat-release ]; then
        dnf install -y postgresql-server postgresql-contrib
        postgresql-setup --initdb
        handle_error "PostgreSQL installation"
    fi

    # Start and enable PostgreSQL service
    systemctl start postgresql
    systemctl enable postgresql
    handle_error "PostgreSQL service setup"

    # Configure PostgreSQL
    sudo -u postgres psql -c "CREATE DATABASE automation_db;"
    sudo -u postgres psql -c "CREATE USER automation_user WITH PASSWORD 'secure_password';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE automation_db TO automation_user;"
    handle_error "PostgreSQL configuration"

    log "INFO" "PostgreSQL installation and configuration completed"
}

# Install Docker and Docker Compose
install_docker() {
    log "INFO" "Installing Docker and Docker Compose..."

    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    handle_error "Docker installation"

    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    handle_error "Docker service setup"

    # Add current user to docker group
    usermod -aG docker $USER
    handle_error "Docker user setup"

    log "INFO" "Docker installation completed"
}

# Install Node.js and npm
install_nodejs() {
    log "INFO" "Installing Node.js and npm..."

    # Install Node.js repository
    if [ -f /etc/debian_version ]; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
    elif [ -f /etc/redhat-release ]; then
        curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
        dnf install -y nodejs
    fi
    handle_error "Node.js installation"

    # Install global npm packages
    npm install -g pm2 yarn
    handle_error "npm global packages installation"

    log "INFO" "Node.js and npm installation completed"
}

# Install and configure Nginx
install_nginx() {
    log "INFO" "Installing Nginx..."

    if [ -f /etc/debian_version ]; then
        apt-get install -y nginx
    elif [ -f /etc/redhat-release ]; then
        dnf install -y nginx
    fi
    handle_error "Nginx installation"

    # Start and enable Nginx service
    systemctl start nginx
    systemctl enable nginx
    handle_error "Nginx service setup"

    log "INFO" "Nginx installation completed"
}

# Install and configure FreeIPA
install_freeipa() {
    log "INFO" "Installing FreeIPA..."

    if [ -f /etc/debian_version ]; then
        apt-get install -y freeipa-server freeipa-server-dns
    elif [ -f /etc/redhat-release ]; then
        dnf install -y freeipa-server freeipa-server-dns
    fi
    handle_error "FreeIPA installation"

    log "INFO" "FreeIPA installation completed"
}

# Main installation function
main() {
    init_logging
    check_system_requirements
    update_system
    install_python
    install_postgresql
    install_docker
    install_nodejs
    install_nginx
    install_freeipa

    log "INFO" "Core installation completed successfully"
}

# Execute main function
main

exit 0
