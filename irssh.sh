#!/bin/bash

# Quiet typing mode for introduction (fallback if 'pv' is not installed)
if ! command -v pv &> /dev/null; then
    echo "pv command not found. Installing pv..."
    apt-get install -y pv
fi

# Introduction
echo -n "I hope the moments you use IRANSSH have been useful for you" | pv -qL 20
sleep 1
echo ""
sleep 1
echo -e "\033[1;31mBASED ON THE IDEA OF MeHrSaM\033[0m"
sleep 2

# 1. Prompt admin for setup information
read -p "Enter admin username for IRANSSH web panel: " admin_username
read -sp "Enter admin password for IRANSSH web panel: " admin_password
echo ""
read -p "Enter the server's IP address: " server_ip
read -p "Enter port for the web-based user interface (default 8080): " web_port
web_port=${web_port:-8080}

# 2. Update system and install necessary packages
echo "Updating system and installing necessary packages..."
apt update && apt upgrade -y
apt install -y postgresql nginx python3-pip python3-venv ufw certbot python3-certbot-nginx dropbear git

# Fix for 'badvpn' missing in default repos
if ! apt install -y badvpn; then
    echo "Badvpn is not available in the default repositories. Skipping Badvpn installation."
fi

# Set up PostgreSQL
echo "Setting up PostgreSQL..."
if ! sudo -u postgres psql -c "CREATE USER iranssh_manager WITH PASSWORD 'password';"; then
    echo "Error setting up PostgreSQL. Make sure PostgreSQL is installed and running."
fi

if ! sudo -u postgres psql -c "CREATE DATABASE iranssh_manager OWNER iranssh_manager;"; then
    echo "Error creating database. Make sure PostgreSQL is configured properly."
fi

# Set up firewall rules
echo "Configuring firewall..."
ufw allow OpenSSH
ufw allow $web_port
ufw allow 443
ufw enable

# 3. Set up BadVPN for UDPGW (optional step if installation was skipped)
read -p "Enter port for BadVPN UDPGW (default 7300): " badvpn_port
badvpn_port=${badvpn_port:-7300}
if command -v badvpn-udpgw &> /dev/null; then
    nohup badvpn-udpgw --listen-addr 0.0.0.0:$badvpn_port &
else
    echo "Badvpn was not installed, skipping UDPGW setup."
fi

# Set up Dropbear for SSH-Dropbear and SSH-Dropbear-TLS
echo "Configuring Dropbear..."
if [ -f /etc/default/dropbear ]; then
    cat <<EOT >> /etc/default/dropbear
DROPBEAR_PORT=2222
DROPBEAR_EXTRA_ARGS="-p 443 -K 300"
EOT
    systemctl restart dropbear
else
    echo "Dropbear not installed or not configured properly."
fi

# 4. Set up Django project for IRANSSH
echo "Setting up Django project for IRANSSH..."
mkdir -p /var/www/iranssh
cd /var/www/iranssh

# Ensure python3-venv is installed
if ! command -v python3 -m venv &> /dev/null; then
    echo "python3-venv not found, installing..."
    apt install -y python3-venv
fi

# Create Python virtual environment
python3 -m venv env
source env/bin/activate

# Install Django and dependencies
pip install django psycopg2-binary gunicorn paramiko chartjs

# Start Django project
django-admin startproject iranssh_manager
cd iranssh_manager
python3 manage.py startapp sshpanel

# Modify Django settings to use PostgreSQL
sed -i '/DATABASES =/,+5d' iranssh_manager/settings.py
cat <<EOT >> iranssh_manager/settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'iranssh_manager',
        'USER': 'iranssh_manager',
        'PASSWORD': 'password',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}

STATIC_URL = '/static/'

# Security settings for production
ALLOWED_HOSTS = ['$server_ip']
EOT

# Migrate database and create Django superuser
python3 manage.py migrate
echo "from django.contrib.auth.models import User; User.objects.create_superuser('$admin_username', 'admin@example.com', '$admin_password')" | python3 manage.py shell

# Collect static files
python3 manage.py collectstatic --noinput

# Configure Gunicorn
echo "Configuring Gunicorn..."
cat <<EOT >> /etc/systemd/system/gunicorn.service
[Unit]
Description=gunicorn daemon for IRANSSH Manager
After=network.target

[Service]
User=root
Group=www-data
WorkingDirectory=/var/www/iranssh/iranssh_manager
ExecStart=/var/www/iranssh/env/bin/gunicorn --workers 3 --bind unix:/var/www/iranssh/iranssh_manager.sock iranssh_manager.wsgi:application

[Install]
WantedBy=multi-user.target
EOT

systemctl start gunicorn
systemctl enable gunicorn

# Configure NGINX
echo "Configuring NGINX..."
cat <<EOT > /etc/nginx/sites-available/iranssh_manager
server {
    listen 80;
    server_name $server_ip;

    location / {
        proxy_pass http://unix:/var/www/iranssh/iranssh_manager.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /static/ {
        alias /var/www/iranssh/iranssh_manager/static/;
    }
}
EOT

ln -s /etc/nginx/sites-available/iranssh_manager /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# Set up SSL with Let's Encrypt
echo "Setting up Let's Encrypt SSL for HTTPS..."
if ! command -v certbot &> /dev/null; then
    echo "Certbot is not installed. Installing certbot for SSL."
    apt install -y certbot
    apt install -y python3-certbot-nginx
fi

certbot --nginx -d $server_ip --non-interactive --agree-tos -m admin@example.com

# Customize login page and panel pages for IRANSSH branding
echo "Customizing IRANSSH branding..."
cat <<EOT >> /var/www/iranssh/iranssh_manager/sshpanel/templates/base.html
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
EOT

# Customizing login page
cat <<EOT > /var/www/iranssh/iranssh_manager/sshpanel/templates/registration/login.html
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
EOT

# Final message to the user
echo "Installation of IRANSSH complete!"
echo -e "\033[1;31mBASED ON THE IDEA OF MeHrSaM\033[0m"
echo "Access the IRANSSH web interface at http://$server_ip:$web_port."
echo "Log in with the credentials you provided."
