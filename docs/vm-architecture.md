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

### 5. Network Sensor (NSM)

**Purpose**: Passive IDS/protocol analysis — detects suspicious and inappropriate
traffic via SPAN port mirroring from the TL-SG108PE switch.

**Specifications:**
- **VM ID**: 102
- **IP**: 192.168.10.30
- **OS**: Debian 13 (Trixie)
- **vCPU**: 2 cores
- **RAM**: 4 GB
- **Storage**: 60 GB SSD
- **Network**: eth0 (management, 192.168.10.30) + eth1 (monitor, no IP, promiscuous)
- **Priority**: Medium

**Software Stack:**
- **Suricata** — signature-based IDS with Emerging Threats Open rules
- **Zeek** — protocol analyzer, generates structured conn/dns/http/ssl/tls logs
- **Filebeat** — ships EVE JSON and Zeek logs to Elastic Stack VM

**Notes:**
- Entirely passive — cannot affect network connectivity
- SPAN source: switch port 1 (router uplink); SPAN destination: port 8
- See `docs/network-sensor-setup.md` for full setup guide
- See `docs/nsm-architecture.md` for system design

### 6. Elastic Stack (NSM)

**Purpose**: Log storage, indexing, dashboards, and alerting for the NSM pipeline.

**Specifications:**
- **VM ID**: 103
- **IP**: 192.168.10.31
- **OS**: Debian 13 (Trixie)
- **vCPU**: 2 cores
- **RAM**: 10 GB
- **Storage**: 100 GB SSD (log retention)
- **Network**: eth0 only (management)
- **Priority**: Medium

**Software Stack:**
- **Elasticsearch** — indexes all Suricata and Zeek logs (JVM heap: 4 GB)
- **Kibana** — dashboards, Discover search, alerting rules

**Notes:**
- Elasticsearch 8.x with TLS and authentication enabled by default
- ILM policy: roll at 10 GB or 7 days, delete after 30 days
- Pre-built Suricata and Zeek dashboards loaded via Filebeat setup
- See `docs/elastic-stack-setup.md` for full setup guide

## Resource Allocation Summary

| VM | ID | IP | vCPU | RAM | Storage (SSD) | Storage (HDD) | Status |
|----|----|----|------|-----|---------------|---------------|--------|
| Proxmox Host | — | 192.168.10.2 | 1 | 4 GB | 30 GB | — | Running |
| Pi-hole | CT 100 | 192.168.10.8 | 1 | 2 GB | 20 GB | — | Running |
| Recipes Server | VM 101 | 192.168.10.20 | 2 | 3 GB | 50 GB | — | Running |
| Network Sensor | VM 102 | 192.168.10.30 | 2 | 4 GB | 60 GB | — | Planned |
| Elastic Stack | VM 103 | 192.168.10.31 | 2 | 10 GB | 100 GB | — | Planned |
| Network Storage | VM 104 | 192.168.10.40 | 2 | 2 GB | 30 GB | 3 TB | Planned |
| Ubuntu Dev (Optional) | VM 105 | TBD | 2 | 4 GB | 50 GB | — | Deferred |
| **Total (excl. Dev)** | | | **10** | **25 GB** | **290 GB** | **3 TB** | |

**Notes on Allocation:**
- Total RAM with all planned VMs (excl. Dev): 25 GB against 32 GB physical — 7 GB comfortable headroom
- Recipes Server reduced from 6 GB to 3 GB; JVM heap explicitly capped at 512m via service flags
- Network Storage reduced from 4 GB to 2 GB; basic Samba/NFS doesn't require more
- Ubuntu Dev VM deferred — could be added later using the freed headroom
- vCPU oversubscription (10 vCPUs on 4 cores) is normal and acceptable for this workload mix

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
