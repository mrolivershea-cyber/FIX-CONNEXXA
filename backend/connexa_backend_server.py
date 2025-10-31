#!/usr/bin/env python3
"""
CONNEXA Backend Server v7.9
Provides REST API and web admin interface on port 8081
"""

from flask import Flask, jsonify, render_template_string
import subprocess
import logging
import sys
import re
import os

# Configuration
PORT = 8081
LOGFILE = "/var/log/connexa-backend.log"

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [Backend] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.FileHandler(LOGFILE),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)
app = Flask(__name__)


def log(message):
    """Log message"""
    logger.info(message)


def run_command(cmd, timeout=10):
    """Run shell command and return output"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.stdout.strip()
    except Exception as e:
        return f"Error: {e}"


def get_ppp_interfaces():
    """Get list of active PPP interfaces"""
    try:
        output = run_command("ip a")
        interfaces = []
        for line in output.split('\n'):
            match = re.search(r'(\d+):\s+(ppp\d+):.*state\s+(\w+)', line)
            if match:
                interfaces.append({
                    'id': match.group(1),
                    'name': match.group(2),
                    'state': match.group(3)
                })
        return interfaces
    except Exception as e:
        log(f"Error getting PPP interfaces: {e}")
        return []


def get_socks_ports():
    """Get list of active SOCKS ports"""
    ports = []
    for port in range(1080, 1090):
        result = run_command(f"lsof -i :{port}", timeout=2)
        if result and "LISTEN" in result:
            ports.append(port)
    return ports


def get_system_stats():
    """Get system statistics"""
    stats = {}
    
    # Uptime
    uptime = run_command("uptime -p")
    stats['uptime'] = uptime
    
    # Load average
    load = run_command("cat /proc/loadavg | cut -d' ' -f1-3")
    stats['load'] = load
    
    # Memory
    mem = run_command("free -h | grep Mem | awk '{print $3\"/\"$2}'")
    stats['memory'] = mem
    
    return stats


# API Endpoints

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'connexa-backend',
        'version': '7.9',
        'port': PORT
    })


@app.route('/metrics')
def metrics():
    """Metrics endpoint for monitoring"""
    ppp_interfaces = get_ppp_interfaces()
    socks_ports = get_socks_ports()
    stats = get_system_stats()
    
    return jsonify({
        'ppp_interfaces': len([i for i in ppp_interfaces if i['state'] == 'UP']),
        'ppp_total': len(ppp_interfaces),
        'socks_ports': len(socks_ports),
        'interfaces': ppp_interfaces,
        'ports': socks_ports,
        'system': stats
    })


@app.route('/api/status')
def api_status():
    """Detailed status API"""
    ppp_interfaces = get_ppp_interfaces()
    socks_ports = get_socks_ports()
    stats = get_system_stats()
    
    # Check supervisor services
    supervisor_status = run_command("supervisorctl status")
    
    return jsonify({
        'status': 'running',
        'ppp_interfaces': ppp_interfaces,
        'socks_ports': socks_ports,
        'system_stats': stats,
        'supervisor': supervisor_status.split('\n')
    })


@app.route('/')
def index():
    """Web admin dashboard"""
    ppp_interfaces = get_ppp_interfaces()
    socks_ports = get_socks_ports()
    stats = get_system_stats()
    
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>CONNEXA Admin Panel v7.9</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                margin: 20px;
                background: #f5f5f5;
            }
            .container {
                max-width: 1200px;
                margin: 0 auto;
                background: white;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            h1 {
                color: #333;
                border-bottom: 3px solid #4CAF50;
                padding-bottom: 10px;
            }
            .status {
                display: flex;
                gap: 20px;
                margin: 20px 0;
            }
            .card {
                flex: 1;
                padding: 20px;
                background: #f9f9f9;
                border-radius: 5px;
                border-left: 4px solid #4CAF50;
            }
            .card h2 {
                margin-top: 0;
                color: #555;
                font-size: 16px;
            }
            .card .value {
                font-size: 32px;
                font-weight: bold;
                color: #4CAF50;
            }
            table {
                width: 100%;
                border-collapse: collapse;
                margin: 20px 0;
            }
            th, td {
                padding: 12px;
                text-align: left;
                border-bottom: 1px solid #ddd;
            }
            th {
                background: #4CAF50;
                color: white;
            }
            .up {
                color: #4CAF50;
                font-weight: bold;
            }
            .down {
                color: #f44336;
                font-weight: bold;
            }
            .refresh {
                margin: 20px 0;
            }
            .refresh button {
                background: #4CAF50;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 5px;
                cursor: pointer;
                font-size: 14px;
            }
            .refresh button:hover {
                background: #45a049;
            }
        </style>
        <script>
            function refreshData() {
                location.reload();
            }
            // Auto-refresh every 30 seconds
            setTimeout(refreshData, 30000);
        </script>
    </head>
    <body>
        <div class="container">
            <h1>🔧 CONNEXA Admin Panel v7.9</h1>
            
            <div class="status">
                <div class="card">
                    <h2>PPP Interfaces</h2>
                    <div class="value">{{ ppp_up }}/{{ ppp_total }}</div>
                    <small>Active/Total</small>
                </div>
                <div class="card">
                    <h2>SOCKS Ports</h2>
                    <div class="value">{{ socks_count }}</div>
                    <small>Listening</small>
                </div>
                <div class="card">
                    <h2>System Load</h2>
                    <div class="value" style="font-size: 20px;">{{ load }}</div>
                    <small>Load Average</small>
                </div>
            </div>
            
            <div class="refresh">
                <button onclick="refreshData()">🔄 Refresh Now</button>
                <small style="margin-left: 10px;">Auto-refresh in 30s</small>
            </div>
            
            <h2>PPP Interfaces</h2>
            <table>
                <tr>
                    <th>ID</th>
                    <th>Interface</th>
                    <th>State</th>
                </tr>
                {% for iface in interfaces %}
                <tr>
                    <td>{{ iface.id }}</td>
                    <td>{{ iface.name }}</td>
                    <td class="{{ 'up' if iface.state == 'UP' else 'down' }}">{{ iface.state }}</td>
                </tr>
                {% endfor %}
                {% if not interfaces %}
                <tr>
                    <td colspan="3" style="text-align: center; color: #999;">No PPP interfaces found</td>
                </tr>
                {% endif %}
            </table>
            
            <h2>SOCKS Ports</h2>
            <table>
                <tr>
                    <th>Port</th>
                    <th>Status</th>
                </tr>
                {% for port in ports %}
                <tr>
                    <td>{{ port }}</td>
                    <td class="up">LISTENING</td>
                </tr>
                {% endfor %}
                {% if not ports %}
                <tr>
                    <td colspan="2" style="text-align: center; color: #999;">No SOCKS ports active</td>
                </tr>
                {% endif %}
            </table>
            
            <h2>System Information</h2>
            <table>
                <tr>
                    <th>Metric</th>
                    <th>Value</th>
                </tr>
                <tr>
                    <td>Uptime</td>
                    <td>{{ uptime }}</td>
                </tr>
                <tr>
                    <td>Memory Usage</td>
                    <td>{{ memory }}</td>
                </tr>
                <tr>
                    <td>Load Average</td>
                    <td>{{ load }}</td>
                </tr>
            </table>
            
            <p style="margin-top: 30px; color: #999; font-size: 12px;">
                CONNEXA Backend v7.9 | Port {{ port }} | 
                <a href="/api/status" style="color: #4CAF50;">API Status</a> | 
                <a href="/metrics" style="color: #4CAF50;">Metrics</a>
            </p>
        </div>
    </body>
    </html>
    """
    
    ppp_up = len([i for i in ppp_interfaces if i['state'] == 'UP'])
    
    return render_template_string(
        html,
        ppp_up=ppp_up,
        ppp_total=len(ppp_interfaces),
        socks_count=len(socks_ports),
        interfaces=ppp_interfaces,
        ports=socks_ports,
        uptime=stats.get('uptime', 'Unknown'),
        memory=stats.get('memory', 'Unknown'),
        load=stats.get('load', 'Unknown'),
        port=PORT
    )


if __name__ == '__main__':
    log("=" * 50)
    log(f"CONNEXA Backend Server v7.9 starting on port {PORT}")
    log("=" * 50)
    log(f"Backend service started on port {PORT}")
    log(f"Web admin available at: http://localhost:{PORT}/")
    log(f"Health check: http://localhost:{PORT}/health")
    log(f"Metrics: http://localhost:{PORT}/metrics")
    
    try:
        app.run(host='0.0.0.0', port=PORT, debug=False)
    except Exception as e:
        log(f"Fatal error: {e}")
        sys.exit(1)
