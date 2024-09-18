#!/bin/bash

# ---------------------------
# SSH User Management Setup
# ---------------------------

# Function to check if the script is running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run this script as root."
        exit 1
    fi
}

# Function to prompt for input with default values
prompt_with_default() {
    local prompt_message=$1
    local default_value=$2
    read -p "$prompt_message [$default_value]: " input
    echo "${input:-$default_value}"
}

# Check if running as root
check_root

# Create a directory for configuration
CONFIG_DIR="/etc/ssh_user_management"
mkdir -p "$CONFIG_DIR"

# Prompt for required inputs
echo "=== SSH User Management Setup ==="
ADMIN_USERNAME=$(prompt_with_default "Enter Server Administrator Username" "admin")
echo "Enter Server Administrator Password:"
read -s ADMIN_PASSWORD
echo
SERVER_ADDRESS=$(prompt_with_default "Enter your Server IP address or Domain" "$(curl -s https://ipinfo.io/ip)")
SUBDOMAIN=$(prompt_with_default "Enter your Subdomain (leave blank if not applicable)" "")
BADVPN_PORT=$(prompt_with_default "Enter Badvpn UDPGW Port (default: 7300)" "7300")

# Save configuration to a file
cat <<EOF > "$CONFIG_DIR/config.env"
ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
SERVER_ADDRESS=${SERVER_ADDRESS}
SUBDOMAIN=${SUBDOMAIN}
BADVPN_PORT=${BADVPN_PORT}
MYSQL_USER=ssh_user_admin
MYSQL_PASSWORD=$(openssl rand -base64 12)
EOF

# Source the configuration
source "$CONFIG_DIR/config.env"

# Update and install necessary packages
echo "Updating system and installing dependencies..."
apt-get update -y
apt-get upgrade -y
apt-get install -y python3 python3-pip mysql-server nginx curl wget git unzip

# Secure MySQL Installation (optional, can be automated further if desired)
echo "Securing MySQL installation..."
mysql_secure_installation <<EOF

y
$MYSQL_PASSWORD
$MYSQL_PASSWORD
y
y
y
y
EOF

