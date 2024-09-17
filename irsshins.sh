#!/bin/bash

# Basic details setup
echo "Enter the administrator username for SSH panel:"
read admin_user
echo "Enter the administrator password for SSH panel:"
read admin_password

# Ask for server IP or domain once
echo "Enter the IP address or domain for the server:"
read server_address

# Ask for Badvpn port at the start
echo "Enter the Badvpn port for voice and video calls (default: 7300):"
read badvpn_port
badvpn_port=${badvpn_port:-7300}

# Store admin credentials and server details for later use
echo "Admin Username: $admin_user" > /etc/ssh-panel/admin.conf
echo "Admin Password: $admin_password" >> /etc/ssh-panel/admin.conf
echo "Server Address: $server_address" >> /etc/ssh-panel/admin.conf
echo "Badvpn Port: $badvpn_port" >> /etc/ssh-panel/admin.conf

# System and dependency setup
echo "Installing necessary packages..."
apt-get update
apt-get install -y nginx python3 python3-pip mariadb-server

# Set up NGINX and the database
systemctl start nginx
systemctl enable nginx

# Setting up the Python environment
pip3 install flask gunicorn pymysql

# Python Flask SSH Panel Web App Setup
echo "Setting up the SSH panel..."

cat << EOF > /var/www/ssh-panel/app.py
from flask import Flask, render_template, request, redirect, url_for
import pymysql

app = Flask(__name__)

# Database connection
def connect_db():
    return pymysql.connect(host='localhost', user='root', password='', db='ssh_panel')

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/login', methods=['POST'])
def login():
    username = request.form['username']
    password = request.form['password']
    if username == '$admin_user' and password == '$admin_password':
        return redirect(url_for('dashboard'))
    else:
        return "Invalid credentials"

@app.route('/dashboard')
def dashboard():
    # Show registered users
    conn = connect_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users")
    users = cursor.fetchall()
    conn.close()
    return render_template('dashboard.html', users=users)

@app.route('/register', methods=['POST'])
def register():
    username = request.form['username']
    expiration = request.form['expiration']
    bandwidth_limit = request.form['bandwidth']
    
    # Register the user in the database
    conn = connect_db()
    cursor = conn.cursor()
    cursor.execute("INSERT INTO users (username, expiration, bandwidth) VALUES (%s, %s, %s)", (username, expiration, bandwidth_limit))
    conn.commit()
    conn.close()

    return redirect(url_for('dashboard'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Create templates for the panel
mkdir -p /var/www/ssh-panel/templates

# HTML Templates
cat << EOF > /var/www/ssh-panel/templates/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SSH Panel - Login</title>
</head>
<body>
    <h2>Login to SSH Panel</h2>
    <form action="/login" method="POST">
        Username: <input type="text" name="username"><br>
        Password: <input type="password" name="password"><br>
        <input type="submit" value="Login">
    </form>
</body>
</html>
EOF

cat << EOF > /var/www/ssh-panel/templates/dashboard.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SSH Panel - Dashboard</title>
</head>
<body>
    <h2>Registered Users</h2>
    <table border="1">
        <tr>
            <th>Username</th>
            <th>Expiration</th>
            <th>Bandwidth Limit</th>
        </tr>
        {% for user in users %}
        <tr>
            <td>{{ user[0] }}</td>
            <td>{{ user[1] }}</td>
            <td>{{ user[2] }}</td>
        </tr>
        {% endfor %}
    </table>

    <h2>Register New User</h2>
    <form action="/register" method="POST">
        Username: <input type="text" name="username"><br>
        Expiration Date: <input type="date" name="expiration"><br>
        Bandwidth Limit: <input type="text" name="bandwidth"><br>
        <input type="submit" value="Register">
    </form>
</body>
</html>
EOF

# Database setup for user management
echo "Setting up the MySQL database..."
mysql -e "CREATE DATABASE ssh_panel"
mysql -e "CREATE TABLE ssh_panel.users (username VARCHAR(50), expiration DATE, bandwidth VARCHAR(20))"

# Configure Gunicorn for production
echo "Configuring Gunicorn..."
cat << EOF > /etc/systemd/system/gunicorn.service
[Unit]
Description=Gunicorn instance to serve SSH Panel
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/ssh-panel
ExecStart=/usr/bin/gunicorn --workers 3 --bind unix:ssh-panel.sock -m 007 app:app

[Install]
WantedBy=multi-user.target
EOF

# Start and enable the Gunicorn service
systemctl start gunicorn
systemctl enable gunicorn

# Configure NGINX to serve the panel
cat << EOF > /etc/nginx/sites-available/ssh-panel
server {
    listen 80;
    server_name $server_address;

    location / {
        include proxy_params;
        proxy_pass http://unix:/var/www/ssh-panel/ssh-panel.sock;
    }
}
EOF

# Enable NGINX configuration
ln -s /etc/nginx/sites-available/ssh-panel /etc/nginx/sites-enabled
nginx -t && systemctl restart nginx

# Badvpn Installation (Silent)
echo "Installing and configuring Badvpn..."
wget -N https://raw.githubusercontent.com/opiran-club/VPS-Optimizer/main/Install/udpgw.sh
bash udpgw.sh $badvpn_port

# Completion message
echo "Installation complete! Access the SSH Panel at http://$server_address"
