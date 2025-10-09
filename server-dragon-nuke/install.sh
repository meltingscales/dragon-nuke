#!/usr/bin/env bash

# DragonNuke Server Installation Script
# Run with: sudo ./install.sh

set -e

echo "🐉 Installing DragonNuke Server..."

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
INSTALL_DIR="/opt/dragon-nuke/server-dragon-nuke"
mkdir -p "$INSTALL_DIR"

# Copy files
echo "Copying files to $INSTALL_DIR..."
cp -r ./* "$INSTALL_DIR/"

# Set proper permissions
chown -R root:root "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/../scripts/dragon-nuke.sh"
chmod +x "$INSTALL_DIR/index.js"

# Install dependencies
echo "Installing Node.js dependencies..."
cd "$INSTALL_DIR"
npm install --production

# Create log directory
mkdir -p /var/log/dragon-nuke
touch /var/log/dragon-nuke.log
chmod 640 /var/log/dragon-nuke.log

# Install systemd service
echo "Installing systemd service..."
cp dragon-nuke.service /etc/systemd/system/
systemctl daemon-reload

# Create sudoers rule for nuke script
echo "Setting up sudo permissions..."
cat > /etc/sudoers.d/dragon-nuke << 'EOF'
# Allow dragon-nuke service to execute nuke script
root ALL=(ALL) NOPASSWD: /opt/dragon-nuke/scripts/dragon-nuke.sh
EOF

# Set up environment file
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
    if [[ -f "$INSTALL_DIR/../.env.example" ]]; then
        cp "$INSTALL_DIR/../.env.example" "$INSTALL_DIR/.env"
    else
        echo "⚠️  .env.example not found, please create .env manually"
    fi
    echo "⚠️  Please edit $INSTALL_DIR/.env with your GCP configuration"
fi

echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Configure GCP settings in $INSTALL_DIR/.env"
echo "2. Set up GCP bucket and service account (see GCP_SETUP.md)"
echo "3. Start the service: sudo systemctl start dragon-nuke"
echo "4. Enable auto-start: sudo systemctl enable dragon-nuke"
echo "5. Check status: sudo systemctl status dragon-nuke"