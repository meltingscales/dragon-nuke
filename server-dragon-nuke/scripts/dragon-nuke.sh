#!/usr/bin/env bash

echo "DragonNuke triggered! Nuking..."

# Log the wipe event
echo "$(date): DragonNuke triggered by remote command" >> /var/log/dragon-nuke.log

# Function to send notification to all logged-in users
notify_users() {
    local message="$1"
    local delay="$2"
    
    # Send wall message to all terminals
    echo "$message" | wall
    
    # Try to send desktop notifications to all active X11 sessions
    for user_session in $(who | awk '{print $1":"$2}' | sort -u); do
        user=$(echo $user_session | cut -d: -f1)
        display=$(echo $user_session | cut -d: -f2)
        
        if [[ "$display" =~ ^:[0-9]+$ ]]; then
            # This looks like an X11 display
            sudo -u "$user" DISPLAY="$display" notify-send --urgency=critical --expire-time=0 \
                "🔥 System Nuke" \
                "DragonNuke triggered! System will destroy all block devices in $delay seconds." 2>/dev/null || true
        fi
    done
    
    # Send systemd user notifications if available
    for user_id in $(loginctl list-users --no-legend | awk '{print $1}'); do
        user=$(getent passwd "$user_id" | cut -d: -f1)
        sudo -u "$user" systemd-notify --user "STATUS=DragonNuke: System nuke starting in $delay seconds" 2>/dev/null || true
    done
}

# Send initial warning
notify_users "URGENT: Remote nuke triggered! System will destroy all block devices in 1 seconds." "1"
sleep 1

notify_users "Filesystem nuke starting NOW!" "0"

# Final log entry
echo "$(date): Executing nuke command" >> /var/log/dragon-nuke.log

# Execute the reboot in multiple ways
/sbin/reboot &
sudo reboot now &