import subprocess
import secrets
import string

# VPN protocols and their configurations
VPN_PROTOCOLS = {
    "xl2tpd": {
        "packages": ["xl2tpd", "ppp"],
        "config_files": {
            "/etc/xl2tpd/xl2tpd.conf": [
                "[global]\nipsec saref = yes\n",
                "[lns default]\nip range = 192.168.2.2-192.168.2.254\nlocal ip = 192.168.2.1\nrequire chap = yes\nrefuse pap = yes\nrequire authentication = yes\nname = l2tpd\nppp debug = yes\npppoptfile = /etc/ppp/options.l2tpd.client\n"
            ],
            "/etc/ppp/options.l2tpd.client": "noipdefault\nnoauth\nmtu 1280\nmru 1280\nnocrtscts\nlock\nhide-password\nlcp-echo-interval 30\nlcp-echo-failure 4\n"
        }
    },
    "ipsec": {
        "packages": ["strongswan"],
        "config_files": {
            "/etc/ipsec.conf": "[global]\nrightsubnet=192.168.2.0/24\n",
            "/etc/ipsec.secrets": ": PSK \"your_pre_shared_key_l2tp_ipsec\"\n: PSK \"your_pre_shared_key_ikev2_ipsec\"\n"
        }
    },
    "wireguard": {
        "packages": ["wireguard"],
        "config_files": {
            "/etc/wireguard/wg0.conf": "[Interface]\nListenPort = 51820\nPrivateKey = <your_private_key>\n\n[Peer]\nAllowedIPs = 192.168.2.0/24\nPublicKey = <your_public_key>\nEndpoint = <your_server_ip>:51820\nPersistentKeepalive = 25\n"
        }
    }
}

# Function to install VPN server software
def install_vpn_software():
    packages = set()
    for protocol in VPN_PROTOCOLS.values():
        packages.update(protocol["packages"])
    subprocess.run(["sudo", "apt-get", "update"])
    subprocess.run(["sudo", "apt-get", "install", "-y", *packages])

# Function to generate unique PSK for each client user
def generate_psk():
    return ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))

# Function to add a new client user with a unique PSK
def add_client_user(username):
    psk_l2tp_ipsec = generate_psk()
    psk_ikev2_ipsec = generate_psk()
    subprocess.run(["sudo", "sh", "-c", f'echo "{username} l2tpd {psk_l2tp_ipsec}" >> /etc/ppp/chap-secrets'])
    subprocess.run(["sudo", "sh", "-c", f'echo ": PSK \"{psk_l2tp_ipsec}\"" >> /etc/ipsec.secrets'])
    subprocess.run(["sudo", "sh", "-c", f'echo ": PSK \"{psk_ikev2_ipsec}\"" >> /etc/ipsec.secrets'])
    print(f"Client user {username} added with L2TP/IPSec PSK: {psk_l2tp_ipsec} and IKEv2/IPsec PSK: {psk_ikev2_ipsec}")

# Function to generate VPN configuration files
def generate_config_files():
    for config_file, content in VPN_PROTOCOLS["xl2tpd"]["config_files"].items():
        with open(config_file, "a") as file:
            file.write(content)
    for config_file, content in VPN_PROTOCOLS["ipsec"]["config_files"].items():
        with open(config_file, "a") as file:
            file.write(content)
    for config_file, content in VPN_PROTOCOLS["wireguard"]["config_files"].items():
        with open(config_file, "w") as file:
            file.write(content)

# Function to restart VPN server
def restart_vpn_server():
    for protocol in VPN_PROTOCOLS.keys():
        subprocess.run(["sudo", "systemctl", "restart", protocol])

# Function to enable VPN services
def enable_vpn_services():
    for protocol in VPN_PROTOCOLS.keys():
        subprocess.run(["sudo", "systemctl", "enable", protocol])

import os
import mysql.connector
from mysql.connector import Error
import hashlib
import getpass

# Prompt the server administrator user for MySQL connection details
def prompt_mysql_details():
    host = input("Enter MySQL host: ")
    user = input("Enter MySQL user: ")
    password = getpass.getpass("Enter MySQL password: ")
    database = input("Enter MySQL database: ")
    return host, user, password, database

