#!/bin/bash

# Environment variables
export POSTGRES_USER="postgres"
export POSTGRES_PASSWORD="mysecretpassword"
export POSTGRES_DB="scanner_db"
export DB_HOST="localhost"
export DB_PORT="5432"

# Install dependencies
function install_dependencies() {
    apt-get update
    apt-get install -y nmap postgresql postgresql-contrib python3-pip docker.io iperf3
    pip3 install psycopg2-binary nmap docker backoff aioping pyyaml prometheus_client
}

# Setup Docker and PostgreSQL
function setup_docker() {
    cat << EOF > docker-compose.yml
version: '3.1'
services:
  postgres:
    image: postgres:latest
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    ports:
      - "\${DB_PORT}:\${DB_PORT}"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
EOF

    docker-compose up -d
}

# Initialize database
function init_database() {
    until docker exec postgres pg_isready -U ${POSTGRES_USER}; do
        echo "Waiting for PostgreSQL..."
        sleep 2
    done

    docker exec -i postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} << EOF
    CREATE TABLE IF NOT EXISTS udp_ports (
        id SERIAL PRIMARY KEY,
        ip_version VARCHAR(4),
        server_ip VARCHAR(45),
        port INT,
        stability FLOAT,
        ping FLOAT,
        packet_loss FLOAT,
        throughput FLOAT,
        quality_score FLOAT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(server_ip, port)
    );

    CREATE TABLE IF NOT EXISTS scan_metrics (
        id SERIAL PRIMARY KEY,
        scan_duration FLOAT,
        ports_scanned INT,
        open_ports INT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS scan_requests (
        id SERIAL PRIMARY KEY,
        request_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        status VARCHAR(20) DEFAULT 'pending'
    );

    CREATE INDEX idx_quality_score ON udp_ports(quality_score DESC);
EOF
}

# Create Python scanner
function create_python_scanner() {
    cat << 'EOF' > udp_scanner.py
import asyncio
import nmap
import psycopg2
from psycopg2 import pool
import time
import concurrent.futures
import docker
import logging
import os
import yaml
from prometheus_client import start_http_server, Counter, Gauge
import backoff
import aioping
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Database configuration from environment
db_config = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", 5432)),
    "user": os.getenv("POSTGRES_USER", "postgres"),
    "password": os.getenv("POSTGRES_PASSWORD", "mysecretpassword"),
    "dbname": os.getenv("POSTGRES_DB", "scanner_db")
}

# Initialize metrics
SCAN_COUNTER = Counter('port_scans_total', 'Total number of port scans')
OPEN_PORTS = Gauge('open_ports_total', 'Number of open ports found')
SCAN_DURATION = Gauge('scan_duration_seconds', 'Duration of port scan')

class DatabasePool:
    _instance = None

    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = pool.SimpleConnectionPool(1, 20, **db_config)
        return cls._instance

    @classmethod
    def close_all(cls):
        if cls._instance:
            cls._instance.closeall()

async def scan_port(ip, port):
    try:
        start_time = time.time()
        ping_result = await aioping.ping(ip)
        
        scanner = nmap.PortScanner()
        scanner.scan(ip, str(port), arguments='-sU -T4')
        
        if scanner[ip].has_tcp(port):
            throughput, packet_loss = await measure_performance(ip, port)
            quality_score = calculate_quality_score(ping_result, throughput, packet_loss)
            
            return {
                'port': port,
                'ping': ping_result,
                'throughput': throughput,
                'packet_loss': packet_loss,
                'quality_score': quality_score
            }
    except Exception as e:
        logger.error(f"Error scanning port {port}: {e}")
    return None

async def measure_performance(ip, port):
    try:
        # Simulate network performance measurement
        throughput = float(os.popen(f"iperf3 -c {ip} -u -p {port} -t 5 2>/dev/null | grep receiver | awk '{{print $7}}'").read().strip())
        packet_loss = float(os.popen(f"ping -c 10 {ip} | grep 'packet loss' | awk '{{print $6}}' | cut -d'%' -f1").read().strip())
        return throughput, packet_loss
    except:
        return 0.0, 100.0

