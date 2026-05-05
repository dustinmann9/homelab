# Claude Code Context - Homelab Project

## Project Overview

This is a Proxmox-based homelab server documentation and configuration repository. The goal is reproducible, well-documented infrastructure that can be rebuilt from scratch.

## Hardware

- **CPU**: Intel Core i7 (Ivy Bridge), 4 cores
- **RAM**: 32 GB
- **Storage**: 250 GB SSD (system) + 4x1TB HDDs in RAID5 (~3TB usable)
- **Platform**: Proxmox VE

## Planned VMs

| VM | vCPU | RAM | Priority | Status |
|----|------|-----|----------|--------|
| Recipes Server | 2 | 3 GB | High | Running (VM 101, 192.168.10.20, API deployed) |
| Pi-hole | 1 | 2 GB | High | Running (CT 100, 192.168.10.8) |
| Network Storage | 2 | 6 GB | High | Planned |
| Network Sensor | 2 | 4 GB | Medium | Planned (VM 102, 192.168.10.30) |
| Elastic Stack | 2 | 10 GB | Medium | Planned (VM 103, 192.168.10.31) |
| Ubuntu Dev | 2 | 4 GB | Low | Optional |

## Certificate Authority Infrastructure

Three-tier PKI hierarchy is already created:

```
Mannsclann Homelab Root CA (2025-2045, 20 years)
  └── Mannsclann Homelab Intermediate CA (2025-2035, 10 years)
      └── Service Certificates (issued as needed)
```

### Issuing Server Certificates

```bash
./scripts/generate-server-cert.sh <service-name> <fqdn> [ip-address]
# Example:
./scripts/generate-server-cert.sh proxmox pve.home 192.168.10.2
```

### Domain Naming Convention

Services use `*.home` format (not `.local` which conflicts with macOS mDNS):
- `pve.home`
- `pihole.home`
- `storage.home`
- `recipes.home`
- `monitor.home`

## Directory Structure

```
homelab/
├── certs/              # CA infrastructure and certificates
│   ├── root-ca/        # Root CA (private key should be offline)
│   ├── intermediate-ca/# Intermediate CA for signing
│   └── services/       # Service certificates
├── docs/               # Documentation
├── specs/              # VM specifications
└── scripts/            # Automation scripts
```

## Security Notes

- Private keys (`*.key`) are NOT committed to git (see `.gitignore`)
- Root CA private key should be stored offline after setup
- CA private keys are currently unencrypted - consider passphrase protection
- File permissions on private keys should be 400

## Key Files

- `docs/proxmox-installation.md` - Proxmox installation and hardening guide
- `docs/proxmox-usb-installer.md` - Creating bootable USB on macOS
- `docs/pihole-lxc-setup.md` - Pi-hole LXC container setup
- `docs/ssl-certificate-management.md` - Complete SSL/TLS strategy
- `docs/vm-architecture.md` - VM resource allocation and planning
- `docs/hardware-specs.md` - Server hardware details
- `docs/raid-storage-setup.md` - RAID5 array setup and management
- `docs/vlan-network-setup.md` - VLAN configuration for DMZ isolation
- `docs/webserver-vm-setup.md` - Recipes server VM setup guide
- `docs/nsm-architecture.md` - NSM two-VM architecture overview (Sensor + Elastic Stack)
- `docs/network-sensor-setup.md` - Suricata, Zeek, and Filebeat setup (VM 102)
- `docs/elastic-stack-setup.md` - Elasticsearch and Kibana setup (VM 103)
- `certs/README.md` - CA infrastructure status and usage

## Implementation Phases

1. **Foundation**: Proxmox install, RAID5 config, networking
2. **Core Services**: Pi-hole, Network Storage, data migration
3. **Applications**: Recipes Server VM (documented), SSL/TLS setup
4. **Monitoring**: Network monitoring and parental controls
5. **Optional**: Ubuntu Dev VM if needed

## TODO

