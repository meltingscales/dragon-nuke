#!/usr/bin/env bash

# Wrap entire script in braces to ensure it's fully loaded before execution
{

# CRITICAL: Root check MUST be first thing before any operations
if [ "$UID" -ne 0 ]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

echo "DragonNuke triggered! Nuking..."

# ============================================================================
# CONFIGURATION
# ============================================================================
# WIPE_MODE options:
#   "fast"   - LUKS header wipe + ext4 superblock destruction + random offsets (fastest)
#   "shred"  - Use shred on all block devices (safest, slowest)
#   "full"   - Full urandom wipe after fast mode (thorough but very slow)
WIPE_MODE="${WIPE_MODE:-fast}"
# ============================================================================

# Function to disable network adapters
# WARNING: If running over SSH, start as './dragon-nuke.sh & disown' to avoid interruption
disable_network_adapters() {
    echo "WARNING: Network shutdown will interrupt SSH connections!"

    # Disable NetworkManager if it's running
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        systemctl stop NetworkManager 2>/dev/null
    fi

    # Disable systemd-networkd if it's running
    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        systemctl stop systemd-networkd 2>/dev/null
    fi

    # Disable all network interfaces
    for interface in $(ip -o link show | awk -F': ' '{print $2}'); do
        ip link set down "$interface" 2>/dev/null
    done
}

# Function to collect block devices
collect_block_devices() {
    local devices=()

    # Try lsblk first (most reliable if available)
    if command -v lsblk &>/dev/null; then
        readarray -t devices < <(lsblk --list --output NAME,RO --paths --nodeps | awk '$2==0 {print $1}')
    else
        # Fallback: parse /proc/mounts for mounted devices
        echo "Warning: lsblk not found, using /proc/mounts fallback" >&2
        readarray -t devices < <(awk '$1 ~ /^\/dev\// && $1 !~ /^\/dev\/(loop|ram|dm-)/ {print $1}' /proc/mounts | sort -u | sed 's/[0-9]*$//' | sort -u)
    fi

    printf '%s\n' "${devices[@]}"
}

# Function to check if device is LUKS encrypted
is_luks_device() {
    local dev="$1"
    cryptsetup isLuks "$dev" 2>/dev/null
    return $?
}

# Function to destroy partition table
destroy_partition_table() {
    local dev="$1"
    echo "Destroying partition table on $dev..."

    # Wipe MBR/GPT header at start (first 10MB)
    dd if=/dev/zero of="$dev" bs=1M count=10 status=none 2>/dev/null || true

    # Wipe GPT backup header at end (last 34 sectors of 512 bytes)
    local device_size=$(blockdev --getsz "$dev" 2>/dev/null || echo 0)
    if [ "$device_size" -gt 0 ]; then
        dd if=/dev/zero of="$dev" bs=512 seek=$((device_size - 34)) count=34 status=none 2>/dev/null || true
    fi

    echo "Partition table destroyed on $dev"
}

# Function to wipe LUKS header (fast, effective for encrypted volumes)
wipe_luks_header() {
    local dev="$1"
    echo "Wiping LUKS header on $dev..."

    # First destroy partition table
    destroy_partition_table "$dev"

    # LUKS1 header is 2MB, LUKS2 header is 16MB
    # Wipe first 20MB to be safe
    dd if=/dev/urandom of="$dev" bs=1M count=20 status=progress 2>/dev/null

    echo "LUKS header wiped on $dev"
}

# Function to wipe ext4 filesystem (destroy superblocks + random data)
wipe_ext4_filesystem() {
    local dev="$1"
    echo "Attempting ext4 superblock destruction on $dev..."

    # First destroy partition table
    destroy_partition_table "$dev"

    # Try to get superblock locations
    if command -v dumpe2fs &>/dev/null; then
        local superblocks=$(dumpe2fs "$dev" 2>/dev/null | grep -i 'superblock' | grep -oE '[0-9]+' | head -20)

        if [ -n "$superblocks" ]; then
            echo "Found ext4 superblocks, destroying them..."
            for sb in $superblocks; do
                # Wipe 1MB at each superblock location
                dd if=/dev/urandom of="$dev" bs=1k seek=$sb count=1024 status=none 2>/dev/null
            done
            echo "Superblocks destroyed on $dev"
        fi
    fi

    # Random offset wiping strategy
    echo "Wiping random offsets on $dev..."
    local device_size=$(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)

    if [ "$device_size" -gt 0 ]; then
        # Wipe ~5GB worth of random 1MB chunks
        local chunks_to_wipe=5000
        local chunk_size=$((1024 * 1024)) # 1MB

        for ((i=0; i<chunks_to_wipe; i++)); do
            # Random offset within device
            local random_offset=$((RANDOM * RANDOM % (device_size / chunk_size)))
            dd if=/dev/urandom of="$dev" bs=1M seek=$random_offset count=1 status=none 2>/dev/null || true

            # Progress indicator every 500 chunks
            if [ $((i % 500)) -eq 0 ]; then
                echo "  Random wipe progress: $i/$chunks_to_wipe chunks..."
            fi
        done
        echo "Random offset wiping complete on $dev"
    fi
}

# Function to shred device (safest method)
shred_device() {
    local dev="$1"
    echo "Shredding $dev (this is the safest but slowest method)..."

    # First destroy partition table
    destroy_partition_table "$dev"

    # Use shred - it handles everything properly
    if command -v shred &>/dev/null; then
        shred -v "$dev" 2>/dev/null || shred "$dev" 2>/dev/null || true
    else
        # Fallback to dd if shred not available
        echo "shred not found, using dd fallback..."
        dd if=/dev/urandom of="$dev" bs=4M status=progress 2>/dev/null || true
    fi

    echo "Shred complete on $dev"
}

# Function to full wipe device with urandom
full_wipe_device() {
    local dev="$1"
    echo "Full wiping $dev with urandom (this will take a while)..."
    dd if=/dev/urandom of="$dev" bs=4M status=progress 2>/dev/null || true
    echo "Full wipe complete on $dev"
}

# Function to scramble RAM
scramble_ram() {
    echo "Scrambling RAM..."

    # Fill /dev/shm multiple times to ensure we overwrite more RAM
    for i in {1..3}; do
        dd if=/dev/urandom of=/dev/shm/ram_fill_$i bs=1M status=none 2>/dev/null || true
    done

    # Try to allocate and fill more memory locations
    for i in {1..5}; do
        dd if=/dev/urandom of=/tmp/ram_fill_tmp_$i bs=1M count=100 status=none 2>/dev/null || true
    done

    # Drop all caches to clear more RAM
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    # Clean up
    rm -f /dev/shm/ram_fill_* /tmp/ram_fill_tmp_* 2>/dev/null || true

    echo "RAM scrambled"
}

# Disable network first
disable_network_adapters

# Collect all block devices
declare -a devices=($(collect_block_devices))

echo "Found block devices: ${devices[*]}"
echo "Wipe mode: $WIPE_MODE"

# Wipe each device based on configured mode
for dev in "${devices[@]}"; do
    echo ""
    echo "Processing device: $dev"

    case "$WIPE_MODE" in
        shred)
            # Safest option: just shred everything
            echo "Using shred mode (safest)"
            shred_device "$dev"
            ;;

        full)
            # Fast mode first, then full wipe
            echo "Using full mode (thorough)"
            if is_luks_device "$dev"; then
                echo "Detected LUKS volume on $dev"
                wipe_luks_header "$dev"
            else
                echo "Not a LUKS volume, using ext4/generic approach on $dev"
                wipe_ext4_filesystem "$dev"
            fi
            # Then do full wipe
            full_wipe_device "$dev"
            ;;

        fast|*)
            # Fast mode: LUKS header or ext4 superblocks + random offsets
            echo "Using fast mode (LUKS/ext4 targeted)"
            if is_luks_device "$dev"; then
                echo "Detected LUKS volume on $dev"
                wipe_luks_header "$dev"
            else
                echo "Not a LUKS volume, using ext4/generic approach on $dev"
                wipe_ext4_filesystem "$dev"
            fi
            ;;
    esac

    echo "Device $dev processing complete"
done

# Scramble RAM before shutdown
scramble_ram

# Final sync
sync

echo ""
echo "All devices have been wiped. Powering off..."

# Poweroff immediately
poweroff -f

# Close the brace that wraps the entire script
}
