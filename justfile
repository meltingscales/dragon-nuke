# DragonReboot - Just Commands
# Run `just` to see all available commands

default:
    @just --list

# Development Commands

# Install dependencies
install:
    npm install

# Start the server in development mode
dev:
    npm run dev

# Start the server
start:
    npm start

# Start the phone app
app:
    npm run app

# Installation Commands

# Install system-wide (requires sudo)
install-system:
    sudo ./install.sh

# Create systemd service (requires sudo)
setup-service:
    sudo cp dragon-reboot.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable dragon-reboot

# Service Management

# Start the service
service-start:
    sudo systemctl start dragon-reboot

# Stop the service
service-stop:
    sudo systemctl stop dragon-reboot

# Restart the service
service-restart:
    sudo systemctl restart dragon-reboot

# Check service status
service-status:
    sudo systemctl status dragon-reboot

# Enable service to start on boot
service-enable:
    sudo systemctl enable dragon-reboot

# Disable service from starting on boot
service-disable:
    sudo systemctl disable dragon-reboot

# Monitoring & Logs

# Show recent logs
logs:
    ./scripts/monitor.sh logs

# Follow logs in real-time
tail:
    ./scripts/monitor.sh tail

# Follow logs with verbose output
verbose:
    ./scripts/monitor.sh verbose

# Show service status and health
status:
    ./scripts/monitor.sh status

# Show connection statistics
stats:
    ./scripts/monitor.sh stats

# Show only errors
errors:
    ./scripts/monitor.sh errors

# Show complete health check
health:
    ./scripts/monitor.sh health

# Clear log files (requires sudo)
clear-logs:
    ./scripts/monitor.sh clear-logs

# GCP Management

# Test GCP connection
test-gcp:
    ./scripts/monitor.sh test-gcp

# Initialize GCP bucket with safe state
init-gcp:
    echo "safe" | gsutil cp - gs://$(grep GCP_BUCKET_NAME .env | cut -d= -f2)/$(grep GCP_FILE_NAME .env | cut -d= -f2)

# Check GCP file content
check-gcp:
    gsutil cat gs://$(grep GCP_BUCKET_NAME .env | cut -d= -f2)/$(grep GCP_FILE_NAME .env | cut -d= -f2)

# Trigger reboot (DANGEROUS - will actually reboot!)
trigger-reboot:
    @echo "⚠️  WARNING: This will trigger an actual reboot!"
    @echo "Type 'YES' to confirm:"
    @read confirm && [ "$$confirm" = "YES" ] || exit 1
    echo "REBOOT=TRUE" | gsutil cp - gs://$(grep GCP_BUCKET_NAME .env | cut -d= -f2)/$(grep GCP_FILE_NAME .env | cut -d= -f2)

# Configuration

# Create .env file from example
init-config:
    cp .env.example .env
    @echo "✅ Created .env file. Please edit it with your GCP settings."

# Validate configuration
check-config:
    @echo "🔍 Checking configuration..."
    @test -f .env || (echo "❌ .env file missing. Run 'just init-config'" && exit 1)
    @source .env && test -n "$$GOOGLE_CLOUD_PROJECT_ID" || (echo "❌ GOOGLE_CLOUD_PROJECT_ID not set" && exit 1)
    @source .env && test -n "$$GCP_BUCKET_NAME" || (echo "❌ GCP_BUCKET_NAME not set" && exit 1)
    @source .env && test -f "$$GOOGLE_APPLICATION_CREDENTIALS" || (echo "❌ Service account key file not found" && exit 1)
    @echo "✅ Configuration looks good!"

# Security & Maintenance

# Run security check
security-check:
    @echo "🔒 Security Checklist:"
    @cat security-checklist.md

# Update dependencies
update:
    npm update
    npm audit fix

# Clean up temporary files
clean:
    rm -rf node_modules/.cache
    rm -rf /tmp/dragon-reboot-*

# Development & Testing

# Run in debug mode with verbose logging
debug:
    VERBOSE_LOGGING=true npm start

# Test reboot script (dry run - won't actually reboot)
test-reboot:
    @echo "🧪 Testing reboot script (dry run)..."
    @echo "This would execute: sudo bash scripts/reboot.sh"
    @echo "Script contents:"
    @head -10 scripts/reboot.sh

# Check all scripts are executable
check-permissions:
    @echo "🔍 Checking script permissions..."
    @ls -la scripts/
    @test -x scripts/reboot.sh || echo "❌ reboot.sh not executable"
    @test -x scripts/monitor.sh || echo "❌ monitor.sh not executable"
    @test -x install.sh || echo "❌ install.sh not executable"
    @echo "✅ Permission check complete"

# Quick Setup

# Complete setup (install deps, config, service)
setup: install init-config
    @echo "🚀 Dragon Reboot setup complete!"
    @echo "Next steps:"
    @echo "1. Edit .env with your GCP settings"
    @echo "2. Run 'just install-system' to install system-wide"
    @echo "3. Run 'just service-start' to start the service"

# Full installation and start
deploy: setup install-system service-start
    @echo "🎉 Dragon Reboot deployed and running!"
    @just status

# Emergency Commands

# Emergency stop (kills all dragon-reboot processes)
emergency-stop:
    @echo "🚨 Emergency stop - killing all dragon-reboot processes"
    sudo pkill -f "dragon-reboot"
    sudo systemctl stop dragon-reboot || true

# Reset GCP trigger to safe state
emergency-safe:
    @echo "🛡️  Resetting GCP trigger to safe state"
    echo "safe" | gsutil cp - gs://$(grep GCP_BUCKET_NAME .env | cut -d= -f2)/$(grep GCP_FILE_NAME .env | cut -d= -f2)

# Show help
help:
    @echo "🐉 DragonReboot - Just Commands Help"
    @echo ""
    @echo "Common workflows:"
    @echo "  just setup          # Initial setup"
    @echo "  just deploy         # Full deployment"
    @echo "  just logs           # View logs" 
    @echo "  just status         # Check status"
    @echo "  just test-gcp       # Test GCP connection"
    @echo ""
    @echo "Run 'just' to see all available commands"