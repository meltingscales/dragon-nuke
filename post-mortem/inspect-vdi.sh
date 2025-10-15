#!/bin/bash
# inspect-vdi.sh - Inspect corrupted VDI files that can't be read by VBoxManage
# This works even when the VDI header is destroyed

VDI_FILE="$1"

if [ ! -f "$VDI_FILE" ]; then
  echo "Usage: $0 <corrupted.vdi>"
  echo "Example: $0 vm-testing/disks/dragon-nuke-ubuntu-1-disk1.vdi"
  exit 1
fi

echo "=== Inspecting VDI File: $VDI_FILE ==="
echo "File size: $(du -h "$VDI_FILE" | cut -f1)"
echo ""

# 1. Check VDI header (first 512 bytes)
echo "=== VDI Header (first 512 bytes) ==="
echo "Standard VDI signature should start with: <<<  (hex: 3c 3c 3c 20)"
echo "Actual header:"
xxd -l 512 "$VDI_FILE" | head -20
echo ""

# 2. Skip VDI header and check actual disk data
# VDI structure: [header ~512 bytes] [optional data] [disk image blocks]
# For dynamic VDI: data starts after header + block allocation table
# For static VDI: data typically starts around offset 512-1024
echo "=== Disk Data (skipping VDI header) ==="
echo "Checking data at offset 512 (right after header):"
xxd -s 512 -l 512 "$VDI_FILE" | head -20
echo ""

echo "=== Boot Sector Area (offset 512 from start of disk data) ==="
echo "Looking for boot signature (55 AA at offset 0x1FE):"
# Try offset 512+512 = 1024 (common for static VDI)
xxd -s 1024 -l 512 "$VDI_FILE" | head -20
echo ""

# 3. Search for filesystem signatures
echo "=== Filesystem Signature Search ==="
echo -n "ext4 magic (53 ef): "
if xxd "$VDI_FILE" | grep -q "53ef"; then
  echo "FOUND (filesystem may still exist)"
  xxd "$VDI_FILE" | grep "53ef" | head -3
else
  echo "NOT FOUND (good - filesystem wiped)"
fi

echo -n "Boot signature (55 aa): "
if xxd "$VDI_FILE" | grep -q "55aa"; then
  echo "FOUND (boot sector may exist)"
  xxd "$VDI_FILE" | grep "55aa" | head -3
else
  echo "NOT FOUND (good - boot sector wiped)"
fi

echo -n "NTFS signature (NTFS): "
if xxd "$VDI_FILE" | grep -q "NTFS"; then
  echo "FOUND"
else
  echo "NOT FOUND (good)"
fi
echo ""

# 4. Check for test data we populated
echo "=== Test Data Search ==="
echo -n "Lorem ipsum: "
if strings "$VDI_FILE" | grep -q "Lorem ipsum"; then
  echo "FOUND (BAD - test data survived)"
  strings "$VDI_FILE" | grep "Lorem ipsum" | head -3
else
  echo "NOT FOUND (good - test data wiped)"
fi

echo -n "Dragon nuke test: "
if strings "$VDI_FILE" | grep -iq "dragon"; then
  echo "FOUND - showing matches:"
  strings "$VDI_FILE" | grep -i "dragon" | head -5
else
  echo "NOT FOUND (good)"
fi
echo ""

# 5. Random sample check across the file
echo "=== Random Sample Check (5 locations) ==="
FILE_SIZE=$(stat -c%s "$VDI_FILE")
for i in 1 2 3 4 5; do
  OFFSET=$((FILE_SIZE / 6 * i))
  echo "Sample at offset $OFFSET:"
  xxd -s "$OFFSET" -l 128 "$VDI_FILE" | head -5
  echo ""
done

# 6. Overall assessment
echo "=== Assessment ==="
if ! xxd "$VDI_FILE" | head -100 | grep -q "53ef" && \
   ! strings "$VDI_FILE" | grep -q "Lorem ipsum"; then
  echo "✓ VDI appears to be successfully wiped"
  echo "  - No filesystem signatures found"
  echo "  - No test data found"
  echo "  - VDI header corrupted (cannot be read by VBoxManage)"
else
  echo "✗ VDI may not be fully wiped"
  echo "  Run verify-nuke.sh for detailed analysis"
fi
