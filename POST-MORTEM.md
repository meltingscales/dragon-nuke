# Post-Nuke Disk Inspection Guide

After running dragon-nuke on VMs or baremetal machines, the filesystems will be wiped and the systems will be unbootable. This guide shows how to inspect the nuked disks to verify the operation was successful.

## ⚠️ Baremetal Considerations

When running dragon-nuke on baremetal machines, additional precautions and analysis methods are needed:

### Before Nuking Baremetal
- **Boot from USB/CD**: Ensure you have a recovery environment ready
- **Network isolation**: The nuke script disables network adapters, so remote access will be lost
- **Physical access required**: You'll need console/KVM access to see the final destruction
- **Backup critical data**: Unlike VMs, there's no snapshot to revert to

### Baremetal-Specific Analysis
- **Remove drives physically**: For forensic analysis, remove storage devices and connect to analysis machine
- **UEFI/BIOS settings**: Check if boot entries are wiped (modern UEFI stores boot data on ESP)
- **Multiple drive scenarios**: Verify all drives were detected and wiped (RAID, NVMe, SATA, USB)
- **Firmware storage**: Some data may persist in UEFI NVRAM, BMC storage, or hardware RAID metadata

### Hardware-Specific Concerns
- **NVMe drives**: May have over-provisioned areas not accessible via `/dev/sdX`
- **SSDs with wear leveling**: Physical blocks may retain data even after logical wiping
- **Hardware RAID**: Controller metadata may survive logical disk wiping
- **USB/removable media**: Script only targets non-removable block devices
- **Network-attached storage**: iSCSI, NFS mounts are network-based and won't be physically wiped

## Table of Contents

