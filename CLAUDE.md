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
| Recipes Server | 2 | 6 GB | High | Running (VM 101, 192.168.10.20, API deployed) |
| Pi-hole | 1 | 2 GB | High | Running (CT 100) |
| Network Storage | 2 | 6 GB | High | Planned |
| Network Monitor | 1 | 4 GB | Medium | Planned |
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
- `docs/vlan-network-setup.md` - VLAN configuration for DMZ isolation
- `docs/webserver-vm-setup.md` - Recipes server VM setup guide
- `certs/README.md` - CA infrastructure status and usage

## Implementation Phases

1. **Foundation**: Proxmox install, RAID5 config, networking
2. **Core Services**: Pi-hole, Network Storage, data migration
3. **Applications**: Recipes Server VM (documented), SSL/TLS setup
4. **Monitoring**: Network monitoring and parental controls
5. **Optional**: Ubuntu Dev VM if needed

## TODO

- [ ] Set up Omada Controller (LXC or VM) to manage TP-Link EAP access points and enable custom SSL certificates (cert already generated for wap1)
