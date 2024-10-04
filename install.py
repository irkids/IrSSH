import os
import subprocess
import secrets
import string
import getpass
import mysql.connector
from mysql.connector import Error, pooling
import hashlib
import re
import logging
import paramiko
import pyotp
import wireguard
from cryptography.fernet import Fernet
import netifaces
import ipaddress
import socket
import fcntl
import struct

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Database configuration
DB_CONFIG = {
    'host': 'localhost',
    'database': 'vpn_users',
    'user': 'vpn_admin',
    'password': 'your_secure_password'
}

# VPN Server configuration
VPN_CONFIG = {
    'public_ip': 'your_public_ip',
    'ssh_port': 22,
    'l2tp_port': 1701,
    'ipsec_port': 500,
    'ikev2_port': 4500,
    'wireguard_port': 51820,
    'anyconnect_port': 443
}

def create_database_connection():
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        if connection.is_connected():
            return connection
    except Error as e:
        logging.error(f"Error connecting to MySQL database: {e}")
    return None

def setup_database():
    connection = create_database_connection()
    if connection is None:
        return

    cursor = connection.cursor()
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(50) UNIQUE NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                ssh_enabled BOOLEAN DEFAULT FALSE,
                l2tp_enabled BOOLEAN DEFAULT FALSE,
                ikev2_enabled BOOLEAN DEFAULT FALSE,
                wireguard_enabled BOOLEAN DEFAULT FALSE,
                anyconnect_enabled BOOLEAN DEFAULT FALSE,
                wireguard_private_key VARCHAR(255),
                wireguard_public_key VARCHAR(255),
                anyconnect_cert VARCHAR(2048),
                totp_secret VARCHAR(32),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_login TIMESTAMP
            )
        """)
        connection.commit()
        logging.info("Database setup completed successfully")
    except Error as e:
        logging.error(f"Error setting up database: {e}")
    finally:
        cursor.close()
        connection.close()

def get_interface_ip(ifname):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    return socket.inet_ntoa(fcntl.ioctl(
        s.fileno(),
        0x8915,  # SIOCGIFADDR
        struct.pack('256s', ifname[:15].encode('utf-8'))
    )[20:24])

def get_public_ip():
    try:
        return subprocess.check_output(['curl', '-s', 'https://api.ipify.org']).decode('utf-8').strip()
    except subprocess.CalledProcessError:
        logging.warning("Could not determine public IP. Using default.")
        return VPN_CONFIG['public_ip']

def initialize_vpn_config():
    VPN_CONFIG['public_ip'] = get_public_ip()
    interfaces = netifaces.interfaces()
    for interface in interfaces:
        if interface.startswith('eth') or interface.startswith('ens'):
            try:
                VPN_CONFIG['private_ip'] = get_interface_ip(interface)
                break
            except IOError:
                continue
    
    if 'private_ip' not in VPN_CONFIG:
        logging.error("Could not determine private IP address.")
        VPN_CONFIG['private_ip'] = '10.0.0.1'  # Fallback to a default private IP

# Initialize VPN configuration
initialize_vpn_config()

# Set up the database
setup_database()
# User management and authentication functions

def generate_password(length=16):
    characters = string.ascii_letters + string.digits + string.punctuation
    return ''.join(secrets.choice(characters) for _ in range(length))

def hash_password(password):
    salt = secrets.token_hex(16)
    hashed_password = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 200000)
    return f"{salt}${hashed_password.hex()}"

def check_password(password, stored_password_hash):
    salt, hashed_password = stored_password_hash.split("$")
    return hashed_password == hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 200000).hex()

def validate_input(input_string, input_type):
    if input_type == "username":
        return re.match(r'^[a-zA-Z0-9_-]{3,16}$', input_string) is not None
    elif input_type == "vpn_type":
        return input_string in ["SSH", "L2TP", "IKEv2", "WireGuard", "AnyConnect"]
    return True

def add_user(username, password, vpn_types):
    if not validate_input(username, "username"):
        logging.error("Invalid username. It should be 3-16 characters long and contain only letters, numbers, underscores, and hyphens.")
        return

    connection = create_database_connection()
    if not connection:
        return

    cursor = connection.cursor()
    try:
        hashed_password = hash_password(password)
        totp_secret = pyotp.random_base32()
        
        cursor.execute("""
            INSERT INTO users (username, password_hash, totp_secret, 
                               ssh_enabled, l2tp_enabled, ikev2_enabled, 
                               wireguard_enabled, anyconnect_enabled)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (username, hashed_password, totp_secret, 
              "SSH" in vpn_types, "L2TP" in vpn_types, "IKEv2" in vpn_types, 
              "WireGuard" in vpn_types, "AnyConnect" in vpn_types))
        
        connection.commit()
        logging.info(f"User {username} added successfully.")

        if "WireGuard" in vpn_types:
            private_key, public_key = wireguard.generate_keypair()
            cursor.execute("""
                UPDATE users SET wireguard_private_key = %s, wireguard_public_key = %s
                WHERE username = %s
            """, (private_key, public_key, username))
            connection.commit()
            logging.info(f"WireGuard keys generated for user {username}")

        if "AnyConnect" in vpn_types:
            cert = generate_anyconnect_cert(username)
            cursor.execute("""
                UPDATE users SET anyconnect_cert = %s
                WHERE username = %s
            """, (cert, username))
            connection.commit()
            logging.info(f"AnyConnect certificate generated for user {username}")

    except Error as e:
        logging.error(f"Error adding user: {e}")
    finally:
        cursor.close()
        connection.close()

