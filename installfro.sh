// File: frontend/src/App.js
import React from 'react';
import { BrowserRouter as Router, Route, Switch } from 'react-router-dom';
import { ThemeProvider, createTheme } from '@material-ui/core/styles';
import CssBaseline from '@material-ui/core/CssBaseline';
import Dashboard from './components/Dashboard';
import Users from './components/Users';
import Connections from './components/Connections';
import Protocols from './components/Protocols';
import Settings from './components/Settings';
import Login from './components/Login';
import PrivateRoute from './components/PrivateRoute';

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
        <Switch>
          <Route exact path="/login" component={Login} />
          <PrivateRoute exact path="/" component={Dashboard} />
          <PrivateRoute path="/users" component={Users} />
          <PrivateRoute path="/connections" component={Connections} />
          <PrivateRoute path="/protocols" component={Protocols} />
          <PrivateRoute path="/settings" component={Settings} />
        </Switch>
      </Router>
    </ThemeProvider>
  );
}

export default App;

// File: frontend/src/components/Dashboard.js
import React, { useState, useEffect } from 'react';
import { Grid, Paper, Typography } from '@material-ui/core';
import { makeStyles } from '@material-ui/core/styles';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend } from 'recharts';
import axios from 'axios';

const useStyles = makeStyles((theme) => ({
  root: {
    flexGrow: 1,
    padding: theme.spacing(3),
  },
  paper: {
    padding: theme.spacing(2),
    textAlign: 'center',
    color: theme.palette.text.secondary,
  },
}));

function Dashboard() {
  const classes = useStyles();
  const [stats, setStats] = useState({ cpu: 0, memory: 0, disk: 0 });
  const [chartData, setChartData] = useState([]);

  useEffect(() => {
    const fetchStats = async () => {
      const response = await axios.get('/api/system/stats');
      setStats(response.data);
      setChartData(prevData => [...prevData, { time: new Date().toLocaleTimeString(), ...response.data }]);
    };

    fetchStats();
    const interval = setInterval(fetchStats, 5000);

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
            <Typography variant="h6">Memory Usage</Typography>
            <Typography variant="h4">{stats.memory}%</Typography>
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
            <Typography variant="h6">System Resource Usage Over Time</Typography>
            <LineChart width={600} height={300} data={chartData}>
              <XAxis dataKey="time" />
              <YAxis />
              <CartesianGrid strokeDasharray="3 3" />
              <Tooltip />
              <Legend />
              <Line type="monotone" dataKey="cpu" stroke="#8884d8" />
              <Line type="monotone" dataKey="memory" stroke="#82ca9d" />
              <Line type="monotone" dataKey="disk" stroke="#ffc658" />
            </LineChart>
          </Paper>
        </Grid>
      </Grid>
    </div>
  );
}

export default Dashboard;

// Additional components (Users.js, Connections.js, Protocols.js, Settings.js) would be implemented similarly,
// each fetching and displaying relevant data from the backend API.

// File: frontend/src/components/PrivateRoute.js
import React from 'react';
import { Route, Redirect } from 'react-router-dom';

const PrivateRoute = ({ component: Component, ...rest }) => (
  <Route
    {...rest}
    render={props =>
      localStorage.getItem('token') ? (
        <Component {...props} />
      ) : (
        <Redirect to={{ pathname: '/login', state: { from: props.location } }} />
      )
    }
  />
);

export default PrivateRoute;

// File: frontend/src/components/Login.js
import React, { useState } from 'react';
import { TextField, Button, Typography, Container } from '@material-ui/core';
import { makeStyles } from '@material-ui/core/styles';
import axios from 'axios';
import { useHistory } from 'react-router-dom';

const useStyles = makeStyles((theme) => ({
  paper: {
    marginTop: theme.spacing(8),
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
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

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const response = await axios.post('/api/login', { username, password });
      localStorage.setItem('token', response.data.token);
      history.push('/');
    } catch (error) {
      console.error('Login failed:', error);
    }
  };

  return (
    <Container component="main" maxWidth="xs">
      <div className={classes.paper}>
        <Typography component="h1" variant="h5">
          Sign in
        </Typography>
        <form className={classes.form} onSubmit={handleSubmit}>
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
      </div>
    </Container>
  );
}

export default Login;
