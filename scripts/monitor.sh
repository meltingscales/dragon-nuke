#!/usr/bin/env bash

# DragonReboot Monitoring Script

LOG_FILE="/var/log/dragon-reboot.log"
SERVICE_NAME="dragon-reboot"

show_help() {
    echo "🐉 DragonReboot Monitor"
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  status      Show service status"
    echo "  logs        Show recent logs (last 50 lines)"
    echo "  tail        Follow logs in real-time"
    echo "  verbose     Follow logs with verbose output"
    echo "  stats       Show connection statistics"
    echo "  test-gcp    Test GCP connection"
    echo "  health      Show health status"
    echo "  errors      Show only error logs"
    echo "  clear-logs  Clear log file (requires sudo)"
    echo "  help        Show this help"
}

show_status() {
    echo "🔍 Service Status:"
    systemctl status $SERVICE_NAME --no-pager
    echo ""
    echo "📊 Process Info:"
    ps aux | grep -E "(dragon-reboot|node.*server/index.js)" | grep -v grep
}

show_logs() {
    echo "📝 Recent Logs (last 50 lines):"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 50 "$LOG_FILE"
    else
        echo "Log file not found: $LOG_FILE"
        echo "Checking systemd logs instead:"
        journalctl -u $SERVICE_NAME -n 50 --no-pager
    fi
}

tail_logs() {
    echo "📝 Following logs (Ctrl+C to stop):"
    if [[ -f "$LOG_FILE" ]]; then
        tail -f "$LOG_FILE"
    else
        echo "Log file not found, following systemd logs:"
        journalctl -u $SERVICE_NAME -f
    fi
}

show_verbose() {
    echo "🔍 Enabling verbose logging and following..."
    echo "Note: This will temporarily enable verbose logging"
    
    # Check if service is running
    if systemctl is-active $SERVICE_NAME >/dev/null 2>&1; then
        echo "Restarting service with verbose logging..."
        sudo systemctl restart $SERVICE_NAME
        sleep 2
    fi
    
    tail_logs
}

show_stats() {
    echo "📊 Connection Statistics:"
    if [[ -f "$LOG_FILE" ]]; then
        echo "Total polls: $(grep -c "Poll #" "$LOG_FILE")"
        echo "Successful polls: $(grep -c "Content=" "$LOG_FILE")"
        echo "Errors: $(grep -c "\[ERROR\]" "$LOG_FILE")"
        echo "Reboot triggers: $(grep -c "REBOOT TRIGGER DETECTED" "$LOG_FILE")"
        echo ""
        echo "Last 5 poll results:"
        grep "Poll #" "$LOG_FILE" | tail -5
    else
        echo "Log file not found. Using systemd logs:"
        journalctl -u $SERVICE_NAME --no-pager | grep -c "Poll #" | head -1 | xargs echo "Total polls:"
    fi
}

test_gcp_connection() {
    echo "🧪 Testing GCP Connection..."
    
    # Read config from env file
    if [[ -f "/opt/dragon-reboot/.env" ]]; then
        source "/opt/dragon-reboot/.env"
    else
        echo "Config file not found. Checking current directory..."
        if [[ -f ".env" ]]; then
            source ".env"
        else
            echo "❌ No .env file found"
            return 1
        fi
    fi
    
    echo "Project ID: $GOOGLE_CLOUD_PROJECT_ID"
    echo "Bucket: $GCP_BUCKET_NAME"
    echo "File: $GCP_FILE_NAME"
    echo ""
    
    # Test gsutil if available
    if command -v gsutil >/dev/null 2>&1; then
        echo "Testing bucket access with gsutil..."
        if gsutil ls "gs://$GCP_BUCKET_NAME/$GCP_FILE_NAME" >/dev/null 2>&1; then
            echo "✅ File accessible via gsutil"
            echo "Current content:"
            gsutil cat "gs://$GCP_BUCKET_NAME/$GCP_FILE_NAME"
        else
            echo "❌ File not accessible via gsutil"
        fi
    else
        echo "gsutil not installed, skipping direct test"
    fi
}

show_health() {
    echo "🏥 Health Status:"
    show_status
    echo ""
    show_stats
    echo ""
    echo "📈 System Resources:"
    echo "Memory usage:"
    ps -o pid,ppid,cmd,%mem,%cpu --sort=-%mem | grep -E "(dragon-reboot|node.*server/index.js)" | grep -v grep
    echo ""
    echo "Disk space for logs:"
    df -h "$(dirname "$LOG_FILE")" 2>/dev/null || df -h /var/log
}

show_errors() {
    echo "❌ Error Logs:"
    if [[ -f "$LOG_FILE" ]]; then
        grep "\[ERROR\]\|\[WARN\]" "$LOG_FILE" | tail -20
    else
        journalctl -u $SERVICE_NAME --no-pager | grep -i error | tail -20
    fi
}

clear_logs() {
    echo "🧹 Clearing logs..."
    if [[ $EUID -ne 0 ]]; then
        echo "This operation requires sudo privileges"
        sudo truncate -s 0 "$LOG_FILE"
    else
        truncate -s 0 "$LOG_FILE"
    fi
    echo "Log file cleared: $LOG_FILE"
}

# Main script logic
case "${1:-help}" in
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    tail)
        tail_logs
        ;;
    verbose)
        show_verbose
        ;;
    stats)
        show_stats
        ;;
    test-gcp)
        test_gcp_connection
        ;;
    health)
        show_health
        ;;
    errors)
        show_errors
        ;;
    clear-logs)
        clear_logs
        ;;
    help|*)
        show_help
        ;;
esac