def authenticate_user(username, password, vpn_type):
    connection = create_database_connection()
    if not connection:
        return False

    cursor = connection.cursor()
    try:
        cursor.execute(f"""
            SELECT password_hash, {vpn_type.lower()}_enabled 
            FROM users WHERE username = %s
        """, (username,))
        result = cursor.fetchone()
        
        if result:
            stored_password_hash, vpn_enabled = result
            if vpn_enabled and check_password(password, stored_password_hash):
                return True
        
        logging.warning(f"Authentication failed for user {username}")
        return False
    except Error as e:
        logging.error(f"Error authenticating user: {e}")
        return False
    finally:
        cursor.close()
        connection.close()

def update_user_info(username, column, value):
    if not validate_input(username, "username"):
        logging.error("Invalid username.")
        return

    connection = create_database_connection()
    if not connection:
        return

    cursor = connection.cursor()
    try:
        if column == "password":
            value = hash_password(value)
        cursor.execute(f"""
            UPDATE users SET {column} = %s WHERE username = %s
        """, (value, username))
        connection.commit()
        logging.info(f"Updated {column} for user {username}.")

        if column == "wireguard_enabled" and value:
            private_key, public_key = wireguard.generate_keypair()
            cursor.execute("""
                UPDATE users SET wireguard_private_key = %s, wireguard_public_key = %s
                WHERE username = %s
            """, (private_key, public_key, username))
            connection.commit()
            logging.info(f"WireGuard keys generated for user {username}")

        if column == "anyconnect_enabled" and value:
            cert = generate_anyconnect_cert(username)
            cursor.execute("""
                UPDATE users SET anyconnect_cert = %s
                WHERE username = %s
            """, (cert, username))
            connection.commit()
            logging.info(f"AnyConnect certificate generated for user {username}")

    except Error as e:
        logging.error(f"Error updating user information: {e}")
    finally:
        cursor.close()
        connection.close()

def generate_anyconnect_cert(username):
    # This is a placeholder function. In a real-world scenario, you would use a proper
    # certificate authority to generate and sign certificates for AnyConnect clients.
    return f"PLACEHOLDER_CERT_FOR_{username}"

def get_user_vpn_config(username, vpn_type):
    connection = create_database_connection()
    if not connection:
        return None

    cursor = connection.cursor()
    try:
        if vpn_type == "WireGuard":
            cursor.execute("""
                SELECT wireguard_private_key, wireguard_public_key 
                FROM users WHERE username = %s
            """, (username,))
        elif vpn_type == "AnyConnect":
            cursor.execute("""
                SELECT anyconnect_cert 
                FROM users WHERE username = %s
            """, (username,))
        else:
            cursor.execute(f"""
                SELECT {vpn_type.lower()}_enabled 
                FROM users WHERE username = %s
            """, (username,))
        
        result = cursor.fetchone()
        if result:
            return result[0]
        else:
            logging.error(f"VPN configuration not found for user {username}")
            return None
    except Error as e:
        logging.error(f"Error retrieving VPN configuration: {e}")
        return None
    finally:
        cursor.close()
        connection.close()
