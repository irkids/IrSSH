#!/bin/bash

# IRANSSH Installation Script
# Based on the idea of MeHrSaM
# Version: 3.0

set -euo pipefail

# Function to output script content
output_script() {
    cat << 'EOF'
#!/bin/bash
# (The entire script content goes here)
EOF
    exit 0
}

# Check if no arguments are provided
if [ $# -eq 0 ]; then
    output_script
fi

# Constants
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOG_FILE="/var/log/iranssh_install.log"
IRANSSH_DIR="/var/www/iranssh"
VENV_DIR="$IRANSSH_DIR/env"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --admin-username) ADMIN_USERNAME="$2"; shift 2 ;;
        --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
        --server-ip) SERVER_IP="$2"; shift 2 ;;
        --domain-name) DOMAIN_NAME="$2"; shift 2 ;;
        --web-port) WEB_PORT="$2"; shift 2 ;;
        --db-name) DB_NAME="$2"; shift 2 ;;
        --db-user) DB_USER="$2"; shift 2 ;;
        --db-password) DB_PASSWORD="$2"; shift 2 ;;
        --ssh-port) SSH_PORT="$2"; shift 2 ;;
        --dropbear-port) DROPBEAR_PORT="$2"; shift 2 ;;
        --badvpn-port) BADVPN_PORT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Function to validate configuration
validate_config() {
    local required_vars=(
        "ADMIN_USERNAME" "ADMIN_PASSWORD" "SERVER_IP" "DOMAIN_NAME" "WEB_PORT"
        "DB_NAME" "DB_USER" "DB_PASSWORD" "SSH_PORT" "DROPBEAR_PORT"
        "BADVPN_PORT"
    )
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_message "ERROR" "Missing required configuration: $var"
            exit 1
        fi
    done
}

# Function to install dependencies
install_dependencies() {
    log_message "INFO" "Updating system and installing dependencies..."
    apt update && apt upgrade -y
    apt install -y postgresql nginx python3-pip python3-venv ufw certbot python3-certbot-nginx dropbear git badvpn
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to install dependencies"
        exit 1
    fi
}

# Function to set up PostgreSQL
setup_postgresql() {
    log_message "INFO" "Setting up PostgreSQL..."
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to set up PostgreSQL"
        exit 1
    fi
}

# Function to configure firewall
configure_firewall() {
    log_message "INFO" "Configuring firewall..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT"/tcp
    ufw allow "$WEB_PORT"/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow "$DROPBEAR_PORT"/tcp
    ufw allow "$BADVPN_PORT"/udp
    echo "y" | ufw enable
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to configure firewall"
        exit 1
    fi
}

# Function to set up BadVPN
setup_badvpn() {
    log_message "INFO" "Setting up BadVPN..."
    cat << EOF > /etc/systemd/system/badvpn.service
[Unit]
Description=BadVPN UDPGW Service
After=network.target

[Service]
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 0.0.0.0:$BADVPN_PORT --max-clients 1000 --max-connections-for-client 10
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable badvpn
    systemctl start badvpn
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to set up BadVPN"
        exit 1
    fi
}

# Function to set up Dropbear
setup_dropbear() {
    log_message "INFO" "Setting up Dropbear..."
    sed -i "s/^NO_START=1/NO_START=0/" /etc/default/dropbear
    sed -i "s/^DROPBEAR_PORT=22/DROPBEAR_PORT=$DROPBEAR_PORT/" /etc/default/dropbear
    echo "DROPBEAR_EXTRA_ARGS=\"-p 443 -K 300\"" >> /etc/default/dropbear
    systemctl restart dropbear
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to set up Dropbear"
        exit 1
    fi
}

# Function to set up Django project
setup_django() {
    log_message "INFO" "Setting up Django project..."
    mkdir -p "$IRANSSH_DIR"
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    pip install django psycopg2-binary gunicorn paramiko django-chartjs
    django-admin startproject iranssh_manager "$IRANSSH_DIR"
    cd "$IRANSSH_DIR"
    python manage.py startapp sshpanel

    # Update settings.py
    cat << EOF >> "$IRANSSH_DIR/iranssh_manager/settings.py"

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '$DB_NAME',
        'USER': '$DB_USER',
        'PASSWORD': '$DB_PASSWORD',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}

STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'static')

ALLOWED_HOSTS = ['$DOMAIN_NAME', '$SERVER_IP']

SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'
EOF

    python manage.py migrate
    python manage.py collectstatic --noinput
    echo "from django.contrib.auth.models import User; User.objects.create_superuser('$ADMIN_USERNAME', 'admin@example.com', '$ADMIN_PASSWORD')" | python manage.py shell
    
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to set up Django project"
        exit 1
    fi
}

# Function to configure Gunicorn
configure_gunicorn() {
    log_message "INFO" "Configuring Gunicorn..."
    cat << EOF > /etc/systemd/system/gunicorn.service
[Unit]
Description=gunicorn daemon for IRANSSH Manager
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$IRANSSH_DIR
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --bind unix:$IRANSSH_DIR/iranssh_manager.sock iranssh_manager.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

    systemctl start gunicorn
    systemctl enable gunicorn
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to configure Gunicorn"
        exit 1
    fi
}

# Function to configure Nginx
configure_nginx() {
    log_message "INFO" "Configuring Nginx..."
    cat << EOF > /etc/nginx/sites-available/iranssh_manager
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://unix:$IRANSSH_DIR/iranssh_manager.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /static/ {
        alias $IRANSSH_DIR/static/;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/iranssh_manager /etc/nginx/sites-enabled/
    nginx -t
    systemctl restart nginx
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to configure Nginx"
        exit 1
    fi
}

# Function to set up SSL
setup_ssl() {
    log_message "INFO" "Setting up SSL..."
    certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m admin@example.com
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to set up SSL"
        exit 1
    fi
}

# Function to customize IRANSSH branding
customize_branding() {
    log_message "INFO" "Customizing IRANSSH branding..."
    mkdir -p "$IRANSSH_DIR/sshpanel/templates"
    cat << EOF > "$IRANSSH_DIR/sshpanel/templates/base.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IRANSSH - SSH Manager</title>
    <link rel="stylesheet" href="{% static 'css/styles.css' %}">
</head>
<body>
    <div class="content">
        <div class="branding">
            <h1 style="text-align: center;">IRANSSH</h1>
            <div style="position: absolute; bottom: 0; left: 0;">
                <p style="font-size: 12px;">based on the idea of <span style="font-size: 14px; font-weight: bold;">MeHrSaM</span></p>
            </div>
        </div>
        {% block content %}{% endblock %}
    </div>
</body>
</html>
EOF

    cat << EOF > "$IRANSSH_DIR/sshpanel/templates/registration/login.html"
{% extends 'base.html' %}
{% block content %}
    <div class="login-form">
        <h2 style="text-align: center;">Login to IRANSSH Panel</h2>
        <form method="post">
            {% csrf_token %}
            {{ form.as_p }}
            <button type="submit">Login</button>
        </form>
    </div>
{% endblock %}
EOF
}

# Main installation function
install_iranssh() {
    log_message "INFO" "Starting IRANSSH installation..."
    
    check_root
    validate_config
    install_dependencies
    setup_postgresql
    configure_firewall
    setup_badvpn
    setup_dropbear
    setup_django
    configure_gunicorn
    configure_nginx
    setup_ssl
    customize_branding
    
    log_message "INFO" "IRANSSH installation completed successfully!"
    echo "Access the IRANSSH web interface at https://$DOMAIN_NAME"
    echo "Log in with the credentials you provided."
}

# Run the installation
install_iranssh