# Set environment variables for MySQL connection details
def set_environment_variables(host, user, password, database):
    os.environ["MYSQL_HOST"] = host
    os.environ["MYSQL_USER"] = user
    os.environ["MYSQL_PASSWORD"] = password
    os.environ["MYSQL_DATABASE"] = database

# Check if MySQL is running
def check_mysql_running():
    try:
        subprocess.check_output(["systemctl", "is-active", "mysql"])
        print("MySQL is running.")
    except subprocess.CalledProcessError:
        print("MySQL is not running. Please start the MySQL service.")
        exit(1)

# Check if server administrator user has necessary privileges
def check_mysql_privileges():
    host, user, password, database = prompt_mysql_details()
    set_environment_variables(host, user, password, database)
    try:
        connection = mysql.connector.connect(
            host=host,
            user=user,
            password=password,
            database=database
        )
        cursor = connection.cursor()
        cursor.execute("CREATE TABLE IF NOT EXISTS test_table (id INT)")
        cursor.execute("DROP TABLE test_table")
        print("Server administrator user has necessary privileges.")
    except Error as e:
        print("Server administrator user does not have necessary privileges. Please provide the correct credentials.")
        exit(1)
    finally:
        if connection:
            connection.close()

# Connect to MySQL database
def create_connection():
    host = os.getenv("MYSQL_HOST", "localhost")
    user = os.getenv("MYSQL_USER", "root")
    password = os.getenv("MYSQL_PASSWORD")
    database = os.getenv("MYSQL_DATABASE", "mydatabase")
    connection = None
    try:
        connection = mysql.connector.connect(
            host=host,
            user=user,
            password=password,
            database=database
        )
    except Error as e:
        print(f"Error connecting to MySQL database: {e}")
    return connection

# Generate a random password
def generate_password(length=12):
    characters = string.ascii_letters + string.digits + string.punctuation
    return ''.join(secrets.choice(characters) for _ in range(length))

# Hash a password using SHA256
def hash_password(password):
    salt = secrets.token_hex(16)
    hashed_password = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000)
    return f"{salt}${hashed_password.hex()}"

# Check if the provided password matches the stored password hash
def check_password(password, stored_password_hash):
    salt, hashed_password = stored_password_hash.split("$")
    return hashed_password == hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000).hex()

# Add a new user
def add_user(username, password, vpn_type, ssh_enabled=False, vpn_enabled=True):
    connection = create_connection()
    cursor = connection.cursor()
    try:
        hashed_password = hash_password(password)
        cursor.execute("""
            INSERT INTO users (username, password_hash, vpn_type, ssh_enabled, vpn_enabled)
            VALUES (%s, %s, %s, %s, %s)
        """, (username, hashed_password, vpn_type, ssh_enabled, vpn_enabled))
        connection.commit()
        print(f"User {username} added.")
    except Error as e:
        print(f"Error adding user: {e}")
    finally:
        if connection:
            connection.close()

# Connect to the VPN
def connect_to_vpn(username, password, vpn_type):
    connection = create_connection()
    cursor = connection.cursor()
    try:
        cursor.execute("""
            SELECT password_hash, vpn_enabled FROM users WHERE username=%s AND vpn_type=%s
        """, (username, vpn_type))
        result = cursor.fetchone()
        if result:
            stored_password_hash, vpn_enabled = result
            if vpn_enabled and check_password(password, stored_password_hash):
                print(f"Connected to {vpn_type} VPN as user {username}.")
            else:
                print("Invalid password or VPN not enabled.")
        else:
            print("User not found.")
    except Error as e:
        print(f"Error connecting to VPN: {e}")
    finally:
        if connection:
            connection.close()

# Update user information
def update_user_info(username, column, value):
    connection = create_connection()
    cursor = connection.cursor()
    try:
        cursor.execute(f"""
            UPDATE users SET {column}=%s WHERE username=%s
        """, (value, username))
        connection.commit()
        print(f"Updated {column} for user {username}.")
    except Error as e:
        print(f"Error updating user information: {e}")
    finally:
        if connection:
            connection.close
