#!/usr/bin/env bash

# Wrap entire script in braces to ensure it's fully loaded before execution
{

# CRITICAL: Root check MUST be first thing before any operations
if [ "$UID" -ne 0 ]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

echo "DragonNuke triggered! Nuking..."

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

# Function to wipe LUKS header (fast, effective for encrypted volumes)
wipe_luks_header() {
    local dev="$1"
    echo "Wiping LUKS header on $dev..."

    # LUKS1 header is 2MB, LUKS2 header is 16MB
    # Wipe first 20MB to be safe
    dd if=/dev/urandom of="$dev" bs=1M count=20 status=progress 2>/dev/null

    echo "LUKS header wiped on $dev"
}

# Function to wipe ext4 filesystem (destroy superblocks + random data)
wipe_ext4_filesystem() {
    local dev="$1"
    echo "Attempting ext4 superblock destruction on $dev..."

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

    # Fill /dev/shm (which is RAM) with random data
    dd if=/dev/urandom of=/dev/shm/ram_fill bs=1M status=progress 2>/dev/null || true
    rm -f /dev/shm/ram_fill 2>/dev/null || true

    # Drop all caches
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    echo "RAM scrambled"
}

# Disable network first
disable_network_adapters

# Collect all block devices
declare -a devices=($(collect_block_devices))

echo "Found block devices: ${devices[*]}"

# Wipe each device based on type
for dev in "${devices[@]}"; do
    echo ""
    echo "Processing device: $dev"

    if is_luks_device "$dev"; then
        echo "Detected LUKS volume on $dev"
        wipe_luks_header "$dev"
    else
        echo "Not a LUKS volume, using ext4/generic approach on $dev"

        # Try ext4 superblock destruction + random offsets
        wipe_ext4_filesystem "$dev"

        # Optional: Full wipe (comment out if time is critical)
        # full_wipe_device "$dev"
    fi

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
