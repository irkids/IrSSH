#!/bin/bash

# Create project structure
mkdir -p vpn-management-system/{frontend,backend,scripts}
cd vpn-management-system

# Frontend setup
cat << 'EOF' > frontend/package.json
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
EOF

# Create frontend source files
mkdir -p frontend/src/components
cat << 'EOF' > frontend/src/index.js
import React from 'react';
import ReactDOM from 'react-dom';
import App from './App';

ReactDOM.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
  document.getElementById('root')
);
EOF

cat << 'EOF' > frontend/src/App.js
import React from 'react';
import { BrowserRouter as Router, Route, Switch } from 'react-router-dom';
import { ThemeProvider, createTheme } from '@material-ui/core/styles';
import CssBaseline from '@material-ui/core/CssBaseline';
import Dashboard from './components/Dashboard';
import Users from './components/Users';
import Protocols from './components/Protocols';
import Settings from './components/Settings';
import Backups from './components/Backups';
import Connections from './components/Connections';
import Login from './components/Login';
import PrivateRoute from './components/PrivateRoute';
import Navbar from './components/Navbar';

const theme = createTheme({
  palette: {
    type: 'dark',
    primary: {
      main: '#1976d2',
    },
    secondary: {
      main: '#dc004e',
    },
  },
});

function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Router>
        <div style={{ display: 'flex' }}>
          <Navbar />
          <main style={{ flexGrow: 1, padding: '20px' }}>
            <Switch>
              <Route exact path="/login" component={Login} />
              <PrivateRoute exact path="/" component={Dashboard} />
              <PrivateRoute path="/users" component={Users} />
              <PrivateRoute path="/protocols" component={Protocols} />
              <PrivateRoute path="/settings" component={Settings} />
              <PrivateRoute path="/backups" component={Backups} />
              <PrivateRoute path="/connections" component={Connections} />
            </Switch>
          </main>
        </div>
      </Router>
    </ThemeProvider>
  );
}

export default App;
EOF

cat << 'EOF' > frontend/src/components/Dashboard.js
import React, { useState, useEffect } from 'react';
import { makeStyles } from '@material-ui/core/styles';
import { Grid, Paper, Typography } from '@material-ui/core';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import axios from 'axios';

const useStyles = makeStyles((theme) => ({
  root: {
    flexGrow: 1,
  },
  paper: {
    padding: theme.spacing(2),
    textAlign: 'center',
    color: theme.palette.text.secondary,
  },
}));

