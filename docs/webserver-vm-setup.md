# Recipes Server VM Setup Guide

Complete guide for setting up an internet-facing web server VM with nginx reverse proxy, SSL/TLS, and security hardening. This server will host the recipes application.

## Overview

| Setting | Value |
|---------|-------|
| VM ID | 101 |
| Hostname | recipes |
| OS | Debian 13 (Trixie) |
| vCPU | 2 |
| RAM | 6 GB |
| Disk | 50 GB (SSD) |
| IP Address | 192.168.10.20/24 (LAN) or 192.168.20.10/24 (DMZ) |
| Domain | recipes.home |

> **Note**: This guide documents the LAN setup (192.168.10.20). For DMZ isolation with VLAN 20, see [VLAN Network Setup](vlan-network-setup.md) and adjust IP addresses accordingly.

## Prerequisites

- [ ] Proxmox VE running
- [ ] SSH public key ready for deployment
- [ ] (Optional) VLAN 20 configured for DMZ isolation

## Phase 1: VM Creation

### Download Debian ISO

On Proxmox web UI:
1. Navigate to **Datacenter → pve → local (pve)**
2. Click **ISO Images** → **Download from URL**
3. Browse to `https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/` to find the current version
4. Use URL: `https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-X.X.X-amd64-netinst.iso` (replace X.X.X with current version)

> **Note**: Version numbers change frequently. As of February 2026, the current version is Debian 13.3.0.

### Create VM in Proxmox

**Via Web UI:**

1. Click **Create VM** (top right)
2. **General**:
   - VM ID: `101`
   - Name: `recipes`
3. **OS**:
   - ISO image: Select the Debian ISO
   - Type: Linux
   - Version: 6.x - 2.6 Kernel
4. **System**:
   - BIOS: Default (SeaBIOS)
   - SCSI Controller: VirtIO SCSI
   - Qemu Agent: Check this box
5. **Disks**:
   - Storage: local-lvm (SSD)
   - Disk size: 50 GB
6. **CPU**:
   - Cores: 2
   - Type: host (or x86-64-v2-AES for compatibility)
7. **Memory**:
   - Memory: 6144 MB
   - Minimum memory: 2048 MB (for ballooning)
8. **Network**:
   - Bridge: vmbr0
   - VLAN Tag: (leave blank for LAN, or `20` for DMZ)
   - Model: VirtIO
9. **Confirm** and create

**Via CLI:**
```bash
qm create 101 \
  --name recipes \
  --cores 2 \
  --memory 6144 \
  --balloon 2048 \
  --net0 virtio,bridge=vmbr0 \
  --scsi0 local-lvm:50,format=raw \
  --scsihw virtio-scsi-pci \
  --ide2 local:iso/debian-13.3.0-amd64-netinst.iso,media=cdrom \
  --boot order=ide2 \
  --agent enabled=1
```

### Install Debian

1. Start VM and open console
2. Select **Install** (not graphical)
3. Follow prompts:
   - Language: English
   - Location: United States
   - Keyboard: American English
   - Hostname: `recipes`
   - Domain: `home`
   - Root password: (set strong password or disable)
   - User: `dustin` (full name and password)
   - Timezone: Pacific
   - Partitioning: **Guided - use entire disk** → All files in one partition
   - Package manager mirror: Select a mirror, or **skip** if network isn't ready
   - Software selection:
     - [ ] Debian desktop environment (uncheck)
     - [x] SSH server
     - [x] Standard system utilities
4. Install GRUB to primary disk
5. Reboot and remove ISO

> **Troubleshooting**: If the mirror selection fails (404 errors or network issues), select **No** when asked to use a network mirror. You can configure apt sources after installation.

### Post-Install: Configure Apt Sources (if skipped during install)

If you skipped the network mirror during installation:

```bash
su -
nano /etc/apt/sources.list
```

Add:
```
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
```

### Post-Install: Network Configuration

Configure static IP:

```bash
su -
nano /etc/network/interfaces
```

**For LAN setup (192.168.10.x):**
```
auto lo
iface lo inet loopback

auto ens18
iface ens18 inet static
    address 192.168.10.20/24
    gateway 192.168.10.1
```

**For DMZ setup (192.168.20.x):**
```
auto lo
iface lo inet loopback

auto ens18
iface ens18 inet static
    address 192.168.20.10/24
    gateway 192.168.20.1
```

Configure DNS:
```bash
nano /etc/resolv.conf
```

```
nameserver 192.168.10.1
nameserver 1.1.1.1
```

Apply changes:
```bash
systemctl restart networking

# Verify
ip addr show ens18
ping -c 3 8.8.8.8
ping -c 3 google.com
```

### Install Essential Packages

```bash
apt update && apt upgrade -y
apt install -y qemu-guest-agent sudo
usermod -aG sudo dustin
```

