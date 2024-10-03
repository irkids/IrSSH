#!/usr/bin/env python3

import os
import subprocess
import sys
import time
from typing import List, Dict, Any
import asyncio
import aiohttp
import psutil
import uvloop
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_bcrypt import Bcrypt
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from sqlalchemy.exc import SQLAlchemyError
from prometheus_client import start_http_server, Counter, Gauge
from apscheduler.schedulers.background import BackgroundScheduler
from cryptography.fernet import Fernet

# Initialize Flask app
app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'postgresql://vpn_admin:your_secure_password@localhost/vpn_management'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['JWT_SECRET_KEY'] = 'your_jwt_secret_key'  # Change this!
app.config['SECRET_KEY'] = 'your_app_secret_key'  # Change this!

# Initialize extensions
db = SQLAlchemy(app)
migrate = Migrate(app, db)
bcrypt = Bcrypt(app)
jwt = JWTManager(app)

# Prometheus metrics
REQUESTS = Counter('vpn_requests_total', 'Total VPN requests')
ACTIVE_CONNECTIONS = Gauge('vpn_active_connections', 'Number of active VPN connections')

# Encryption key for sensitive data
ENCRYPTION_KEY = Fernet.generate_key()
cipher_suite = Fernet(ENCRYPTION_KEY)

# Models
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password = db.Column(db.String(120), nullable=False)
    role = db.Column(db.String(20), nullable=False, default='user')
    connections = db.relationship('VPNConnection', backref='user', lazy=True)

class VPNConnection(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    protocol = db.Column(db.String(20), nullable=False)
    ip_address = db.Column(db.String(15), nullable=False)
    connected_at = db.Column(db.DateTime, nullable=False)
    disconnected_at = db.Column(db.DateTime)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)

class VPNProtocol(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(20), unique=True, nullable=False)
    is_installed = db.Column(db.Boolean, default=False)
    config = db.Column(db.Text)

# Helper functions
def encrypt_data(data: str) -> bytes:
    return cipher_suite.encrypt(data.encode())

def decrypt_data(data: bytes) -> str:
    return cipher_suite.decrypt(data).decode()

async def check_server_health():
    cpu_percent = psutil.cpu_percent()
    memory_percent = psutil.virtual_memory().percent
    disk_percent = psutil.disk_usage('/').percent
    
    if cpu_percent > 90 or memory_percent > 90 or disk_percent > 90:
        # Implement alerting mechanism here (e.g., send email, Slack notification)
        print(f"Alert: High resource usage - CPU: {cpu_percent}%, Memory: {memory_percent}%, Disk: {disk_percent}%")

# Routes
@app.route('/api/register', methods=['POST'])
def register():
    data = request.get_json()
    hashed_password = bcrypt.generate_password_hash(data['password']).decode('utf-8')
    new_user = User(username=data['username'], password=hashed_password)
    db.session.add(new_user)
    try:
        db.session.commit()
        return jsonify({"message": "User created successfully"}), 201
    except SQLAlchemyError as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

@app.route('/api/login', methods=['POST'])
def login():
    data = request.get_json()
    user = User.query.filter_by(username=data['username']).first()
    if user and bcrypt.check_password_hash(user.password, data['password']):
        access_token = create_access_token(identity=user.id)
        return jsonify(access_token=access_token), 200
    return jsonify({"error": "Invalid credentials"}), 401

@app.route('/api/vpn/connect', methods=['POST'])
@jwt_required()
def vpn_connect():
    REQUESTS.inc()
    data = request.get_json()
    user_id = get_jwt_identity()
    new_connection = VPNConnection(
        protocol=data['protocol'],
        ip_address=request.remote_addr,
        connected_at=db.func.now(),
        user_id=user_id
    )
    db.session.add(new_connection)
    try:
        db.session.commit()
        ACTIVE_CONNECTIONS.inc()
        return jsonify({"message": "VPN connected successfully"}), 200
    except SQLAlchemyError as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

@app.route('/api/vpn/disconnect', methods=['POST'])
@jwt_required()
def vpn_disconnect():
    user_id = get_jwt_identity()
    connection = VPNConnection.query.filter_by(user_id=user_id, disconnected_at=None).first()
    if connection:
        connection.disconnected_at = db.func.now()
        try:
            db.session.commit()
            ACTIVE_CONNECTIONS.dec()
            return jsonify({"message": "VPN disconnected successfully"}), 200
        except SQLAlchemyError as e:
            db.session.rollback()
            return jsonify({"error": str(e)}), 500
    return jsonify({"error": "No active connection found"}), 404

