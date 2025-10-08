#!/usr/bin/env bash

echo "DragonReboot triggered! Rebooting..."

# Log the reboot event
echo "$(date): DragonReboot triggered by remote command" >> /var/log/dragon-reboot.log

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
                "🔥 System Reboot" \
                "DragonReboot triggered! System will reboot in $delay seconds." 2>/dev/null || true
        fi
    done
    
    # Send systemd user notifications if available
    for user_id in $(loginctl list-users --no-legend | awk '{print $1}'); do
        user=$(getent passwd "$user_id" | cut -d: -f1)
        sudo -u "$user" systemd-notify --user "STATUS=DragonReboot: System rebooting in $delay seconds" 2>/dev/null || true
    done
}

# Send initial warning
notify_users "URGENT: Remote reboot triggered! System will restart in 60 seconds." "60"

# Wait and send countdown notifications
sleep 30
notify_users "System reboot in 30 seconds!" "30"

sleep 20
notify_users "System reboot in 10 seconds!" "10"

sleep 5
notify_users "System rebooting NOW!" "0"

# Final log entry
echo "$(date): Executing reboot command" >> /var/log/dragon-reboot.log

# Wait a moment for notifications to be processed
sleep 5

# Execute the reboot
/sbin/reboot