# Gmail SMTP Relay and System Alerting

## Overview

Configure postfix (matching the PVE host setup) on each VM to relay system
notifications through Gmail. The PVE host already has postfix relaying through
`smtp.gmail.com:587` and is confirmed working (sudo alerts landing in inbox).

VMs 101, 102, 103 need the same postfix relay configured.

## Email Addressing Convention

Each host sends to a Gmail plus address so inbox filters can route by host:

| Host / Service | MAILTO address |
|----------------|---------------|
| PVE (192.168.10.2) | dustin.mann9+pve@gmail.com |
| VM 101 Recipes (192.168.10.20) | dustin.mann9+recipes@gmail.com |
| VM 102 Sensor (192.168.10.30) | dustin.mann9+sensor@gmail.com |
| VM 102 Zeek (zeekctl built-in mailer) | dustin.mann9+zeek-sensor@gmail.com |
| VM 103 Elastic (192.168.10.31) | dustin.mann9+elastic@gmail.com |

The SMTP auth credential in `/etc/postfix/sasl/sasl_passwd` remains the base address (`dustin.mann9@gmail.com`) — only the destination changes.

## Current State (as of 2026-05-05)

| Host | Postfix relay | mdadm monitor | fail2ban | smartd | disk cron | VM health cron |
|------|--------------|---------------|----------|--------|-----------|----------------|
| PVE (192.168.10.2) | Working | Working | Active (+pve) | Active (+pve) | Active | Active (every 15 min) |
| VM 101 (192.168.10.20) | Working | N/A | Active (+recipes) | N/A | Active | N/A |
| VM 102 (192.168.10.30) | Working | N/A | Active (+sensor) | N/A | Active | N/A |
| VM 103 (192.168.10.31) | Working | N/A | Active (+elastic) | N/A | Active | N/A |
| PVE2 (192.168.10.9) | Working | N/A | Active (+pve2) | Active (+pve2) | Active | Active (every 15 min) |

## Prerequisites

### Gmail App Password (one-time)
1. Go to myaccount.google.com → Security → 2-Step Verification
2. Scroll to App passwords → create one named "homelab smtp"
3. Save the 16-character password — used on all VMs

## Step 1 — Configure Postfix Relay on VMs 101, 102, 103

Match the PVE host config. On each VM:

```bash
sudo apt install -y postfix mailutils libsasl2-modules
```

During install, select **"Internet Site"** then set the system mail name to the hostname (e.g. `recipes`).

Create SASL credentials file:
```bash
sudo mkdir -p /etc/postfix/sasl
sudo tee /etc/postfix/sasl/sasl_passwd > /dev/null << EOF
[smtp.gmail.com]:587 dustin.mann9@gmail.com:<app-password>
EOF
sudo chmod 600 /etc/postfix/sasl/sasl_passwd
sudo postmap /etc/postfix/sasl/sasl_passwd
```

Configure postfix settings using `postconf -e` (avoids conflicts with existing defaults in main.cf):
```bash
sudo postconf -e 'relayhost = [smtp.gmail.com]:587'
sudo postconf -e 'smtp_use_tls = yes'
sudo postconf -e 'smtp_sasl_auth_enable = yes'
sudo postconf -e 'smtp_sasl_password_maps = hash:/etc/postfix/sasl/sasl_passwd'
sudo postconf -e 'smtp_sasl_security_options = noanonymous'
sudo postconf -e 'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt'
sudo postconf -e 'inet_interfaces = loopback-only'
```

Restart and test:
```bash
sudo systemctl restart postfix
echo "Test from $(hostname)" | mail -s "postfix test" dustin.mann9@gmail.com
```

### Configure aliases (routes root mail to Gmail)
```bash
echo "root: dustin.mann9+<hostname>@gmail.com" | sudo tee -a /etc/aliases
sudo newaliases
```

## Step 2 — Fix RAID Monitoring on PVE (CRITICAL)

mdadm has your Gmail address configured but the monitor service is masked — no
disk failure emails will be sent in current state.

```bash
# On PVE host
sudo systemctl unmask mdadm
sudo systemctl enable --now mdadm
sudo systemctl status mdadm
```

Verify the config in `/etc/mdadm/mdadm.conf`:
```
MAILADDR dustin.mann9+pve@gmail.com
```

