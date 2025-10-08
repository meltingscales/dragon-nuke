# Dragon Reboot Server

Node.js server that monitors GCP Storage for reboot triggers and executes system reboots.

## Features

- 🔍 Monitors GCP Storage bucket for reboot triggers
- 🔥 Executes system reboot when triggered
- 📊 Health monitoring and logging
- ⚡ Configurable poll intervals
- 🛡️ Security-focused design

## Setup

1. **Environment Setup**
   ```bash
   # Enter Nix shell (if using Nix)
   nix-shell
   
   # Or install dependencies manually
   npm install
   ```

2. **Configuration**
   ```bash
   # Create configuration
   just init-config
   
   # Edit .env with your settings
   nano .env
   ```

3. **GCP Setup**
   ```bash
   # Initialize bucket
   just init-gcp
   
   # Test connection
   just test-gcp
   ```

## Usage

### Development
```bash
# Start in debug mode
just debug

# Start as root (required for reboot)
just start-root
```

### Production
```bash
# Start server
just start-root
```

## Configuration

Required environment variables in `.env`:

```bash
GOOGLE_CLOUD_PROJECT_ID=dragon-nuke
GCP_BUCKET_NAME=dragon-reboot-bucket
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
POLL_INTERVAL_SECONDS=10
LOG_FILE=/var/log/dragon-reboot.log
VERBOSE_LOGGING=false
```

## Monitoring

The server logs all activity and provides health status information. Check logs for monitoring reboot triggers and system health.

## Security

- Runs as root (required for system reboot)
- Validates service account credentials
- Logs all reboot activities
- No automatic trigger reset (allows multiple servers to reboot)