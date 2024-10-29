#!/bin/bash

# Source the core installation script for shared functions
source ./core-installation.sh

# Backend specific variables
BACKEND_DIR="/opt/automation-backend"
BACKEND_LOG="/var/log/backend-setup.log"
BACKEND_USER="backend-service"
API_PORT=8080
REDIS_PORT=6379

# Backend specific logging
backend_log() {
    local level=$1
    local message=$2
    log "$level" "[Backend] $message"
}

# Create backend service user
create_backend_user() {
    backend_log "INFO" "Creating backend service user..."
    useradd -r -s /bin/false $BACKEND_USER
    handle_error "Backend user creation"
}

# Install Redis
install_redis() {
    backend_log "INFO" "Installing Redis..."
    
    if [ -f /etc/debian_version ]; then
        apt-get install -y redis-server
    elif [ -f /etc/redhat-release ]; then
        dnf install -y redis
    fi
    
    # Configure Redis
    sed -i 's/bind 127.0.0.1/bind 127.0.0.1/' /etc/redis/redis.conf
    sed -i 's/# maxmemory <bytes>/maxmemory 256mb/' /etc/redis/redis.conf
    sed -i 's/# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
    
    systemctl start redis
    systemctl enable redis
    handle_error "Redis installation and configuration"
}

# Initialize backend project
init_backend_project() {
    backend_log "INFO" "Initializing backend project..."
    
    mkdir -p $BACKEND_DIR
    cd $BACKEND_DIR
    
    # Initialize Node.js project
    npm init -y
    
    # Install core dependencies
    npm install \
        express \
        typescript \
        @types/express \
        @types/node \
        ts-node \
        prisma \
        @prisma/client \
        dotenv \
        cors \
        helmet \
        compression \
        express-rate-limit \
        handle_error "Core dependencies installation"
        
    # Install microservices dependencies
    npm install \
        express-jwt \
        jsonwebtoken \
        bcryptjs \
        socket.io \
        redis \
        ioredis \
        bull \
        winston \
        node-cron \
        axios \
        zod \
        handle_error "Microservices dependencies installation"
        
    # Install development dependencies
    npm install --save-dev \
        @types/jest \
        jest \
        ts-jest \
        supertest \
        @types/supertest \
        nodemon \
        handle_error "Development dependencies installation"
        
    backend_log "INFO" "Backend dependencies installed successfully"
}

# Configure TypeScript
setup_typescript() {
    backend_log "INFO" "Configuring TypeScript..."
    
    # Initialize TypeScript configuration
    cat > $BACKEND_DIR/tsconfig.json << EOL
{
  "compilerOptions": {
    "target": "es2018",
    "module": "commonjs",
    "lib": ["es2018", "esnext.asynciterable"],
    "skipLibCheck": true,
    "sourceMap": true,
    "outDir": "./dist",
    "moduleResolution": "node",
    "removeComments": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "noImplicitThis": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "allowSyntheticDefaultImports": true,
    "esModuleInterop": true,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "resolveJsonModule": true,
    "baseUrl": "."
  },
  "exclude": ["node_modules"],
  "include": ["./src/**/*.ts"]
}
EOL
    handle_error "TypeScript configuration"
}

# Setup Prisma ORM
setup_prisma() {
    backend_log "INFO" "Setting up Prisma ORM..."
    
    # Initialize Prisma
    npx prisma init
    
    # Create base schema
    cat > $BACKEND_DIR/prisma/schema.prisma << EOL
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  password  String
  name      String?
  role      Role     @default(USER)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
}

enum Role {
  USER
  ADMIN
}
EOL
    
    # Generate Prisma client
    npx prisma generate
    handle_error "Prisma setup"
}

# Setup directory structure
setup_directory_structure() {
    backend_log "INFO" "Setting up directory structure..."
    
    # Create directory structure
    mkdir -p $BACKEND_DIR/src/{config,controllers,middleware,models,routes,services,utils}
    
    # Create basic configuration files
    cat > $BACKEND_DIR/src/config/database.ts << EOL
import { PrismaClient } from '@prisma/client';
export const prisma = new PrismaClient();
EOL
    
    cat > $BACKEND_DIR/src/config/redis.ts << EOL
import Redis from 'ioredis';
export const redis = new Redis();
EOL
    
    handle_error "Directory structure setup"
}

# Setup environment configuration
setup_environment() {
    backend_log "INFO" "Setting up environment configuration..."
    
    # Create .env file
    cat > $BACKEND_DIR/.env << EOL
# Application
NODE_ENV=development
PORT=$API_PORT
API_PREFIX=/api/v1

# Database
DATABASE_URL="postgresql://automation_user:secure_password@localhost:5432/automation_db?schema=public"

# Redis
REDIS_URL="redis://localhost:$REDIS_PORT"

# JWT
JWT_SECRET="your-super-secret-jwt-key"
JWT_EXPIRES_IN="1d"

# Rate Limiting
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=100

# Logging
LOG_LEVEL=debug
EOL
    
    handle_error "Environment configuration"
}

# Setup microservices structure
setup_microservices() {
    backend_log "INFO" "Setting up microservices..."
    
    # Create base microservices
    local services=("vpn" "identity" "analytics" "ai-integration" "task-scheduler" "event-bus" "cache-manager")
    
    for service in "${services[@]}"; do
        mkdir -p $BACKEND_DIR/src/services/$service
        cat > $BACKEND_DIR/src/services/$service/index.ts << EOL
import { Router } from 'express';
const router = Router();

// Add routes here

export default router;
EOL
    done
    
    handle_error "Microservices setup"
}

# Setup PM2 process management
setup_pm2() {
    backend_log "INFO" "Configuring PM2 for backend..."
    
    # Create PM2 ecosystem file
    cat > $BACKEND_DIR/ecosystem.config.js << EOL
module.exports = {
  apps: [{
    name: 'backend-api',
    script: 'dist/index.js',
    instances: 'max',
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '/var/log/pm2/backend-error.log',
    out_file: '/var/log/pm2/backend-out.log',
  }]
}
EOL
    
    # Create log directory
    mkdir -p /var/log/pm2
    chown $BACKEND_USER:$BACKEND_USER /var/log/pm2
    
    handle_error "PM2 configuration"
}

# Setup Docker Compose for services
setup_docker_compose() {
    backend_log "INFO" "Setting up Docker Compose configuration..."
    
    cat > $BACKEND_DIR/docker-compose.yml << EOL
version: '3.8'
services:
  api:
    build: .
    ports:
      - "$API_PORT:$API_PORT"
    environment:
      - NODE_ENV=production
    depends_on:
      - redis
    restart: unless-stopped

  redis:
    image: redis:alpine
    ports:
      - "$REDIS_PORT:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped

volumes:
  redis_data:
EOL
    
    # Create Dockerfile
    cat > $BACKEND_DIR/Dockerfile << EOL
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .
RUN npm run build

EXPOSE $API_PORT

CMD ["npm", "start"]
EOL
    
    handle_error "Docker Compose setup"
}

# Main backend setup function
setup_backend() {
    backend_log "INFO" "Starting backend setup..."
    
    create_backend_user
    install_redis
    init_backend_project
    setup_typescript
    setup_prisma
    setup_directory_structure
    setup_environment
    setup_microservices
    setup_pm2
    setup_docker_compose
    
    backend_log "INFO" "Backend setup completed successfully"
}

# Execute backend setup
setup_backend

exit 0
