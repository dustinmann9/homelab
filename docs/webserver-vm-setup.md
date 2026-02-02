# Recipes Server VM Setup Guide

Complete guide for setting up an internet-facing web server VM with nginx reverse proxy, SSL/TLS, and security hardening. This server will host the recipes application.

## Overview

| Setting | Value |
|---------|-------|
| VM ID | 101 |
| Hostname | recipes |
| OS | Debian 12 (Bookworm) |
| vCPU | 2 |
| RAM | 6 GB |
| Disk | 50 GB (SSD) |
| IP Address | 192.168.20.10/24 |
| Gateway | 192.168.20.1 |
| VLAN | 20 (DMZ) |
| Domain | recipes.home |

## Prerequisites

- [ ] VLAN 20 (DMZ) configured on network (see [VLAN Network Setup](vlan-network-setup.md))
- [ ] Debian 12 ISO downloaded to Proxmox
- [ ] SSH public key ready for deployment

## Phase 1: VM Creation

### Download Debian 12 ISO

On Proxmox web UI:
1. Navigate to **Datacenter → pve → local (storage)**
2. Click **ISO Images** → **Download from URL**
3. URL: `https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso`
4. Or upload from your workstation

### Create VM in Proxmox

**Via Web UI:**

1. Click **Create VM** (top right)
2. **General**:
   - VM ID: `101`
   - Name: `recipes`
3. **OS**:
   - ISO image: Select Debian 12 ISO
   - Type: Linux
   - Version: 6.x - 2.6 Kernel
4. **System**:
   - BIOS: Default (SeaBIOS)
   - SCSI Controller: VirtIO SCSI
   - Qemu Agent: Check this box
5. **Disks**:
   - Storage: local-lvm (SSD)
   - Disk size: 50 GB
   - Format: Raw or QCOW2
6. **CPU**:
   - Cores: 2
   - Type: host (or kvm64 for compatibility)
7. **Memory**:
   - Memory: 6144 MB
   - Minimum memory: 2048 MB (for ballooning)
8. **Network**:
   - Bridge: vmbr0
   - VLAN Tag: 20
   - Model: VirtIO
9. **Confirm** and create

**Via CLI:**
```bash
qm create 101 \
  --name recipes \
  --cores 2 \
  --memory 6144 \
  --balloon 2048 \
  --net0 virtio,bridge=vmbr0,tag=20 \
  --scsi0 local-lvm:50,format=raw \
  --scsihw virtio-scsi-pci \
  --ide2 local:iso/debian-12.8.0-amd64-netinst.iso,media=cdrom \
  --boot order=ide2 \
  --agent enabled=1
```

### Install Debian 12

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
   - Package manager mirror: deb.debian.org
   - Software selection:
     - [ ] Debian desktop environment (uncheck)
     - [x] SSH server
     - [x] Standard system utilities
4. Install GRUB to primary disk
5. Reboot and remove ISO

### Post-Install: Network Configuration

After first boot, configure static IP:

```bash
# Login as dustin
su -

# Edit network configuration
nano /etc/network/interfaces
```

Replace DHCP configuration with static:

```
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto ens18
iface ens18 inet static
    address 192.168.20.10/24
    gateway 192.168.20.1
    dns-nameservers 192.168.10.100 1.1.1.1
```

Apply changes:
```bash
systemctl restart networking

# Verify
ip addr show ens18
ping -c 3 192.168.20.1
ping -c 3 8.8.8.8
```

### Install QEMU Guest Agent

```bash
apt update
apt install -y qemu-guest-agent
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
```

## Phase 2: Base System Hardening

### Update System

```bash
apt update && apt upgrade -y
```

### SSH Hardening

#### Deploy SSH Key

From your workstation:
```bash
ssh-copy-id dustin@192.168.20.10
```

Or manually on the server:
```bash
mkdir -p /home/dustin/.ssh
chmod 700 /home/dustin/.ssh

# Paste your public key
cat >> /home/dustin/.ssh/authorized_keys << 'EOF'
ssh-rsa AAAA... your-key-here
EOF

chmod 600 /home/dustin/.ssh/authorized_keys
chown -R dustin:dustin /home/dustin/.ssh
```