1. [Quick Verification](#quick-verification)
2. [VBoxManage Disk Export (VMs only)](#vboxmanage-disk-export)
3. [Baremetal Disk Analysis](#baremetal-disk-analysis)
4. [Hex Editor Inspection](#hex-editor-inspection)
5. [GParted Live Analysis](#gparted-live-analysis)
6. [What to Look For](#what-to-look-for)

## Quick Verification

First, verify the VM is unbootable and the nuke operation completed:

```bash
# Try to start the VM (should fail to boot)
cd vm-testing
vagrant up dragon-nuke-vm-1

# Check the last logs before nuke
vagrant ssh dragon-nuke-vm-1 -c "sudo tail -100 /var/log/dragon-nuke.log" 2>/dev/null || echo "VM is unbootable (expected)"
```

## VBoxManage Disk Export (VMs only)

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

## Baremetal Disk Analysis

For baremetal machines, you'll need to physically remove drives and connect them to an analysis machine:

### Physical Drive Removal and Connection

```bash
# 1. Power down the nuked machine completely
# 2. Remove drives (SATA, NVMe, etc.)
# 3. Connect to analysis machine via:
#    - USB-to-SATA adapter
#    - PCIe NVMe adapter  
#    - External drive enclosure
#    - Secondary SATA/NVMe slot in analysis machine

# Once connected, identify the new drive
sudo dmesg | tail -20  # Look for new drive detection
lsblk                  # List all block devices
sudo fdisk -l          # List all drives and partitions

# Example: Drive appears as /dev/sdb
NUKED_DRIVE="/dev/sdb"
```

### Create Raw Image for Analysis

```bash
# Create a forensic image of the entire drive
sudo dd if=${NUKED_DRIVE} of=/tmp/nuked-baremetal.raw bs=4M status=progress conv=noerror,sync

# Verify image integrity
sudo sha256sum ${NUKED_DRIVE} > /tmp/original-drive.sha256
sha256sum /tmp/nuked-baremetal.raw > /tmp/disk-image.sha256

# Compare checksums (should match if drive is readable)
diff /tmp/original-drive.sha256 /tmp/disk-image.sha256
```

### Hardware-Specific Analysis

```bash
# Check for NVMe-specific information
if [[ ${NUKED_DRIVE} == *"nvme"* ]]; then
  echo "Analyzing NVMe drive..."
  sudo nvme id-ctrl ${NUKED_DRIVE}
  sudo nvme smart-log ${NUKED_DRIVE}
  
  # Check for over-provisioned areas
  sudo nvme id-ns ${NUKED_DRIVE}n1
fi

# Check for SSD-specific information
sudo hdparm -I ${NUKED_DRIVE} 2>/dev/null | grep -E "(Model|Serial|Firmware)"

# Look for any surviving partition tables or boot sectors
sudo sfdisk -l ${NUKED_DRIVE} 2>/dev/null || echo "No partition table found (good)"
sudo parted ${NUKED_DRIVE} print 2>/dev/null || echo "No partitions found (good)"
```

### UEFI/BIOS Analysis

```bash
# If the machine had UEFI, check for EFI System Partition remnants
# This requires the original machine or similar hardware
# Boot from live USB and check:

# List EFI variables (requires original machine with same firmware)
efibootmgr -v 2>/dev/null || echo "No EFI boot entries found"

# Check for ESP (EFI System Partition) remnants
sudo blkid | grep -i "TYPE=\"vfat\"" || echo "No FAT32 partitions found"
```

### Multi-Drive Verification

```bash
# If the baremetal machine had multiple drives, analyze each one
for drive in /dev/sd? /dev/nvme?n?; do
  if [[ -b "$drive" ]]; then
    echo "=== Analyzing $drive ==="
    sudo fdisk -l "$drive" 2>/dev/null || echo "No partition table on $drive"
    
    # Check first few MB for any surviving data
    sudo dd if="$drive" bs=1M count=10 2>/dev/null | hexdump -C | head -50
    echo ""
  fi
done
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

Create a quick verification script that works for both VM images and baremetal drives:

```bash
#!/bin/bash
# verify-nuke.sh - Quick verification that disk was properly nuked

TARGET="$1"

if [ ! -e "$TARGET" ]; then
  echo "Usage: $0 <disk-image.raw|/dev/sdX>"
  echo "Examples:"
  echo "  $0 /tmp/dragon-nuke-vm-1-disk1.raw    # VM disk image"
  echo "  $0 /dev/sdb                           # Baremetal drive (requires sudo)"
  exit 1
fi

# Check if target is a block device (baremetal) or file (VM image)
if [ -b "$TARGET" ]; then
  echo "Analyzing block device: $TARGET"
  if [ "$EUID" -ne 0 ]; then
    echo "Error: Block device analysis requires root privileges"
    echo "Run: sudo $0 $TARGET"
    exit 1
  fi
  DISK_TYPE="block"
else
  echo "Analyzing disk image: $TARGET"
  DISK_TYPE="file"
fi

echo "Size: $(du -h "$TARGET" | cut -f1 2>/dev/null || echo "N/A (block device)")"
echo ""

# Check boot signature
echo -n "Boot signature (0x1FE): "
BOOT_SIG=$(xxd -s 0x1FE -l 2 -p "$TARGET")
if [ "$BOOT_SIG" = "0000" ]; then
  echo "✓ Zeroed (was 55aa)"
else
  echo "✗ Still present: $BOOT_SIG"
fi

# Check ext4 magic
echo -n "ext4 magic (0x438): "
EXT4_SIG=$(xxd -s 0x438 -l 2 -p "$TARGET")
if [ "$EXT4_SIG" = "0000" ]; then
  echo "✓ Zeroed (was 53ef)"
else
  echo "✗ Still present: $EXT4_SIG"
fi

# Sample check for non-zero bytes
echo -n "Non-zero bytes check: "
NONZERO=$(hexdump -C "$TARGET" | head -1000 | grep -v "00 00 00 00 00 00 00 00" | wc -l)
if [ "$NONZERO" -eq 0 ]; then
  echo "✓ First 4MB all zeros"
else
  echo "✗ Found $NONZERO lines with non-zero data"
fi

# Search for lorem ipsum (should be gone)
echo -n "Lorem ipsum search: "
if grep -q "Lorem ipsum" "$TARGET"; then
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

# For VM disk images
./verify-nuke.sh /tmp/dragon-nuke-vm-1-disk1.raw

# For baremetal drives (requires sudo)
sudo ./verify-nuke.sh /dev/sdb
```

## Data Recovery Tools

To verify the nuke was effective, try using data recovery tools - **they should fail to recover anything meaningful**:

### Command-Line Recovery Tools

```bash
# TestDisk - Partition and file recovery
sudo apt-get install testdisk
sudo testdisk /dev/sdb          # Should find no recoverable partitions
sudo photorec /dev/sdb          # Should find no recoverable files

# Sleuth Kit - Forensic analysis
sudo apt-get install sleuthkit
img_stat /tmp/nuked-drive.raw   # Should show no filesystem
fls /tmp/nuked-drive.raw        # Should fail or show nothing

# Scrounge NTFS - NTFS file recovery  
sudo apt-get install scrounge-ntfs
scrounge-ntfs /dev/sdb /tmp/recovered/   # Should recover nothing

# Foremost - File carving based on headers
sudo apt-get install foremost
sudo foremost -i /dev/sdb -o /tmp/foremost-output/   # Should find no files

# Bulk Extractor - Extract features from disk images
sudo apt-get install bulk-extractor  
bulk_extractor -o /tmp/bulk-output/ /tmp/nuked-drive.raw   # Should extract nothing useful
```

### GUI Recovery Tools

```bash
# R-Linux - Free Linux data recovery (GUI)
# Download from: https://www.r-studio.com/free-linux-recovery/
wget https://www.r-studio.com/downloads/rlinux64.tar.gz
tar -xzf rlinux64.tar.gz && cd rlinux64
sudo ./rlinux_en    # Should find no recoverable data

# PhotoRec GUI - Part of TestDisk
sudo apt-get install qphotorec
sudo qphotorec      # GUI version, should recover no photos/files

# GParted - Partition editor (should show unallocated space)
sudo apt-get install gparted
sudo gparted        # Should show drive as unallocated/unknown

# UFS Explorer - Commercial tool (trial version)
# Download from: https://www.ufsexplorer.com/download_std.php
# Should be unable to detect any filesystem structures

# DMDE - Free disk editor and data recovery
# Download from: https://dmde.com/download.html
# Should show only zeros when examining the drive
```

### System Recovery Boot Disks

Test these live environments to see if they can detect/recover anything:

```bash
# System Rescue - Comprehensive rescue toolkit
# Download: https://www.system-rescue.org/Download/
# Boot from USB - should find no filesystems to mount

# Kali Linux - Forensic tools included
# Download: https://www.kali.org/get-kali/
# Includes: autopsy, volatility, binwalk, etc.

# CAINE - Computer Aided INvestigative Environment  
# Download: https://www.caine-live.net/
# Forensic-focused Linux distro

# REMnux - Reverse engineering and malware analysis
# Download: https://remnux.org/
# Should find no recognizable file structures
```

### Expected Results After Successful Nuke

All recovery tools should show:

✅ **No partitions detected**  
✅ **No filesystem signatures found**  
✅ **No recoverable files**  
✅ **Drive shows as "unallocated" or "unknown"**  
✅ **Hex dumps show only zeros (00 00 00 00...)**  
✅ **No boot sectors or MBR/GPT tables**  
✅ **File carving tools find nothing**  

If any recovery tool succeeds in finding data, the nuke was **incomplete**.

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
