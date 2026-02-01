# Proxmox VE 8.x Installation Guide

## Overview

This guide covers installing Proxmox VE 8.x and performing initial configuration and hardening.

## Prerequisites

- Proxmox VE 8.x ISO (download from https://www.proxmox.com/en/downloads)
- USB drive (minimum 2 GB)
- Server hardware meeting Proxmox requirements
- Network connection

## Step 1: Create Bootable USB

See [proxmox-usb-installer.md](proxmox-usb-installer.md) for detailed instructions on creating the installer USB from macOS.

## Step 2: Install Proxmox

1. Boot server from USB drive
2. Follow the Proxmox installer prompts
3. Set root password and email
4. Configure basic network settings (can use DHCP initially)
5. Complete installation and reboot

## Step 3: Configure Static IP

After installation, configure a static IP address.

### Edit network interfaces

```bash
nano /etc/network/interfaces
```

Change from DHCP to static configuration:

```
auto lo
iface lo inet loopback

iface eno1 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.10.2/24
    gateway 192.168.10.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0
```

Adjust `address` and `gateway` for your network.

### Apply changes

```bash
systemctl restart networking
```

### Update login banner

The console login screen shows the old IP. Update it:

```bash
nano /etc/issue
```

Change the IP address in the welcome message to match your new static IP.

## Step 4: Configure Repositories

Proxmox enterprise repositories require a subscription. For homelab use, switch to the no-subscription repository.

```bash
# Disable enterprise repositories
mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.disabled
mv /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.list.disabled 2>/dev/null

# Add no-subscription repository
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list

# Update package lists
apt update
```

## Step 5: SSH Hardening

Secure SSH access by creating a non-root user with sudo privileges and disabling password authentication.

### Create admin user

```bash
apt install sudo -y
adduser dustin
usermod -aG sudo dustin
```

### Set up SSH key authentication

From your workstation, copy your public key:

```bash
ssh-copy-id dustin@192.168.10.2
```

Or manually on the server:

```bash
mkdir -p /home/dustin/.ssh
nano /home/dustin/.ssh/authorized_keys
# Paste your public key
chmod 700 /home/dustin/.ssh
chmod 600 /home/dustin/.ssh/authorized_keys
chown -R dustin:dustin /home/dustin/.ssh
```

### Verify login

Before changing SSH config, verify key-based login works:

```bash
ssh dustin@192.168.10.2
sudo whoami  # Should return "root"
```

### Disable password authentication

Edit SSH configuration:

```bash
sudo nano /etc/ssh/sshd_config
```

Set these values:

```
PermitRootLogin prohibit-password
PasswordAuthentication no
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

**Important**: Keep an existing SSH session open until you verify the new configuration works.

## Step 6: Configure Web Console User

Proxmox has its own user/permission system separate from Linux. Add the admin user to Proxmox for web console access.

### Add user to Proxmox

```bash
sudo pveum user add dustin@pam
```

### Assign Administrator role

```bash
sudo pveum aclmod / -user dustin@pam -role Administrator
```

### Login to web console

- Username: `dustin` (select "Linux PAM standard authentication" from realm dropdown)
- Password: your Linux password

**Note**: Root login remains enabled as a recovery option, but use `dustin@pam` for daily administration to maintain an audit trail of actions.

## Step 7: Verify Installation

- [ ] Can access web console at `https://192.168.10.2:8006/`
- [ ] Can login to web console as `dustin@pam`
- [ ] Can SSH as non-root user with key authentication
- [ ] Cannot SSH as root with password
- [ ] `sudo apt update` works without 401 errors

## Accessing Proxmox

- **Web Console**: https://192.168.10.2:8006/
  - Login: `dustin@pam` with Linux password (preferred for audit trail)
  - Backup: `root@pam` with root password
- **SSH**: `ssh dustin@192.168.10.2`
  - Use sudo for administrative tasks

## Next Steps

- Configure storage (see [vm-architecture.md](vm-architecture.md))
- Set up SSL certificates (see [ssl-certificate-management.md](ssl-certificate-management.md))
- Create VMs as outlined in project plan
