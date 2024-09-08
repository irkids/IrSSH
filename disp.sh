#!/bin/bash

# ---- Initial setup: Check directories and permissions ----

# Check if the directory exists, if not, create it
if [ ! -d "/var/www/html/app/Scripts" ]; then
  echo "Directory /var/www/html/app/Scripts not found. Creating it..."
  sudo mkdir -p /var/www/html/app/Scripts
fi

# Check if get_network_stats.php file exists, if not, create a placeholder
if [ ! -f "/var/www/html/app/Scripts/get_network_stats.php" ]; then
  echo "File get_network_stats.php not found. Creating a placeholder..."
  sudo touch /var/www/html/app/Scripts/get_network_stats.php
  echo "<?php // Placeholder for get_network_stats.php ?>" | sudo tee /var/www/html/app/Scripts/get_network_stats.php > /dev/null
fi

# Set ownership and permissions for the files
echo "Setting ownership and permissions for /var/www/html/..."
sudo chown -R www-data:www-data /var/www/html/
sudo chmod -R 755 /var/www/html/

# ---- Install and Configure Nethogs ----

# Install nethogs if not already installed
if ! command -v nethogs &> /dev/null
then
    echo "Nethogs could not be found. Installing Nethogs..."
    sudo apt-get update && sudo apt-get install -y nethogs
else
    echo "Nethogs is already installed."
fi

# Function to extract network stats using nethogs and display in real-time
cat > /var/www/html/app/Scripts/get_network_stats.php <<EOF
<?php
function get_network_stats() {
    \$interface = "eth0"; // Adjust this if necessary for your network interface
    
    // Execute the nethogs command to get network stats
    \$output = shell_exec("nethogs -t -c 1 | grep ssh");
    
    // If there's output from nethogs, return it
    if (\$output) {
        return nl2br(\$output);
    } else {
        return "No data available";
    }
}

echo get_network_stats();
EOF

# ---- Add Laravel API route for network stats ----
echo "Route::get('/network-stats', function () { return response()->json(shell_exec('php /var/www/html/app/Scripts/get_network_stats.php')); });" >> /var/www/html/app/routes/api.php

# ---- React component for displaying network stats in the Online User section ----

cat > /var/www/html/app/resources/js/components/NetworkStats.js <<EOF
import React, { useState, useEffect } from 'react';
import { Card, CardHeader, CardContent } from '@/components/ui/card';

const NetworkStats = () => {
    const [stats, setStats] = useState({ data: 'Loading...' });

    useEffect(() => {
        const fetchStats = async () => {
            try {
                const response = await fetch('/api/network-stats');
                const data = await response.text();
                setStats({ data });
            } catch (error) {
                console.error('Error fetching network stats:', error);
            }
        };

        fetchStats();
        const interval = setInterval(fetchStats, 5000); // Refresh every 5 seconds

        return () => clearInterval(interval);
    }, []);

    return (
        <Card className="w-full max-w-sm mx-auto">
            <CardHeader>Network Statistics</CardHeader>
            <CardContent>
                <pre>{stats.data}</pre>
            </CardContent>
        </Card>
    );
};

export default NetworkStats;
EOF

# ---- Import and use the component in the Dashboard ----
cat >> /var/www/html/app/resources/js/components/Dashboard.js <<EOF
import NetworkStats from './components/NetworkStats';

function Dashboard() {
  return (
    <div>
      {/* Other dashboard components */}
      <NetworkStats />
      {/* More dashboard components */}
    </div>
  );
}
EOF

# ---- Build and Refresh Frontend (React) ----
cd /var/www/html/app

# Ensure npm is installed
if ! command -v npm &> /dev/null
then
    echo "npm is not installed. Installing npm..."
    sudo apt-get install -y npm
fi

# Install dependencies and build the project
echo "Installing npm dependencies and building frontend..."
npm install
npm run build

# ---- Test the API endpoint ----
echo "Testing API endpoint to check network stats..."
curl http://localhost/api/network-stats

# Final message
echo "Setup complete. The network statistics will be displayed in the Online User section."
