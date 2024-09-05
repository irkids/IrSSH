import os
import subprocess
import sys
import time
import requests
import shutil
import mysql.connector

# Helper function to print text with a delay
def print_with_delay(text, delay):
    for char in text:
        print(char, end='', flush=True)
        time.sleep(delay)
    print()

# Check if the script is run as root
def is_root():
    return os.geteuid() == 0

# Run a shell command and return the output
def run_command(command):
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.stdout.decode('utf-8')
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e}")
        return None

# Check if Python 3 is installed
def check_python():
    print("Checking if Python 3 is installed...")
    if sys.version_info[0] < 3:
        print("Python 3 is not installed. Please install Python 3 to continue.")
        sys.exit(1)
    print("Python 3 is installed.")

# Check if pip is installed
def check_pip():
    print("Checking if pip is installed...")
    try:
        subprocess.run(["pip3", "--version"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print("pip is installed.")
    except subprocess.CalledProcessError:
        print("pip is not installed. Installing pip...")
        subprocess.run(["apt-get", "update"], check=True)
        subprocess.run(["apt-get", "install", "-y", "python3-pip"], check=True)
        print("pip has been installed successfully.")

# Install required Python packages
def install_packages():
    print("Installing required Python packages...")
    packages = ["requests", "mysql-connector-python"]
    for package in packages:
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", package], check=True)
            print(f"{package} installed successfully.")
        except subprocess.CalledProcessError:
            print(f"Failed to install {package}. Exiting.")
            sys.exit(1)

# Set DNS configuration
def set_dns():
    print("Setting DNS configuration...")
    try:
        with open('/etc/resolv.conf', 'w') as f:
            f.write("#shahanDNS\nnameserver 8.8.8.8\n")
        print("DNS configuration set successfully.")
    except Exception as e:
        print(f"Failed to set DNS configuration: {e}")

# Get current panel port
def get_panel_port():
    print("Fetching current panel port...")
    command = "lsof -i -P -n | grep -i LISTEN | grep apache2 | awk '{if(!seen[$9]++)print $9;exit}'"
    panel_port_tmp = run_command(command)
    if panel_port_tmp:
        panel_port = ''.join(filter(str.isdigit, panel_port_tmp))
        print(f"Panel is running on port: {panel_port}")
        return panel_port
    else:
        print("Failed to retrieve panel port. Defaulting to 8080.")
        return "8080"

# Modify SSH configuration
def modify_ssh_config():
    print("Modifying SSH configuration...")
    ssh_config_path = '/etc/ssh/sshd_config'
    try:
        # Uncomment the Port 22 line if it's commented
        run_command(f"sed -i 's/#Port 22/Port 22/' {ssh_config_path}")
        with open(ssh_config_path, 'r') as f:
            ssh_config = f.read()
        port = next((line.split()[1] for line in ssh_config.splitlines() if line.startswith('Port')), '22')
        print(f"SSH is set to listen on port: {port}")
    except Exception as e:
        print(f"Failed to modify SSH configuration: {e}")

# Connect to MySQL and fetch admin credentials
def fetch_admin_credentials():
    print("Connecting to MySQL to fetch admin credentials...")
    try:
        db = mysql.connector.connect(
            host="localhost",
            user="root",
            password="root_password",  # Replace with your actual MySQL root password
            database="ShaHaN"
        )
        cursor = db.cursor()
        cursor.execute("SELECT adminuser, adminpassword FROM setting WHERE id='1'")
        result = cursor.fetchone()
        admin_user, admin_pass = result if result else ("admin", "123456")
        print(f"Admin credentials fetched: {admin_user}")
        return admin_user, admin_pass
    except mysql.connector.Error as err:
        print(f"Error connecting to MySQL: {err}")
        print("Using default admin credentials.")
        return "admin", "123456"
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'db' in locals() and db.is_connected():
            db.close()

# Download scripts and binaries
def download_scripts():
    print("Downloading scripts and binaries...")
    urls = [
        ("https://raw.githubusercontent.com/HamedAp/Ssh-User-management/main/screenshot/shahan", "/usr/local/bin/shahan"),
        ("https://raw.githubusercontent.com/HamedAp/Ssh-User-management/main/screenshot/shahancheck", "/usr/local/bin/shahancheck"),
        ("https://github.com/HamedAp/Ssh-User-management/raw/main/tls.sh.x", "/root/tls.sh.x"),
        ("https://github.com/HamedAp/Ssh-User-management/raw/main/shadow.sh.x", "/root/shadow.sh.x"),
        ("https://github.com/HamedAp/Ssh-User-management/raw/main/signbox.sh.x", "/root/signbox.sh.x"),
        ("https://github.com/HamedAp/Ssh-User-management/raw/main/updatesignbox.sh.x", "/root/updatesignbox.sh.x")
    ]
    
    for url, path in urls:
        try:
            response = requests.get(url)
            if response.status_code == 200:
                with open(path, 'wb') as f:
                    f.write(response.content)
                os.chmod(path, 0o755)
                print(f"Downloaded and set permissions for {path}.")
            else:
                print(f"Failed to download {url}. Status code: {response.status_code}")
        except Exception as e:
            print(f"Error downloading {url}: {e}")

# Add new APT sources if not present
def add_apt_sources():
    print("Checking and adding APT sources if necessary...")
    sources_list_path = '/etc/apt/sources.list'
    try:
        with open(sources_list_path, 'r') as f:
            sources_list = f.read()
        
        if 'shahansources' not in sources_list:
            print("Adding new APT sources...")
            run_command("sed -i '/shahansources/d' /etc/apt/sources.list")
            run_command("sed -i '/ubuntu focal main restricted universe/d' /etc/apt/sources.list")
            run_command("sed -i '/ubuntu focal-updates main restricted universe/d' /etc/apt/sources.list")
            run_command("sed -i '/ubuntu focal-security main restricted universe multiverse/d' /etc/apt/sources.list")
            run_command("sed -i '/ubuntu focal partner/d' /etc/apt/sources.list")
            with open(sources_list_path, 'a') as f:
                f.write("""
#shahansources
deb http://archive.ubuntu.com/ubuntu focal main restricted universe
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
deb http://archive.canonical.com/ubuntu focal partner
                """)
            print("APT sources added successfully.")
            run_command("apt-get update")
        else:
            print("APT sources already present.")
    except Exception as e:
        print(f"Failed to add APT sources: {e}")

# Clear the terminal
def clear_terminal():
    os.system('clear')

# Setup videocall service
def setup_videocall_service():
    print("Setting up videocall service...")
    videocall_service_path = '/etc/systemd/system/videocall.service'
    if not os.path.exists(videocall_service_path):
        udp_port = input("Default Port is 7300, press Enter to use this Port or enter a new one: ") or "7300"
        try:
            with open(videocall_service_path, 'w') as f:
                f.write(f"""
[Unit]
Description=UDP forwarding for badvpn-tun2socks
After=nss-lookup.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:{udp_port} --max-clients 999
User=videocall

[Install]
WantedBy=multi-user.target
                """)
            run_command("useradd -m videocall")
            run_command("systemctl enable videocall")
            run_command("systemctl start videocall")
            print("videocall service setup successfully.")
        except Exception as e:
            print(f"Failed to set up videocall service: {e}")
    else:
        print("videocall service already exists.")

# Proceed with admin input if necessary
def admin_input(admin_user, admin_pass):
    if not admin_user:
        admin_user = input(f"Default user name is {admin_user}, press Enter to use this user name: ") or admin_user
    if not admin_pass:
        admin_pass = input(f"Default password is {admin_pass}, press Enter to use this password: ") or admin_pass
    return admin_user, admin_pass

# Main installation and configuration function
def main_installation():
    # Set DNS
    set_dns()
    
    # Get panel port
    panel_port = get_panel_port()
    
    # Modify SSH config
    modify_ssh_config()
    
    # Fetch admin credentials
    admin_user, admin_pass = fetch_admin_credentials()
    
    # Download necessary scripts and binaries
    download_scripts()
    
    # Add APT sources if necessary
    add_apt_sources()
    
    # Clear terminal
    clear_terminal()
    
    # Print installation messages
    print_with_delay("ShaHaN Panel Installation :) By HamedAp", 0.1)
    print_with_delay("Please Wait . . .", 0.1)
    
    # Proceed with admin input
    admin_user, admin_pass = admin_input(admin_user, admin_pass)
    
    # Setup videocall service
    setup_videocall_service()
    
    # Additional installation steps can be added here
    # For example: setting up firewall rules, configuring services, etc.

    print("Installation and configuration completed successfully.")

# Function to create SSH user
def create_ssh_user(username, password):
    print(f"Creating SSH user: {username}")
    command = f"useradd -m {username} && echo '{username}:{password}' | chpasswd"
    run_command(command)
    print(f"SSH user {username} created successfully.")

# Function to create MySQL user
def create_mysql_user(username, password):
    print(f"Creating MySQL user: {username}")
    try:
        connection = mysql.connector.connect(
            host='localhost',
            user='root',
            password='root_password',  # Replace with your actual MySQL root password
        )
        cursor = connection.cursor()
        cursor.execute(f"CREATE USER '{username}'@'localhost' IDENTIFIED BY '{password}';")
        cursor.execute(f"GRANT ALL PRIVILEGES ON *.* TO '{username}'@'localhost';")
        connection.commit()
        print(f"MySQL user {username} created successfully.")
    except mysql.connector.Error as err:
        print(f"Error: {err}")
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'connection' in locals() and connection.is_connected():
            connection.close()

# Function to display the main menu
def main_menu():
    while True:
        print("\n--- ShaHaN Panel Main Menu ---")
        print("1. Create SSH User")
        print("2. Create MySQL User")
        print("3. Install Protocols")
        print("4. Check Panel Status")
        print("5. Exit")
        choice = input("Enter your choice: ")

        if choice == '1':
            username = input("Enter SSH username: ")
            password = input("Enter SSH password: ")
            create_ssh_user(username, password)
        elif choice == '2':
            username = input("Enter MySQL username: ")
            password = input("Enter MySQL password: ")
            create_mysql_user(username, password)
        elif choice == '3':
            install_protocols_menu()
        elif choice == '4':
            check_panel_status()
        elif choice == '5':
            print("Exiting...")
            sys.exit(0)
        else:
            print("Invalid choice. Please try again.")

# Function to install protocols
def install_protocols_menu():
    while True:
        print("\n--- Install Protocols Menu ---")
        print("1. Install Protocol A")
        print("2. Install Protocol B")
        print("3. Back to Main Menu")
        choice = input("Enter your choice: ")

        if choice == '1':
            install_protocol_a()
        elif choice == '2':
            install_protocol_b()
        elif choice == '3':
            break
        else:
            print("Invalid choice. Please try again.")

# Placeholder functions for protocol installations
def install_protocol_a():
    print("Installing Protocol A...")
    # Add actual installation commands here
    time.sleep(2)
    print("Protocol A installed successfully.")

def install_protocol_b():
    print("Installing Protocol B...")
    # Add actual installation commands here
    time.sleep(2)
    print("Protocol B installed successfully.")

# Function to check panel status
def check_panel_status():
    print("Checking panel status...")
    # Add actual status checking commands here
    status = run_command("systemctl status apache2")
    if status:
        print("Apache2 is running.")
    else:
        print("Apache2 is not running.")

# Main function
def main():
    if not is_root():
        print("Sorry, you need to run this script as root.")
        sys.exit(1)
    
    check_python()
    check_pip()
    install_packages()
    main_installation()
    main_menu()

if __name__ == "__main__":
    main()
