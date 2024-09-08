#!/bin/bash

# نصب نیازمندی‌ها
apt-get update && apt-get install -y php curl

# تنظیمات اولیه شبکه برای گرفتن سرعت و میزان مصرف
cat > /var/www/html/app/Scripts/get_network_stats.php <<EOF
<?php
function get_network_stats() {
    \$interface = "eth0"; // اگر نیاز به تغییر اینترفیس هست، تغییر دهید
    
    // دریافت آمار شبکه
    \$current = file("/sys/class/net/\$interface/statistics/rx_bytes")[0] + 
               file("/sys/class/net/\$interface/statistics/tx_bytes")[0];
    
    // انتظار 1 ثانیه
    sleep(1);
    
    // دریافت آمار جدید شبکه
    \$new = file("/sys/class/net/\$interface/statistics/rx_bytes")[0] + 
           file("/sys/class/net/\$interface/statistics/tx_bytes")[0];
    
    // محاسبه سرعت
    \$speed = \$new - \$current;
    
    return [
        'speed' => format_speed(\$speed),
        'rx' => format_speed(file("/sys/class/net/\$interface/statistics/rx_bytes")[0]),
        'tx' => format_speed(file("/sys/class/net/\$interface/statistics/tx_bytes")[0])
    ];
}

function format_speed(\$bytes) {
    \$units = ['B', 'KB', 'MB', 'GB', 'TB'];
    \$bytes = max(\$bytes, 0);
    \$pow = floor((\$bytes ? log(\$bytes) : 0) / log(1024));
    \$pow = min(\$pow, count(\$units) - 1);
    \$bytes /= (1 << (10 * \$pow));
    return round(\$bytes, 2) . ' ' . \$units[\$pow] . '/s';
}

echo json_encode(get_network_stats());
EOF

# اضافه کردن Route جدید به فایل لاراول
echo "Route::get('/network-stats', function () { return response()->json(json_decode(shell_exec('php /var/www/html/app/Scripts/get_network_stats.php'))); });" >> /var/www/html/app/routes/api.php

# اضافه کردن کامپوننت ریکت برای نمایش آمار شبکه
cat > /var/www/html/app/resources/js/components/NetworkStats.js <<EOF
import React, { useState, useEffect } from 'react';
import { Card, CardHeader, CardContent } from '@/components/ui/card';
import { ArrowUpRight, ArrowDownRight, Activity } from 'lucide-react';

const NetworkStats = () => {
    const [stats, setStats] = useState({ speed: '0 B/s', rx: '0 B', tx: '0 B' });

    useEffect(() => {
        const fetchStats = async () => {
            try {
                const response = await fetch('/api/network-stats');
                const data = await response.json();
                setStats(data);
            } catch (error) {
                console.error('Error fetching network stats:', error);
            }
        };

        fetchStats();
        const interval = setInterval(fetchStats, 5000); // بروزرسانی هر 5 ثانیه

        return () => clearInterval(interval);
    }, []);

    return (
        <Card className="w-full max-w-sm mx-auto">
            <CardHeader>Network Statistics</CardHeader>
            <CardContent>
                <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center">
                        <Activity className="mr-2" />
                        <span>سرعت فعلی:</span>
                    </div>
                    <span className="font-bold">{stats.speed}</span>
                </div>
                <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center">
                        <ArrowDownRight className="mr-2" />
                        <span>کل دریافت شده:</span>
                    </div>
                    <span className="font-bold">{stats.rx}</span>
                </div>
                <div className="flex items-center justify-between">
                    <div className="flex items-center">
                        <ArrowUpRight className="mr-2" />
                        <span>کل ارسال شده:</span>
                    </div>
                    <span className="font-bold">{stats.tx}</span>
                </div>
            </CardContent>
        </Card>
    );
};

export default NetworkStats;
EOF

# وارد کردن و استفاده از کامپوننت در داشبورد اصلی
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

# تنظیمات اضافی و نهایی
echo "تموم شد. اسکریپت کامل و نهایی اجرا شد."