# VPN protocol setup and management functions

def setup_ssh_server():
    try:
        # Install OpenSSH server if not already installed
        subprocess.run(["sudo", "apt-get", "update"], check=True)
        subprocess.run(["sudo", "apt-get", "install", "-y", "openssh-server"], check=True)

        # Configure SSH server
        ssh_config = f"""
        Port {VPN_CONFIG['ssh_port']}
        PermitRootLogin no
        PasswordAuthentication yes
        PubkeyAuthentication yes
        AllowUsers vpn_*
        """
        
        with open("/etc/ssh/sshd_config", "w") as f:
            f.write(ssh_config)

        # Restart SSH service
        subprocess.run(["sudo", "systemctl", "restart", "ssh"], check=True)

        logging.info("SSH server setup completed successfully")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error setting up SSH server: {e}")

def setup_l2tp_server():
    try:
        # Install L2TP/IPsec packages
        subprocess.run(["sudo", "apt-get", "update"], check=True)
        subprocess.run(["sudo", "apt-get", "install", "-y", "strongswan", "xl2tpd"], check=True)

        # Configure IPsec
        ipsec_config = f"""
        config setup
            charondebug="ike 1, knl 1, cfg 0"
            uniqueids=no

        conn L2TP-PSK-NAT
            type=transport
            keyexchange=ikev1
            authby=secret
            leftprotoport=17/1701
            left=%any
            rightprotoport=17/1701
            right=%any
            rekey=no
            forceencaps=yes
            ike=aes128-sha1-modp2048
            esp=aes128-sha1
            auto=add
        """
        
        with open("/etc/ipsec.conf", "w") as f:
            f.write(ipsec_config)

        # Configure xl2tpd
        xl2tpd_config = f"""
        [global]
        ipsec saref = yes
        saref refinfo = 30

        [lns default]
        ip range = 10.10.10.100-10.10.10.200
        local ip = 10.10.10.1
        refuse chap = yes
        refuse pap = yes
        require authentication = yes
        ppp debug = yes
        pppoptfile = /etc/ppp/options.xl2tpd
        length bit = yes
        """
        
        with open("/etc/xl2tpd/xl2tpd.conf", "w") as f:
            f.write(xl2tpd_config)

        # Configure PPP options
        ppp_options = """
        ipcp-accept-local
        ipcp-accept-remote
        ms-dns 8.8.8.8
        ms-dns 8.8.4.4
        noccp
        auth
        crtscts
        idle 1800
        mtu 1280
        mru 1280
        lcp-echo-failure 4
        lcp-echo-interval 30
        default-asyncmap
        mppe-stateful
        """
        
        with open("/etc/ppp/options.xl2tpd", "w") as f:
            f.write(ppp_options)

        # Restart services
        subprocess.run(["sudo", "systemctl", "restart", "strongswan"], check=True)
        subprocess.run(["sudo", "systemctl", "restart", "xl2tpd"], check=True)

        logging.info("L2TP/IPsec server setup completed successfully")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error setting up L2TP/IPsec server: {e}")

