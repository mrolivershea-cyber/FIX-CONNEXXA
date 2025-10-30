#!/bin/bash

# Install necessary packages
apt-get update
apt-get install -y ppp pptp-linux dante-server net-tools

# Load kernel modules
echo -e "ppp_generic\nppp_mppe\nppp_deflate\nppp_async" > /etc/modules-load.d/ppp.conf
modprobe ppp_generic
modprobe ppp_mppe
modprobe ppp_deflate
modprobe ppp_async

# Create systemd service
cat <<EOL > /etc/systemd/system/connexa-backend.service
[Unit]
Description=Connexa Backend
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/app/backend
ExecStart=/app/backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8001
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Create the link_socks_to_ppp.sh script
cat <<'EOL' > /usr/local/bin/link_socks_to_ppp.sh
#!/bin/bash

# Detect ppp interface and restart danted
if ip a | grep -q ppp0; then
    systemctl restart danted
fi
EOL

chmod +x /usr/local/bin/link_socks_to_ppp.sh

# Create the backend/service_manager.py file
cat <<'EOL' > /app/backend/service_manager.py
import os
import subprocess

class ServiceManager:
    def start(self):
        # Connect to ppp and configure danted
        os.system('pon connexa')
        self._configure_danted()

    def stop(self):
        os.system('killall pppd')
        os.system('systemctl stop danted')

    def status(self):
        ppp_active = os.system('ip a | grep -q ppp0') == 0
        danted_active = os.system('netstat -tuln | grep -q :1080') == 0
        return {'ppp0': ppp_active, 'danted': danted_active}

    def _configure_danted(self):
        # Configure danted
        pass
EOL

# Create necessary ppp configuration files
cat <<EOL > /etc/ppp/peers/connexa
# Connexa configuration
pty "pptp your.provider --nolaunchpppd"
name your_username
password your_password
EOL

cat <<EOL > /etc/ppp/chap-secrets
# Secrets for authentication
# client    server    secret          IP addresses
your_username    *    your_password    *
EOL

# Restart the connexa-backend service
systemctl daemon-reload
systemctl start connexa-backend
systemctl enable connexa-backend
