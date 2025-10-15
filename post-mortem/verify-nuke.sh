#!/bin/bash
# verify-nuke.sh - Quick verification that disk was properly nuked

TARGET="$1"

if [ ! -e "$TARGET" ]; then
  echo "Usage: $0 <disk-image.raw|/dev/sdX|corrupted.vdi>"
  echo "Examples:"
  echo "  $0 /tmp/dragon-nuke-vm-1-disk1.raw    # VM disk image"
  echo "  $0 /dev/sdb                           # Baremetal drive (requires sudo)"
  echo "  $0 vm-testing/disks/*.vdi             # Corrupted VDI file"
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
BOOT_SIG=$(xxd -s 0x1FE -l 2 -p "$TARGET" 2>/dev/null)
if [ "$BOOT_SIG" = "0000" ]; then
  echo "✓ Zeroed (was 55aa)"
elif [ -z "$BOOT_SIG" ]; then
  echo "✗ Unable to read"
else
  echo "✗ Still present: $BOOT_SIG"
fi

# Check ext4 magic
echo -n "ext4 magic (0x438): "
EXT4_SIG=$(xxd -s 0x438 -l 2 -p "$TARGET" 2>/dev/null)
if [ "$EXT4_SIG" = "0000" ]; then
  echo "✓ Zeroed (was 53ef)"
elif [ -z "$EXT4_SIG" ]; then
  echo "✗ Unable to read"
else
  echo "✗ Still present: $EXT4_SIG"
fi

# Sample check for non-zero bytes
echo -n "Non-zero bytes check: "
NONZERO=$(hexdump -C "$TARGET" 2>/dev/null | head -1000 | grep -v "00 00 00 00 00 00 00 00" | wc -l)
if [ "$NONZERO" -eq 0 ]; then
  echo "✓ First 4MB all zeros"
else
  echo "✗ Found $NONZERO lines with non-zero data"
fi

# Search for lorem ipsum (should be gone)
echo -n "Lorem ipsum search: "
if grep -q "Lorem ipsum" "$TARGET" 2>/dev/null; then
  echo "✗ Found lorem ipsum text (BAD)"
else
  echo "✓ No lorem ipsum found"
fi

# Check VDI header if it's a VDI file
if [[ "$TARGET" == *.vdi ]]; then
  echo ""
  echo "=== VDI-Specific Checks ==="
  echo -n "VDI header signature: "
  VDI_SIG=$(xxd -l 64 -p "$TARGET" 2>/dev/null | head -1)
  if echo "$VDI_SIG" | grep -q "3c3c3c20"; then
    echo "✗ VDI header intact (signature found)"
  else
    echo "✓ VDI header corrupted/wiped (expected after nuke)"
  fi
fi

echo ""
echo "Summary: Disk appears to be $([ "$BOOT_SIG" = "0000" ] && [ "$EXT4_SIG" = "0000" ] && [ "$NONZERO" -eq 0 ] && echo 'SUCCESSFULLY NUKED' || echo 'NOT FULLY WIPED')"
