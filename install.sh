#!/usr/bin/env bash

# DragonReboot Installation Script
# Run with: sudo ./install.sh

set -e

echo "🐉 Installing DragonReboot..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Install Node.js if not present
if ! command -v node &> /dev/null; then
    echo "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
fi

# Create installation directory
INSTALL_DIR="/opt/dragon-reboot"
mkdir -p "$INSTALL_DIR"

# Copy files
echo "Copying files to $INSTALL_DIR..."
cp -r ./* "$INSTALL_DIR/"

# Set proper permissions
chown -R root:root "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/scripts/reboot.sh"
chmod +x "$INSTALL_DIR/server/index.js"

# Install dependencies
echo "Installing Node.js dependencies..."
cd "$INSTALL_DIR"
npm install --production

# Create log directory
mkdir -p /var/log/dragon-reboot
touch /var/log/dragon-reboot.log
chmod 640 /var/log/dragon-reboot.log

# Install systemd service
echo "Installing systemd service..."
cp dragon-reboot.service /etc/systemd/system/
systemctl daemon-reload

# Create sudoers rule for reboot script
echo "Setting up sudo permissions..."
cat > /etc/sudoers.d/dragon-reboot << 'EOF'
# Allow dragon-reboot service to execute reboot script
root ALL=(ALL) NOPASSWD: /opt/dragon-reboot/scripts/reboot.sh
EOF

# Set up environment file
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
    cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
    echo "⚠️  Please edit $INSTALL_DIR/.env with your GCP configuration"
fi

echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Configure GCP settings in $INSTALL_DIR/.env"
echo "2. Set up GCP bucket and service account (see GCP_SETUP.md)"
echo "3. Start the service: sudo systemctl start dragon-reboot"
echo "4. Enable auto-start: sudo systemctl enable dragon-reboot"
echo "5. Check status: sudo systemctl status dragon-reboot"
echo ""
echo "To access the phone app:"
echo "1. Start app server: cd $INSTALL_DIR && npm run app"
echo "2. Access from phone: http://YOUR_SERVER_IP:3000"