### Networking
- [ ] Terminate RJ45 connectors on spare cables between router closet and switch room
- [ ] Connect Proxmox eno1 (Atheros AR8151) to TL-SG108PE switch; disconnect from router
- [ ] Create vmbr1 on Proxmox bridged to eno1; move sensor VM net1 from vmbr0 to vmbr1
- [ ] Find TL-SG108PE switch IP address (not yet known; check router ARP table or device label)
- [ ] Configure SPAN port on TL-SG108PE: mirror router uplink port → Proxmox eno1 port
- [ ] Configure VLAN 20 for DMZ isolation - requires configuring trunk ports on TL-SG108PE and DSR-250 (see docs/vlan-network-setup.md)
- [ ] Design and document full VLAN layout (VLAN 10 trusted, 20 DMZ, 30 IoT/cameras, 40 kids/guest) and SPAN architecture — create docs/network-design.md
- [ ] Set up Omada Controller (LXC or VM) to manage TP-Link EAP access points and enable custom SSL certificates (cert already generated for wap1)
- [ ] Long-term: move modem/router to switch room (coax already run); this simplifies all network topology

### DNS
- [x] Configure VMs to use Pi-hole (192.168.10.8) for DNS to resolve *.home local records — update /etc/resolv.conf on VM 101, 102, 103
- [ ] NOTE: Do NOT configure router to use Pi-hole as upstream DNS — reliability requirement, wife must be able to restore network without homelab access

### VM Maintenance
- [x] Enable unattended-upgrades on VM 101 (recipes), VM 102 (sensor), and VM 103 (elastic) — security patches only; exclude elasticsearch/kibana packages on VM 103
- [x] Disable swap on all VMs: `sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab` — applies to VM 101 (Recipes), VM 103 (Elastic), VM 102 (Sensor)
- [x] Configure SSH key auth on VM 103 (elastic) — copy Mac public key to ~/.ssh/authorized_keys

### Notifications
- [x] Fix mdadm monitor on PVE — service masked by design on Proxmox; monitor was already running (PID via boot). Fixed duplicate relayhost entry in postfix main.cf that could have silently dropped emails.
- [x] Configure postfix relay on VM 101, 102, 103 — match PVE host config (already working on PVE)
- [ ] Enable fail2ban on PVE and all VMs — email on SSH brute force and Proxmox web UI failures
- [ ] Enable smartd on PVE — email on SMART pre-failure attributes before drives fail
- [ ] Add disk space cron on all VMs + PVE — alert at 85% full (especially important for VM 103)
- [ ] Add VM health check cron on PVE — email if CT 100, VM 101/102/103 unexpectedly stop
- [ ] Suricata alert emails on VM 102 — simple daily cron now; migrate to Kibana alerting once VM 103 is up
- [x] Configure unattended-upgrades Mail setting on all VMs — see docs/email-relay.md
- [ ] See docs/email-relay.md for full setup guide and priority order

### NSM Pipeline
- [ ] Set up Elastic Stack VM (VM 103, 192.168.10.31): Elasticsearch + Kibana — see docs/elastic-stack-setup.md
- [ ] Configure SSL for Kibana (VM 103) using homelab CA: `./scripts/generate-server-cert.sh elastic elastic.home 192.168.10.31`

### Documentation
- [ ] Write docs/nsm-design-rationale.md — explain NSM tooling choices (Suricata vs Snort, Zeek, ELK stack), trade-offs considered, and why this architecture was chosen
- [ ] Create docs/network-design.md — full network layout diagram with SPAN and VLAN configurations

### Storage
- [ ] Set up NFS share on /data/shared for VMs/containers
- [ ] Configure /data/backups as Proxmox Directory storage for VM backups

### Other
- [x] Generate data analysis report for migrated files on /data - identify duplicates, large files, old files for potential cleanup
- [ ] Sync Obsidian notes with AI and GitHub
- [ ] Self-hosted password manager — consider Vaultwarden (lightweight Bitwarden-compatible server, LXC container)
