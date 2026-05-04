# Gmail SMTP Relay and System Alerting

## Overview

Configure postfix (matching the PVE host setup) on each VM to relay system
notifications through Gmail. The PVE host already has postfix relaying through
`smtp.gmail.com:587` and is confirmed working (sudo alerts landing in inbox).

VMs 101, 102, 103 need the same postfix relay configured.

## Current State (as of 2026-05-04)

| Host | Postfix relay | mdadm monitor | fail2ban | smartd | Notes |
|------|--------------|---------------|----------|--------|-------|
| PVE (192.168.10.2) | Working | **Masked/broken** | Inactive | Unknown | Most critical to fix |
| VM 101 (192.168.10.20) | Not set up | N/A | Inactive | N/A | |
| VM 102 (192.168.10.30) | Not set up | N/A | Inactive | N/A | Suricata running |
| VM 103 (192.168.10.31) | Not set up | N/A | Inactive | N/A | Not yet stood up |

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

Configure `/etc/postfix/main.cf`:
```
relayhost = [smtp.gmail.com]:587
smtp_use_tls = yes
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
inet_interfaces = loopback-only
```

Restart and test:
```bash
sudo systemctl restart postfix
echo "Test from $(hostname)" | mail -s "postfix test" dustin.mann9@gmail.com
```

### Configure aliases (routes root mail to Gmail)
```bash
echo "root: dustin.mann9@gmail.com" | sudo tee -a /etc/aliases
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
MAILADDR dustin.mann9@gmail.com
```

Test by forcing a monitor scan (does not send email unless there's an event, but confirms it runs):
```bash
sudo mdadm --monitor --scan --oneshot --test
```

## Step 3 — Enable fail2ban on PVE and all VMs

Monitors auth logs and bans IPs with repeated failures. Emails on ban events.

```bash
sudo apt install -y fail2ban
```

Create `/etc/fail2ban/jail.local`:
```ini
[DEFAULT]
destemail = dustin.mann9@gmail.com
sender = fail2ban@pve.home
action = %(action_mwl)s
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
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
  -m dustin.mann9@gmail.com \
  -M exec /usr/share/smartmontools/smartd-runner
```

This scans all drives, enables automatic offline testing, emails on any SMART
attribute failure, and alerts if drive temp exceeds 55°C.

```bash
sudo systemctl enable --now smartd
sudo smartctl -a /dev/sda  # verify SMART is readable on each drive
```

## Step 5 — Disk Space Alerts (all VMs + PVE)

Simple cron job — emails when any filesystem exceeds 85% full. Especially
important for VM 103 (Elastic Stack) where logs can fill disk quickly.

Create `/etc/cron.daily/disk-space-check`:
```bash
#!/bin/bash
THRESHOLD=85
MAILTO="dustin.mann9@gmail.com"
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
MAILTO="dustin.mann9@gmail.com"
EXPECTED_VMS="100 101 102 103"  # CT 100 (pihole), VM 101, 102, 103

for vmid in $EXPECTED_VMS; do
    status=$(qm status $vmid 2>/dev/null | awk '{print $2}' || pct status $vmid 2>/dev/null | awk '{print $2}')
    if [ "$status" != "running" ]; then
        echo "VM/CT $vmid is not running (status: $status)" \
          | mail -s "VM alert: $vmid down on $(hostname)" "$MAILTO"
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
MAILTO="dustin.mann9@gmail.com"
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
Unattended-Upgrade::Mail "dustin.mann9@gmail.com";
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
