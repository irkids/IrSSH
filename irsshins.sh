#!/bin/bash

# Update and install necessary packages
echo "Updating system and installing dependencies..."
sudo apt update
sudo apt install -y python3 python3-pip mysql-server nginx openssl

# Install Flask and MySQL Connector for Python
echo "Installing Flask and MySQL connector..."
sudo pip3 install flask mysql-connector-python paramiko

# Create the SSH user management Python script
echo "Setting up SSH user management script..."
cat <<EOF > /opt/ssh_user_management.py
from flask import Flask, render_template, request, redirect, flash
import paramiko
import mysql.connector
from mysql.connector import Error
import os

app = Flask(__name__)
app.secret_key = 'your_secret_key'

# MySQL Database Configuration
DB_CONFIG = {
    'host': 'localhost',
    'database': 'ssh_user_management',
    'user': 'your_mysql_user',
    'password': 'your_mysql_password'
}

# SSH Server Configuration
SSH_CONFIG = {
    'hostname': 'your_ssh_server_ip',
    'port': 22,
    'ssh_user': 'your_ssh_user',
    'ssh_password': 'your_ssh_password'
}

# Administrator credentials
admin_username = os.getenv('ADMIN_USERNAME')
admin_password = os.getenv('ADMIN_PASSWORD')

# Function to create a new SSH user on the remote machine
def create_ssh_user(new_username, new_password):
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(SSH_CONFIG['hostname'], port=SSH_CONFIG['port'], 
                       username=SSH_CONFIG['ssh_user'], password=SSH_CONFIG['ssh_password'])
        
        # Create a new user on the remote machine
        command = f'sudo useradd -m -p $(openssl passwd -1 {new_password}) {new_username}'
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
def add_user_to_db(username):
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        cursor = connection.cursor()
        query = "INSERT INTO users (username, ssh_user) VALUES (%s, %s)"
        cursor.execute(query, (username, 'ssh_user'))  
        connection.commit()
        cursor.close()
        connection.close()
    except Error as e:
        print(f"Error connecting to MySQL: {str(e)}")

# Route to display registered users
@app.route('/')
def index():
    connection = mysql.connector.connect(**DB_CONFIG)
    cursor = connection.cursor()
    cursor.execute("SELECT * FROM users")
    users = cursor.fetchall()
    cursor.close()
    connection.close()
    return render_template('index.html', users=users)

# Route for the login page
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        if username == admin_username and password == admin_password:
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
        
        success, error = create_ssh_user(username, password)
        if success:
            add_user_to_db(username)
            flash('User created successfully!', 'success')
            return redirect('/')
        else:
            flash(f"Error creating user: {error}", 'danger')
    
    return render_template('register.html')

if __name__ == '__main__':
    app.run(debug=True)
EOF

# Create HTML templates directory
echo "Creating HTML templates..."
mkdir -p /opt/templates

# Create index.html
cat <<EOF > /opt/templates/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SSH User Management</title>
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
                    <th>SSH User</th>
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
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</body>
</html>
EOF

# Create register.html
cat <<EOF > /opt/templates/register.html
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
            <button type="submit" class="btn btn-primary">Register</button>
        </form>
    </div>
</body>
</html>
EOF

# Create login.html
cat <<EOF > /opt/templates/login.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Login</title>
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
    </div>
</body>
</html>
EOF

# Prompt for the admin username and password
read -p "Enter the admin username: " admin_username
read -sp "Enter the admin password: " admin_password
echo

# Set environment variables for the admin credentials
export ADMIN_USERNAME=$admin_username
export ADMIN_PASSWORD=$admin_password

# Configure MySQL database
echo "Configuring MySQL database..."
sudo mysql -u root -e "CREATE DATABASE ssh_user_management;"
sudo mysql -u root -e "CREATE USER 'your_mysql_user'@'localhost' IDENTIFIED BY 'your_mysql_password';"
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON ssh_user_management.* TO 'your_mysql_user'@'localhost';"
sudo mysql -u root -e "FLUSH PRIVILEGES;"

# Create the users table
sudo mysql -u root ssh_user_management -e "
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    ssh_user VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);"

# NGINX configuration
echo "Configuring NGINX..."
sudo cat <<EOF > /etc/nginx/sites-available/ssh_management
server {
    listen 80;
    server_name your_domain_or_ip;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/ssh_management /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# Run the Flask app
echo "Starting the Flask app..."
cd /opt
sudo ADMIN_USERNAME=$admin_username ADMIN_PASSWORD=$admin_password python3 ssh_user_management.py &

echo "SSH User Management system is now running!"