> **Note**: The `qemu-guest-agent` may show a warning about missing installation config on Debian 13. This is not critical - the agent still functions.

## Phase 2: SSH Configuration

### Install SSH (if not installed during setup)

```bash
apt install -y openssh-server
systemctl enable ssh
systemctl start ssh
```

> **Note**: On Debian, the service is named `ssh`, not `sshd`.

### Deploy SSH Key

From your workstation:
```bash
ssh-copy-id dustin@192.168.10.20
```

Verify key login works:
```bash
ssh dustin@192.168.10.20
```

### Harden SSH

```bash
sudo nano /etc/ssh/sshd_config
```

Apply these settings:
```
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
AllowUsers dustin
```

Test and restart:
```bash
sudo sshd -t
sudo systemctl restart ssh
```

**Important**: Test SSH key login in a NEW terminal before closing your current session!

## Phase 3: Firewall Configuration (UFW)

```bash
sudo apt install -y ufw

# Set defaults
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH from LAN only
sudo ufw allow from 192.168.10.0/24 to any port 22 proto tcp comment 'SSH from LAN'

# Allow web traffic from anywhere
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# Enable firewall
sudo ufw enable

# Verify
sudo ufw status verbose
```

Expected output:
```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    192.168.10.0/24            # SSH from LAN
80/tcp                     ALLOW IN    Anywhere                   # HTTP
443/tcp                    ALLOW IN    Anywhere                   # HTTPS
80/tcp (v6)                ALLOW IN    Anywhere (v6)              # HTTP
443/tcp (v6)               ALLOW IN    Anywhere (v6)              # HTTPS
```

## Phase 4: fail2ban Setup

```bash
sudo apt install -y fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

Configure these settings:

Under `[DEFAULT]`:
```ini
bantime = 3600
findtime = 600
maxretry = 5
banaction = ufw
```

Under `[sshd]`:
```ini
[sshd]
enabled = true
port = ssh
maxretry = 3
```

Start fail2ban:
```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo fail2ban-client status
```

## Phase 5: Automatic Security Updates

```bash
sudo apt install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -plow unattended-upgrades
```

Select **Yes** when prompted.

## Phase 6: Nginx Installation

### Install nginx

```bash
sudo apt install -y nginx
sudo systemctl enable nginx
```

### Create Default Site (Security)

Generate self-signed cert for unknown hosts:
```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/default.key \
    -out /etc/nginx/ssl/default.crt \
    -subj "/CN=invalid"
sudo chmod 600 /etc/nginx/ssl/default.key
```

Configure default site to drop unknown requests:
```bash
sudo nano /etc/nginx/sites-available/default
```

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    ssl_certificate /etc/nginx/ssl/default.crt;
    ssl_certificate_key /etc/nginx/ssl/default.key;

    server_name _;
    return 444;
}
```

### Create SSL Configuration Snippet

```bash
sudo nano /etc/nginx/snippets/ssl-params.conf
```

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;

add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

> **Note**: OCSP stapling is omitted since it requires certificates from a public CA.

### Deploy SSL Certificate

From your workstation (homelab project directory):
```bash
scp certs/services/recipes/recipes.key dustin@192.168.10.20:/tmp/
scp certs/services/recipes/recipes-chain.crt dustin@192.168.10.20:/tmp/
```

On the recipes server:
```bash
sudo mv /tmp/recipes.key /etc/nginx/ssl/
sudo mv /tmp/recipes-chain.crt /etc/nginx/ssl/
sudo chmod 600 /etc/nginx/ssl/recipes.key
sudo chown root:root /etc/nginx/ssl/recipes.*
```

### Create recipes.home Site

```bash
sudo nano /etc/nginx/sites-available/recipes.home
```

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name recipes.home;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name recipes.home;

    ssl_certificate /etc/nginx/ssl/recipes-chain.crt;
    ssl_certificate_key /etc/nginx/ssl/recipes.key;
    include snippets/ssl-params.conf;

    access_log /var/log/nginx/recipes.home.access.log;
    error_log /var/log/nginx/recipes.home.error.log;

    root /var/www/recipes.home;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

> **Note**: Debian 13 uses a newer nginx that requires `http2 on;` as a separate directive instead of `listen 443 ssl http2;`.

Create web root and enable site:
```bash
sudo mkdir -p /var/www/recipes.home
echo '<h1>Recipes Server</h1><p>Server is running.</p>' | sudo tee /var/www/recipes.home/index.html
sudo chown -R www-data:www-data /var/www/recipes.home
sudo ln -s /etc/nginx/sites-available/recipes.home /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Phase 7: DNS Configuration

### Add DNS Entry in Pi-hole

1. Access Pi-hole admin UI
2. Navigate to **Local DNS → DNS Records**
3. Add:
   - Domain: `recipes.home`
   - IP Address: `192.168.10.20`

> **Troubleshooting**: If DNS works in browsers but not in terminal (curl, ssh), flush your macOS DNS cache:
> ```bash
> sudo dscacheutil -flushcache
> sudo killall -HUP mDNSResponder
> ```

## Phase 8: Runtime Installation (Optional)

### Node.js

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node --version
```