Test by forcing a monitor scan (does not send email unless there's an event, but confirms it runs):
```bash
sudo mdadm --monitor --scan --oneshot --test
```

## Step 3 — Enable fail2ban on PVE and all VMs

Monitors auth logs and bans IPs with repeated failures. Emails on ban events.

```bash
sudo apt install -y fail2ban rsyslog
# rsyslog required on Debian Bookworm — creates /var/log/daemon.log needed by proxmox jail
# Create the file immediately in case rsyslog hasn't written it yet before fail2ban starts
sudo touch /var/log/daemon.log
```

Create `/etc/fail2ban/jail.local`:
```ini
[DEFAULT]
destemail = dustin.mann9+<hostname>@gmail.com
sender = fail2ban@pve.home
action = %(action_mwl)s
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
backend = systemd
```

On the PVE host, also enable the Proxmox web UI jail:
```ini
[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 5
findtime = 1h
bantime = 1h
```

Note: Proxmox filter may need to be created at `/etc/fail2ban/filter.d/proxmox.conf`:
```ini
[Definition]
failregex = pvedaemon\[.*\]: authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
```

Start and verify:
```bash
sudo systemctl enable --now fail2ban
sudo fail2ban-client status
```

## Step 4 — Enable smartd on PVE (Disk Health)

Monitors SMART data on all drives and emails on pre-failure indicators (reallocated
sectors, pending sectors, etc.) — catches dying drives before they fail and degrade
the RAID array.

```bash
# On PVE host
sudo apt install -y smartmontools
```

Edit `/etc/smartd.conf` — replace default content with:
```
DEVICESCAN -a -o on -S on -n standby,q \
  -W 4,45,55 \
  -m dustin.mann9+pve@gmail.com \
  -M exec /usr/share/smartmontools/smartd-runner
```

This scans all drives, enables automatic offline testing, emails on any SMART
attribute failure, and alerts if drive temp exceeds 55°C.

```bash
sudo systemctl enable --now smartmontools.service
# Note: smartd.service is an alias on Debian Bookworm — use smartmontools.service directly
sudo smartctl -a /dev/sda  # verify SMART is readable on each drive (use /dev/nvme0 for NVMe)
```

## Step 5 — Disk Space Alerts (all VMs + PVE)

Simple cron job — emails when any filesystem exceeds 85% full. Especially
important for VM 103 (Elastic Stack) where logs can fill disk quickly.

Create `/etc/cron.daily/disk-space-check`:
```bash
#!/bin/bash
THRESHOLD=85
MAILTO="dustin.mann9+<hostname>@gmail.com"
HOSTNAME=$(hostname)

df -H | grep -vE '^Filesystem|tmpfs|cdrom|udev' | awk '{ print $5 " " $1 " " $6 }' | while read output; do
    usage=$(echo "$output" | awk '{ print $1}' | cut -d'%' -f1)
    partition=$(echo "$output" | awk '{ print $2 }')
    mountpoint=$(echo "$output" | awk '{ print $3 }')
    if [ "$usage" -ge "$THRESHOLD" ]; then
        echo "WARNING: $partition ($mountpoint) is ${usage}% full on $HOSTNAME" \
          | mail -s "Disk space alert: $HOSTNAME $mountpoint ${usage}%" "$MAILTO"
    fi
done
```

```bash
sudo chmod +x /etc/cron.daily/disk-space-check
```

## Step 6 — VM Health Check on PVE

Cron job on PVE that emails if any expected VM/CT is not running.

Create `/etc/cron.d/vm-health-check`:
```bash
*/15 * * * * root /usr/local/bin/vm-health-check.sh
```

Create `/usr/local/bin/vm-health-check.sh`:
```bash
#!/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin
MAILTO="dustin.mann9+pve@gmail.com"
HOSTNAME=$(hostname)

# Check all VMs with onboot=1
qm list | awk "NR>1 {print \$1}" | while read vmid; do
    if qm config "$vmid" 2>/dev/null | grep -q "^onboot: 1"; then
        name=$(qm config "$vmid" | awk -F": " "/^name:/ {print \$2}")
        status=$(qm status "$vmid" | awk "{print \$2}")
        if [ "$status" != "running" ]; then
            echo "VM $vmid ($name) is not running (status: ${status:-unknown})" \
              | mail -s "VM alert: $name ($vmid) down on $HOSTNAME" "$MAILTO"
        fi
    fi
done

# Check all CTs with onboot=1
pct list | awk "NR>1 {print \$1}" | while read ctid; do
    if pct config "$ctid" 2>/dev/null | grep -q "^onboot: 1"; then
        name=$(pct config "$ctid" | awk -F": " "/^hostname:/ {print \$2}")
        status=$(pct status "$ctid" | awk "{print \$2}")
        if [ "$status" != "running" ]; then
            echo "CT $ctid ($name) is not running (status: ${status:-unknown})" \
              | mail -s "VM alert: $name ($ctid) down on $HOSTNAME" "$MAILTO"
        fi
    fi
done
```

```bash
sudo chmod +x /usr/local/bin/vm-health-check.sh
```

## Step 7 — Suricata Alerts (VM 102)

Suricata logs alerts to `/var/log/suricata/fast.log` but has no native email.
Two options:

### Option A: Simple script (now)
Daily cron that emails a summary of new high-severity alerts:
```bash
#!/bin/bash
# /etc/cron.daily/suricata-alert-summary
LOGFILE=/var/log/suricata/fast.log
MAILTO="dustin.mann9+sensor@gmail.com"
LAST_RUN=/var/run/suricata-last-alert-check

SINCE=$(cat "$LAST_RUN" 2>/dev/null || echo "0")
NEW_ALERTS=$(awk -v since="$SINCE" 'NR > since' "$LOGFILE" | grep -i "priority: 1\|priority: 2" | wc -l)

if [ "$NEW_ALERTS" -gt 0 ]; then
    awk -v since="$SINCE" 'NR > since' "$LOGFILE" | grep -i "priority: 1\|priority: 2" \
      | mail -s "Suricata: $NEW_ALERTS high-severity alerts on $(hostname)" "$MAILTO"
fi

wc -l < "$LOGFILE" > "$LAST_RUN"
```

### Option B: Kibana alerting (later — requires VM 103)
Once Elastic Stack is stood up, configure Kibana alerting rules with threshold-based
triggers. More control over deduplication, severity filtering, and alert fatigue.
Preferred long-term solution.

## Unattended-Upgrades Email (all VMs)

Already configured. Add to `/etc/apt/apt.conf.d/50unattended-upgrades` if not present:
```
Unattended-Upgrade::Mail "dustin.mann9+<hostname>@gmail.com";
Unattended-Upgrade::MailReport "on-change";
```

## Priority Order

1. **Fix mdadm on PVE** — RAID failure alerts are broken right now
2. **Postfix relay on VMs 101, 102, 103** — nothing can email without this
3. **fail2ban on PVE** — most exposed host
4. **smartd on PVE** — early warning on drive health
5. **fail2ban on VMs** — lower priority, less exposed
6. **Disk space cron** — especially important for VM 103
7. **VM health check cron on PVE**
8. **Suricata alert script on VM 102** — or wait for Kibana