def setup_ikev2_server():
    try:
        # Install strongSwan if not already installed
        subprocess.run(["sudo", "apt-get", "update"], check=True)
        subprocess.run(["sudo", "apt-get", "install", "-y", "strongswan", "strongswan-pki", "libcharon-extra-plugins", "libcharon-extauth-plugins", "libstrongswan-extra-plugins"], check=True)

        # Generate CA and server certificates
        subprocess.run(["sudo", "mkdir", "-p", "/etc/ipsec.d/private", "/etc/ipsec.d/cacerts", "/etc/ipsec.d/certs"], check=True)
        subprocess.run(["sudo", "strongswan", "pki", "--gen", "--type", "rsa", "--size", "4096", "--outform", "pem", ">" "/etc/ipsec.d/private/ca-key.pem"], check=True)
        subprocess.run(["sudo", "strongswan", "pki", "--self", "--ca", "--lifetime", "3650", "--in", "/etc/ipsec.d/private/ca-key.pem", "--type", "rsa", "--dn", f"CN=VPN CA", "--outform", "pem", ">" "/etc/ipsec.d/cacerts/ca-cert.pem"], check=True)
        subprocess.run(["sudo", "strongswan", "pki", "--gen", "--type", "rsa", "--size", "4096", "--outform", "pem", ">" "/etc/ipsec.d/private/server-key.pem"], check=True)
        subprocess.run(["sudo", "strongswan", "pki", "--pub", "--in", "/etc/ipsec.d/private/server-key.pem", "--type", "rsa", "|", "strongswan", "pki", "--issue", "--lifetime", "1825", "--cacert", "/etc/ipsec.d/cacerts/ca-cert.pem", "--cakey", "/etc/ipsec.d/private/ca-key.pem", "--dn", f"CN={VPN_CONFIG['public_ip']}", "--san", VPN_CONFIG['public_ip'], "--flag", "serverAuth", "--flag", "ikeIntermediate", "--outform", "pem", ">" "/etc/ipsec.d/certs/server-cert.pem"], check=True)

        # Configure strongSwan
        ipsec_config = f"""
        config setup
            charondebug="ike 1, knl 1, cfg 0"
            uniqueids=no

        conn ikev2-vpn
            auto=add
            compress=no
            type=tunnel
            keyexchange=ikev2
            fragmentation=yes
            forceencaps=yes
            ike=aes256-sha1-modp1024,3des-sha1-modp1024!
            esp=aes256-sha1,3des-sha1!
            dpdaction=clear
            dpddelay=300s
            rekey=no
            left=%any
            leftid=@server
            leftcert=server-cert.pem
            leftsendcert=always
            leftsubnet=0.0.0.0/0
            right=%any
            rightid=%any
            rightauth=eap-mschapv2
            rightsourceip=10.10.10.0/24
            rightdns=8.8.8.8,8.8.4.4
            rightsendcert=never
            eap_identity=%identity
        """
        
        with open("/etc/ipsec.conf", "w") as f:
            f.write(ipsec_config)

        # Restart strongSwan service
        subprocess.run(["sudo", "systemctl", "restart", "strongswan-starter"], check=True)

        logging.info("IKEv2 server setup completed successfully")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error setting up IKEv2 server: {e}")

def setup_wireguard_server():
    try:
        # Install WireGuard
        subprocess.run(["sudo", "apt-get", "update"], check=True)
        subprocess.run(["sudo", "apt-get", "install", "-y", "wireguard"], check=True)

        # Generate server keys
        private_key = subprocess.check_output(["wg", "genkey"]).decode().strip()
        public_key = subprocess.check_output(["echo", private_key, "|", "wg", "pubkey"]).decode().strip()

        # Configure WireGuard
        wg_config = f"""
        [Interface]
        PrivateKey = {private_key}
        Address = 10.0.0.1/24
        ListenPort = {VPN_CONFIG['wireguard_port']}
        SaveConfig = true
        PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
        PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
        """
        
        with open("/etc/wireguard/wg0.conf", "w") as f:
            f.write(wg_config)

        # Enable IP forwarding
        subprocess.run(["sudo", "sysctl", "-w", "net.ipv4.ip_forward=1"], check=True)
        subprocess.run(["sudo", "sysctl", "-p"], check=True)

        # Start WireGuard
        subprocess.run(["sudo", "systemctl", "enable", "wg-quick@wg0"], check=True)
        subprocess.run(["sudo", "systemctl", "start", "wg-quick@wg0"], check=True)

        logging.info("WireGuard server setup completed successfully")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error setting up WireGuard server: {e}")

