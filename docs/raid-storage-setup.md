# RAID5 Storage Setup

## Overview

This guide covers setting up the 4x1TB RAID5 array on Proxmox. The array was originally created on `server2` in August 2012 and migrated to the current Proxmox host.

## Array Specifications

| Property | Value |
|----------|-------|
| RAID Level | RAID5 |
| Devices | 4 x 1TB HDD |
| Partitions | `/dev/sda1`, `/dev/sdb1`, `/dev/sdc1`, `/dev/sdd1` |
| Array Device | `/dev/md0` |
| Usable Capacity | 2.73 TB |
| Filesystem | ext4 |
| Mount Point | `/data` |

## Prerequisites

Install mdadm if not already present:

```bash
apt update && apt install mdadm
```

## Checking for Existing RAID Metadata

If drives were previously part of a RAID array, check for existing metadata:

```bash
mdadm --examine /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1
```

Look for matching Array UUIDs and Event counts across all drives. If they match, the array can be reassembled without data loss.

## Assembling an Existing Array

If drives contain valid RAID metadata:

```bash
# Assemble the array
mdadm --assemble /dev/md0 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1

# Verify assembly
cat /proc/mdstat
```

## Creating a New Array

**Warning**: This destroys all data on the drives.

```bash
# Create new RAID5 array
mdadm --create /dev/md0 --level=5 --raid-devices=4 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1

# Monitor initial sync (can take hours)
watch cat /proc/mdstat

# Create filesystem
mkfs.ext4 /dev/md0
```

## Persistent Configuration

Save the array configuration so it auto-assembles on boot:

```bash
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u
```

## Mounting the Array

```bash
# Create mount point
mkdir -p /data

# Mount
mount /dev/md0 /data

# Add to fstab (use blkid to get UUID)
blkid /dev/md0
echo 'UUID=63e2b5f9-7259-4333-83d3-4fd06a278773 /data ext4 defaults 0 2' >> /etc/fstab

# Reload systemd and verify
systemctl daemon-reload
findmnt --verify
```

## Monitoring

### Check Array Status

```bash
# Quick status
cat /proc/mdstat

# Detailed status
mdadm --detail /dev/md0
```

### Periodic RAID Scrub

A monthly scrub is configured by default via `/etc/cron.d/mdadm`. It runs on the first Sunday of each month and verifies all data against parity.

To run a manual scrub:

```bash
echo check > /sys/block/md0/md/sync_action
cat /proc/mdstat  # watch progress
```

Check for mismatches after scrub completes:

```bash
cat /sys/block/md0/md/mismatch_cnt
```

A count of `0` means all data matches parity.

### SMART Drive Monitoring

smartd monitors drive health every 30 minutes and alerts on failures.

```bash
apt install smartmontools
systemctl enable smartd
systemctl start smartd
```

Configure email alerts in `/etc/smartd.conf`:

```
DEVICESCAN -d removable -n standby -m your-email@example.com -M exec /usr/share/smartmontools/smartd-runner
```

To send a test email, temporarily add `-M test`:

```
DEVICESCAN -d removable -n standby -m your-email@example.com -M test -M exec /usr/share/smartmontools/smartd-runner
```

Then restart: `systemctl restart smartd`. Remove `-M test` after confirming.

### RAID Degradation Alerts

Configure mdadm to email on array issues. Edit `/etc/mdadm/mdadm.conf`:

```
MAILADDR your-email@example.com
```

Restart the monitor:

```bash
systemctl restart mdmonitor
```

Test with:

```bash
mdadm --monitor --scan --test --oneshot
```

## Email Relay Setup (Gmail)

Proxmox may not be able to send emails directly to external addresses. Configure Postfix to relay through Gmail.

### Prerequisites

- Gmail account with 2FA enabled
- App password generated at https://myaccount.google.com/apppasswords

### Configure Postfix

```bash
apt install libsasl2-modules
```

Edit `/etc/postfix/main.cf` and add:

```
relayhost = [smtp.gmail.com]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
```

Create credentials file:

```bash
echo "[smtp.gmail.com]:587 your-email@gmail.com:your-app-password" > /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
systemctl restart postfix
```

### Test Email

```bash
echo "Test email from Proxmox" | mail -s "Test" your-email@gmail.com
```

Check mail log for issues:

```bash
tail -20 /var/log/mail.log
```

## Monitoring Summary

| Check | Frequency | Alert Method |
|-------|-----------|--------------|
| SMART health | Every 30 min | Email |
| RAID scrub | Monthly (1st Sunday) | Email if issues |
| RAID status | Continuous (mdmonitor) | Email on degradation |

## Troubleshooting

### Array not auto-assembling on boot

Ensure configuration is saved:

```bash
mdadm --detail --scan
# Compare output with /etc/mdadm/mdadm.conf
cat /etc/mdadm/mdadm.conf
```

Regenerate initramfs:

```bash
update-initramfs -u
```

### Checking individual drive health

```bash
smartctl -a /dev/sda
smartctl -a /dev/sdb
smartctl -a /dev/sdc
smartctl -a /dev/sdd
```

Install smartmontools if needed: `apt install smartmontools`