#### Configure SSH Daemon

```bash
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
nano /etc/ssh/sshd_config
```

Apply these settings:

```
# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Security
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
MaxAuthTries 3
MaxSessions 2

# Only allow specific user
AllowUsers dustin

# Logging
LogLevel VERBOSE
```

Test and restart:
```bash
# Test configuration
sshd -t

# Restart SSH
systemctl restart sshd
```

**Important**: Test SSH key login in a NEW terminal before closing current session!

### Configure Sudo

```bash
# Add dustin to sudo group (if not already)
usermod -aG sudo dustin

# Optionally configure passwordless sudo for specific commands
visudo
```

Add at end (optional):
```
dustin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx, /usr/bin/systemctl reload nginx
```

## Phase 3: Firewall Configuration (UFW)

### Install and Configure UFW

```bash
apt install -y ufw

# Set defaults
ufw default deny incoming
ufw default allow outgoing

# Allow SSH from LAN only (192.168.10.0/24)
ufw allow from 192.168.10.0/24 to any port 22 proto tcp comment 'SSH from LAN'

# Allow HTTP and HTTPS from anywhere
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Enable firewall
ufw enable

# Verify
ufw status verbose
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

### UFW Useful Commands

```bash
# View rules with numbers
ufw status numbered

# Delete a rule
ufw delete <number>

# Allow additional port
ufw allow <port>/tcp

# Deny specific IP
ufw deny from <ip>
```

## Phase 4: fail2ban Setup

### Install fail2ban

```bash
apt install -y fail2ban
```

### Configure fail2ban

```bash
# Create local configuration (don't edit jail.conf directly)
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
nano /etc/fail2ban/jail.local
```

Configure these settings in `jail.local`:

```ini
[DEFAULT]
# Ban for 1 hour
bantime = 3600

# Find patterns within 10 minutes
findtime = 600

# Ban after 5 failures
maxretry = 5

# Use UFW for banning
banaction = ufw

# Email notifications (optional)
# destemail = your@email.com
# sender = fail2ban@recipes.home
# action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
```

### Add nginx Jail

Create nginx filter and jail for when nginx is installed:

```bash
nano /etc/fail2ban/jail.d/nginx.local
```

```ini
[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

[nginx-botsearch]
enabled = true
port = http,https
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400
```

### Start fail2ban

```bash
systemctl enable fail2ban
systemctl start fail2ban

# Verify
fail2ban-client status
fail2ban-client status sshd
```

### fail2ban Useful Commands

```bash
# Check status of all jails
fail2ban-client status

# Check specific jail
fail2ban-client status sshd

# Unban an IP
fail2ban-client set sshd unbanip <IP>

# View banned IPs
fail2ban-client get sshd banned
```

## Phase 5: Automatic Security Updates

### Install unattended-upgrades

```bash
apt install -y unattended-upgrades apt-listchanges

# Configure
dpkg-reconfigure -plow unattended-upgrades
```

Select **Yes** to enable automatic updates.

### Configure unattended-upgrades

```bash
nano /etc/apt/apt.conf.d/50unattended-upgrades
```

Ensure these are uncommented:

```
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};

// Automatically reboot if required (optional - be careful with this)
// Unattended-Upgrade::Automatic-Reboot "true";
// Unattended-Upgrade::Automatic-Reboot-Time "03:00";

// Email notifications
// Unattended-Upgrade::Mail "your@email.com";
```

### Enable Auto-Update Timer

```bash
nano /etc/apt/apt.conf.d/20auto-upgrades
```

```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
```

## Phase 6: Nginx Installation

### Install nginx

```bash
apt install -y nginx
systemctl enable nginx
```

### Configure Default Site (Security)

Drop connections to unknown hosts:

```bash
nano /etc/nginx/sites-available/default
```

```nginx
# Default server - drop unknown hosts
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    # Self-signed cert for default (to handle HTTPS probes)
    ssl_certificate /etc/nginx/ssl/default.crt;
    ssl_certificate_key /etc/nginx/ssl/default.key;

    server_name _;

    # Return 444 (nginx special: close connection without response)
    return 444;
}
```

Generate self-signed cert for default server:

```bash
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/default.key \
    -out /etc/nginx/ssl/default.crt \
    -subj "/CN=invalid"