def setup_anyconnect_server():
    try:
        # Install OpenConnect server
        subprocess.run(["sudo", "apt-get", "update"], check=True)
        subprocess.run(["sudo", "apt-get", "install", "-y", "ocserv"], check=True)

        # Generate self-signed certificate
        subprocess.run(["sudo", "certtool", "--generate-privkey", "--outfile", "/etc/ssl/private/ocserv.pem"], check=True)
        
        cert_template = f"""
        cn = "{VPN_CONFIG['public_ip']}"
        organization = "VPN Server"
        expiration_days = 3650
        signing_key
        encryption_key
        tls_www_server
        """
        
        with open("/tmp/ocserv.tmpl", "w") as f:
            f.write(cert_template)
        
        subprocess.run(["sudo", "certtool", "--generate-self-signed", "--load-privkey", "/etc/ssl/private/ocserv.pem", "--template", "/tmp/ocserv.tmpl", "--outfile", "/etc/ssl/certs/ocserv.pem"], check=True)

        # Configure OpenConnect server
        ocserv_config = f"""
        auth = "plain[/etc/ocserv/ocpasswd]"
        tcp-port = {VPN_CONFIG['anyconnect_port']}
        udp-port = {VPN_CONFIG['anyconnect_port']}
        run-as-user = nobody
        run-as-group = daemon
        socket-file = /var/run/ocserv-socket
        server-cert = /etc/ssl/certs/ocserv.pem
        server-key = /etc/ssl/private/ocserv.pem
        ca-cert = /etc/ssl/certs/ocserv.pem
        isolate-workers = true
        max-clients = 0
        max-same-clients = 0
        server-stats-reset-time = 604800
        keepalive = 32400
        dpd = 90
        mobile-dpd = 1800
        switch-to-tcp-timeout = 25
        try-mtu-discovery = true
        cert-user-oid = 0.9.2342.19200300.100.1.1
        tls-priorities = "NORMAL:%SERVER_PRECEDENCE:%COMPAT:-VERS-SSL3.0"
        auth-timeout = 240
        min-reauth-time = 300
        max-ban-score = 50
        ban-reset-time = 300
        cookie-timeout = 300
        deny-roaming = false
        rekey-time = 172800
        rekey-method = ssl
        use-occtl = true
        pid-file = /var/run/ocserv.pid
        device = vpns
        predictable-ips = true
        ipv4-network = 192.168.1.0
        ipv4-netmask = 255.255.255.0
        dns = 8.8.8.8
        dns = 8.8.4.4
        ping-leases = false
        route = default
        no-route = 192.168.1.0/255.255.255.0
        cisco-client-compat = true
        dtls-legacy = true
        """
        
        with open("/etc/ocserv/ocserv.conf", "w") as f:
            f.write(ocserv_config)

        # Enable IP forwarding
        subprocess.run(["sudo", "sysctl", "-w", "net.ipv4.ip_forward=1"], check=True)
        subprocess.run(["sudo", "sysctl", "-p"], check=True)

        # Configure NAT
        subprocess.run(["sudo", "iptables", "-t", "nat", "-A", "POSTROUTING", "-j", "MASQUERADE"], check=True)
        subprocess.run(["sudo", "iptables-save", ">", "/etc/iptables.rules"], check=True)

        # Start OpenConnect server
        subprocess.run(["sudo", "systemctl", "enable", "ocserv"], check=True)
        subprocess.run(["sudo", "systemctl", "start", "ocserv"], check=True)

        logging.info("Cisco AnyConnect (OpenConnect) server setup completed successfully")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error setting up Cisco AnyConnect (OpenConnect) server: {e}")

def setup_all_vpn_servers():
    setup_ssh_server()
    setup_l2tp_server()
    setup_ikev2_server()
    setup_wireguard_server()
    setup_anyconnect_server()
    logging.info("All VPN servers have been set up successfully")

# Main program and user interface

def print_menu():
    print("\nVPN Server Management")
    print("1. Add User")
    print("2. Update User")
    print("3. Delete User")
    print("4. List Users")
    print("5. Setup VPN Servers")
    print("6. Start/Stop VPN Services")
    print("7. View Server Status")
    print("8. Exit")

def add_user_menu():
    username = input("Enter username: ")
    password = getpass.getpass("Enter password: ")
    vpn_types = []
    print("Select VPN types (comma-separated):")
    print("1. SSH, 2. L2TP, 3. IKEv2, 4. WireGuard, 5. AnyConnect")
    choices = input("Enter your choices: ").split(',')
    vpn_map = {
        '1': 'SSH',
        '2': 'L2TP',
        '3': 'IKEv2',
        '4': 'WireGuard',
        '5': 'AnyConnect'
    }
    vpn_types = [vpn_map[choice.strip()] for choice in choices if choice.strip() in vpn_map]
    add_user(username, password, vpn_types)

