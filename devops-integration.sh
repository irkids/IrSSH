#!/bin/bash

# Part 7: DevOps Integration Setup
# This section handles Jenkins, testing infrastructure, and deployment automation

# Set error handling
set -e
trap 'handle_error $? $LINENO' ERR

# Load common functions and variables
source ./common/utils.sh
source ./common/config.sh

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# DevOps Integration Functions
setup_jenkins() {
    log_info "Setting up Jenkins integration..."
    
    # Add Jenkins repository and key
    wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | sudo apt-key add -
    sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
    
    # Install Jenkins and Java
    sudo apt-get update
    sudo apt-get install -y jenkins openjdk-11-jdk
    
    # Wait for Jenkins to start
    until $(curl --output /dev/null --silent --head --fail http://localhost:8080); do
        printf '.'
        sleep 5
    done
    
    # Get initial admin password
    JENKINS_PASS=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)
    
    # Configure Jenkins with automation script
    cat > jenkins_config.groovy << EOF
import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule

def instance = Jenkins.getInstance()

// Security setup
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
instance.setAuthorizationStrategy(strategy)

// CSRF Protection
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// Save configuration
instance.save()
EOF
    
    # Apply Jenkins configuration
    sudo java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:${JENKINS_PASS} groovy = < jenkins_config.groovy
}

setup_kubernetes() {
    log_info "Setting up Kubernetes cluster..."
    
    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
    # Install minikube for local development
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    
    # Start minikube
    minikube start --driver=docker
    
    # Create basic namespace and configurations
    kubectl create namespace development
    kubectl create namespace production
    
    # Apply base configurations
    cat > k8s-base-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: development
data:
  APP_ENV: development
  LOGGING_LEVEL: debug
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
data:
  APP_ENV: production
  LOGGING_LEVEL: info
EOF
    
    kubectl apply -f k8s-base-config.yaml
}

setup_ci_pipeline() {
    log_info "Configuring CI/CD pipeline..."
    
    # Create Jenkins pipeline configuration
    cat > Jenkinsfile << EOF
pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = 'registry.example.com'
        APP_NAME = 'vpn-management'
    }
    
    stages {
        stage('Build') {
            steps {
                sh 'npm install'
                sh 'npm run build'
            }
        }
        
        stage('Test') {
            steps {
                sh 'npm run test'
                sh 'npm run lint'
            }
        }
        
        stage('Docker Build') {
            steps {
                sh 'docker build -t \${DOCKER_REGISTRY}/\${APP_NAME}:\${BUILD_NUMBER} .'
            }
        }
        
        stage('Deploy to K8s') {
            steps {
                sh '''
                    kubectl apply -f k8s/
                    kubectl set image deployment/\${APP_NAME} \${APP_NAME}=\${DOCKER_REGISTRY}/\${APP_NAME}:\${BUILD_NUMBER}
                '''
            }
        }
    }
    
    post {
        success {
            notify_slack("Deployment successful!")
        }
        failure {
            notify_slack("Deployment failed!")
        }
    }
}
EOF
}

setup_monitoring_integration() {
    log_info "Setting up monitoring integration for CI/CD..."
    
    # Create Prometheus configuration for CI/CD metrics
    cat > prometheus-ci-config.yaml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'jenkins'
    metrics_path: '/prometheus'
    static_configs:
      - targets: ['localhost:8080']
  
  - job_name: 'kubernetes'
    kubernetes_sd_configs:
      - role: node
EOF
    
    # Apply Prometheus configuration
    kubectl apply -f prometheus-ci-config.yaml
}

setup_test_infrastructure() {
    log_info "Setting up testing infrastructure..."
    
    # Install testing dependencies
    npm install -g jest enzyme cypress
    
    # Create test configuration
    cat > jest.config.js << EOF
module.exports = {
    verbose: true,
    testEnvironment: 'jsdom',
    setupFilesAfterEnv: ['<rootDir>/src/setupTests.js'],
    moduleNameMapper: {
        '\\.(css|less|scss|sass)$': 'identity-obj-proxy',
    },
    collectCoverageFrom: [
        'src/**/*.{js,jsx}',
        '!src/index.js',
        '!src/serviceWorker.js',
    ],
    coverageThreshold: {
        global: {
            branches: 80,
            functions: 80,
            lines: 80,
            statements: 80,
        },
    },
};
EOF
    
    # Create E2E test configuration
    cat > cypress.json << EOF
{
    "baseUrl": "http://localhost:3000",
    "video": false,
    "screenshotOnRunFailure": true,
    "defaultCommandTimeout": 10000,
    "requestTimeout": 10000,
    "responseTimeout": 10000,
    "pageLoadTimeout": 30000,
    "watchForFileChanges": false
}
EOF
}

# Main execution
main() {
    log_info "Starting DevOps integration setup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup components
    setup_jenkins
    setup_kubernetes
    setup_ci_pipeline
    setup_monitoring_integration
    setup_test_infrastructure
    
    # Verify installation
    verify_devops_setup
    
    log_success "DevOps integration setup completed successfully!"
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for required tools
    command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed. Aborting."; exit 1; }
    command -v npm >/dev/null 2>&1 || { echo "npm is required but not installed. Aborting."; exit 1; }
    command -v git >/dev/null 2>&1 || { echo "git is required but not installed. Aborting."; exit 1; }
}

# Verification function
verify_devops_setup() {
    log_info "Verifying DevOps setup..."
    
    # Verify Jenkins
    curl -s http://localhost:8080/login >/dev/null || log_error "Jenkins verification failed"
    
    # Verify Kubernetes
    kubectl get nodes >/dev/null || log_error "Kubernetes verification failed"
    
    # Verify Docker registry
    curl -s localhost:5000/v2/_catalog >/dev/null || log_error "Docker registry verification failed"
}

# Error handler
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Error occurred in script at line: ${line_number}, exit code: ${exit_code}"
}

# Execute main function
main "$@"
