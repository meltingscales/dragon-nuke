#!/bin/bash
# Setup additional hard drives for Dragon Nuke testing
# This script formats and mounts /dev/sdc and /dev/sdd

set -e

echo "Setting up additional hard drives..."

# Format and mount disk1 (/dev/sdc)
if [ ! -b /dev/sdc ]; then
  echo "Warning: /dev/sdc not found, skipping disk1 setup"
else
  if ! blkid /dev/sdc | grep -q ext4; then
    echo "Formatting /dev/sdc as ext4..."
    mkfs.ext4 -F /dev/sdc
  fi
  mkdir -p /mnt/data1
  if ! mountpoint -q /mnt/data1; then
    mount /dev/sdc /mnt/data1
    echo "/dev/sdc /mnt/data1 ext4 defaults 0 0" >> /etc/fstab
  fi
  echo "✓ /dev/sdc mounted at /mnt/data1"
fi

# Format and mount disk2 (/dev/sdd)
if [ ! -b /dev/sdd ]; then
  echo "Warning: /dev/sdd not found, skipping disk2 setup"
else
  if ! blkid /dev/sdd | grep -q ext4; then
    echo "Formatting /dev/sdd as ext4..."
    mkfs.ext4 -F /dev/sdd
  fi
  mkdir -p /mnt/data2
  if ! mountpoint -q /mnt/data2; then
    mount /dev/sdd /mnt/data2
    echo "/dev/sdd /mnt/data2 ext4 defaults 0 0" >> /etc/fstab
  fi
  echo "✓ /dev/sdd mounted at /mnt/data2"
fi

echo "Disk setup complete"
