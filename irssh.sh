// File: docker-compose.yml
version: '3.8'

services:
  frontend:
    build: ./frontend
    ports:
      - "${WEB_PORT}:3000"
    environment:
      - REACT_APP_API_URL=http://backend:5000
    depends_on:
      - backend
    volumes:
      - ./frontend:/app
      - /app/node_modules

  backend:
    build: ./backend
    ports:
      - "5000:5000"
    environment:
      - DATABASE_URL=postgresql://${DB_USERNAME}:${DB_PASSWORD}@db:5432/${DB_DATABASE}
      - JWT_SECRET=${JWT_SECRET}
      - NODE_ENV=production
    depends_on:
      - db
    volumes:
      - ./backend:/app
      - /app/node_modules

  db:
    image: postgres:13
    environment:
      POSTGRES_DB: ${DB_DATABASE}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:

// File: backend/Dockerfile
FROM node:14

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 5000

CMD ["npm", "start"]

// File: frontend/Dockerfile
FROM node:14

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "start"]

// File: backend/package.json
{
  "name": "vpn-management-backend",
  "version": "1.0.0",
  "description": "Backend for VPN Management System",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js"
  },
  "dependencies": {
    "@prisma/client": "^3.0.0",
    "bcrypt": "^5.0.1",
    "cors": "^2.8.5",
    "express": "^4.17.1",
    "jsonwebtoken": "^8.5.1",
    "winston": "^3.3.3"
  },
  "devDependencies": {
    "nodemon": "^2.0.12",
    "prisma": "^3.0.0"
  }
}

// File: frontend/package.json
{
  "name": "vpn-management-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@material-ui/core": "^4.12.3",
    "@material-ui/icons": "^4.11.2",
    "axios": "^0.21.1",
    "react": "^17.0.2",
    "react-dom": "^17.0.2",
    "react-router-dom": "^5.2.0",
    "react-scripts": "4.0.3",
    "recharts": "^2.1.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  }
}

// File: backend/prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id             Int          @id @default(autoincrement())
  username       String       @unique
  password       String
  email          String       @unique
  createdAt      DateTime     @default(now())
  lastLogin      DateTime?
  status         String
  trafficQuota   Int?
  expirationDate DateTime?
  connections    Connection[]
}

model Connection {
  id             Int      @id @default(autoincrement())
  userId         Int
  protocolId     Int
  ipAddress      String
  connectedAt    DateTime @default(now())
  disconnectedAt DateTime?
  bytesSent      Int      @default(0)
  bytesReceived  Int      @default(0)
  user           User     @relation(fields: [userId], references: [id])
  protocol       Protocol @relation(fields: [protocolId], references: [id])
}

model Protocol {
  id           Int          @id @default(autoincrement())
  name         String
  version      String
  isInstalled  Boolean      @default(false)
  installDate  DateTime?
  port         Int?
  connections  Connection[]
}

model Setting {
  key         String   @id
  value       String
  description String?
}

model Backup {
  id        Int      @id @default(autoincrement())
  fileName  String
  createdAt DateTime @default(now())
  size      Int
  status    String
}

// File: backend/src/server.js
const express = require('express');
const { PrismaClient } = require('@prisma/client');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { exec } = require('child_process');
const winston = require('winston');

const app = express();
const prisma = new PrismaClient();

// Setup logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  defaultMeta: { service: 'vpn-management' },
  transports: [
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' }),
  ],
});

if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.simple(),
  }));
}

app.use(cors());
app.use(express.json());

// Middleware to verify JWT token
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (token == null) return res.sendStatus(401);

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) return res.sendStatus(403);
    req.user = user;
    next();
  });
};

// Routes
app.post('/login', async (req, res) => {
  const { username, password } = req.body;
  const user = await prisma.user.findUnique({ where: { username } });

  if (user && await bcrypt.compare(password, user.password)) {
    const token = jwt.sign({ id: user.id, username: user.username }, process.env.JWT_SECRET);
    await prisma.user.update({
      where: { id: user.id },
      data: { lastLogin: new Date() }
    });
    res.json({ token });
  } else {
    res.status(400).json({ error: 'Invalid credentials' });
  }
});