def update_user_menu():
    username = input("Enter username to update: ")
    print("Select field to update:")
    print("1. Password")
    print("2. VPN Access")
    choice = input("Enter your choice: ")
    if choice == '1':
        new_password = getpass.getpass("Enter new password: ")
        update_user_info(username, 'password', new_password)
    elif choice == '2':
        print("Select VPN type to update:")
        print("1. SSH, 2. L2TP, 3. IKEv2, 4. WireGuard, 5. AnyConnect")
        vpn_choice = input("Enter your choice: ")
        vpn_map = {
            '1': 'ssh_enabled',
            '2': 'l2tp_enabled',
            '3': 'ikev2_enabled',
            '4': 'wireguard_enabled',
            '5': 'anyconnect_enabled'
        }
        if vpn_choice in vpn_map:
            new_value = input("Enable access? (yes/no): ").lower() == 'yes'
            update_user_info(username, vpn_map[vpn_choice], new_value)
        else:
            print("Invalid choice")
    else:
        print("Invalid choice")

def delete_user_menu():
    username = input("Enter username to delete: ")
    confirm = input(f"Are you sure you want to delete user {username}? (yes/no): ")
    if confirm.lower() == 'yes':
        delete_user(username)
    else:
        print("User deletion cancelled")

def list_users_menu():
    connection = create_database_connection()
    if not connection:
        return

    cursor = connection.cursor()
    try:
        cursor.execute("""
            SELECT username, ssh_enabled, l2tp_enabled, ikev2_enabled, 
                   wireguard_enabled, anyconnect_enabled, created_at, last_login
            FROM users
        """)
        users = cursor.fetchall()
        
        print("\nUser List:")
        print("Username | SSH | L2TP | IKEv2 | WireGuard | AnyConnect | Created At | Last Login")
        print("-" * 80)
        for user in users:
            print(f"{user[0]} | {'✓' if user[1] else 'x'} | {'✓' if user[2] else 'x'} | {'✓' if user[3] else 'x'} | {'✓' if user[4] else 'x'} | {'✓' if user[5] else 'x'} | {user[6]} | {user[7] or 'Never'}")
    except Error as e:
        logging.error(f"Error listing users: {e}")
    finally:
        cursor.close()
        connection.close()

def setup_vpn_servers_menu():
    print("\nSetting up VPN servers...")
    setup_all_vpn_servers()
    print("VPN servers setup completed.")

def start_stop_vpn_services_menu():
    print("\nVPN Services:")
    print("1. SSH")
    print("2. L2TP/IPsec")
    print("3. IKEv2")
    print("4. WireGuard")
    print("5. AnyConnect (OpenConnect)")
    choice = input("Enter the number of the service to start/stop: ")
    action = input("Enter 'start' or 'stop': ")
    
    service_map = {
        '1': 'ssh',
        '2': 'xl2tpd',
        '3': 'strongswan-starter',
        '4': 'wg-quick@wg0',
        '5': 'ocserv'
    }
    
    if choice in service_map:
        try:
            subprocess.run(["sudo", "systemctl", action, service_map[choice]], check=True)
            print(f"{service_map[choice]} service {action}ed successfully.")
        except subprocess.CalledProcessError as e:
            logging.error(f"Error {action}ing {service_map[choice]} service: {e}")
    else:
        print("Invalid choice")

def view_server_status_menu():
    print("\nVPN Server Status:")
    services = ['ssh', 'xl2tpd', 'strongswan-starter', 'wg-quick@wg0', 'ocserv']
    
    for service in services:
        try:
            result = subprocess.run(["systemctl", "is-active", service], capture_output=True, text=True)
            status = result.stdout.strip()
            print(f"{service}: {status}")
        except subprocess.CalledProcessError as e:
            logging.error(f"Error checking status of {service}: {e}")

def main():
    while True:
        print_menu()
        choice = input("Enter your choice: ")
        
        if choice == '1':
            add_user_menu()
        elif choice == '2':
            update_user_menu()
        elif choice == '3':
            delete_user_menu()
        elif choice == '4':
            list_users_menu()
        elif choice == '5':
            setup_vpn_servers_menu()
        elif choice == '6':
            start_stop_vpn_services_menu()
        elif choice == '7':
            view_server_status_menu()
        elif choice == '8':
            print("Exiting...")
            break
        else:
            print("Invalid choice. Please try again.")

if __name__ == "__main__":
    main()
