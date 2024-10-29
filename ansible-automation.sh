#!/bin/bash

# Section 4: Ansible Automation Setup
# This section handles Ansible configuration, playbook setup, and automation framework

# Set error handling
set -e
trap 'echo "Error occurred in Ansible Automation setup at line $LINENO. Exit code: $?"; exit 1' ERR

# Define logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/ansible-setup.log
}

# Function to verify Ansible installation
verify_ansible() {
    log "Verifying Ansible installation..."
    if ! command -v ansible >/dev/null 2>&1; then
        log "Ansible not found. Installing..."
        python3 -m pip install --upgrade ansible
    fi
    ansible --version >> /var/log/ansible-setup.log
}

# Function to setup Ansible directory structure
setup_ansible_dirs() {
    log "Setting up Ansible directory structure..."
    mkdir -p /etc/ansible/{playbooks,roles,inventory,group_vars,host_vars,templates}
    mkdir -p /etc/ansible/roles/{common,security,monitoring,deployment,maintenance,ai_integration,auto_update}
}

# Function to create base configuration
create_ansible_config() {
    log "Creating Ansible configuration..."
    cat > /etc/ansible/ansible.cfg << 'EOF'
[defaults]
inventory = /etc/ansible/inventory/hosts
roles_path = /etc/ansible/roles
remote_user = ansible
host_key_checking = False
retry_files_enabled = True
retry_files_save_path = /tmp/ansible-retries
log_path = /var/log/ansible.log
callback_whitelist = profile_tasks
gathering = smart

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
control_path = /tmp/ansible-ssh-%%h-%%p-%%r
EOF
}

# Function to setup custom playbooks
setup_custom_playbooks() {
    log "Setting up custom playbooks..."
    
    # Infrastructure Setup Playbook
    cat > /etc/ansible/playbooks/infrastructure_setup.yml << 'EOF'
---
- name: Infrastructure Setup
  hosts: all
  become: yes
  roles:
    - common
    - security
  tasks:
    - name: Verify system requirements
      ansible.builtin.include_tasks: tasks/verify_requirements.yml
    
    - name: Configure system settings
      ansible.builtin.include_tasks: tasks/configure_system.yml
EOF

    # Service Deployment Playbook
    cat > /etc/ansible/playbooks/service_deployment.yml << 'EOF'
---
- name: Service Deployment
  hosts: all
  become: yes
  roles:
    - deployment
  vars_files:
    - vars/service_config.yml
  tasks:
    - name: Deploy services
      ansible.builtin.include_tasks: tasks/deploy_services.yml
    
    - name: Verify deployment
      ansible.builtin.include_tasks: tasks/verify_deployment.yml
EOF

    # Security Management Playbook
    cat > /etc/ansible/playbooks/security_management.yml << 'EOF'
---
- name: Security Management
  hosts: all
  become: yes
  roles:
    - security
  vars_files:
    - vars/security_config.yml
  tasks:
    - name: Apply security policies
      ansible.builtin.include_tasks: tasks/security_policies.yml
    
    - name: Configure firewall rules
      ansible.builtin.include_tasks: tasks/firewall_config.yml
EOF

    # Create remaining playbooks structure
    for playbook in monitoring_config backup_recovery update_maintenance ai_integration auto_update; do
        mkdir -p "/etc/ansible/playbooks/${playbook}"
        touch "/etc/ansible/playbooks/${playbook}/main.yml"
    done
}

# Function to setup version control for playbooks
setup_version_control() {
    log "Setting up version control for playbooks..."
    
    cd /etc/ansible
    if [ ! -d .git ]; then
        git init
        git config --global user.email "ansible@localhost"
        git config --global user.name "Ansible Automation"
        echo "*.retry" > .gitignore
        echo "*.log" >> .gitignore
        git add .
        git commit -m "Initial commit of Ansible configuration"
    fi
}

# Function to setup playbook validation
setup_playbook_validation() {
    log "Setting up playbook validation..."
    
    # Create pre-commit hook for playbook syntax checking
    cat > /etc/ansible/.git/hooks/pre-commit << 'EOF'
#!/bin/bash
for file in $(git diff --cached --name-only | grep -E '\.ya?ml$'); do
    ansible-playbook --syntax-check "$file" || exit 1
done
EOF
    chmod +x /etc/ansible/.git/hooks/pre-commit
}

# Function to setup rollback system
setup_rollback_system() {
    log "Setting up rollback system..."
    mkdir -p /etc/ansible/backups
    
    cat > /etc/ansible/roles/common/tasks/backup.yml << 'EOF'
---
- name: Create backup timestamp
  command: date +%Y%m%d_%H%M%S
  register: backup_timestamp

- name: Create backup directory
  file:
    path: "/etc/ansible/backups/{{ backup_timestamp.stdout }}"
    state: directory
    mode: '0755'

- name: Backup configuration files
  copy:
    src: "{{ item }}"
    dest: "/etc/ansible/backups/{{ backup_timestamp.stdout }}/"
    remote_src: yes
  with_items:
    - /etc/ansible/ansible.cfg
    - /etc/ansible/playbooks
    - /etc/ansible/roles
EOF
}

# Main execution
main() {
    log "Starting Ansible Automation setup..."
    
    verify_ansible
    setup_ansible_dirs
    create_ansible_config
    setup_custom_playbooks
    setup_version_control
    setup_playbook_validation
    setup_rollback_system
    
    log "Ansible Automation setup completed successfully"
}

# Execute main function
main
