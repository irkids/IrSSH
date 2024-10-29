#!/bin/bash

# Part 6: System Monitoring & Resource Management
# This section focuses on implementing system monitoring, resource limitations,
# and performance optimization

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Load common functions from previous sections
source ./common_functions.sh

# Define monitoring configuration directory
MONITORING_CONFIG_DIR="/etc/ansible/monitoring"
GRAFANA_CONFIG_DIR="/etc/grafana"
PROMETHEUS_CONFIG_DIR="/etc/prometheus"

setup_monitoring_infrastructure() {
    log_info "Setting up monitoring infrastructure..."
    
    # Create necessary directories
    mkdir -p "${MONITORING_CONFIG_DIR}"
    mkdir -p "${GRAFANA_CONFIG_DIR}"
    mkdir -p "${PROMETHEUS_CONFIG_DIR}"

    # Install monitoring stack using Docker Compose
    cat > docker-compose-monitoring.yml << 'EOL'
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ${PROMETHEUS_CONFIG_DIR}:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    ports:
      - "9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    volumes:
      - ${GRAFANA_CONFIG_DIR}:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
    ports:
      - "9100:9100"
    restart: unless-stopped

volumes:
  prometheus_data:
EOL

    # Configure Prometheus
    cat > "${PROMETHEUS_CONFIG_DIR}/prometheus.yml" << 'EOL'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'ansible_metrics'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
EOL

    # Set up resource monitoring playbook
    cat > "${MONITORING_CONFIG_DIR}/resource_monitoring.yml" << 'EOL'
---
- name: Configure System Resource Monitoring
  hosts: all
  become: true
  tasks:
    - name: Set System Resource Limits
      pam_limits:
        domain: '*'
        limit_type: "{{ item.limit_type }}"
        limit_item: "{{ item.limit_item }}"
        value: "{{ item.value }}"
      loop:
        - { limit_type: soft, limit_item: nofile, value: 65535 }
        - { limit_type: hard, limit_item: nofile, value: 65535 }
        - { limit_type: soft, limit_item: nproc, value: 65535 }
        - { limit_type: hard, limit_item: nproc, value: 65535 }

    - name: Configure Sysctl Parameters
      sysctl:
        name: "{{ item.name }}"
        value: "{{ item.value }}"
        state: present
        reload: yes
      loop:
        - { name: 'net.core.somaxconn', value: '65535' }
        - { name: 'vm.max_map_count', value: '262144' }
        - { name: 'fs.file-max', value: '2097152' }

    - name: Setup Monitoring Alerts
      template:
        src: alerts.yml.j2
        dest: /etc/prometheus/alerts.yml
EOL

    # Create alert rules template
    cat > "${PROMETHEUS_CONFIG_DIR}/alerts.yml" << 'EOL'
groups:
  - name: ansible_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: High CPU usage detected
          description: CPU usage is above 80% for 5 minutes

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: High memory usage detected
          description: Memory usage is above 85% for 5 minutes

      - alert: DiskSpaceRunningLow
        expr: (node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: Disk space running low
          description: Disk usage is above 85% for 5 minutes
EOL

    # Set up performance monitoring function
    setup_performance_monitoring() {
        python3 - << 'EOL'
import psutil
import time
from prometheus_client import start_http_server, Gauge

# Create Prometheus metrics
cpu_usage = Gauge('system_cpu_usage', 'System CPU usage percentage')
memory_usage = Gauge('system_memory_usage', 'System memory usage percentage')
disk_usage = Gauge('system_disk_usage', 'System disk usage percentage')

def collect_metrics():
    while True:
        # Collect CPU metrics
        cpu_usage.set(psutil.cpu_percent(interval=1))
        
        # Collect memory metrics
        memory = psutil.virtual_memory()
        memory_usage.set(memory.percent)
        
        # Collect disk metrics
        disk = psutil.disk_usage('/')
        disk_usage.set(disk.percent)
        
        time.sleep(5)

if __name__ == '__main__':
    # Start Prometheus HTTP server
    start_http_server(8080)
    collect_metrics()
EOL
    }

    # Start monitoring services
    docker-compose -f docker-compose-monitoring.yml up -d

    # Setup performance monitoring as a systemd service
    cat > /etc/systemd/system/performance-monitoring.service << 'EOL'
[Unit]
Description=Performance Monitoring Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/monitoring/performance_monitor.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable performance-monitoring
    systemctl start performance-monitoring

    log_success "Monitoring infrastructure setup completed"
}

# Execute main monitoring setup
main() {
    log_info "Starting monitoring and resource management setup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup monitoring infrastructure
    setup_monitoring_infrastructure
    
    # Apply resource monitoring playbook
    ansible-playbook "${MONITORING_CONFIG_DIR}/resource_monitoring.yml"
    
    # Verify monitoring services
    verify_monitoring_services
    
    log_success "Monitoring and resource management setup completed successfully"
}

# Run main function
main "$@"
