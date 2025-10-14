#!/bin/bash
# Populate drives with dummy test data for Dragon Nuke testing
# Generates large files with lorem ipsum text

set -e

echo "Populating drives with dummy test data..."

# Create a reusable lorem ipsum generator function
generate_lorem() {
  local size_mb=$1
  local output_file=$2
  local lorem="Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. "

  # Calculate how many times to repeat (lorem is ~446 bytes, so ~2300 times per MB)
  local repeats=$((size_mb * 2300))

  for i in $(seq 1 $repeats); do
    echo "$lorem"
  done > "$output_file"

  echo "  Created $(du -h "$output_file" | cut -f1) file: $output_file"
}

# Data1 - Various file types and structures
echo "Populating /mnt/data1..."
mkdir -p /mnt/data1/documents /mnt/data1/images /mnt/data1/databases

echo "Important document content - Project Report 2025" > /mnt/data1/documents/report.txt
cat >> /mnt/data1/documents/report.txt << 'EOFR'
This is a comprehensive report on the Dragon Nuke testing infrastructure.
It contains important information about system architecture and deployment.
EOFR
generate_lorem 100 /mnt/data1/documents/report.txt

echo '{"server": "dragon-nuke-vm", "version": "1.0", "config": "production"}' > /mnt/data1/documents/config.json

generate_lorem 150 /mnt/data1/images/photo1.txt
generate_lorem 150 /mnt/data1/images/photo2.txt

echo "Database records for user management system" > /mnt/data1/databases/records.db
generate_lorem 200 /mnt/data1/databases/large.db

# Data1 shared (for bind mount)
echo "Populating /mnt/data1/shared (bind mount source)..."
echo "Shared file 1 - Team collaboration document" > /mnt/data1/shared/shared1.txt
generate_lorem 100 /mnt/data1/shared/shared1.txt

echo "Shared file 2 - Project specifications" > /mnt/data1/shared/shared2.txt
generate_lorem 100 /mnt/data1/shared/shared2.txt

generate_lorem 250 /mnt/data1/shared/largefile.txt

# Data1 readonly source
echo "Populating /mnt/data1/readonly-source..."
echo "Read-only configuration data - DO NOT MODIFY" > /mnt/data1/readonly-source/readonly.txt
generate_lorem 50 /mnt/data1/readonly-source/readonly.txt

echo "[protected]" > /mnt/data1/readonly-source/protected.conf
echo "encryption=enabled" >> /mnt/data1/readonly-source/protected.conf
echo "backup=daily" >> /mnt/data1/readonly-source/protected.conf

# Data2 - Backup and archive data
echo "Populating /mnt/data2..."
mkdir -p /mnt/data2/archives /mnt/data2/logs

echo "Archive 1 - Historical data from 2024" > /mnt/data2/archives/archive1.tar
generate_lorem 150 /mnt/data2/archives/archive1.tar

echo "Archive 2 - Backup snapshots" > /mnt/data2/archives/archive2.tar
generate_lorem 150 /mnt/data2/archives/archive2.tar

generate_lorem 300 /mnt/data2/archives/bigarchive.tar

# Generate realistic log files
echo "Generating log files..."
for i in {1..1000}; do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Application event $i - Processing request from user$(( RANDOM % 100 ))" >> /mnt/data2/logs/app.log
done
generate_lorem 100 /mnt/data2/logs/system.log

# Data2 backup (for bind mount)
echo "Populating /mnt/data2/backup (bind mount source)..."
echo "Backup file 1 - Weekly backup" > /mnt/data2/backup/backup1.bak
generate_lorem 100 /mnt/data2/backup/backup1.bak

echo "Backup file 2 - Monthly snapshot" > /mnt/data2/backup/backup2.bak
generate_lorem 100 /mnt/data2/backup/backup2.bak

generate_lorem 200 /mnt/data2/backup/fullbackup.bak

# tmpfs - Temporary cache data (smaller since it's memory-based)
echo "Populating /mnt/tmpfs-cache..."
echo "Cache entry 1 - Session cache" > /mnt/tmpfs-cache/cache1.tmp
echo "Cache entry 2 - Query results" > /mnt/tmpfs-cache/cache2.tmp
mkdir -p /mnt/tmpfs-cache/session
echo "Session data for user123 - authenticated at $(date)" > /mnt/tmpfs-cache/session/user123.session

# Set proper permissions
echo "Setting permissions..."
chown -R vagrant:vagrant /mnt/data1 /mnt/data2 /mnt/shared-bind /mnt/backup-bind /mnt/tmpfs-cache
chmod -R 755 /mnt/data1 /mnt/data2

# Display summary
echo ""
echo "=== Data Population Complete ==="
echo "Total disk usage:"
df -h | grep -E '/mnt' | awk '{printf "  %-20s %10s used of %10s\n", $6, $3, $2}'
echo ""
