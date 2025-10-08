# Distribution-Specific Installation

## Ubuntu/Debian

```bash
# Install dependencies
sudo apt update
sudo apt install -y nodejs npm curl

# Clone and install
git clone <repo-url> dragon-reboot
cd dragon-reboot/server-dragon-reboot
sudo ./install.sh
```

### Service Management
```bash
sudo systemctl start dragon-reboot
sudo systemctl enable dragon-reboot
sudo systemctl status dragon-reboot
```

## Fedora

```bash
# Install dependencies
sudo dnf install -y nodejs npm curl

# Clone and install
git clone <repo-url> dragon-reboot
cd dragon-reboot/server-dragon-reboot
sudo ./install.sh
```

### Service Management
```bash
sudo systemctl start dragon-reboot
sudo systemctl enable dragon-reboot
sudo systemctl status dragon-reboot
```

## CachyOS (Arch-based)

```bash
# Install dependencies
sudo pacman -S nodejs npm curl

# Clone and install
git clone <repo-url> dragon-reboot
cd dragon-reboot/server-dragon-reboot
sudo ./install.sh
```

### Service Management
```bash
sudo systemctl start dragon-reboot
sudo systemctl enable dragon-reboot
sudo systemctl status dragon-reboot
```

## NixOS

### Option 1: Traditional Installation
```bash
# Enter shell with Node.js
nix-shell -p nodejs npm

# Clone and install
git clone <repo-url> dragon-reboot
cd dragon-reboot/server-dragon-reboot
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

  # Create dragon-reboot user
  users.users.dragon-reboot = {
    isSystemUser = true;
    group = "dragon-reboot";
    home = "/opt/dragon-reboot";
  };
  users.groups.dragon-reboot = {};

  # Create systemd service
  systemd.services.dragon-reboot = {
    description = "DragonReboot Server - Remote reboot listener";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      User = "root";  # Needs root for reboot
      ExecStart = "${pkgs.nodejs}/bin/node /opt/dragon-reboot/server-dragon-reboot/index.js";
      WorkingDirectory = "/opt/dragon-reboot/server-dragon-reboot";
      EnvironmentFile = "/opt/dragon-reboot/server-dragon-reboot/.env";
      
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
  system.activationScripts.dragon-reboot = ''
    mkdir -p /opt/dragon-reboot/server-dragon-reboot
    mkdir -p /var/log/dragon-reboot
    chown dragon-reboot:dragon-reboot /opt/dragon-reboot
    chmod 755 /opt/dragon-reboot
  '';

  # Sudo permissions for reboot
  security.sudo.extraRules = [
    {
      users = [ "root" ];
      commands = [
        {
          command = "/opt/dragon-reboot/scripts/reboot.sh";
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
sudo mkdir -p /opt/dragon-reboot/server-dragon-reboot
sudo cp -r ./* /opt/dragon-reboot/server-dragon-reboot/
sudo chown -R root:root /opt/dragon-reboot

# Install dependencies
cd /opt/dragon-reboot/server-dragon-reboot
nix-shell -p nodejs npm --run "npm install --production"

# Create service file
sudo cp dragon-reboot.service /etc/systemd/system/
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
RUN chmod +x ../scripts/reboot.sh
RUN chmod +x index.js

# Note: Container won't actually reboot the host
# Use with caution and proper container orchestration
CMD ["node", "index.js"]
```

```bash
# Build and run
docker build -t dragon-reboot-server .
docker run -d --name dragon-reboot-server \
  --privileged \
  -v /var/log:/var/log \
  --env-file .env \
  dragon-reboot-server
```

## OpenRC Systems (Alpine, Gentoo)

Create `/etc/init.d/dragon-reboot`:
```bash
#!/sbin/openrc-run

name="dragon-reboot"
description="DragonReboot Server - Remote reboot listener"
command="/usr/bin/node"
command_args="/opt/dragon-reboot/server-dragon-reboot/index.js"
command_user="root"
pidfile="/run/${RC_SVCNAME}.pid"
command_background="yes"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --owner root:root --mode 0755 /var/log/dragon-reboot
}
```

```bash
# Make executable and enable
sudo chmod +x /etc/init.d/dragon-reboot
sudo rc-update add dragon-reboot default
sudo service dragon-reboot start
```

## Verification Commands (All Distros)

```bash
# Check service status
sudo systemctl status dragon-reboot  # systemd
sudo service dragon-reboot status     # OpenRC

# Check logs
sudo journalctl -u dragon-reboot -f   # systemd
sudo tail -f /var/log/dragon-reboot.log

# Test configuration
cd /opt/dragon-reboot/server-dragon-reboot
just test-gcp

# Start server manually
just start-root
```