# Install Badvpn (UDPGW) using the provided script
echo "Installing Badvpn (UDPGW)..."
bash <(curl -Ls https://raw.githubusercontent.com/HamedAp/Ssh-User-management/master/install.sh --ipv4) $BADVPN_PORT

# Install Python dependencies
echo "Installing Flask, Gunicorn, MySQL Connector, and Paramiko..."
pip3 install flask gunicorn mysql-connector-python paramiko

# Create the SSH user management Python script
echo "Setting up SSH user management script..."
mkdir -p /opt/ssh_user_management/templates

cat <<'EOF' > /opt/ssh_user_management/app.py
from flask import Flask, render_template, request, redirect, flash
import paramiko
import mysql.connector
from mysql.connector import Error
import os

app = Flask(__name__)
app.secret_key = 'your_secret_key'  # Replace with a strong secret key

# MySQL Database Configuration
DB_CONFIG = {
    'host': 'localhost',
    'database': 'ssh_user_management',
    'user': os.getenv('MYSQL_USER'),
    'password': os.getenv('MYSQL_PASSWORD')
}

# SSH Server Configuration
SSH_CONFIG = {
    'hostname': os.getenv('SERVER_ADDRESS'),
    'port': 22,
    'ssh_user': 'root',  # Replace with the SSH user if different
    'ssh_password': os.getenv('SSH_ROOT_PASSWORD')  # You can set this in the config.env if needed
}

# Administrator credentials
ADMIN_USERNAME = os.getenv('ADMIN_USERNAME')
ADMIN_PASSWORD = os.getenv('ADMIN_PASSWORD')

# Function to create a new SSH user on the remote machine
def create_ssh_user(new_username, new_password):
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(SSH_CONFIG['hostname'], port=SSH_CONFIG['port'],
                       username=SSH_CONFIG['ssh_user'], password=SSH_CONFIG['ssh_password'])

        # Create a new user on the remote machine with expiration date and bandwidth limit
        command = f"sudo useradd -m -s /bin/bash -e $(date -d '+30 days' +%Y-%m-%d) -p $(openssl passwd -1 {new_password}) {new_username}"
        stdin, stdout, stderr = client.exec_command(command)
        error = stderr.read().decode('utf-8')

        if error:
            return False, error
        else:
            return True, None
    except Exception as e:
        return False, str(e)
    finally:
        client.close()

# Function to store new user in MySQL database
def add_user_to_db(username, expiration, bandwidth):
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        cursor = connection.cursor()
        query = "INSERT INTO users (username, expiration, bandwidth) VALUES (%s, %s, %s)"
        cursor.execute(query, (username, expiration, bandwidth))
        connection.commit()
        cursor.close()
        connection.close()
    except Error as e:
        print(f"Error connecting to MySQL: {str(e)}")

# Route to display registered users
@app.route('/')
def index():
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        cursor = connection.cursor()
        cursor.execute("SELECT * FROM users")
        users = cursor.fetchall()
        cursor.close()
        connection.close()
        return render_template('index.html', users=users)
    except Error as e:
        return f"Error: {str(e)}"

# Route for the login page
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
            return redirect('/')
        else:
            flash('Invalid credentials', 'danger')
            return redirect('/login')
    return render_template('login.html')

# Route to show user registration form and handle form submissions
@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        expiration = request.form['expiration']
        bandwidth = request.form['bandwidth']

        success, error = create_ssh_user(username, password)
        if success:
            add_user_to_db(username, expiration, bandwidth)
            flash('User created successfully!', 'success')
            return redirect('/')
        else:
            flash(f"Error creating user: {error}", 'danger')

    return render_template('register.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Create HTML templates
echo "Creating HTML templates..."

# index.html
cat <<'EOF' > /opt/ssh_user_management/templates/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SSH User Management - Dashboard</title>
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
</head>
<body>
    <div class="container mt-5">
        <h1>Registered SSH Users</h1>
        <a href="/register" class="btn btn-primary mb-3">Register New User</a>
        <table class="table table-striped">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Username</th>
                    <th>Expiration</th>
                    <th>Bandwidth Limit</th>
                    <th>Created At</th>
                </tr>
            </thead>
            <tbody>
                {% for user in users %}
                <tr>
                    <td>{{ user[0] }}</td>
                    <td>{{ user[1] }}</td>
                    <td>{{ user[2] }}</td>
                    <td>{{ user[3] }}</td>
                    <td>{{ user[4] }}</td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</body>
</html>
EOF

# register.html
cat <<'EOF' > /opt/ssh_user_management/templates/register.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Register SSH User</title>
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
</head>
<body>
    <div class="container mt-5">
        <h1>Register New SSH User</h1>
        <form method="POST">
            <div class="form-group">
                <label for="username">Username</label>
                <input type="text" class="form-control" id="username" name="username" required>
            </div>
            <div class="form-group">
                <label for="password">Password</label>
                <input type="password" class="form-control" id="password" name="password" required>
            </div>
            <div class="form-group">
                <label for="expiration">Expiration Date</label>
                <input type="date" class="form-control" id="expiration" name="expiration" required>
            </div>
            <div class="form-group">
                <label for="bandwidth">Bandwidth Limit (MB)</label>
                <input type="number" class="form-control" id="bandwidth" name="bandwidth" required>
            </div>
            <button type="submit" class="btn btn-primary">Register</button>
        </form>
    </div>
</body>
</html>
EOF

# login.html
cat <<'EOF' > /opt/ssh_user_management/templates/login.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SSH User Management - Login</title>
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
</head>
<body>
    <div class="container mt-5">
        <h1>Admin Login</h1>
        <form method="POST">
            <div class="form-group">
                <label for="username">Username</label>
                <input type="text" class="form-control" id="username" name="username" required>
            </div>
            <div class="form-group">
                <label for="password">Password</label>
                <input type="password" class="form-control" id="password" name="password" required>
            </div>
            <button type="submit" class="btn btn-primary">Login</button>
        </form>
        {% with messages = get_flashed_messages(with_categories=true) %}
          {% if messages %}
            <div class="mt-3">
              {% for category, message in messages %}
                <div class="alert alert-{{ category }}">{{ message }}</div>
              {% endfor %}
            </div>
          {% endif %}
        {% endwith %}
    </div>
</body>
</html>
EOF

# Configure MySQL database
echo "Configuring MySQL database..."
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 12)
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';"
mysql -e "CREATE DATABASE IF NOT EXISTS ssh_user_management;"
mysql -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON ssh_user_management.* TO '$MYSQL_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Create the users table if it doesn't exist
mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" ssh_user_management <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) NOT NULL UNIQUE,
    expiration DATE NOT NULL,
    bandwidth VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

# Export MySQL credentials for Flask app
export MYSQL_USER
export MYSQL_PASSWORD

# Set up Gunicorn systemd service
echo "Setting up Gunicorn service..."
cat <<EOF > /etc/systemd/system/ssh_user_management.service
[Unit]
Description=Gunicorn instance to serve SSH User Management
After=network.target

[Service]
User=root
Group=www-data
WorkingDirectory=/opt/ssh_user_management
Environment="MYSQL_USER=$MYSQL_USER"
Environment="MYSQL_PASSWORD=$MYSQL_PASSWORD"
Environment="ADMIN_USERNAME=$ADMIN_USERNAME"
Environment="ADMIN_PASSWORD=$ADMIN_PASSWORD"
ExecStart=/usr/local/bin/gunicorn --workers 3 --bind unix:/opt/ssh_user_management/ssh_user_management.sock -m 007 app:app

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, start and enable Gunicorn service
systemctl daemon-reload
systemctl start ssh_user_management
systemctl enable ssh_user_management

# Configure NGINX to proxy pass to Gunicorn
echo "Configuring NGINX..."
cat <<EOF > /etc/nginx/sites-available/ssh_user_management
server {
    listen 80;
    server_name $SERVER_ADDRESS $SUBDOMAIN;

    location / {
        include proxy_params;
        proxy_pass http://unix:/opt/ssh_user_management/ssh_user_management.sock;
    }
}
EOF

# Enable the NGINX configuration
ln -s /etc/nginx/sites-available/ssh_user_management /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# Completion message
echo "===================================="
echo "SSH User Management system is now running!"
echo "Access the panel at: http://$SERVER_ADDRESS/login"
echo "Admin Username: $ADMIN_USERNAME"
echo "Admin Password: [Hidden]"
echo "Badvpn UDPGW Port: $BADVPN_PORT"
echo "===================================="

# ---------------------------
# End of SSH User Management Setup
# ---------------------------
