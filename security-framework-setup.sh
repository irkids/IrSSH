#!/bin/bash

# Part 8: Security Framework Setup
# This script handles the security components installation and configuration

# Set error handling
set -euo pipefail
trap 'echo "Error on line $LINENO. Exit code: $?"' ERR

# Load common functions and variables
source ./common/utils.sh
source ./common/config.sh

log_section "Starting Security Framework Installation"

# Function to install security dependencies
install_security_deps() {
    log_info "Installing security dependencies"
    apt-get update
    apt-get install -y \
        openssl \
        certbot \
        python3-certbot-nginx \
        fail2ban \
        ufw \
        vault \
        auditd \
        libpam-google-authenticator
}

# Function to configure JWT
setup_jwt() {
    log_info "Configuring JWT authentication"
    
    # Generate JWT secret key
    JWT_SECRET=$(openssl rand -base64 32)
    
    # Store JWT secret in Vault
    vault kv put secret/jwt \
        secret=$JWT_SECRET \
        issuer="system" \
        expiry="24h"
    
    # Configure JWT middleware
    cat > /etc/ansible/roles/security/files/jwt-config.yml <<EOF
jwt:
  secret: ${JWT_SECRET}
  issuer: system
  expiry: 24h
  algorithms:
    - HS256
EOF
}

# Function to setup Role-Based Access Control
setup_rbac() {
    log_info "Configuring RBAC system"
    
    # Create role definitions
    cat > /etc/ansible/roles/security/files/rbac-config.yml <<EOF
roles:
  admin:
    permissions: ["*"]
  operator:
    permissions:
      - "read:*"
      - "write:vpn"
      - "write:users"
  viewer:
    permissions:
      - "read:*"
EOF

    # Apply RBAC configuration using Ansible
    ansible-playbook /etc/ansible/roles/security/tasks/rbac.yml
}

# Function to setup SSL/TLS
setup_ssl() {
    log_info "Configuring SSL/TLS"
    
    # Generate self-signed certificates for development
    if [ "${ENVIRONMENT}" = "development" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/private/nginx-selfsigned.key \
            -out /etc/ssl/certs/nginx-selfsigned.crt \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN}"
    else
        # Use Let's Encrypt for production
        certbot --nginx -d "${DOMAIN}" --non-interactive \
            --agree-tos -m "${ADMIN_EMAIL}" \
            --redirect
    fi
}

# Function to setup secrets management
setup_secrets_manager() {
    log_info "Configuring HashiCorp Vault for secrets management"
    
    # Initialize Vault
    vault operator init > /root/vault-keys.txt
    
    # Configure Vault audit logging
    vault audit enable file file_path=/var/log/vault/audit.log
    
    # Setup Vault policies
    cat > /etc/vault.d/policies/app-policy.hcl <<EOF
path "secret/data/*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

    vault policy write app-policy /etc/vault.d/policies/app-policy.hcl
}

# Function to setup security scanning
setup_security_scanner() {
    log_info "Setting up security scanning tools"
    
    # Install and configure security scanners
    apt-get install -y \
        clamav \
        rkhunter \
        lynis
    
    # Setup periodic security scans
    cat > /etc/cron.d/security-scans <<EOF
0 2 * * * root /usr/bin/clamscan -r / --exclude-dir=/proc --exclude-dir=/sys --exclude-dir=/dev --log=/var/log/clamav/scan.log
0 3 * * * root /usr/bin/rkhunter --check --skip-keypress --report-warnings-only --log
0 4 * * 1 root /usr/bin/lynis audit system --quick --no-colors > /var/log/lynis-audit.log
EOF
}

# Function to setup compliance checking
setup_compliance() {
    log_info "Configuring compliance checking"
    
    # Install OpenSCAP
    apt-get install -y \
        openscap-scanner \
        scap-security-guide
    
    # Setup compliance scan job
    cat > /etc/ansible/roles/security/files/compliance-scan.yml <<EOF
- name: Run compliance scan
  hosts: localhost
  tasks:
    - name: Execute OpenSCAP scan
      shell: >
        oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_standard
        --results /var/log/compliance/scan-results-$(date +%Y%m%d).xml
        --report /var/log/compliance/scan-report-$(date +%Y%m%d).html
        /usr/share/xml/scap/ssg/content/ssg-ubuntu2004-ds.xml
EOF
}

# Main execution
main() {
    log_info "Starting security framework installation"
    
    # Create necessary directories
    mkdir -p /etc/ansible/roles/security/{files,tasks,handlers,templates}
    mkdir -p /var/log/{vault,compliance}
    
    # Run installation steps
    install_security_deps
    setup_jwt
    setup_rbac
    setup_ssl
    setup_secrets_manager
    setup_security_scanner
    setup_compliance
    
    # Verify installation
    verify_security_setup
    
    log_success "Security framework installation completed successfully"
}

# Function to verify security setup
verify_security_setup() {
    log_info "Verifying security setup"
    
    # Check services status
    systemctl is-active vault
    systemctl is-active fail2ban
    systemctl is-active auditd
    
    # Verify SSL configuration
    openssl x509 -in /etc/ssl/certs/nginx-selfsigned.crt -text -noout
    
    # Test Vault accessibility
    vault status
    
    # Verify RBAC configuration
    ansible-playbook /etc/ansible/roles/security/tasks/verify-rbac.yml
}

# Execute main function
main "$@"
