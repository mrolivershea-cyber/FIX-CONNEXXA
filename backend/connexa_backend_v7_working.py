#!/usr/bin/env python3
"""
Connexa Backend Server v7 - Working Version
Port 8001 (not 8081!)
Provides API for service management and admin panel
"""

import os
import sys
import time
import json
import logging
import sqlite3
import subprocess
from datetime import datetime
from flask import Flask, jsonify, request
from flask_cors import CORS

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [Backend] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
CORS(app)  # Enable CORS for cross-origin requests from port 3000

# Database path
DB_PATH = '/root/connexa.db'

# Import service manager
sys.path.insert(0, '/usr/local/bin')
try:
    from service_manager_v7_working import ServiceManager
    service_manager = ServiceManager()
    logger.info("Service manager loaded successfully")
except ImportError as e:
    logger.error(f"Failed to load service manager: {e}")
    service_manager = None


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'timestamp': datetime.now().isoformat(),
        'service': 'connexa-backend',
        'port': 8001
    })


@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus-style metrics"""
    ppp_count = count_ppp_interfaces()
    socks_count = count_socks_ports()
    
    metrics_text = f"""# HELP connexa_ppp_interfaces Number of active PPP interfaces
# TYPE connexa_ppp_interfaces gauge
connexa_ppp_interfaces {ppp_count}

# HELP connexa_socks_ports Number of active SOCKS ports
# TYPE connexa_socks_ports gauge
connexa_socks_ports {socks_count}

# HELP connexa_backend_up Backend service status (1=up, 0=down)
# TYPE connexa_backend_up gauge
connexa_backend_up 1
"""
    return metrics_text, 200, {'Content-Type': 'text/plain; version=0.0.4'}


@app.route('/api/status', methods=['GET'])
def api_status():
    """Get system status"""
    try:
        ppp_count = count_ppp_interfaces()
        socks_count = count_socks_ports()
        
        # Get uptime
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
        
        # Get load average
        with open('/proc/loadavg', 'r') as f:
            load = f.readline().split()[:3]
        
        # Get memory info
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.readlines()
        mem_total = int([x for x in meminfo if 'MemTotal' in x][0].split()[1])
        mem_free = int([x for x in meminfo if 'MemAvailable' in x][0].split()[1])
        mem_used_pct = ((mem_total - mem_free) / mem_total) * 100
        
        return jsonify({
            'status': 'ok',
            'ppp_interfaces': ppp_count,
            'socks_ports': socks_count,
            'uptime_seconds': int(uptime_seconds),
            'load_average': load,
            'memory_used_percent': round(mem_used_pct, 2)
        })
    except Exception as e:
        logger.error(f"Error getting status: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/service/start', methods=['POST'])
def service_start():
    """Start PPTP service"""
    if not service_manager:
        return jsonify({'error': 'Service manager not available'}), 500
    
    try:
        data = request.get_json() or {}
        node_id = data.get('node_id')
        
        result = service_manager.start_service(node_id)
        return jsonify(result)
    except Exception as e:
        logger.error(f"Error starting service: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/service/stop', methods=['POST'])
def service_stop():
    """Stop PPTP service"""
    if not service_manager:
        return jsonify({'error': 'Service manager not available'}), 500
    
    try:
        data = request.get_json() or {}
        node_id = data.get('node_id')
        
        result = service_manager.stop_service(node_id)
        return jsonify(result)
    except Exception as e:
        logger.error(f"Error stopping service: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/service/status', methods=['GET'])
def service_status():
    """Get service status"""
    if not service_manager:
        return jsonify({'error': 'Service manager not available'}), 500
    
    try:
        node_id = request.args.get('node_id')
        result = service_manager.get_status(node_id)
        return jsonify(result)
    except Exception as e:
        logger.error(f"Error getting service status: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/nodes', methods=['GET'])
def get_nodes():
    """Get list of PPTP nodes from database"""
    try:
        if not os.path.exists(DB_PATH):
            return jsonify({'nodes': []})
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT id, ip, username, password, status, created_at 
            FROM nodes 
            ORDER BY created_at DESC
        """)
        
        nodes = []
        for row in cursor.fetchall():
            nodes.append({
                'id': row[0],
                'ip': row[1],
                'username': row[2],
                'password': row[3],
                'status': row[4],
                'created_at': row[5]
            })
        
        conn.close()
        return jsonify({'nodes': nodes})
    except Exception as e:
        logger.error(f"Error getting nodes: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/')
def index():
    """Simple HTML status page"""
    ppp_count = count_ppp_interfaces()
    socks_count = count_socks_ports()
    
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Connexa Backend - Port 8001</title>
        <meta charset="utf-8">
        <meta http-equiv="refresh" content="30">
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; background: #f0f0f0; }}
            .container {{ background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
            h1 {{ color: #333; }}
            .metric {{ margin: 15px 0; padding: 10px; background: #f8f8f8; border-left: 4px solid #4CAF50; }}
            .status {{ color: #4CAF50; font-weight: bold; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🔗 Connexa Backend Server</h1>
            <div class="metric">
                <strong>Status:</strong> <span class="status">RUNNING</span>
            </div>
            <div class="metric">
                <strong>Port:</strong> 8001
            </div>
            <div class="metric">
                <strong>PPP Interfaces:</strong> {ppp_count}
            </div>
            <div class="metric">
                <strong>SOCKS Ports:</strong> {socks_count}
            </div>
            <div class="metric">
                <strong>Time:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
            </div>
            <p><small>Auto-refresh: 30 seconds</small></p>
        </div>
    </body>
    </html>
    """
    return html


def count_ppp_interfaces():
    """Count active PPP interfaces"""
    try:
        result = subprocess.run(
            ['ip', 'a'],
            capture_output=True,
            text=True,
            timeout=5
        )
        count = result.stdout.count('ppp') // 2  # Each interface appears twice
        return count
    except Exception as e:
        logger.error(f"Error counting PPP interfaces: {e}")
        return 0


def count_socks_ports():
    """Count listening SOCKS ports"""
    try:
        result = subprocess.run(
            ['ss', '-tulnp'],
            capture_output=True,
            text=True,
            timeout=5
        )
        # Count lines with dante or sockd
        count = sum(1 for line in result.stdout.split('\n') 
                   if 'dante' in line.lower() or 'sockd' in line.lower())
        return count
    except Exception as e:
        logger.error(f"Error counting SOCKS ports: {e}")
        return 0


if __name__ == '__main__':
    logger.info("=" * 50)
    logger.info("Starting Connexa Backend Server v7")
    logger.info("Port: 8001 (CORRECT PORT!)")
    logger.info("Admin Panel: http://localhost:3000")
    logger.info("API Base: http://localhost:8001")
    logger.info("=" * 50)
    
    # Start Flask server on port 8001
    app.run(host='0.0.0.0', port=8001, debug=False)
