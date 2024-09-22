import os
import subprocess
import secrets
import string
import getpass
import mysql.connector
from mysql.connector import Error
import hashlib

# Prompt the server administrator user for MySQL connection details
def prompt_mysql_details():
    host = os.getenv("MYSQL_HOST", "localhost")
    user = os.getenv("MYSQL_USER", "root")
    password = os.getenv("MYSQL_PASSWORD")
    database = os.getenv("MYSQL_DATABASE", "mydatabase")
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
            vpn_type = input("Enter VPN type (SSH, IKEv2-PSK, L2TP-PSK): ")
            ssh_enabled = input("Enable SSH access? (yes/no): ").lower() == "yes"
            vpn_enabled = input("Enable VPN access? (yes/no): ").lower() == "yes"
            add_user(username, password, vpn_type, ssh_enabled, vpn_enabled)
        elif option == "2":
            username = input("Enter username: ")
            password = getpass.getpass("Enter password: ")
            vpn_type = input("Enter VPN type (SSH, IKEv2-PSK, L2TP-PSK): ")
            connect_to_vpn(username, password, vpn_type)
        elif option == "3":
            username = input("Enter username: ")
            column = input("Enter column to update (username, password, vpn_type, ssh_enabled, vpn_enabled): ")
            value = input("Enter new value: ")
            update_user_info(username, column, value)
        elif option == "4":
            break
        else:
            print("Invalid option. Try again.")

# Run the main menu
if __name__ == "__main__":
    check_mysql_running()
    check_mysql_privileges()
    main_menu()
