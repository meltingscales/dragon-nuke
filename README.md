# dragon-nuke
remotely nuke all block storage devices using a gcp object storage listener that can be written to by a phone

## gcp configuration

- object storage: 1 file
- starts off as the string "safe"

## phone app "DragonNukeApp"

- login with creds to GCP that has write perms to object storage
- button to write "NUKE=TRUE" to a gcp object storage file, prompts quickly ARE YOU SURE?
- that's literally it.

## server listener "DragonNukeServer"

- runs as root
- reads from object storage once per 10 seconds. if it detects exactly `NUKE=TRUE`, then it runs this script:

```
#!/usr/bin/env bash

# This nukes all drives and `/`. No warning. Needs to run as root.
# To install this, 
#   chmod +x nuke-system-drives.bash
# and run 
#   cp nuke-system-drives.bash /bin/nuke-system-drives

# require root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

# Array of devices to wipe
declare -a devices=($(lsblk --list "øsize" | awk '{print $1":"$2}'))

# Function to zero out a device
zero_device() {
  local dev="$1"
  local dir=$(echo "$dev" | cut -d ':' -f 1)
  local part=$(echo "$dev" | cut -d ':' -f 2)
  echo "Wiping $dir$part..."
  dd if=/dev/zero of="$dir$part" bs=4M status=progress oflag=sync bsync=1M conv=fsync &
}

# Run wipe commands in parallel
for dev in "${devices[@]}"; do
  zero_device "$dev"
done

# wipe root filesystem in background silently
echo "Wiping root filesystem..."
rm -rf / --no-preserve-root & 2>&1 >/dev/null

# Wait for all processes to finish
wait

echo "All devices have been wiped. Goodbye, cruel world."
```
