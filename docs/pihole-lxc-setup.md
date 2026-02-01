# Pi-hole LXC Container Setup

## Overview

Pi-hole provides network-wide ad blocking and local DNS resolution. This guide covers setting up Pi-hole v6+ in a Proxmox LXC container.

**Note**: Pi-hole v6+ uses an embedded web server (pihole-FTL) instead of lighttpd.

## Container Specifications

| Setting | Value |
|---------|-------|
| CT ID | 100 |
| Hostname | pihole |
| Template | debian-12-standard |
| Disk | 8 GB |
| CPU | 1 core |
| Memory | 2048 MB |
| Swap | 512 MB |
| IP Address | 192.168.10.8/24 |
| Gateway | 192.168.10.1 |

## Step 1: Download Container Template

In Proxmox web UI:

1. Ensure storage has "Container template" content type enabled:
   - **Datacenter** → **Storage** → select **local** → **Edit**
   - Check **Container template** in Content dropdown
2. Select **local** storage under your node
3. Click **CT Templates** → **Templates**
4. Download **debian-12-standard**

Or via CLI:
```bash
pveam update
pveam available --section system | grep debian-12
pveam download local debian-12-standard_12.12-1_amd64.tar.zst
```

## Step 2: Create Container

In Proxmox web UI, click **Create CT**:

1. **General tab**
   - CT ID: `100`
   - Hostname: `pihole`
   - Password: set root password

2. **Template tab**
   - Storage: `local`
   - Template: `debian-12-standard_12.12-1_amd64.tar.zst`

3. **Disks tab**
   - Storage: `local-lvm`
   - Disk size: `8` GB

4. **CPU tab**
   - Cores: `1`

5. **Memory tab**
   - Memory: `2048` MB
   - Swap: `512` MB

6. **Network tab**
   - Bridge: `vmbr0`
   - IPv4: `Static`
   - IPv4/CIDR: `192.168.10.8/24`
   - Gateway: `192.168.10.1`

7. **DNS tab**
   - Leave defaults

8. **Confirm tab**
   - Check **Start after created**
   - Click **Finish**

## Step 3: Install Pi-hole

Enter the container:
```bash
pct enter 100
```

Update and install dependencies:
```bash
apt update && apt upgrade -y
apt install curl -y
```

Run Pi-hole installer:
```bash
curl -sSL https://install.pi-hole.net | bash
```

Installer prompts:
- Interface: `eth0`
- Upstream DNS: Your preference (Cloudflare, Google, etc.)
- Blocklists: Default
- Web admin interface: **Yes**
- Logging: **Yes**
- Privacy mode: Your preference

**Important**: Save the admin password displayed at the end.

## Step 4: Harden SSH Access

Install SSH server:
```bash
apt install openssh-server -y
```

Create admin user:
```bash
adduser dustin
apt install sudo -y
usermod -aG sudo dustin
```

From your workstation, copy SSH key:
```bash
ssh-copy-id dustin@192.168.10.8
```

Verify key-based login works:
```bash
ssh dustin@192.168.10.8
sudo whoami  # Should return "root"
```

Harden SSH configuration:
```bash
sudo nano /etc/ssh/sshd_config
```

Set:
```
PermitRootLogin no
PasswordAuthentication no
```

Restart SSH:
```bash
sudo systemctl restart sshd
```

## Step 5: Configure SSL/TLS

Pi-hole v6+ uses the embedded pihole-FTL web server. SSL is configured using a combined PEM file containing both the certificate chain and private key.

### Generate Certificate

From your workstation (in the homelab repo):
```bash
./scripts/generate-server-cert.sh pihole pihole.home 192.168.10.8
```

### Create Combined PEM File

The FTL web server requires a single file with the certificate chain and private key:
```bash
cat certs/services/pihole/pihole-fullchain.crt certs/services/pihole/pihole.key > /tmp/pihole-combined.pem
```

### Deploy to Pi-hole

Copy the combined PEM to Pi-hole:
```bash
scp /tmp/pihole-combined.pem dustin@192.168.10.8:/tmp/
rm /tmp/pihole-combined.pem
```

On Pi-hole, move to permanent location and set permissions:
```bash
sudo mkdir -p /etc/pihole/tls
sudo mv /tmp/pihole-combined.pem /etc/pihole/tls/
sudo chmod 400 /etc/pihole/tls/pihole-combined.pem
sudo chown pihole:pihole /etc/pihole/tls/pihole-combined.pem
```

### Configure FTL to Use Certificate

```bash
sudo pihole-FTL --config webserver.tls.cert /etc/pihole/tls/pihole-combined.pem
sudo systemctl restart pihole-FTL
```

### Verify SSL Configuration

```bash
pihole-FTL --config webserver.tls.cert
```

Access `https://pihole.home/admin` to verify (requires Root CA trust on client).

## Step 6: Verify Installation

- [ ] Web interface accessible at `http://192.168.10.8/admin`
- [ ] HTTPS works at `https://pihole.home/admin` (after SSL setup)
- [ ] Can SSH as non-root user with key authentication
- [ ] Cannot SSH as root
- [ ] DNS queries resolve: `dig @192.168.10.8 google.com`

## Accessing Pi-hole

- **Web Interface**: https://pihole.home/admin (or http://192.168.10.8/admin)
- **SSH**: `ssh dustin@192.168.10.8`
- **Proxmox Console**: `pct enter 100`

## Post-Installation Configuration

### Change Admin Password

```bash
pihole -a -p
```

### Update Pi-hole

```bash
pihole -up
```

### Check Version

```bash
pihole -v
```

### Add Local DNS Entries

In web UI: **Local DNS** → **DNS Records**

Add entries for homelab services:
| Domain | IP Address |
|--------|------------|
| pve.home | 192.168.10.2 |
| pihole.home | 192.168.10.8 |

### Configure Clients

Set DNS server to `192.168.10.8` on:
- Individual devices, or
- Router DHCP settings (network-wide)

## Troubleshooting

### Cannot reach web interface
```bash
pihole status
systemctl status pihole-FTL
```

### Check FTL configuration
```bash
pihole-FTL --config
```

### DNS not resolving
```bash
pihole restartdns
```

### Check logs
```bash
pihole -t  # Live tail of query log
journalctl -u pihole-FTL -f  # FTL service logs
```

### SSL not working
```bash
# Verify certificate path is set
pihole-FTL --config webserver.tls.cert

# Check file permissions
ls -la /etc/pihole/tls/

# Check FTL logs for TLS errors
journalctl -u pihole-FTL | grep -i tls
```

## Next Steps

- Configure router to use Pi-hole as DNS server
- Add local DNS entries for all homelab services
- Import Root CA on client devices (see [ssl-certificate-management.md](ssl-certificate-management.md))
- Configure blocklists as needed