function Dashboard() {
  const classes = useStyles();
  const [stats, setStats] = useState({ cpu: 0, ram: 0, disk: 0 });
  const [usageData, setUsageData] = useState([]);

  useEffect(() => {
    const fetchStats = async () => {
      const response = await axios.get('/api/system/stats');
      setStats(response.data);
    };

    const fetchUsageData = async () => {
      const response = await axios.get('/api/system/usage');
      setUsageData(response.data);
    };

    fetchStats();
    fetchUsageData();
    const interval = setInterval(() => {
      fetchStats();
      fetchUsageData();
    }, 5000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className={classes.root}>
      <Grid container spacing={3}>
        <Grid item xs={12} sm={4}>
          <Paper className={classes.paper}>
            <Typography variant="h6">CPU Usage</Typography>
            <Typography variant="h4">{stats.cpu}%</Typography>
          </Paper>
        </Grid>
        <Grid item xs={12} sm={4}>
          <Paper className={classes.paper}>
            <Typography variant="h6">RAM Usage</Typography>
            <Typography variant="h4">{stats.ram}%</Typography>
          </Paper>
        </Grid>
        <Grid item xs={12} sm={4}>
          <Paper className={classes.paper}>
            <Typography variant="h6">Disk Usage</Typography>
            <Typography variant="h4">{stats.disk}%</Typography>
          </Paper>
        </Grid>
        <Grid item xs={12}>
          <Paper className={classes.paper}>
            <Typography variant="h6">System Usage Over Time</Typography>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={usageData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis />
                <Tooltip />
                <Legend />
                <Line type="monotone" dataKey="cpu" stroke="#8884d8" />
                <Line type="monotone" dataKey="ram" stroke="#82ca9d" />
                <Line type="monotone" dataKey="disk" stroke="#ffc658" />
              </LineChart>
            </ResponsiveContainer>
          </Paper>
        </Grid>
      </Grid>
    </div>
  );
}

export default Dashboard;
EOF

cat << 'EOF' > frontend/src/components/Users.js
import React, { useState, useEffect } from 'react';
import { makeStyles } from '@material-ui/core/styles';
import { 
  Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper, 
  Button, Typography, Dialog, DialogTitle, DialogContent, DialogActions, TextField 
} from '@material-ui/core';
import axios from 'axios';

const useStyles = makeStyles((theme) => ({
  root: {
    width: '100%',
  },
  paper: {
    width: '100%',
    marginBottom: theme.spacing(2),
  },
  table: {
    minWidth: 750,
  },
  visuallyHidden: {
    border: 0,
    clip: 'rect(0 0 0 0)',
    height: 1,
    margin: -1,
    overflow: 'hidden',
    padding: 0,
    position: 'absolute',
    top: 20,
    width: 1,
  },
}));

function Users() {
  const classes = useStyles();
  const [users, setUsers] = useState([]);
  const [open, setOpen] = useState(false);
  const [newUser, setNewUser] = useState({ username: '', email: '', password: '' });

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async () => {
    const response = await axios.get('/api/users');
    setUsers(response.data);
  };

  const handleClickOpen = () => {
    setOpen(true);
  };

  const handleClose = () => {
    setOpen(false);
  };

  const handleInputChange = (e) => {
    setNewUser({ ...newUser, [e.target.name]: e.target.value });
  };

  const handleAddUser = async () => {
    await axios.post('/api/users', newUser);
    setOpen(false);
    fetchUsers();
  };

  return (
    <div className={classes.root}>
      <Paper className={classes.paper}>
        <TableContainer>
          <Table className={classes.table} aria-labelledby="tableTitle" size="medium" aria-label="enhanced table">
            <TableHead>
              <TableRow>
                <TableCell>Username</TableCell>
                <TableCell>Email</TableCell>
                <TableCell>Status</TableCell>
                <TableCell>Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {users.map((user) => (
                <TableRow key={user.id}>
                  <TableCell component="th" scope="row">{user.username}</TableCell>
                  <TableCell>{user.email}</TableCell>
                  <TableCell>{user.status}</TableCell>
                  <TableCell>
                    <Button variant="contained" color="secondary">Delete</Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
      <Button variant="contained" color="primary" onClick={handleClickOpen}>
        Add User
      </Button>
      <Dialog open={open} onClose={handleClose} aria-labelledby="form-dialog-title">
        <DialogTitle id="form-dialog-title">Add New User</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            name="username"
            label="Username"
            type="text"
            fullWidth
            value={newUser.username}
            onChange={handleInputChange}
          />
          <TextField
            margin="dense"
            name="email"
            label="Email Address"
            type="email"
            fullWidth
            value={newUser.email}
            onChange={handleInputChange}
          />
          <TextField
            margin="dense"
            name="password"
            label="Password"
            type="password"
            fullWidth
            value={newUser.password}
            onChange={handleInputChange}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={handleClose} color="primary">
            Cancel
          </Button>
          <Button onClick={handleAddUser} color="primary">
            Add
          </Button>
        </DialogActions>
      </Dialog>
    </div>
  );
}

export default Users;
EOF

cat << 'EOF' > frontend/src/components/Protocols.js
import React, { useState, useEffect } from 'react';
import { makeStyles } from '@material-ui/core/styles';
import { 
  Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper, 
  Button, Typography 
} from '@material-ui/core';
import axios from 'axios';

const useStyles = makeStyles((theme) => ({
  root: {
    width: '100%',
  },
  paper: {
    width: '100%',
    marginBottom: theme.spacing(2),
  },
  table: {
    minWidth: 750,
  },
}));

function Protocols() {
  const classes = useStyles();
  const [protocols, setProtocols] = useState([]);

  useEffect(() => {
    fetchProtocols();
  }, []);

  const fetchProtocols = async () => {
    const response = await axios.get('/api/protocols');
    setProtocols(response.data);
  };

  const handleInstall = async (name) => {
    await axios.post(`/api/protocols/install/${name}`);
    fetchProtocols();
  };

  return (
    <div className={classes.root}>
      <Paper className={classes.paper}>
        <TableContainer>
          <Table className={classes.table} aria-labelledby="tableTitle" size="medium" aria-label="enhanced table">
            <TableHead>
              <TableRow>
                <TableCell>Protocol</TableCell>
                <TableCell>Version</TableCell>
                <TableCell>Status</TableCell>
                <TableCell>Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {protocols.map((protocol) => (
                <TableRow key={protocol.id}>
                  <TableCell component="th" scope="row">{protocol.name}</TableCell>
                  <TableCell>{protocol.version}</TableCell>
                  <TableCell>{protocol.isInstalled ? 'Installed' : 'Not Installed'}</TableCell>
                  <TableCell>
                    {!protocol.isInstalled && (
                      <Button 
                        variant="contained" 
                        color="primary" 
                        onClick={() => handleInstall(protocol.name)}
                      >
                        Install
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
    </div>
  );
}

export default Protocols;
EOF

cat << 'EOF' > frontend/src/components/Settings.js
import React, { useState, useEffect } from 'react';
import { makeStyles } from '@material-ui/core/styles';
import { 
  Paper, Typography, TextField, Button 
} from '@material-ui/core';
import axios from 'axios';

const useStyles = makeStyles((theme) => ({
  root: {
    flexGrow: 1,
    padding: theme.spacing(3),
  },
  paper: {
    padding: theme.spacing(2),
  },
  form: {
    '& > *': {
      margin: theme.spacing(1),
      width: '25ch',
    },
  },
}));

function Settings() {
  const classes = useStyles();
  const [settings, setSettings] = useState({});

  useEffect(() => {
    fetchSettings();
  }, []);

  const fetchSettings = async () => {
    const response = await axios.get('/api/settings');
    const settingsObj = {};
    response.data.forEach(setting => {
      settingsObj[setting.key] = setting.value;
    });
    setSettings(settingsObj);
  };

  const handleSettingChange = (key, value) => {
    setSettings({ ...settings, [key]: value });
  };

  const handleSaveSettings = async () => {
    for (const [key, value] of Object.entries(settings)) {
      await axios.put(`/api/settings/${key}`, { value });
    }
    alert('Settings saved successfully!');
  };

  return (
    <div className={classes.root}>
      <Paper className={classes.paper}>
        <Typography variant="h6" gutterBottom>
          General Settings
        </Typography>
        <form className={classes.form} noValidate autoComplete="off">
          <TextField
            label="Language"
            value={settings.language || ''}
            onChange={(e) => handleSettingChange('language', e.target.value)}
          />
          <TextField
            label="Theme"
            value={settings.theme || ''}
            onChange={(e) => handleSettingChange('theme', e.target.value)}
          />
          <TextField
            label="Time Zone"
            value={settings.timeZone || ''}
            onChange={(e) => handleSettingChange('timeZone', e.target.value)}
          />
          <Button variant="contained" color="primary" onClick={handleSaveSettings}>
            Save Settings
          </Button>
        </form>
      </Paper>
    </div>
  );
}

export default Settings;
EOF

# Create Backups component
cat << 'EOF' > frontend/src/components/Backups.js
import React, { useState, useEffect } from 'react';
import { makeStyles } from '@material-ui/core/styles';
import { 
  Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper, 
  Button, Typography 
} from '@material-ui/core';
import axios from 'axios';

const useStyles = makeStyles((theme) => ({
  root: {
    width: '100%',
  },
  paper: {
    width: '100%',
    marginBottom: theme.spacing(2),
  },
  table: {
    minWidth: 750,
  },
}));

function Backups() {
  const classes = useStyles();
  const [backups, setBackups] = useState([]);

  useEffect(() => {
    fetchBackups();
  }, []);

  const fetchBackups = async () => {
    const response = await axios.get('/api/backups');
    setBackups(response.data);
  };

  const handleCreateBackup = async () => {
    await axios.post('/api/backups');
    fetchBackups();
  };

  const handleDownloadBackup = async (id) => {
    const response = await axios.get(`/api/backups/${id}/download`, { responseType: 'blob' });
    const url = window.URL.createObjectURL(new Blob([response.data]));
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `backup_${id}.zip`);
    document.body.appendChild(link);
    link.click();
  };

  return (
    <div className={classes.root}>
      <Button variant="contained" color="primary" onClick={handleCreateBackup}>
        Create Backup
      </Button>
      <Paper className={classes.paper}>
        <TableContainer>
          <Table className={classes.table} aria-labelledby="tableTitle" size="medium" aria-label="enhanced table">
            <TableHead>
              <TableRow>
                <TableCell>ID</TableCell>
                <TableCell>Created At</TableCell>
                <TableCell>Size</TableCell>
                <TableCell>Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {backups.map((backup) => (
                <TableRow key={backup.id}>
                  <TableCell component="th" scope="row">{backup.id}</TableCell>
                  <TableCell>{new Date(backup.createdAt).toLocaleString()}</TableCell>
                  <TableCell>{backup.size}</TableCell>
                  <TableCell>
                    <Button variant="contained" color="primary" onClick={() => handleDownloadBackup(backup.id)}>
                      Download
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
    </div>
  );
}

export default Backups;
EOF

# Create Connections component
cat << 'EOF' > frontend/src/components/Connections.js
import React, { useState, useEffect } from 'react';
import { makeStyles } from '@material-ui/core/styles';
import { 
  Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper, 
  Button, Typography 
} from '@material-ui/core';
import axios from 'axios';

const useStyles = makeStyles((theme) => ({
  root: {
    width: '100%',
  },
  paper: {
    width: '100%',
    marginBottom: theme.spacing(2),
  },
  table: {
    minWidth: 750,
  },
}));

function Connections() {
  const classes = useStyles();
  const [connections, setConnections] = useState([]);

  useEffect(() => {
    fetchConnections();
    const interval = setInterval(fetchConnections, 5000);
    return () => clearInterval(interval);
  }, []);

  const fetchConnections = async () => {
    const response = await axios.get('/api/connections');
    setConnections(response.data);
  };

  const handleKillConnection = async (id) => {
    await axios.post(`/api/connections/${id}/kill`);
    fetchConnections();
  };

  return (
    <div className={classes.root}>
      <Paper className={classes.paper}>
        <TableContainer>
          <Table className={classes.table} aria-labelledby="tableTitle" size="medium" aria-label="enhanced table">
            <TableHead>
              <TableRow>
                <TableCell>Username</TableCell>
                <TableCell>IP Address</TableCell>
                <TableCell>Protocol</TableCell>
                <TableCell>Connected Since</TableCell>
                <TableCell>Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {connections.map((connection) => (
                <TableRow key={connection.id}>
                  <TableCell component="th" scope="row">{connection.username}</TableCell>
                  <TableCell>{connection.ipAddress}</TableCell>
                  <TableCell>{connection.protocol}</TableCell>
                  <TableCell>{new Date(connection.connectedAt).toLocaleString()}</TableCell>
                  <TableCell>
                    <Button 
                      variant="contained" 
                      color="secondary" 
                      onClick={() => handleKillConnection(connection.id)}
                    >
                      Kill Connection
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
    </div>
  );
}

export default Connections;
EOF

# Create Login component
cat << 'EOF' > frontend/src/components/Login.js
import React, { useState } from 'react';
import { makeStyles } from '@material-ui/core/styles';
import { Paper, TextField, Button, Typography } from '@material-ui/core';
import axios from 'axios';
import { useHistory } from 'react-router-dom';

const useStyles = makeStyles((theme) => ({
  root: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100vh',
  },
  paper: {
    padding: theme.spacing(3),
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    width: '300px',
  },
  form: {
    width: '100%',
    marginTop: theme.spacing(1),
  },
  submit: {
    margin: theme.spacing(3, 0, 2),
  },
}));

function Login() {
  const classes = useStyles();
  const history = useHistory();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  const handleLogin = async (e) => {
    e.preventDefault();
    try {
      const response = await axios.post('/api/auth/login', { username, password });
      localStorage.setItem('token', response.data.token);
      history.push('/');
    } catch (error) {
      alert('Login failed. Please check your credentials.');
    }
  };

  return (
    <div className={classes.root}>
      <Paper className={classes.paper}>
        <Typography component="h1" variant="h5">
          Login
        </Typography>
        <form className={classes.form} onSubmit={handleLogin}>
          <TextField
            variant="outlined"
            margin="normal"
            required
            fullWidth
            id="username"
            label="Username"
            name="username"
            autoComplete="username"
            autoFocus
            value={username}
            onChange={(e) => setUsername(e.target.value)}
          />
          <TextField
            variant="outlined"
            margin="normal"
            required
            fullWidth
            name="password"
            label="Password"
            type="password"
            id="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <Button
            type="submit"
            fullWidth
            variant="contained"
            color="primary"
            className={classes.submit}
          >
            Sign In
          </Button>
        </form>
      </Paper>
    </div>
  );
}

export default Login;
EOF

# Create PrivateRoute component
cat << 'EOF' > frontend/src/components/PrivateRoute.js
import React from 'react';
import { Route, Redirect } from 'react-router-dom';

const PrivateRoute = ({ component: Component, ...rest }) => (
  <Route
    {...rest}
    render={(props) =>
      localStorage.getItem('token') ? (
        <Component {...props} />
      ) : (
        <Redirect to="/login" />
      )
    }
  />
);

export default PrivateRoute;
EOF

# Create Navbar component
cat << 'EOF' > frontend/src/components/Navbar.js
import React from 'react';
import { makeStyles } from '@material-ui/core/styles';
import { Drawer, List, ListItem, ListItemIcon, ListItemText, Divider } from '@material-ui/core';
import { Link } from 'react-router-dom';
import DashboardIcon from '@material-ui/icons/Dashboard';
import PeopleIcon from '@material-ui/icons/People';
import SettingsIcon from '@material-ui/icons/Settings';
import BackupIcon from '@material-ui/icons/Backup';
import NetworkCheckIcon from '@material-ui/icons/NetworkCheck';
import ExitToAppIcon from '@material-ui/icons/ExitToApp';

const drawerWidth = 240;

const useStyles = makeStyles((theme) => ({
  drawer: {
    width: drawerWidth,
    flexShrink: 0,
  },
  drawerPaper: {
    width: drawerWidth,
  },
  toolbar: theme.mixins.toolbar,
}));

function Navbar() {
  const classes = useStyles();

  const handleLogout = () => {
    localStorage.removeItem('token');
    window.location.href = '/login';
  };

  return (
    <Drawer
      className={classes.drawer}
      variant="permanent"
      classes={{
        paper: classes.drawerPaper,
      }}
      anchor="left"
    >
      <div className={classes.toolbar} />
      <Divider />
      <List>
        <ListItem button component={Link} to="/">
          <ListItemIcon><DashboardIcon /></ListItemIcon>
          <ListItemText primary="Dashboard" />
        </ListItem>
        <ListItem button component={Link} to="/users">
          <ListItemIcon><PeopleIcon /></ListItemIcon>
          <ListItemText primary="Users" />
        </ListItem>
        <ListItem button component={Link} to="/protocols">
          <ListItemIcon><NetworkCheckIcon /></ListItemIcon>
          <ListItemText primary="Protocols" />
        </ListItem>
        <ListItem button component={Link} to="/settings">
          <ListItemIcon><SettingsIcon /></ListItemIcon>
          <ListItemText primary="Settings" />
        </ListItem>
        <ListItem button component={Link} to="/backups">
          <ListItemIcon><BackupIcon /></ListItemIcon>
          <ListItemText primary="Backups" />
        </ListItem>
        <ListItem button component={Link} to="/connections">
          <ListItemIcon><NetworkCheckIcon /></ListItemIcon>
          <ListItemText primary="Connections" />
        </ListItem>
      </List>
      <Divider />
      <List>
        <ListItem button onClick={handleLogout}>
          <ListItemIcon><ExitToAppIcon /></ListItemIcon>
          <ListItemText primary="Logout" />
        </ListItem>
      </List>
    </Drawer>
  );
}

export default Navbar;
EOF

# Backend setup
cd ../backend

# Initialize package.json
cat << 'EOF' > package.json
{
  "name": "vpn-management-backend",
  "version": "1.0.0",
  "description": "Backend for VPN Management System",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "dev": "nodemon src/index.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "dotenv": "^10.0.0",
    "express": "^4.17.1",
    "jsonwebtoken": "^8.5.1",
    "pg": "^8.7.1",
    "prisma": "^3.6.0",
    "@prisma/client": "^3.6.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.15"
  }
}
EOF

# Install backend dependencies
npm install

# Create Prisma schema
mkdir prisma
cat << 'EOF' > prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  username  String   @unique
  email     String   @unique
  password  String
  status    String
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
}

model Protocol {
  id           Int      @id @default(autoincrement())
  name         String   @unique
  version      String
  isInstalled  Boolean
  installDate  DateTime?
  config       Json?
}

model Setting {
  id    Int    @id @default(autoincrement())
  key   String @unique
  value String
}

model Backup {
  id        Int      @id @default(autoincrement())
  filename  String
  createdAt DateTime @default(now())
  size      Int
  status    String
}

model Connection {
  id         Int      @id @default(autoincrement())
  userId     Int
  protocolId Int
  ipAddress  String
  connectedAt DateTime @default(now())
  disconnectedAt DateTime?
  bytesSent  Int
  bytesReceived Int
}
EOF

# Create .env file
cat << 'EOF' > .env
DATABASE_URL="postgresql://username:password@localhost:5432/vpn_management?schema=public"
JWT_SECRET="your-jwt-secret"
EOF

# Create src directory and main server file
mkdir src
cat << 'EOF' > src/index.js
const express = require('express');
const cors = require('cors');
const { PrismaClient } = require('@prisma/client');
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const protocolRoutes = require('./routes/protocols');
const settingRoutes = require('./routes/settings');
const backupRoutes = require('./routes/backups');
const connectionRoutes = require('./routes/connections');

const prisma = new PrismaClient();
const app = express();

app.use(cors());
app.use(express.json());

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/protocols', protocolRoutes);
app.use('/api/settings', settingRoutes);
app.use('/api/backups', backupRoutes);
app.use('/api/connections', connectionRoutes);

const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
EOF

# Create routes
mkdir src/routes

# Auth routes
cat << 'EOF' > src/routes/auth.js
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { PrismaClient } = require('@prisma/client');

const router = express.Router();
const prisma = new PrismaClient();

router.post('/login', async (req, res) => {
  const { username, password } = req.body;

  try {
    const user = await prisma.user.findUnique({ where: { username } });
    if (!user) {
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET, { expiresIn: '1h' });
    res.json({ token });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
EOF

# User routes
cat << 'EOF' > src/routes/users.js
const express = require('express');
const bcrypt = require('bcryptjs');
const { PrismaClient } = require('@prisma/client');

const router = express.Router();
const prisma = new PrismaClient();

router.get('/', async (req, res) => {
  try {
    const users = await prisma.user.findMany({ select: { id: true, username: true, email: true, status: true } });
    res.json(users);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

router.post('/', async (req, res) => {
  const { username, email, password } = req.body;

  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: {
        username,
        email,
        password: hashedPassword,
        status: 'active'
      }
    });
    res.status(201).json({ id: user.id, username: user.username, email: user.email, status: user.status });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Add more user routes (update, delete) as needed

module.exports = router;
EOF

# Protocol routes
cat << 'EOF' > src/routes/protocols.js
const express = require('express');
const { PrismaClient } = require('@prisma/client');

const router = express.Router();
const prisma = new PrismaClient();

router.get('/', async (req, res) => {
  try {
    const protocols = await prisma.protocol.findMany();
    res.json(protocols);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

router.post('/install/:name', async (req, res) => {
  const { name } = req.params;

  try {
    const protocol = await prisma.protocol.update({
      where: { name },
      data: { isInstalled: true, installDate: new Date() }
    });
    res.json(protocol);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Add more protocol routes as needed

module.exports = router;
EOF

# Setting routes
cat << 'EOF' > src/routes/settings.js
const express = require('express');
const { PrismaClient } = require('@prisma/client');

const router = express.Router();
const prisma = new PrismaClient();

router.get('/', async (req, res) => {
  try {
    const settings = await prisma.setting.findMany();
    res.json(settings);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

router.put('/:key', async (req, res) => {
  const { key } = req.params;
  const { value } = req.body;

  try {
    const setting = await prisma.setting.update({
      where: { key },
      data: { value }
    });
    res.json(setting);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
EOF

# Backup routes
cat << 'EOF' > src/routes/backups.js
const express = require('express');
const { PrismaClient } = require('@prisma/client');

const router = express.Router();
const prisma = new PrismaClient();

router.get('/', async (req, res) => {
  try {
    const backups = await prisma.backup.findMany();
    res.json(backups);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

router.post('/', async (req, res) => {
  try {
    // Implement backup creation logic here
    const backup = await prisma.backup.create({
      data: {
        filename: `backup_${Date.now()}.zip`,
        size: 0, // Update with actual size
        status: 'created'
      }
    });
    res.status(201).json(backup);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Add more backup routes (download, delete) as needed

module.exports = router;
EOF

# Connection routes
cat << 'EOF' > src/routes/connections.js
const express = require('express');
const { PrismaClient } = require('@prisma/client');

const router = express.Router();
const prisma = new PrismaClient();

router.get('/', async (req, res) => {
  try {
    const connections = await prisma.connection.findMany({
      where: { disconnectedAt: null },
      include: { user: true, protocol: true }
    });
    res.json(connections);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

router.post('/:id/kill', async (req, res) => {
  const { id } = req.params;

  try {
    const connection = await prisma.connection.update({
      where: { id: parseInt(id) },
      data: { disconnectedAt: new Date() }
    });
    res.json(connection);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
EOF

# Create middleware for authentication
mkdir src/middleware
cat << 'EOF' > src/middleware/auth.js
const jwt = require('jsonwebtoken');

module.exports = (req, res, next) => {
  const token = req.header('x-auth-token');

  if (!token) {
    return res.status(401).json({ message: 'No token, authorization denied' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded.user;
    next();
  } catch (err) {
    res.status(401).json({ message: 'Token is not valid' });
  }
};
EOF

# Frontend setup
cd ../frontend

# Install frontend dependencies
npm install

# Create public directory and index.html
mkdir public
cat << 'EOF' > public/index.html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>VPN Management System</title>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
EOF

# Main VPN Management System script
cd ../..
cat << 'EOF' > install_vpn_management.sh
#!/bin/bash

# Update and upgrade system
apt update && apt upgrade -y

# Install Node.js and npm
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
apt install -y nodejs

# Install PostgreSQL
apt install -y postgresql postgresql-contrib

# Set up the database
sudo -u postgres psql -c "CREATE DATABASE vpn_management;"
sudo -u postgres psql -c "CREATE USER vpn_user WITH ENCRYPTED PASSWORD 'your_password';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpn_management TO vpn_user;"

# Clone the VPN Management System repository
git clone https://github.com/your-repo/vpn-management-system.git
cd vpn-management-system

# Install backend dependencies
cd backend
npm install

# Set up Prisma
npx prisma generate
npx prisma migrate dev

# Start the backend server
npm start &

# Install frontend dependencies
cd ../frontend
npm install

# Build the frontend
npm run build

# Install and configure Nginx
apt install -y nginx
cat << 'EOF_NGINX' > /etc/nginx/sites-available/vpn-management
server {
    listen 80;
    server_name your_domain.com;

    location / {
        root /path/to/vpn-management-system/frontend/build;
        try_files $uri /index.html;
    }

    location /api {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF_NGINX

ln -s /etc/nginx/sites-available/vpn-management /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo "VPN Management System installed successfully!"
EOF

chmod +x install_vpn_management.sh

echo "The VPN Management System setup script has been created. You can run it using:"
echo "sudo ./install_vpn_management.sh"
