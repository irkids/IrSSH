#!/bin/bash

# System Setup Master Script
# This script orchestrates the installation and configuration of the entire system

# Set error handling
set -euo pipefail

# Configuration
GITHUB_REPO="https://raw.githubusercontent.com/irkids/IrSSH/refs/heads/main"
LOCAL_MODE=${USE_LOCAL:-false}
COMMON_DIR="./common"
CACHE_DIR="/tmp/setup-cache"
LOG_DIR="/var/log/system-setup"
LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
CACHE_EXPIRY=86400  # 24 hours in seconds

# Create necessary directories
mkdir -p "$CACHE_DIR" "$LOG_DIR"

# Initialize log file
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" 
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $*"
}

# Error recovery mechanism
declare -A COMPLETED_STEPS
RECOVERY_FILE="${CACHE_DIR}/recovery_state"

save_progress() {
    local step="$1"
    COMPLETED_STEPS["$step"]=1
    declare -p COMPLETED_STEPS > "$RECOVERY_FILE"
}

load_progress() {
    if [[ -f "$RECOVERY_FILE" ]]; then
        source "$RECOVERY_FILE"
        log_info "Recovered previous progress. Completed steps: ${!COMPLETED_STEPS[*]}"
    fi
}

# Caching mechanism
get_cached_file() {
    local remote_path="$1"
    local cache_path="${CACHE_DIR}/${remote_path//\//_}"
    local cache_time=0
    
    if [[ -f "$cache_path" ]]; then
        cache_time=$(stat -c %Y "$cache_path" 2>/dev/null || echo 0)
    fi
    
    current_time=$(date +%s)
    
    # Check if cache is valid
    if [[ -f "$cache_path" ]] && (( current_time - cache_time < CACHE_EXPIRY )); then
        log_info "Using cached version of $remote_path"
        echo "$cache_path"
        return 0
    fi
    
    # Download and cache new version
    log_info "Downloading fresh copy of $remote_path"
    mkdir -p "$(dirname "$cache_path")"
    if curl -Ls "${GITHUB_REPO}/${remote_path}" --ipv4 -o "$cache_path.tmp"; then
        mv "$cache_path.tmp" "$cache_path"
        echo "$cache_path"
        return 0
    else
        log_error "Failed to download $remote_path"
        rm -f "$cache_path.tmp"
        return 1
    fi
}

# Enhanced source_file function with recovery and caching
source_file() {
    local local_path="$1"
    local remote_path="$2"
    local step_name="$3"
    
    # Skip if step was completed in previous run
    if [[ -n "${COMPLETED_STEPS[$step_name]:-}" ]]; then
        log_info "Skipping previously completed step: $step_name"
        return 0
    fi
    
    # Attempt operation up to 3 times
    for attempt in {1..3}; do
        if [ "$LOCAL_MODE" = true ]; then
            if [ -f "$local_path" ]; then
                source "$local_path"
                save_progress "$step_name"
                return 0
            else
                log_error "Attempt $attempt: Local file $local_path not found"
                if [ "$attempt" -eq 3 ]; then
                    log_error "Creating necessary directories and failing..."
                    mkdir -p "$(dirname "$local_path")"
                    echo "Please place required files in the correct directories"
                    exit 1
                fi
            fi
        else
            local cached_file
            if cached_file=$(get_cached_file "$remote_path"); then
                source "$cached_file"
                save_progress "$step_name"
                return 0
            else
                log_error "Attempt $attempt: Failed to source remote file $remote_path"
                sleep $((attempt * 5))  # Exponential backoff
            fi
        fi
    done
    
    log_error "Failed to source file after 3 attempts: $remote_path"
    exit 1
}

# Cleanup function
cleanup() {
    local exit_code=$?
    log_info "Script execution completed with exit code: $exit_code"
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed. Check $LOG_FILE for details"
    fi
    exit $exit_code
}

trap cleanup EXIT
trap 'log_error "Error on line $LINENO. Exit code: $?"' ERR

# Load previous progress
load_progress

# Main installation steps
log_info "Starting system setup in ${LOCAL_MODE} mode"

# Load common functions and variables
source_file "${COMMON_DIR}/utils.sh" "common/utils.sh" "utils"
source_file "${COMMON_DIR}/config.sh" "common/config.sh" "config"

# Installation steps array
declare -a INSTALL_STEPS=(
    "core-setup.sh|Core Installation"
    "frontend-setup.sh|Frontend Integration"
    "backend-setup.sh|Backend Services"
    "ansible-automation.sh|Ansible Automation"
    "claude-integration.sh|Claude.ai Integration"
    "monitoring-setup.sh|Monitoring & Observability"
    "devops-integration.sh|DevOps Integration"
    "security-framework-setup.sh|Security Framework"
)

# Execute installation steps
for step in "${INSTALL_STEPS[@]}"; do
    IFS="|" read -r script_name step_desc <<< "$step"
    
    log_info "Starting $step_desc"
    if source_file "./$script_name" "$script_name" "${script_name%%.*}"; then
        log_info "$step_desc completed successfully"
    else
        log_error "$step_desc failed"
        exit 1
    fi
done

# Cleanup old cache files (older than 7 days)
find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true

log_info "System setup completed successfully!"

# Function to verify overall system setup
verify_system_setup() {
    log_info "Verifying system setup"
    
    # Check status of all components
    verify_core_setup
    verify_frontend_setup
    verify_backend_setup
    verify_ansible_setup
    verify_claude_setup
    verify_monitoring_setup
    verify_devops_setup
    verify_security_setup
    
    # Run end-to-end tests
    run_system_tests
}

# Function to run end-to-end system tests
run_system_tests() {
    log_info "Running end-to-end system tests"
    
    # Implement system-level tests here
    pytest /etc/tests/system
}

# Execute main script
main() {
    log_info "Starting system setup"
    
    # Create necessary directories
    mkdir -p /etc/{core,frontend,backend,ansible,claude,monitoring,devops,security,tests}
    
    # Run setup steps
    main_core
    main_frontend
    main_backend
    main_ansible
    main_claude
    main_monitoring
    main_devops
    main_security
}

main "$@"
