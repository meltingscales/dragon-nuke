# DragonNuke - Just Commands
# Run `just` to see all available commands

default:
    @just --list

# Quick access to common commands
# For full server commands: cd server-dragon-nuke && just
# For Android app commands: cd android-app && just

# Development shortcuts
dev:
    cd server-dragon-nuke && just dev

# Service management shortcuts
start:
    cd server-dragon-nuke && just start-root

status:
    sudo systemctl status dragon-nuke

logs:
    sudo journalctl -u dragon-nuke -f

# Build Android app
app:
    cd android-app && just dev

# Show available commands in subdirectories
help:
    @echo "🐉 DragonNuke - Just Commands"
    @echo ""
    @echo "Quick commands from root:"
    @echo "  just dev        # Start server in dev mode"
    @echo "  just start      # Start server as root"
    @echo "  just status     # Check service status"
    @echo "  just logs       # Follow service logs"
    @echo "  just app        # Build and install Android app"
    @echo ""
    @echo "For full server commands:"
    @echo "  cd server-dragon-nuke && just"
    @echo ""
    @echo "For Android app commands:"
    @echo "  cd android-app && just"