chmod 600 /etc/nginx/ssl/default.key
```

### Create SSL Configuration Snippet

```bash
nano /etc/nginx/snippets/ssl-params.conf
```

```nginx
# Mozilla Modern SSL Configuration
# https://ssl-config.mozilla.org/

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;

# Session settings
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;

# Security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# HSTS (enable after testing - 1 year)
# add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

### Create Reverse Proxy Template

```bash
nano /etc/nginx/sites-available/template-reverse-proxy
```

```nginx
# Template: Reverse Proxy Virtual Host
# Copy and modify for each application
#
# Usage:
#   cp /etc/nginx/sites-available/template-reverse-proxy /etc/nginx/sites-available/myapp
#   nano /etc/nginx/sites-available/myapp
#   ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/
#   nginx -t && systemctl reload nginx

server {
    listen 80;
    listen [::]:80;
    server_name example.home;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name example.home;

    # SSL Certificate
    ssl_certificate /etc/nginx/ssl/recipes-chain.crt;
    ssl_certificate_key /etc/nginx/ssl/recipes.key;
    include snippets/ssl-params.conf;

    # Logging
    access_log /var/log/nginx/example.access.log;
    error_log /var/log/nginx/example.error.log;

    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 90;
    }
}
```

### Create recipes.home Site

```bash
nano /etc/nginx/sites-available/recipes.home
```

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name recipes.home;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name recipes.home;

    # SSL Certificate (deploy from homelab CA)
    ssl_certificate /etc/nginx/ssl/recipes-chain.crt;
    ssl_certificate_key /etc/nginx/ssl/recipes.key;
    include snippets/ssl-params.conf;

    # Logging
    access_log /var/log/nginx/recipes.home.access.log;
    error_log /var/log/nginx/recipes.home.error.log;

    root /var/www/recipes.home;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Create web root:

```bash
mkdir -p /var/www/recipes.home
cat > /var/www/recipes.home/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Mannsclann Recipes Server</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif;
               max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        .status { color: green; }
    </style>
</head>
<body>
    <h1>Mannsclann Recipes Server</h1>
    <p class="status">Server is running.</p>
    <hr>
    <p>Hostname: recipes.home</p>
    <p>IP: 192.168.20.10</p>
</body>
</html>
EOF

chown -R www-data:www-data /var/www/recipes.home
```

Enable site:

```bash
ln -s /etc/nginx/sites-available/recipes.home /etc/nginx/sites-enabled/
```

## Phase 7: SSL Certificate Deployment

### Generate Certificate (on workstation)

The certificate already exists but needs to be regenerated with the correct DMZ IP address.

From your homelab project directory:

```bash
# Remove old certificate with wrong IP
rm -rf certs/services/recipes

# Generate new certificate with DMZ IP
./scripts/generate-server-cert.sh recipes recipes.home 192.168.20.10
```

### Deploy Certificate to Server

From your workstation:

```bash
# Copy certificate files
scp certs/services/recipes/recipes.key dustin@192.168.20.10:/tmp/
scp certs/services/recipes/recipes-chain.crt dustin@192.168.20.10:/tmp/
```

On the recipes server:

```bash
sudo mv /tmp/recipes.key /etc/nginx/ssl/
sudo mv /tmp/recipes-chain.crt /etc/nginx/ssl/
sudo chmod 600 /etc/nginx/ssl/recipes.key
sudo chown root:root /etc/nginx/ssl/recipes.*
```

### Test nginx Configuration

```bash
nginx -t
```

Expected output:
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### Start nginx

```bash
systemctl restart nginx
systemctl status nginx
```

## Phase 8: Runtime Installation

### Node.js (via NodeSource)

```bash
# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
apt install -y nodejs

# Verify
node --version
npm --version

# Install common global packages (optional)
npm install -g pm2
```

### Python 3

Python 3 is pre-installed on Debian 12. Set up virtual environment support:

```bash
apt install -y python3-pip python3-venv

# Verify
python3 --version
pip3 --version
```

### Creating Application Environments