app.get('/users', authenticateToken, async (req, res) => {
  try {
    const users = await prisma.user.findMany();
    res.json(users);
  } catch (error) {
    logger.error('Error fetching users:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/users', authenticateToken, async (req, res) => {
  try {
    const { username, password, email, trafficQuota, expirationDate } = req.body;
    const hashedPassword = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: { 
        username, 
        password: hashedPassword, 
        email, 
        status: 'Active',
        trafficQuota,
        expirationDate: expirationDate ? new Date(expirationDate) : null
      }
    });
    res.status(201).json(user);
  } catch (error) {
    logger.error('Error creating user:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.put('/users/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { username, email, status, trafficQuota, expirationDate } = req.body;
    const user = await prisma.user.update({
      where: { id: parseInt(id) },
      data: { 
        username, 
        email, 
        status,
        trafficQuota,
        expirationDate: expirationDate ? new Date(expirationDate) : null
      }
    });
    res.json(user);
  } catch (error) {
    logger.error('Error updating user:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/users/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    await prisma.user.delete({ where: { id: parseInt(id) } });
    res.sendStatus(204);
  } catch (error) {
    logger.error('Error deleting user:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/connections', authenticateToken, async (req, res) => {
  try {
    const connections = await prisma.connection.findMany({
      include: { user: true, protocol: true }
    });
    res.json(connections);
  } catch (error) {
    logger.error('Error fetching connections:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/connections/:id/kill', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    const connection = await prisma.connection.findUnique({ where: { id: parseInt(id) } });
    if (!connection) {
      return res.status(404).json({ error: 'Connection not found' });
    }
    // Here you would implement the logic to kill the connection
    // This is a placeholder and should be replaced with actual implementation
    console.log(`Killing connection ${id}`);
    await prisma.connection.update({
      where: { id: parseInt(id) },
      data: { disconnectedAt: new Date() }
    });
    res.sendStatus(200);
  } catch (error) {
    logger.error('Error killing connection:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/protocols', authenticateToken, async (req, res) => {
  try {
    const protocols = await prisma.protocol.findMany();
    res.json(protocols);
  } catch (error) {
    logger.error('Error fetching protocols:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/protocols', authenticateToken, async (req, res) => {
  try {
    const { name, version, port } = req.body;
    const protocol = await prisma.protocol.create({
      data: { name, version, isInstalled: true, installDate: new Date(), port }
    });
    res.status(201).json(protocol);
  } catch (error) {
    logger.error('Error creating protocol:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/protocols/:name/install', authenticateToken, (req, res) => {
  const { name } = req.params;
  const scriptPath = `/opt/vpn-management-system/install${name.toLowerCase()}.sh`;
  
  exec(`bash ${scriptPath}`, (error, stdout, stderr) => {
    if (error) {
      logger.error(`Error installing ${name}:`, error);
      return res.status(500).json({ error: `Installation failed: ${error.message}` });
    }
    logger.info(`${name} installed successfully`);
    res.json({ message: `${name} installed successfully`, output: stdout });
  });
});

app.get('/settings', authenticateToken, async (req, res) => {
  try {
    const settings = await prisma.setting.findMany();
    res.json(settings);
  } catch (error) {
    logger.error('Error fetching settings:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.put('/settings/:key', authenticateToken, async (req, res) => {
  try {
    const { key } = req.params;
    const { value } = req.body;
    const setting = await prisma.setting.update({
      where: { key },
      data: { value }
    });
    res.json(setting);
  } catch (error) {
    logger.error('Error updating setting:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/backups', authenticateToken, (req, res) => {
  const backupScript = '/opt/vpn-management-system/backup.sh';
  
  exec(`bash ${backupScript}`, async (error, stdout, stderr) => {
    if (error) {
      logger.error('Error creating backup:', error);
      return res.status(500).json({ error: `Backup failed: ${error.message}` });
    }
    
    // Assuming the backup script outputs the filename and size
    const [fileName, size] = stdout.trim().split(',');
    
    try {
      const backup = await prisma.backup.create({
        data: {
          fileName,
          size: parseInt(size),
          status: 'Completed'
        }
      });
      
      logger.info('Backup created successfully');
      res.status(201).json(backup);
    } catch (dbError) {
      logger.error('Error saving backup to database:', dbError);
      res.status(500).json({ error: 'Backup created but failed to save to database' });
    }
  });
});

app.get('/system/stats', authenticateToken, (req, res) => {
  exec('top -bn1 | grep "Cpu(s)" | sed "s/.*, *\\([0-9.]*\\)%* id.*/\\1/" | awk \'{print 100 - $1}\'', (error, stdout, stderr) => {
    if (error) {
      logger.error('Error getting CPU usage:', error);
      return res.status(500).json({ error: 'Failed to get system stats' });
    }
    
const cpuUsage = parseFloat(stdout);

exec('free | grep Mem | awk \'{print $3/$2 * 100.0}\'', (error, stdout, stderr) => {
  if (error) {
    logger.error('Error getting RAM usage:', error);
    return res.status(500).json({ error: 'Failed to get system stats' });
  }
  
  const ramUsage = parseFloat(stdout);
  
  exec('df -h / | awk \'NR==2 {print $5}\' | sed \'s/%//\'', (error, stdout, stderr) => {
    if (error) {
      logger.error('Error getting disk usage:', error);
      return res.status(500).json({ error: 'Failed to get system stats' });
    }
    
    const diskUsage = parseFloat(stdout);
    
    // Get bandwidth usage (example using ifstat)
    exec('ifstat -i eth0 1 1 | tail -1 | awk \'{print $1 + $2}\'', (error, stdout, stderr) => {
      if (error) {
        logger.error('Error getting bandwidth usage:', error);
        return res.status(500).json({ error: 'Failed to get system stats' });
      }
      
      const bandwidthUsage = parseFloat(stdout);
      
      res.json({
        cpu: cpuUsage.toFixed(2),
        ram: ramUsage.toFixed(2),
        disk: diskUsage.toFixed(2),
        bandwidth: bandwidthUsage.toFixed(2)
      });
    });
  });
});
});

// Get active, expired, and total users
app.get('/api/users/stats', authenticateToken, async (req, res) => {
  try {
    const activeUsers = await prisma.user.count({ where: { status: 'Active' } });
    const expiredUsers = await prisma.user.count({ where: { status: 'Expired' } });
    const totalUsers = await prisma.user.count();
    
    res.json({ activeUsers, expiredUsers, totalUsers });
  } catch (error) {
    logger.error('Error getting user stats:', error);
    res.status(500).json({ error: 'Failed to get user stats' });
  }
});

// Get most active users
app.get('/api/users/most-active', authenticateToken, async (req, res) => {
  try {
    const mostActiveUsers = await prisma.user.findMany({
      take: 5,
      orderBy: {
        connections: {
          _count: 'desc'
        }
      },
      include: {
        _count: {
          select: { connections: true }
        }
      }
    });
    
    res.json(mostActiveUsers);
  } catch (error) {
    logger.error('Error getting most active users:', error);
    res.status(500).json({ error: 'Failed to get most active users' });
  }
});

// Online Users
app.get('/api/users/online', authenticateToken, async (req, res) => {
  try {
    const onlineUsers = await prisma.connection.findMany({
      where: {
        disconnectedAt: null
      },
      include: {
        user: true,
        protocol: true
      }
    });
    
    res.json(onlineUsers);
  } catch (error) {
    logger.error('Error getting online users:', error);
    res.status(500).json({ error: 'Failed to get online users' });
  }
});

// Kill connection
app.post('/api/connections/:id/kill', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    await prisma.connection.update({
      where: { id: parseInt(id) },
      data: { disconnectedAt: new Date() }
    });
    
    // Here you would implement the actual connection termination logic
    // This might involve calling a system command or interacting with the VPN server
    
    res.json({ message: 'Connection terminated successfully' });
  } catch (error) {
    logger.error('Error killing connection:', error);
    res.status(500).json({ error: 'Failed to kill connection' });
  }
});

// User Management
app.post('/api/users', authenticateToken, async (req, res) => {
  try {
    const { username, password, email, trafficQuota, expirationDate, protocol } = req.body;
    const hashedPassword = await bcrypt.hash(password, 10);
    
    const user = await prisma.user.create({
      data: {
        username,
        password: hashedPassword,
        email,
        status: 'Active',
        trafficQuota,
        expirationDate: expirationDate ? new Date(expirationDate) : null
      }
    });
    
    // Assign protocol to user
    if (protocol) {
      await prisma.userProtocol.create({
        data: {
          userId: user.id,
          protocolId: protocol
        }
      });
    }
    
    res.status(201).json(user);
  } catch (error) {
    logger.error('Error creating user:', error);
    res.status(500).json({ error: 'Failed to create user' });
  }
});

// Settings
app.get('/api/settings', authenticateToken, async (req, res) => {
  try {
    const settings = await prisma.setting.findMany();
    res.json(settings);
  } catch (error) {
    logger.error('Error getting settings:', error);
    res.status(500).json({ error: 'Failed to get settings' });
  }
});

app.put('/api/settings/:key', authenticateToken, async (req, res) => {
  try {
    const { key } = req.params;
    const { value } = req.body;
    
    const setting = await prisma.setting.update({
      where: { key },
      data: { value }
    });
    
    res.json(setting);
  } catch (error) {
    logger.error('Error updating setting:', error);
    res.status(500).json({ error: 'Failed to update setting' });
  }
});

// Backup
app.post('/api/backups', authenticateToken, (req, res) => {
  const backupScript = '/opt/vpn-management-system/backup.sh';
  
  exec(`bash ${backupScript}`, async (error, stdout, stderr) => {
    if (error) {
      logger.error('Error creating backup:', error);
      return res.status(500).json({ error: 'Backup failed' });
    }
    
    const [fileName, size] = stdout.trim().split(',');
    
    try {
      const backup = await prisma.backup.create({
        data: {
          fileName,
          size: parseInt(size),
          status: 'Completed'
        }
      });
      
      // Send notification to Telegram
      const telegramToken = process.env.TELEGRAM_BOT_TOKEN;
      const telegramChatId = process.env.TELEGRAM_CHAT_ID;
      
      if (telegramToken && telegramChatId) {
        const message = `Backup completed: ${fileName}`;
        axios.post(`https://api.telegram.org/bot${telegramToken}/sendMessage`, {
          chat_id: telegramChatId,
          text: message
        }).catch(error => logger.error('Error sending Telegram notification:', error));
      }
      
      res.status(201).json(backup);
    } catch (dbError) {
      logger.error('Error saving backup to database:', dbError);
      res.status(500).json({ error: 'Backup created but failed to save to database' });
    }
  });
});

// Protocol Management
app.get('/api/protocols', authenticateToken, async (req, res) => {
  try {
    const protocols = await prisma.protocol.findMany();
    res.json(protocols);
  } catch (error) {
    logger.error('Error getting protocols:', error);
    res.status(500).json({ error: 'Failed to get protocols' });
  }
});

app.put('/api/protocols/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { port } = req.body;
    
    const protocol = await prisma.protocol.update({
      where: { id: parseInt(id) },
      data: { port }
    });
    
    // Here you would implement the actual port change logic
    // This might involve modifying configuration files and restarting services
    
    res.json(protocol);
  } catch (error) {
    logger.error('Error updating protocol:', error);
    res.status(500).json({ error: 'Failed to update protocol' });
  }
});

// Start the server
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
