# Post-Nuke Disk Inspection Guide

After running dragon-nuke on a VM, the filesystems will be wiped and the VM will be unbootable. This guide shows how to inspect the nuked disks to verify the operation was successful.

## Table of Contents

1. [Quick Verification](#quick-verification)
2. [VBoxManage Disk Export](#vboxmanage-disk-export)
3. [Hex Editor Inspection](#hex-editor-inspection)
4. [GParted Live Analysis](#gparted-live-analysis)
5. [What to Look For](#what-to-look-for)

## Quick Verification

First, verify the VM is unbootable and the nuke operation completed:

```bash
# Try to start the VM (should fail to boot)
cd vm-testing
vagrant up dragon-nuke-vm-1

# Check the last logs before nuke
vagrant ssh dragon-nuke-vm-1 -c "sudo tail -100 /var/log/dragon-nuke.log" 2>/dev/null || echo "VM is unbootable (expected)"
```

## VBoxManage Disk Export

Export the VM disks for offline inspection:

```bash
# List all VirtualBox VMs and their UUIDs
VBoxManage list vms

# Show disk attachments for a specific VM
VBoxManage showvminfo dragon-nuke-vm-1 | grep -E "SCSI|SATA|IDE"

# Clone the main disk to a raw image for inspection
VBoxManage clonehd "vm-testing/disks/dragon-nuke-vm-1-disk1.vdi" \
  "/tmp/dragon-nuke-vm-1-disk1.raw" --format RAW

# Or clone disk2
VBoxManage clonehd "vm-testing/disks/dragon-nuke-vm-1-disk2.vdi" \
  "/tmp/dragon-nuke-vm-1-disk2.raw" --format RAW

# Check disk info
VBoxManage showhdinfo "vm-testing/disks/dragon-nuke-vm-1-disk1.vdi"
```

## Hex Editor Inspection

Use a hex editor to verify the disk has been wiped:

### Using hexdump (CLI)

```bash
# View first 1KB of the disk
hexdump -C /tmp/dragon-nuke-vm-1-disk1.raw | head -100

# Search for filesystem signatures (should return nothing after nuke)
# ext4 magic number (0xEF53 at offset 0x438)
hexdump -C /tmp/dragon-nuke-vm-1-disk1.raw | grep "53 ef"

# Check if disk is all zeros
if hexdump -C /tmp/dragon-nuke-vm-1-disk1.raw | grep -v "00 00 00 00 00 00 00 00" | head -10; then
  echo "Disk contains non-zero data"
else
  echo "Disk appears to be completely zeroed"
fi

# Random sample check - examine multiple 4KB blocks across the disk
for offset in 0 1048576 104857600 524288000; do
  echo "=== Checking offset $offset ==="
  dd if=/tmp/dragon-nuke-vm-1-disk1.raw bs=4096 count=1 skip=$((offset/4096)) 2>/dev/null | hexdump -C | head -20
done
```

### Using xxd (more readable)

```bash
# View first 512 bytes (boot sector area)
xxd -l 512 /tmp/dragon-nuke-vm-1-disk1.raw

# Check boot signature at end of boot sector (offset 0x1FE, should be 55 AA before nuke, 00 00 after)
xxd -s 0x1FE -l 2 /tmp/dragon-nuke-vm-1-disk1.raw

# Check ext4 superblock area (offset 0x400, 1024 bytes)
xxd -s 0x400 -l 1024 /tmp/dragon-nuke-vm-1-disk1.raw
```

### Using GUI Hex Editors

**Bless Hex Editor (Linux):**
```bash
sudo apt-get install bless
bless /tmp/dragon-nuke-vm-1-disk1.raw
```

**wxHexEditor (Linux):**
```bash
sudo apt-get install wxhexeditor
wxhexeditor /tmp/dragon-nuke-vm-1-disk1.raw
```

**HxD (Windows):**
Download from https://mh-nexus.de/en/hxd/

## GParted Live Analysis

For a visual inspection, attach the disk to a GParted Live USB/ISO:

### Method 1: Create a new VM with the nuked disk

```bash
# Create a temporary VM for inspection
VBoxManage createvm --name "disk-inspector" --ostype Ubuntu_64 --register

# Add storage controller
VBoxManage storagectl disk-inspector --name "SATA" --add sata --controller IntelAHCI

# Attach the nuked disk
VBoxManage storageattach disk-inspector --storagectl "SATA" --port 0 --device 0 --type hdd \
  --medium "vm-testing/disks/dragon-nuke-vm-1-disk1.vdi"

# Download GParted Live ISO (if not already downloaded)
wget https://downloads.sourceforge.net/gparted/gparted-live-1.5.0-6-amd64.iso -O /tmp/gparted-live.iso

# Attach GParted ISO as bootable CD
VBoxManage storagectl disk-inspector --name "IDE" --add ide
VBoxManage storageattach disk-inspector --storagectl "IDE" --port 0 --device 0 --type dvddrive \
  --medium /tmp/gparted-live.iso

# Set boot order to CD
VBoxManage modifyvm disk-inspector --boot1 dvd --boot2 disk

# Configure VM
VBoxManage modifyvm disk-inspector --memory 2048 --vram 128

# Start VM
VBoxManage startvm disk-inspector

# When done, clean up
VBoxManage unregistervm disk-inspector --delete
```

### Method 2: Mount disk to existing Linux VM

```bash
# Attach the nuked disk to a running VM
VBoxManage storageattach "some-linux-vm" --storagectl "SATA" --port 2 --device 0 --type hdd \
  --medium "vm-testing/disks/dragon-nuke-vm-1-disk1.vdi"

# Inside the VM, use fdisk to inspect
sudo fdisk -l

# Try to detect filesystems (should fail or show raw/unknown)
sudo blkid

# Use testdisk to analyze (won't be able to recover if nuke worked)
sudo apt-get install testdisk
sudo testdisk /dev/sdc
```

## What to Look For

### Signs of Successful Nuke

✅ **All zeros**: The disk should be filled with `00` bytes throughout
```
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
```

✅ **No filesystem signatures**:
- ext4 magic (`53 ef`) should be absent
- Boot signature (`55 aa` at offset 0x1FE) should be zeroed
- No partition table entries

✅ **GParted shows**: "unallocated" or "unknown" for entire disk

✅ **blkid returns**: Nothing or "unknown"

✅ **VM fails to boot**: No bootloader, no filesystem found

### Signs of Incomplete Nuke (Problems)

❌ **Readable data**: Any recognizable text, filenames, or file contents

❌ **Filesystem signatures present**:
```bash
# Bad - filesystem still detectable
$ sudo blkid /dev/sdc
/dev/sdc: UUID="abc123..." TYPE="ext4"
```

❌ **Partition table intact**:
```bash
# Bad - partitions still exist
$ sudo fdisk -l /dev/sdc
Device     Boot Start      End  Sectors Size Id Type
/dev/sdc1        2048  2099199  2097152   1G 83 Linux
```

❌ **Boot sector present**: `55 aa` signature at offset 0x1FE

❌ **Lorem ipsum or log data visible**: Any of the test data we populated should be completely gone

## Automated Verification Script

Create a quick verification script:

```bash
#!/bin/bash
# verify-nuke.sh - Quick verification that disk was properly nuked

DISK_IMAGE="$1"

if [ ! -f "$DISK_IMAGE" ]; then
  echo "Usage: $0 <disk-image.raw>"
  exit 1
fi

echo "Analyzing: $DISK_IMAGE"
echo "Size: $(du -h "$DISK_IMAGE" | cut -f1)"
echo ""

# Check boot signature
echo -n "Boot signature (0x1FE): "
BOOT_SIG=$(xxd -s 0x1FE -l 2 -p "$DISK_IMAGE")
if [ "$BOOT_SIG" = "0000" ]; then
  echo "✓ Zeroed (was 55aa)"
else
  echo "✗ Still present: $BOOT_SIG"
fi

# Check ext4 magic
echo -n "ext4 magic (0x438): "
EXT4_SIG=$(xxd -s 0x438 -l 2 -p "$DISK_IMAGE")
if [ "$EXT4_SIG" = "0000" ]; then
  echo "✓ Zeroed (was 53ef)"
else
  echo "✗ Still present: $EXT4_SIG"
fi

# Sample check for non-zero bytes
echo -n "Non-zero bytes check: "
NONZERO=$(hexdump -C "$DISK_IMAGE" | head -1000 | grep -v "00 00 00 00 00 00 00 00" | wc -l)
if [ "$NONZERO" -eq 0 ]; then
  echo "✓ First 4MB all zeros"
else
  echo "✗ Found $NONZERO lines with non-zero data"
fi

# Search for lorem ipsum (should be gone)
echo -n "Lorem ipsum search: "
if grep -q "Lorem ipsum" "$DISK_IMAGE"; then
  echo "✗ Found lorem ipsum text (BAD)"
else
  echo "✓ No lorem ipsum found"
fi

echo ""
echo "Summary: Disk appears to be $([ "$BOOT_SIG" = "0000" ] && [ "$EXT4_SIG" = "0000" ] && [ "$NONZERO" -eq 0 ] && echo 'SUCCESSFULLY NUKED' || echo 'NOT FULLY WIPED')"
```

Save and use:
```bash
chmod +x verify-nuke.sh
./verify-nuke.sh /tmp/dragon-nuke-vm-1-disk1.raw
```

## Performance Notes

Nuking a 1GB disk should take approximately:
- **dd with /dev/zero**: ~30-60 seconds (depends on disk speed)
- **dd with /dev/urandom**: ~5-10 minutes (much slower, cryptographically secure)
- **shred -n 3**: ~3-5 minutes (3 passes)

For the test VMs:
- disk1 (1GB) ≈ 1 minute with /dev/zero
- disk2 (2GB) ≈ 2 minutes with /dev/zero
- Main OS disk (~10GB) ≈ 10 minutes with /dev/zero

## References

- [VBoxManage Documentation](https://www.virtualbox.org/manual/ch08.html)
- [GParted Manual](https://gparted.org/display-doc.php)
- [Filesystem signatures reference](https://en.wikipedia.org/wiki/List_of_file_signatures)
