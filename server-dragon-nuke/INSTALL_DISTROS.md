# Distribution-Specific Installation

## Ubuntu/Debian

```bash
# Install dependencies
sudo apt update
sudo apt install -y nodejs npm curl

# Clone and install
git clone <repo-url> dragon-nuke
cd dragon-nuke/server-dragon-nuke
sudo ./install.sh
```

### Service Management
```bash
sudo systemctl start dragon-nuke
sudo systemctl enable dragon-nuke
sudo systemctl status dragon-nuke
```

## Fedora

```bash
# Install dependencies
sudo dnf install -y nodejs npm curl

# Clone and install
git clone <repo-url> dragon-nuke
cd dragon-nuke/server-dragon-nuke
sudo ./install.sh
```

### Service Management
```bash
sudo systemctl start dragon-nuke
sudo systemctl enable dragon-nuke
sudo systemctl status dragon-nuke
```

## CachyOS (Arch-based)

```bash
# Install dependencies
sudo pacman -S nodejs npm curl

# Clone and install
git clone <repo-url> dragon-nuke
cd dragon-nuke/server-dragon-nuke
sudo ./install.sh
```

### Service Management
```bash
sudo systemctl start dragon-nuke
sudo systemctl enable dragon-nuke
sudo systemctl status dragon-nuke
```

## NixOS

### Option 1: Traditional Installation
```bash
# Enter shell with Node.js
nix-shell -p nodejs npm

# Clone and install
git clone <repo-url> dragon-nuke
cd dragon-nuke/server-dragon-nuke
sudo ./install.sh
```

### Option 2: NixOS Configuration (Recommended)

Add to your `/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, ... }:

{
  # Enable Node.js
  environment.systemPackages = with pkgs; [
    nodejs
    npm
  ];

  # Create dragon-nuke user
  users.users.dragon-nuke = {
    isSystemUser = true;
    group = "dragon-nuke";
    home = "/opt/dragon-nuke";
  };
  users.groups.dragon-nuke = {};

  # Create systemd service
  systemd.services.dragon-nuke = {
    description = "DragonNuke Server - Remote wipe listener";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      User = "root";  # Needs root for nuke
      ExecStart = "${pkgs.nodejs}/bin/node /opt/dragon-nuke/server-dragon-nuke/index.js";
      WorkingDirectory = "/opt/dragon-nuke/server-dragon-nuke";
      EnvironmentFile = "/opt/dragon-nuke/server-dragon-nuke/.env";
      
      # Security
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/log" ];
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
    };
  };

  # Create directories
  system.activationScripts.dragon-nuke = ''
    mkdir -p /opt/dragon-nuke/server-dragon-nuke
    mkdir -p /var/log/dragon-nuke
    chown dragon-nuke:dragon-nuke /opt/dragon-nuke
    chmod 755 /opt/dragon-nuke
  '';

  # Sudo permissions for nuke
  security.sudo.extraRules = [
    {
      users = [ "root" ];
      commands = [
        {
          command = "/opt/dragon-nuke/scripts/dragon-nuke.sh";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
```

Then rebuild your system:
```bash
sudo nixos-rebuild switch
```

### Manual NixOS Setup
If using the traditional install method on NixOS:

```bash
# Copy files manually
sudo mkdir -p /opt/dragon-nuke/server-dragon-nuke
sudo cp -r ./* /opt/dragon-nuke/server-dragon-nuke/
sudo chown -R root:root /opt/dragon-nuke

# Install dependencies
cd /opt/dragon-nuke/server-dragon-nuke
nix-shell -p nodejs npm --run "npm install --production"

# Create service file
sudo cp dragon-nuke.service /etc/systemd/system/
sudo systemctl daemon-reload
```

## Docker Installation (All Distros)

```dockerfile
# Dockerfile
FROM node:18-alpine

RUN apk add --no-cache bash sudo

WORKDIR /app
COPY package*.json ./
RUN npm install --production

COPY . .
RUN chmod +x ../scripts/dragon-nuke.sh
RUN chmod +x index.js

# Note: Container won't actually nuke the host's block devices
# Use with caution and proper container orchestration
CMD ["node", "index.js"]
```

```bash
# Build and run
docker build -t dragon-nuke-server .
docker run -d --name dragon-nuke-server \
  --privileged \
  -v /var/log:/var/log \
  --env-file .env \
  dragon-nuke-server
```

## OpenRC Systems (Alpine, Gentoo)

Create `/etc/init.d/dragon-nuke`:
```bash
#!/sbin/openrc-run

name="dragon-nuke"
description="DragonNuke Server - Remote block device wipe listener"
command="/usr/bin/node"
command_args="/opt/dragon-nuke/server-dragon-nuke/index.js"
command_user="root"
pidfile="/run/${RC_SVCNAME}.pid"
command_background="yes"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --owner root:root --mode 0755 /var/log/dragon-nuke
}
```

```bash
# Make executable and enable
sudo chmod +x /etc/init.d/dragon-nuke
sudo rc-update add dragon-nuke default
sudo service dragon-nuke start
```

## Verification Commands (All Distros)

```bash
# Check service status
sudo systemctl status dragon-nuke  # systemd
sudo service dragon-nuke status     # OpenRC

# Check logs
sudo journalctl -u dragon-nuke -f   # systemd
sudo tail -f /var/log/dragon-nuke.log

# Test configuration
cd /opt/dragon-nuke/server-dragon-nuke
just test-gcp

# Start server manually
just start-root
```