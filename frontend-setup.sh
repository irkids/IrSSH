#!/bin/bash

# Source the core installation script for shared functions
source ./core-installation.sh

# Frontend specific variables
FRONTEND_DIR="/opt/automation-frontend"
FRONTEND_LOG="/var/log/frontend-setup.log"
FRONTEND_USER="frontend-service"
FRONTEND_PORT=3000

# Frontend specific logging
frontend_log() {
    local level=$1
    local message=$2
    log "$level" "[Frontend] $message"
}

# Create frontend service user
create_frontend_user() {
    frontend_log "INFO" "Creating frontend service user..."
    useradd -r -s /bin/false $FRONTEND_USER
    handle_error "Frontend user creation"
}

# Install frontend build tools
install_build_tools() {
    frontend_log "INFO" "Installing build tools..."
    
    if [ -f /etc/debian_version ]; then
        apt-get install -y build-essential
    elif [ -f /etc/redhat-release ]; then
        dnf group install -y "Development Tools"
    fi
    handle_error "Build tools installation"
}

# Install frontend dependencies
install_frontend_deps() {
    frontend_log "INFO" "Installing frontend dependencies..."
    
    # Create frontend directory
    mkdir -p $FRONTEND_DIR
    chown $FRONTEND_USER:$FRONTEND_USER $FRONTEND_DIR

    # Initialize new React project with TypeScript
    npx create-react-app $FRONTEND_DIR --template typescript
    handle_error "React project initialization"

    # Navigate to frontend directory
    cd $FRONTEND_DIR

    # Install UI libraries
    npm install \
        @mui/material @emotion/react @emotion/styled \
        @tailwindcss/postcss7-compat tailwindcss@npm:@tailwindcss/postcss7-compat \
        styled-components \
        @types/styled-components \
        handle_error "UI libraries installation"

    # Install routing and state management
    npm install \
        react-router-dom @types/react-router-dom \
        @reduxjs/toolkit react-redux \
        @tanstack/react-query \
        handle_error "Routing and state libraries installation"

    # Install form and validation libraries
    npm install \
        formik yup \
        @hookform/resolvers \
        handle_error "Form libraries installation"

    # Install data visualization libraries
    npm install \
        recharts @types/recharts \
        apexcharts react-apexcharts \
        handle_error "Chart libraries installation"

    # Install utility libraries
    npm install \
        axios \
        socket.io-client \
        react-toastify \
        dayjs \
        jalali-moment \
        handle_error "Utility libraries installation"

    # Install testing libraries
    npm install --save-dev \
        @testing-library/react \
        @testing-library/jest-dom \
        @testing-library/user-event \
        jest \
        handle_error "Testing libraries installation"

    frontend_log "INFO" "Frontend dependencies installed successfully"
}

# Configure Tailwind CSS
setup_tailwind() {
    frontend_log "INFO" "Configuring Tailwind CSS..."
    
    # Create Tailwind config
    npx tailwindcss init
    
    # Create PostCSS config
    cat > postcss.config.js << EOL
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  }
}
EOL

    # Update Tailwind config
    cat > tailwind.config.js << EOL
module.exports = {
  content: [
    "./src/**/*.{js,jsx,ts,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
EOL

    handle_error "Tailwind configuration"
}

# Setup frontend environment
setup_environment() {
    frontend_log "INFO" "Setting up frontend environment..."
    
    # Create environment file
    cat > $FRONTEND_DIR/.env << EOL
REACT_APP_API_URL=http://localhost:8080
REACT_APP_WS_URL=ws://localhost:8080
REACT_APP_ENVIRONMENT=development
EOL

    handle_error "Environment setup"
}

# Configure Nginx for frontend
setup_nginx() {
    frontend_log "INFO" "Configuring Nginx for frontend..."
    
    # Create Nginx configuration
    cat > /etc/nginx/conf.d/frontend.conf << EOL
server {
    listen 80;
    server_name localhost;

    location / {
        root $FRONTEND_DIR/build;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location /ws {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }
}
EOL

    # Test and reload Nginx
    nginx -t
    systemctl reload nginx
    handle_error "Nginx configuration"
}

# Setup PM2 process management
setup_pm2() {
    frontend_log "INFO" "Configuring PM2..."
    
    # Create PM2 ecosystem file
    cat > $FRONTEND_DIR/ecosystem.config.js << EOL
module.exports = {
  apps: [{
    name: 'frontend',
    script: 'npm',
    args: 'start',
    cwd: '$FRONTEND_DIR',
    env: {
      NODE_ENV: 'production',
    },
    max_memory_restart: '500M',
    error_file: '/var/log/pm2/frontend-error.log',
    out_file: '/var/log/pm2/frontend-out.log',
  }]
}
EOL

    # Start frontend with PM2
    pm2 start $FRONTEND_DIR/ecosystem.config.js
    pm2 save
    handle_error "PM2 configuration"
}

# Setup development tools
setup_dev_tools() {
    frontend_log "INFO" "Setting up development tools..."
    
    # Install and configure ESLint
    npm install --save-dev \
        eslint \
        @typescript-eslint/parser \
        @typescript-eslint/eslint-plugin \
        eslint-plugin-react \
        eslint-plugin-react-hooks \
        prettier \
        eslint-config-prettier \
        eslint-plugin-prettier
    
    # Create ESLint config
    cat > $FRONTEND_DIR/.eslintrc.js << EOL
module.exports = {
  parser: '@typescript-eslint/parser',
  extends: [
    'plugin:react/recommended',
    'plugin:@typescript-eslint/recommended',
    'prettier',
  ],
  plugins: ['react-hooks', 'prettier'],
  rules: {
    'react-hooks/rules-of-hooks': 'error',
    'react-hooks/exhaustive-deps': 'warn',
    'prettier/prettier': 'error',
  },
};
EOL

    handle_error "Development tools setup"
}

# Main frontend setup function
setup_frontend() {
    frontend_log "INFO" "Starting frontend setup..."
    
    create_frontend_user
    install_build_tools
    install_frontend_deps
    setup_tailwind
    setup_environment
    setup_nginx
    setup_pm2
    setup_dev_tools
    
    frontend_log "INFO" "Frontend setup completed successfully"
}

# Execute frontend setup
setup_frontend

exit 0