@app.route('/api/vpn/protocols', methods=['GET'])
@jwt_required()
def get_protocols():
    protocols = VPNProtocol.query.all()
    return jsonify([{"id": p.id, "name": p.name, "is_installed": p.is_installed} for p in protocols]), 200

# VPN Protocol Installation
def install_vpn_protocol(protocol_name: str) -> bool:
    # Implement the installation logic for each protocol
    installation_commands = {
        "SSH": ["apt-get update", "apt-get install -y openssh-server"],
        "L2TP/IPSec": ["apt-get update", "apt-get install -y strongswan xl2tpd"],
        "IKEv2/IPSec": ["apt-get update", "apt-get install -y strongswan strongswan-pki libcharon-extra-plugins"],
        "Cisco AnyConnect": ["apt-get update", "apt-get install -y ocserv"],
        "WireGuard": ["apt-get update", "apt-get install -y wireguard"],
        "ShadowSocks": ["apt-get update", "apt-get install -y shadowsocks-libev"],
        "V2Ray": ["bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)"]
    }
    
    if protocol_name not in installation_commands:
        return False
    
    try:
        for command in installation_commands[protocol_name]:
            subprocess.run(command, shell=True, check=True)
        
        protocol = VPNProtocol.query.filter_by(name=protocol_name).first()
        if not protocol:
            protocol = VPNProtocol(name=protocol_name)
        protocol.is_installed = True
        db.session.add(protocol)
        db.session.commit()
        return True
    except subprocess.CalledProcessError:
        return False

@app.route('/api/vpn/install', methods=['POST'])
@jwt_required()
def install_protocol():
    data = request.get_json()
    protocol_name = data.get('protocol')
    if not protocol_name:
        return jsonify({"error": "Protocol name is required"}), 400
    
    success = install_vpn_protocol(protocol_name)
    if success:
        return jsonify({"message": f"{protocol_name} installed successfully"}), 200
    else:
        return jsonify({"error": f"Failed to install {protocol_name}"}), 500

# Nginx configuration
NGINX_CONFIG = """
server {
    listen 80;
    server_name your_domain.com;

    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /metrics {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
"""

def configure_nginx():
    with open('/etc/nginx/sites-available/vpn_management', 'w') as f:
        f.write(NGINX_CONFIG)
    os.symlink('/etc/nginx/sites-available/vpn_management', '/etc/nginx/sites-enabled/vpn_management')
    subprocess.run(['nginx', '-t'], check=True)
    subprocess.run(['systemctl', 'restart', 'nginx'], check=True)

# Main setup function
def setup_vpn_management_system():
    # Update system and install dependencies
    subprocess.run(['apt-get', 'update'], check=True)
    subprocess.run(['apt-get', 'install', '-y', 'nginx', 'postgresql', 'python3-pip'], check=True)
    
    # Install Python dependencies
    subprocess.run(['pip3', 'install', 'flask', 'flask-sqlalchemy', 'flask-migrate', 'flask-bcrypt', 'flask-jwt-extended', 'psycopg2-binary', 'prometheus_client', 'apscheduler', 'cryptography', 'aiohttp', 'uvloop', 'psutil'], check=True)
    
    # Setup PostgreSQL database
    subprocess.run(['sudo', '-u', 'postgres', 'psql', '-c', "CREATE DATABASE vpn_management;"], check=True)
    subprocess.run(['sudo', '-u', 'postgres', 'psql', '-c', "CREATE USER vpn_admin WITH ENCRYPTED PASSWORD 'your_secure_password';"], check=True)
    subprocess.run(['sudo', '-u', 'postgres', 'psql', '-c', "GRANT ALL PRIVILEGES ON DATABASE vpn_management TO vpn_admin;"], check=True)
    
    # Initialize database
    with app.app_context():
        db.create_all()
    
    # Configure Nginx
    configure_nginx()
    
    # Start Prometheus metrics server
    start_http_server(8000)
    
    # Setup background tasks
    scheduler = BackgroundScheduler()
    scheduler.add_job(func=check_server_health, trigger="interval", seconds=60)
    scheduler.start()
    
    # Use uvloop for improved async performance
    uvloop.install()
    
    print("VPN Management System setup complete!")

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'setup':
        setup_vpn_management_system()
    else:
        app.run(host='0.0.0.0', port=5000)
