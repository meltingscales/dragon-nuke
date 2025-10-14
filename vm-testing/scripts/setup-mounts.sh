#!/bin/bash
# Setup complex mount scenarios for Dragon Nuke testing
# Tests bind mounts, nested mounts, read-only mounts, and tmpfs

set -e

echo "Creating complex mount scenarios..."

# Ensure base directories exist (data should already be populated at this point)
# If directories don't exist, create them
if [ ! -d /mnt/data1/shared ]; then
  mkdir -p /mnt/data1/shared
fi
if [ ! -d /mnt/data1/readonly-source ]; then
  mkdir -p /mnt/data1/readonly-source
fi
if [ ! -d /mnt/data1/nested ]; then
  mkdir -p /mnt/data1/nested
fi
if [ ! -d /mnt/data2/backup ]; then
  mkdir -p /mnt/data2/backup
fi

# Bind mount from data1 to another location
mkdir -p /mnt/shared-bind
if ! mountpoint -q /mnt/shared-bind; then
  mount --bind /mnt/data1/shared /mnt/shared-bind
  echo "✓ Bind mount: /mnt/data1/shared -> /mnt/shared-bind"
fi

# Bind mount from data2
mkdir -p /mnt/backup-bind
if ! mountpoint -q /mnt/backup-bind; then
  mount --bind /mnt/data2/backup /mnt/backup-bind
  echo "✓ Bind mount: /mnt/data2/backup -> /mnt/backup-bind"
fi

# tmpfs mount for temporary data
mkdir -p /mnt/tmpfs-cache
if ! mountpoint -q /mnt/tmpfs-cache; then
  mount -t tmpfs -o size=100M tmpfs /mnt/tmpfs-cache
  echo "✓ tmpfs mount: /mnt/tmpfs-cache (100MB)"
fi

# Nested mount: create a directory on data1 and mount data2 inside it
if ! mountpoint -q /mnt/data1/nested; then
  mount --bind /mnt/data2 /mnt/data1/nested
  echo "✓ Nested bind mount: /mnt/data2 -> /mnt/data1/nested"
fi

# Read-only bind mount
mkdir -p /mnt/readonly-bind
if ! mountpoint -q /mnt/readonly-bind; then
  mount --bind /mnt/data1/readonly-source /mnt/readonly-bind
  mount -o remount,ro,bind /mnt/readonly-bind
  echo "✓ Read-only bind mount: /mnt/data1/readonly-source -> /mnt/readonly-bind"
fi

echo "Complex mount setup complete"