def calculate_quality_score(ping, throughput, packet_loss):
    if ping is None or throughput is None or packet_loss is None:
        return 0.0
    # Higher score for lower ping and packet loss, higher throughput
    return (100 - packet_loss) * 0.4 + (min(throughput, 100) * 0.4) + ((1000 - min(ping, 1000)) / 10 * 0.2)

@backoff.on_exception(backoff.expo, psycopg2.Error, max_tries=3)
def store_results(results):
    conn = DatabasePool.get_instance().getconn()
    try:
        with conn.cursor() as cur:
            for result in results:
                if result:
                    cur.execute("""
                        INSERT INTO udp_ports (server_ip, port, ping, throughput, packet_loss, quality_score)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        ON CONFLICT (server_ip, port) 
                        DO UPDATE SET 
                            ping = EXCLUDED.ping,
                            throughput = EXCLUDED.throughput,
                            packet_loss = EXCLUDED.packet_loss,
                            quality_score = EXCLUDED.quality_score,
                            timestamp = CURRENT_TIMESTAMP
                    """, (ip, result['port'], result['ping'], result['throughput'],
                         result['packet_loss'], result['quality_score']))
            conn.commit()
    finally:
        DatabasePool.get_instance().putconn(conn)

async def main():
    try:
        start_http_server(8000)  # Prometheus metrics
        start_time = time.time()
        
        # Sample IP addresses (replace with actual IPs)
        ipv4 = "192.168.1.1"
        ipv6 = "2001:db8::1"
        
        # Scan ports asynchronously
        tasks = []
        for port in range(1, 65536):
            if ipv4:
                tasks.append(scan_port(ipv4, port))
            if ipv6:
                tasks.append(scan_port(ipv6, port))
        
        results = await asyncio.gather(*tasks)
        valid_results = [r for r in results if r]
        
        # Store results
        await store_results(valid_results)
        
        # Update metrics
        duration = time.time() - start_time
        SCAN_DURATION.set(duration)
        SCAN_COUNTER.inc()
        OPEN_PORTS.set(len(valid_results))
        
        logger.info(f"Scan completed in {duration:.2f} seconds")
        
    except Exception as e:
        logger.error(f"Error in main: {e}")
    finally:
        DatabasePool.close_all()

if __name__ == "__main__":
    asyncio.run(main())
EOF
}

# Monitoring function
function monitor() {
    echo "=== System Status ==="
    docker ps
    echo "=== Database Status ==="
    docker exec postgres pg_isready -U ${POSTGRES_USER}
    echo "=== Recent Scan Results ==="
    docker exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c \
        "SELECT server_ip, port, quality_score FROM udp_ports ORDER BY quality_score DESC LIMIT 5;"
}

# Check for scan requests
function check_scan_requests() {
    local request_id=$(docker exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -t -c \
        "SELECT id FROM scan_requests WHERE status = 'pending' ORDER BY request_time LIMIT 1;")
    
    if [ -n "$request_id" ]; then
        echo "Processing scan request $request_id"
        docker exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c \
            "UPDATE scan_requests SET status = 'processing' WHERE id = $request_id;"
        
        python3 udp_scanner.py
        monitor
        
        docker exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c \
            "UPDATE scan_requests SET status = 'completed' WHERE id = $request_id;"
    fi
}

# Main execution
function main() {
    install_dependencies
    setup_docker
    init_database
    create_python_scanner
    
    while true; do
        check_scan_requests
        sleep 60  # Check for requests every minute
    done
}

# Cleanup function
function cleanup() {
    echo "Cleaning up..."
    docker-compose down -v
    rm -f udp_scanner.py docker-compose.yml
}

# Set trap for cleanup
trap cleanup EXIT

# Start the script
main