For Node.js apps:
```bash
mkdir -p /var/www/myapp
cd /var/www/myapp
npm init -y
```

For Python apps:
```bash
mkdir -p /var/www/myapp
cd /var/www/myapp
python3 -m venv venv
source venv/bin/activate
pip install flask  # or whatever framework
```

## Phase 9: DNS Configuration

### Add DNS Entry in Pi-hole

1. SSH to Pi-hole or access admin UI
2. Navigate to **Local DNS → DNS Records**
3. Add:
   - Domain: `recipes.home`
   - IP Address: `192.168.20.10`

Or via CLI on Pi-hole:

```bash
echo "192.168.20.10 recipes.home" >> /etc/pihole/custom.list
pihole restartdns
```

## Verification Checklist

Run these tests to verify setup:

### Network Connectivity

```bash
# From recipes server
ping -c 3 192.168.20.1     # Gateway
ping -c 3 8.8.8.8          # Internet
ping -c 3 google.com       # DNS resolution
```

### SSH Access

```bash
# From LAN workstation
ssh dustin@192.168.20.10   # Should work

# Verify key-only auth (should fail with password)
ssh -o PubkeyAuthentication=no dustin@192.168.20.10
```

### Firewall Status

```bash
# On recipes server
sudo ufw status verbose
```

### fail2ban Status

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

### Web Server

```bash
# Test nginx config
sudo nginx -t

# Check nginx is running
systemctl status nginx

# Test locally
curl -I http://localhost
curl -Ik https://localhost
```

### SSL Certificate

```bash
# From workstation
curl -Iv https://recipes.home 2>&1 | grep -A 5 "Server certificate"

# Or use openssl
openssl s_client -connect 192.168.20.10:443 -servername recipes.home < /dev/null
```

### External Access (after port forwarding)

```bash
# From outside network or using mobile data
curl -I http://your-public-ip
curl -Ik https://your-public-ip
```

## Troubleshooting

### Cannot SSH to Server

1. Check UFW is allowing SSH from your IP:
   ```bash
   sudo ufw status
   ```
2. Check SSH is running:
   ```bash
   sudo systemctl status sshd
   ```
3. Check auth log:
   ```bash
   sudo tail -f /var/log/auth.log
   ```
4. Verify you're not banned by fail2ban:
   ```bash
   sudo fail2ban-client status sshd
   ```

### nginx Won't Start

1. Check configuration syntax:
   ```bash
   sudo nginx -t
   ```
2. Check error log:
   ```bash
   sudo tail -f /var/log/nginx/error.log
   ```
3. Check SSL certificate paths and permissions

### SSL Certificate Issues

1. Verify certificate files exist:
   ```bash
   ls -la /etc/nginx/ssl/
   ```
2. Check certificate validity:
   ```bash
   openssl x509 -in /etc/nginx/ssl/recipes-chain.crt -noout -dates
   ```
3. Verify chain is complete:
   ```bash
   openssl verify -CAfile /path/to/root-ca.crt /etc/nginx/ssl/recipes-chain.crt
   ```

### Cannot Access from Internet

1. Verify port forwarding on router
2. Check public IP and port is reachable:
   ```bash
   # From outside network
   nc -zv your-public-ip 443
   ```
3. Check ISP isn't blocking ports 80/443

## Security Maintenance

### Regular Tasks

- **Weekly**: Check fail2ban logs for suspicious activity
- **Monthly**: Review nginx access logs
- **Quarterly**: Update SSL certificates before expiry
- **As needed**: Apply security updates (automated via unattended-upgrades)

### Useful Commands

```bash
# View recent auth failures
sudo grep "Failed" /var/log/auth.log | tail -20

# View banned IPs
sudo fail2ban-client status sshd

# View nginx access log
sudo tail -f /var/log/nginx/access.log

# Check for available updates
sudo apt update && apt list --upgradable

# View automatic update log
sudo cat /var/log/unattended-upgrades/unattended-upgrades.log
```

## Next Steps

1. Deploy the recipes application
2. Set up monitoring with Uptime Kuma or similar
3. Configure backup for `/var/www` and nginx configs
4. Consider adding rate limiting to nginx
5. Set up log aggregation for centralized monitoring
