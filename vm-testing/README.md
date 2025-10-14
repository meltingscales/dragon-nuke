# Dragon Nuke VM Testing Environment

This directory contains a Vagrant setup for testing the Dragon Nuke server across multiple Linux distributions.

## VM Configuration

The Vagrantfile creates **8 VMs** across **4 different distributions**:

| VM Name | Distribution | Base Box | Package Manager | Notes |
|---------|--------------|----------|-----------------|-------|
| `dragon-nuke-ubuntu-1` | Ubuntu 22.04 | ubuntu/jammy64 | apt | Debian-based, most common |
| `dragon-nuke-ubuntu-2` | Ubuntu 22.04 | ubuntu/jammy64 | apt | Debian-based, most common |
| `dragon-nuke-rhel-1` | RHEL 9 | generic/rhel9 | dnf | Enterprise, rpm-based |
| `dragon-nuke-rhel-2` | RHEL 9 | generic/rhel9 | dnf | Enterprise, rpm-based |
| `dragon-nuke-fedora-1` | Fedora 39 | generic/fedora39 | dnf | Bleeding edge, rpm-based |
| `dragon-nuke-fedora-2` | Fedora 39 | generic/fedora39 | dnf | Bleeding edge, rpm-based |
| `dragon-nuke-nixos-1` | NixOS 23.11 | nixos/nixos-23.11 | nix | Declarative config |
| `dragon-nuke-nixos-2` | NixOS 23.11 | nixos/nixos-23.11 | nix | Declarative config |

## Quick Start

```bash
# Start all VMs
vagrant up

# Start specific distro VMs
vagrant up /ubuntu/
vagrant up /rhel/
vagrant up /fedora/
vagrant up /nixos/

# Start a single VM
vagrant up dragon-nuke-ubuntu-1

# SSH into a VM
vagrant ssh dragon-nuke-ubuntu-1

# Check status of all VMs
vagrant status

# Stop all VMs
vagrant halt

# Destroy all VMs and disks
vagrant destroy -f
rm -rf disks/
```

## Testing the Nuke Script

Each VM runs the dragon-nuke server on boot. To trigger a nuke:

```bash
# Trigger nuke on a specific VM (from your host machine)
curl -X POST http://localhost:8080/nuke -H "Authorization: Bearer your-token"

# Or SSH in and check logs
vagrant ssh dragon-nuke-ubuntu-1
sudo tail -f /var/log/dragon-nuke.log
```

## VM Architecture

Each VM has identical configurations for consistent testing:

### Storage
- **Main OS Disk** (/dev/sda): ~10GB system disk
- **Data Disk 1** (/dev/sdc): 1GB formatted as ext4, mounted at `/mnt/data1`
- **Data Disk 2** (/dev/sdd): 2GB formatted as ext4, mounted at `/mnt/data2`

### Complex Mount Scenarios
To test unmounting logic:
- `/mnt/data1` - Direct mount of /dev/sdc
- `/mnt/data2` - Direct mount of /dev/sdd
- `/mnt/shared-bind` - Bind mount from /mnt/data1/shared
- `/mnt/backup-bind` - Bind mount from /mnt/data2/backup
- `/mnt/data1/nested` - Nested bind mount (data2 inside data1)
- `/mnt/readonly-bind` - Read-only bind mount
- `/mnt/tmpfs-cache` - tmpfs (memory-based, 100MB)

### Test Data
Each VM is populated with ~2GB of dummy data:
- Lorem ipsum text files (100-300MB each)
- Realistic directory structures (documents, databases, archives, logs, backups)
- Files in all mount points to test unmounting

### Safe Mounts (Won't Be Nuked)
- `/vagrant/keys` - Read-only VirtualBox shared folder (host `~/keys`)
- `/vagrant/server-dragon-nuke-ro` - Read-only VirtualBox shared folder (server code)
- `/vagrant/scripts` - Read-only VirtualBox shared folder (provisioning scripts)

## Post-Nuke Inspection

After nuking a VM, see [POST-MORTEM.md](./POST-MORTEM.md) for instructions on:
- Exporting disks with VBoxManage
- Inspecting with hex editors
- Mounting with GParted Live
- Verifying complete data destruction

## Testing Different Scenarios

### Test 1: Standard Nuke
```bash
vagrant up dragon-nuke-ubuntu-1
# Trigger nuke via API
# Verify VM is unbootable
```

### Test 2: Nuke with Active Processes
```bash
vagrant ssh dragon-nuke-ubuntu-1
# Create file handles and processes
dd if=/dev/urandom of=/mnt/data1/test.bin bs=1M count=100 &
# Trigger nuke
# Verify unmounting handles busy filesystems
```

### Test 3: Cross-Distro Consistency
```bash
# Start one of each distro
vagrant up dragon-nuke-ubuntu-1 dragon-nuke-rhel-1 dragon-nuke-fedora-1 dragon-nuke-nixos-1

# Nuke all simultaneously
# Verify behavior is consistent across distros
```

### Test 4: Nested Mount Handling
```bash
vagrant ssh dragon-nuke-ubuntu-1
mount | grep /mnt
# Verify nested mount at /mnt/data1/nested
# Trigger nuke
# Verify unmounting happens in correct order (nested first, then parent)
```

## Troubleshooting

### VM won't boot
```bash
# Check VirtualBox logs
VBoxManage showvminfo dragon-nuke-ubuntu-1 --log 0
```

### Provisioning fails
```bash
# Re-provision a specific VM
vagrant provision dragon-nuke-ubuntu-1

# Full rebuild
vagrant destroy dragon-nuke-ubuntu-1 -f
vagrant up dragon-nuke-ubuntu-1
```

### Disk attachment errors
```bash
# Clean up orphaned disks
rm -rf disks/
vagrant destroy -f
vagrant up
```

### Out of disk space
```bash
# Each VM uses ~3GB (10GB OS + 1GB + 2GB data + overhead)
# 8 VMs = ~24GB total
df -h
```

## Development Workflow

1. Make changes to server code in `../server-dragon-nuke/`
2. Reprovision VMs to pick up changes:
   ```bash
   vagrant provision
   ```
3. Or destroy and rebuild for clean state:
   ```bash
   vagrant destroy -f && rm -rf disks/ && vagrant up
   ```

## Scripts

Provisioning is modularized into separate scripts in `./scripts/`:
- `setup-disks.sh` - Format and mount /dev/sdc and /dev/sdd
- `setup-mounts.sh` - Create complex mount scenarios (bind, nested, tmpfs)
- `populate-data.sh` - Generate ~2GB of test data with lorem ipsum

These scripts are called during VM provisioning but can be run manually:
```bash
vagrant ssh dragon-nuke-ubuntu-1
sudo bash /vagrant/scripts/setup-disks.sh
```

## Performance Notes

- **Provisioning time per VM**: ~5-10 minutes (depends on network speed for downloads)
- **Data population time**: ~2-3 minutes (generating 2GB of lorem ipsum)
- **Expected nuke time**: ~10-15 minutes (zeroing 13GB of disk)
- **Total setup time for all 8 VMs**: ~1 hour

## Distribution-Specific Notes

### Ubuntu
- Most straightforward, well-tested base box
- Uses traditional systemd and apt

### RHEL
- Enterprise-focused, stable
- May require subscription for some packages (generic box includes free repos)
- SELinux enabled by default

### Fedora
- Latest packages, fast-moving
- Good for testing newer kernel features
- Uses dnf like RHEL

### NixOS
- Declarative configuration system
- Package installation via nix-env or configuration.nix
- Most different from other distros, good edge case testing
- May have different mount behavior due to unique filesystem layout

## License

MIT
