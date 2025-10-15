# NixOS Configuration Example for DragonNuke Server
# 
# Add this block to your /etc/nixos/configuration.nix file under the services section.
# 
# Setup Instructions:
# 1. Copy this service definition to your /etc/nixos/configuration.nix
# 2. Update the paths below to match your dragon-nuke installation directory
# 3. Ensure your .env file is properly configured in the working directory
# 4. Run: sudo nixos-rebuild switch
# 5. Verify service status: systemctl status dragon-nuke
# 6. Check logs: journalctl -u dragon-nuke -f
#
# NOTE: This replaces the need for 'just systemd-setup' on NixOS systems.

{
  services.dragon-nuke = {
    enable = true;
    description = "DragonNuke Server - Remote block device wipe listener";
    
    # Service configuration
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      User = "root";
      
      # UPDATE THESE PATHS to match your installation
      ExecStart = "${pkgs.nodejs}/bin/node /path/to/dragon-nuke/server-dragon-nuke/index.js";
      WorkingDirectory = "/path/to/dragon-nuke/server-dragon-nuke";
      
      # Environment
      Environment = [ "NODE_ENV=production" ];
      EnvironmentFile = "/path/to/dragon-nuke/server-dragon-nuke/.env";
      
      # Logging
      StandardOutput = "append:/var/log/dragon-nuke.log";
      StandardError = "append:/var/log/dragon-nuke.log";
      SyslogIdentifier = "dragon-nuke";
    };
    
    # Service dependencies
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    # Restart limits
    startLimitIntervalSec = 0;
  };
  
  # Optional: Add nodejs to system packages if not already present
  # environment.systemPackages = with pkgs; [
  #   nodejs
  #   google-cloud-sdk
  # ];
}

# Alternative manual systemd service definition (if services.dragon-nuke doesn't work):
# systemd.services.dragon-nuke = {
#   enable = true;
#   description = "DragonNuke Server - Remote block device wipe listener";
#   after = [ "network.target" ];
#   wantedBy = [ "multi-user.target" ];
#   startLimitIntervalSec = 0;
#   
#   serviceConfig = {
#     Type = "simple";
#     Restart = "always";
#     RestartSec = 10;
#     User = "root";
#     ExecStart = "${pkgs.nodejs}/bin/node /path/to/dragon-nuke/server-dragon-nuke/index.js";
#     WorkingDirectory = "/path/to/dragon-nuke/server-dragon-nuke";
#     Environment = [ "NODE_ENV=production" ];
#     EnvironmentFile = "/path/to/dragon-nuke/server-dragon-nuke/.env";
#     StandardOutput = "append:/var/log/dragon-nuke.log";
#     StandardError = "append:/var/log/dragon-nuke.log";
#     SyslogIdentifier = "dragon-nuke";
#   };
# };