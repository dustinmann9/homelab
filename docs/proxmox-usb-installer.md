# Creating a Proxmox VE USB Installer on macOS

## Prerequisites

- Proxmox VE 8.x ISO image downloaded from https://www.proxmox.com/en/downloads
- USB drive (minimum 2 GB, will be completely erased)

## Steps

### 1. Identify the USB Device

List all disks to find your USB drive:

```bash
diskutil list
```

Look for an `(external, physical)` disk matching your USB drive's size. Note the device identifier (e.g., `disk4`).

**WARNING**: Double-check you have the correct disk. The next steps will erase all data on the target device.

### 2. Unmount the USB Drive

Replace `diskN` with your actual disk identifier:

```bash
diskutil unmountDisk /dev/diskN
```

### 3. Write the ISO to USB

Use `dd` to write the Proxmox ISO directly to the USB drive. Using `rdisk` (raw disk) instead of `disk` is significantly faster.

```bash
sudo dd if=/path/to/proxmox-ve_8.x.iso of=/dev/rdiskN bs=4M status=progress
```

- `if=` - path to the Proxmox ISO file
- `of=` - output device (use `rdiskN` for faster writes)
- `bs=4M` - block size for faster transfer
- `status=progress` - show write progress

This may take several minutes depending on USB drive speed.

### 4. Eject the USB Drive

After `dd` completes:

```bash
diskutil eject /dev/diskN
```

The USB drive is now ready to boot the Proxmox installer.

## Troubleshooting

### "Resource busy" error
If you get this error, make sure all volumes on the USB are unmounted:
```bash
diskutil unmountDisk force /dev/diskN
```

### macOS tries to initialize the disk after dd
Click "Ignore" or "Eject" - the disk is now formatted for Proxmox, not macOS.

### Verifying the write
You can verify by checking if the USB shows as a bootable device in your server's BIOS/UEFI boot menu.