### Python

```bash
sudo apt install -y python3-pip python3-venv
python3 --version
```

## Phase 9: Recipe Book API Deployment

The Recipe Book API is a Spring Boot application that serves as the backend for the recipes web app.

### Prerequisites

- Java 21 (installed via setup script)
- JAR file built from `recipe-book-api` project
- SQLite database file

### Automated Setup

A setup script is available in the homelab project:

```bash
# From workstation - upload and run setup script
scp scripts/setup-recipe-book-api.sh dustin@192.168.10.20:/tmp/
ssh dustin@192.168.10.20 "sudo /tmp/setup-recipe-book-api.sh"
```

The script:
1. Installs Java 21
2. Creates `/opt/recipe-book` directory and `recipeapp` user
3. Creates systemd service (`recipe-book.service`)
4. Adds API proxy block to nginx config (proxies `/api/` to port 9002)

### Build and Deploy JAR

On your workstation:

```bash
# Build the JAR
cd /path/to/recipe-book/recipe-book-api
mvn clean package -DskipTests

# Upload JAR and database
scp target/recipe-book-api-*.jar dustin@192.168.10.20:/tmp/recipe-book-api.jar
scp sqlite.db dustin@192.168.10.20:/tmp/sqlite.db
```

On the server:

```bash
# Move files to app directory
sudo mv /tmp/recipe-book-api.jar /opt/recipe-book/
sudo mv /tmp/sqlite.db /opt/recipe-book/

# Set ownership
sudo chown recipeapp:recipeapp /opt/recipe-book/*

# Create images directory
sudo mkdir -p /data/recipe-book/image-repo
sudo chown recipeapp:recipeapp /data/recipe-book/image-repo
```

### Configure Spring Profiles

Edit the systemd service to set Spring profiles:

```bash
sudo nano /etc/systemd/system/recipe-book.service
```

Ensure the Environment line is set:

```ini
Environment="SPRING_PROFILES_ACTIVE=prod,sqlite"
```

### Start the Service

```bash
sudo systemctl daemon-reload
sudo systemctl start recipe-book
sudo systemctl enable recipe-book
sudo systemctl status recipe-book
```

### Verify Deployment

```bash
# Check service is running
sudo systemctl status recipe-book

# Test API directly
curl -s http://localhost:9002/api/menuitems | head -20

# Test through nginx
curl -sk https://recipes.home/api/menuitems | head -20

# View logs
sudo journalctl -u recipe-book -f
```

### Configuration Reference

| Setting | Value |
|---------|-------|
| Profiles | `prod,sqlite` |
| Port | 9002 |
| Database | `/opt/recipe-book/sqlite.db` |
| Images | `/data/recipe-book/image-repo` |
| Logs | `/opt/recipe-book/recipe-book.log` |
| Service | `recipe-book.service` |

### Useful Commands

```bash
# Restart API
sudo systemctl restart recipe-book

# View logs
sudo journalctl -u recipe-book -f

# Check what port is in use
sudo ss -tlnp | grep java
```

## Verification Checklist

```bash
# Network
ping -c 3 8.8.8.8
ping -c 3 google.com

# SSH (from workstation)
ssh dustin@192.168.10.20

# Firewall
sudo ufw status verbose

# fail2ban
sudo fail2ban-client status

# nginx
sudo nginx -t
curl -Ik https://recipes.home
```

## Troubleshooting

### Cannot SSH to Server

1. Check UFW: `sudo ufw status`
2. Check SSH: `sudo systemctl status ssh`
3. Check fail2ban: `sudo fail2ban-client status sshd`

### nginx Won't Start

1. Check config: `sudo nginx -t`
2. Check logs: `sudo tail -f /var/log/nginx/error.log`
3. Verify SSL cert paths and permissions

### DNS Not Resolving (macOS)

Flush DNS cache:
```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

Or add to `/etc/hosts`:
```
192.168.10.20 recipes.home
```

## Current Status

- **VM**: Running on LAN (192.168.10.20)
- **Recipe Book API**: Running on port 9002, accessible at https://recipes.home/api/
- **VLAN isolation**: Pending - requires switch/router trunk port configuration

## Next Steps

1. Deploy the recipes frontend (React UI)
2. Configure VLAN 20 for DMZ isolation
3. Set up monitoring
4. Configure backups for `/opt/recipe-book` and nginx configs
