import os
import subprocess
import secrets
import string
import getpass
import mysql.connector
from mysql.connector import Error
import hashlib

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

# MySQL setup and user management
def prompt_mysql_details():
    host = os.getenv("MYSQL_HOST", "localhost")
    user = os.getenv("MYSQL_USER", "root")
    password = os.getenv("MYSQL_PASSWORD")
    database = os.getenv("MYSQL_DATABASE", "mydatabase")
    return host, user, password, database

def set_environment_variables(host, user, password, database):
    os.environ["MYSQL_HOST"] = host
    os.environ["MYSQL_USER"] = user
    os.environ["MYSQL_PASSWORD"] = password
    os.environ["MYSQL_DATABASE"] = database

def check_mysql_running():
    try:
        subprocess.check_output(["systemctl", "is-active", "mysql"])
        print("MySQL is running.")
    except subprocess.CalledProcessError:
        print("MySQL is not running. Please start the MySQL service.")
        exit(1)

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
        print(f"Server administrator user does not have necessary privileges. Error: {e}")
        exit(1)
    finally:
        if connection:
            connection.close()

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

# VPN software installation
def install_vpn_software():
    packages = set()
    for protocol in VPN_PROTOCOLS.values():
        packages.update(protocol["packages"])
    subprocess.run(["sudo", "apt-get", "update"])
    subprocess.run(["sudo", "apt-get", "install", "-y", *packages])

# Generate PSKs and user passwords
def generate_psk():
    return ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))

def generate_password(length=12):
    characters = string.ascii_letters + string.digits + string.punctuation
    return ''.join(secrets.choice(characters) for _ in range(length))

def hash_password(password):
    salt = secrets.token_hex(16)
    hashed_password = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000)
    return f"{salt}${hashed_password.hex()}"

def check_password(password, stored_password_hash):
    salt, hashed_password = stored_password_hash.split("$")
    return hashed_password == hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000).hex()

# Add client user
def add_client_user(username):
    psk_l2tp_ipsec = generate_psk()
    psk_ikev2_ipsec = generate_psk()
    subprocess.run(["sudo", "sh", "-c", f'echo "{username} l2tpd {psk_l2tp_ipsec}" >> /etc/ppp/chap-secrets'])
    subprocess.run(["sudo", "sh", "-c", f'echo ": PSK \"{psk_l2tp_ipsec}\"" >> /etc/ipsec.secrets'])
    subprocess.run(["sudo", "sh", "-c", f'echo ": PSK \"{psk_ikev2_ipsec}\"" >> /etc/ipsec.secrets'])
    print(f"Client user {username} added with L2TP/IPSec PSK: {psk_l2tp_ipsec} and IKEv2/IPsec PSK: {psk_ikev2_ipsec}")

# VPN configuration files and service management
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

def restart_vpn_server():
    for protocol in VPN_PROTOCOLS.keys():
        subprocess.run(["sudo", "systemctl", "restart", protocol])

def enable_vpn_services():
    for protocol in VPN_PROTOCOLS.keys():
        subprocess.run(["sudo", "systemctl", "enable", protocol])

# Add user to database
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
            connection.close()

# Main menu
def main_menu():
    while True:
        print("\nUser Management")
        print("1. Add User")
        print("2. Connect to VPN")
        print("3. Update User Information")
        print("4. Exit")
        option = input("Choose an option: ")
        if option == "1":
            username = input("Enter username: ")
            password = getpass.getpass("Enter password: ")
            vpn_type = input("Enter VPN type (L2TP/IPsec, IKEv2/IPsec, WireGuard): ")
            add_user(username, password, vpn_type)
        elif option == "2":
            username = input("Enter username: ")
            password = getpass.getpass("Enter password: ")
            vpn_type = input("Enter VPN type: ")
            connect_to_vpn(username, password, vpn_type)
        elif option == "3":
            username = input("Enter username: ")
            column = input("Enter column to update (e.g., password_hash, vpn_enabled): ")
            value = input("Enter new value: ")
            update_user_info(username, column, value)
        elif option == "4":
            break
        else:
            print("Invalid option. Please choose again.")

# Run setup
if __name__ == "__main__":
    check_mysql_running()
    check_mysql_privileges()
    install_vpn_software()
    generate_config_files()
    restart_vpn_server()
    enable_vpn_services()
    main_menu()
