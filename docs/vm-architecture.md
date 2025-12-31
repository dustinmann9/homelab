# VM Architecture and Planning

## Resource Allocation Overview

With 4 cores and 32 GB RAM available, resources need to be carefully allocated across VMs and the Proxmox host.

### Total Resources
- **CPU**: 4 cores (8 threads if HyperThreading enabled)
- **RAM**: 32 GB total
- **Storage**: 250 GB SSD (system), 3 TB RAID5 (data)

### Reserved for Proxmox Host
- **CPU**: ~0.5-1 core worth of capacity
- **RAM**: ~4-6 GB recommended minimum
- **Storage**: ~20-30 GB for Proxmox OS

### Available for VMs
- **CPU**: ~3 cores worth of vCPUs (can oversubscribe)
- **RAM**: ~26-28 GB distributable
- **Storage**: ~220 GB SSD + 3 TB RAID5

## Planned Virtual Machines

### 1. Web Server VM

**Purpose**: Host personal web applications and websites

**Specifications (Initial):**
- **OS**: TBD (likely Ubuntu Server or Debian)
- **vCPU**: 2 cores
- **RAM**: 4-6 GB
- **Storage**: 40-60 GB (SSD)
- **Network**: Bridged to main network
- **Priority**: High

**Software Stack:**
- Web server (Apache/Nginx)
- Database (MySQL/PostgreSQL)
- Runtime environments (Node.js, Python, etc.)

**Notes:**
- May need public-facing configuration
- Consider reverse proxy setup
- SSL/TLS certificate management

### 2. Ubuntu Development VM (Optional)

**Purpose**: Ad-hoc development and testing

**Specifications (Initial):**
- **OS**: Ubuntu Desktop or Server
- **vCPU**: 2 cores
- **RAM**: 4-6 GB
- **Storage**: 40-60 GB (SSD)
- **Network**: Bridged to main network
- **Priority**: Medium-Low

**Notes:**
- User notes this may be scratched due to having MacOS primary machine
- Decision pending on whether to implement
- Could be replaced with Docker containers on another VM if needed

### 3. Pi-hole

**Purpose**: Network-wide ad blocking and DNS management

**Specifications (Initial):**
- **OS**: Debian-based (Pi-hole recommended OS) or container
- **vCPU**: 1 core
- **RAM**: 1-2 GB
- **Storage**: 10-20 GB (SSD)
- **Network**: Bridged, static IP required
- **Priority**: High

**Configuration:**
- Primary DNS for entire network
- DHCP server (optional, or use existing router DHCP)
- Web interface for management
- Regular blocklist updates

**Notes:**
- Critical service - needs reliability
- Should have static IP
- Consider as LXC container instead of full VM for efficiency

### 4. Network Storage

**Purpose**: Centralized file storage and backup

**Specifications (Initial):**
- **OS**: TBD (consider OpenMediaVault, TrueNAS Core, or plain Linux with Samba)
- **vCPU**: 2 cores
- **RAM**: 4-8 GB (ZFS would need more)
- **Storage**: 20-30 GB (SSD) + RAID5 array passthrough or mount
- **Network**: Bridged, static IP, possibly 10GbE if available
- **Priority**: High

**Services:**
- SMB/CIFS (Windows/Mac file sharing)
- NFS (Linux file sharing)
- Maybe: FTP/SFTP
- Backup target for other VMs

**Notes:**
- Need to determine best way to present RAID5 array to this VM
- Consider direct disk passthrough vs. shared mount
- Backup strategy for RAID data

### 5. Network Monitoring / Parental Controls

**Purpose**: Monitor network traffic for inappropriate internet usage

**Specifications (Initial):**
- **OS**: Linux-based
- **vCPU**: 1-2 cores
- **RAM**: 2-4 GB
- **Storage**: 30-50 GB (SSD, for traffic logs)
- **Network**: May need promiscuous mode or port mirroring
- **Priority**: Medium

**Potential Solutions:**
- **ntopng**: Network traffic analysis
- **Suricata**: Intrusion detection/prevention
- **pfSense/OPNsense**: Full-featured firewall (if doing router duties)
- **OpenDNS/Cloudflare Gateway**: Cloud-based filtering (simpler)

**Notes:**
- Requirements depend on chosen solution
- May need router configuration for traffic mirroring
- Privacy considerations for monitoring
- Age-appropriate content filtering
- Reporting and alerting capabilities

## Resource Allocation Summary

| VM | vCPU | RAM | Storage (SSD) | Storage (HDD) | Priority |
|----|------|-----|---------------|---------------|----------|
| Proxmox Host | 1 | 4 GB | 30 GB | - | Critical |
| Web Server | 2 | 6 GB | 50 GB | - | High |
| Ubuntu Dev (Optional) | 2 | 4 GB | 50 GB | - | Low |
| Pi-hole | 1 | 2 GB | 20 GB | - | High |
| Network Storage | 2 | 6 GB | 30 GB | 3 TB | High |
| Network Monitor | 1 | 4 GB | 40 GB | - | Medium |
| **Total** | **9** | **26 GB** | **220 GB** | **3 TB** | |

**Notes on Allocation:**
- vCPU count shows oversubscription (9 vCPUs on 4 cores) - this is normal and acceptable
- RAM allocation is within limits (26 GB allocated, 6 GB for host)
- Ubuntu Dev VM may not be implemented

## Implementation Phases

### Phase 1: Foundation
1. Install Proxmox VE
2. Configure RAID5 array
3. Set up networking and storage
4. Create first VM for testing

### Phase 2: Core Services
1. Deploy Pi-hole
2. Configure Network Storage
3. Migrate data from desktop RAID to server

### Phase 3: Applications
1. Deploy Web Server VM
2. Configure and test web applications
3. Set up SSL/TLS and domain configuration

### Phase 4: Monitoring
1. Deploy Network Monitoring solution
2. Configure traffic analysis
3. Set up parental controls and filtering
4. Test and validate monitoring

### Phase 5: Optional
1. Evaluate need for Ubuntu Dev VM
2. Deploy if needed
3. Configure development environment

## Network Architecture

TBD - Will document:
- IP addressing scheme
- VLAN configuration (if used)
- Firewall rules
- Port forwarding
- DNS configuration

## Backup Strategy

TBD - Need to plan:
- VM backup schedule (Proxmox backup)
- RAID5 data backup (external or cloud)
- Configuration backups
- Disaster recovery procedures

## Security Considerations

- Firewall configuration for each VM
- SSH key-based authentication
- Regular updates and patching
- Separate network segments (if needed)
- Intrusion detection
- Access control and user management
