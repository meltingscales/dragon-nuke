#!/bin/bash
# Setup additional hard drives for Dragon Nuke testing
# This script formats and mounts the two additional data disks

set -e

echo "Setting up additional hard drives..."

# Detect the data disks (varies by distro)
# Ubuntu/RHEL/Fedora: /dev/sdc and /dev/sdd
# Arch: /dev/sdb and /dev/sdc
DISK1=""
DISK2=""

if [ -b /dev/sdb ] && [ -b /dev/sdc ] && [ ! -b /dev/sdd ]; then
  # Arch layout: sda (OS), sdb (data1), sdc (data2)
  DISK1="/dev/sdb"
  DISK2="/dev/sdc"
elif [ -b /dev/sdc ] && [ -b /dev/sdd ]; then
  # Ubuntu/RHEL/Fedora layout: sda/sdb (OS), sdc (data1), sdd (data2)
  DISK1="/dev/sdc"
  DISK2="/dev/sdd"
else
  echo "Warning: Expected disk layout not found"
  lsblk
fi

# Format and mount disk1
if [ -z "$DISK1" ]; then
  echo "Warning: Data disk 1 not found, skipping disk1 setup"
else
  if ! blkid $DISK1 | grep -q ext4; then
    echo "Formatting $DISK1 as ext4..."
    mkfs.ext4 -F $DISK1
  fi
  mkdir -p /mnt/data1
  if ! mountpoint -q /mnt/data1; then
    mount $DISK1 /mnt/data1
    # Add to fstab only if not already present
    if ! grep -q "$DISK1.*mnt/data1" /etc/fstab; then
      echo "$DISK1 /mnt/data1 ext4 defaults 0 0" >> /etc/fstab
    fi
  fi
  echo "✓ $DISK1 mounted at /mnt/data1"
fi

# Format and mount disk2
if [ -z "$DISK2" ]; then
  echo "Warning: Data disk 2 not found, skipping disk2 setup"
else
  if ! blkid $DISK2 | grep -q ext4; then
    echo "Formatting $DISK2 as ext4..."
    mkfs.ext4 -F $DISK2
  fi
  mkdir -p /mnt/data2
  if ! mountpoint -q /mnt/data2; then
    mount $DISK2 /mnt/data2
    # Add to fstab only if not already present
    if ! grep -q "$DISK2.*mnt/data2" /etc/fstab; then
      echo "$DISK2 /mnt/data2 ext4 defaults 0 0" >> /etc/fstab
    fi
  fi
  echo "✓ $DISK2 mounted at /mnt/data2"
fi

echo "Disk setup complete"
