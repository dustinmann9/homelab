# VLAN Network Setup for DMZ Isolation

This guide covers configuring VLAN 20 as a DMZ network to isolate internet-facing services from the internal LAN.

## Overview

### Why Use VLANs for DMZ?

A DMZ (Demilitarized Zone) isolates internet-facing services from your internal network:

- **Security**: If the web server is compromised, attackers cannot directly access LAN devices
- **Traffic Control**: Firewall rules control what traffic can flow between VLANs
- **Compliance**: Proper network segmentation is a security best practice

### Network Architecture

```
Internet
    │
    ▼
┌─────────────────┐
│     Router      │
│  192.168.1.1    │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Managed Switch  │ (802.1Q VLAN tagging)
└─────────────────┘
    │         │
    ▼         ▼
┌────────┐  ┌────────┐
│ VLAN 10│  │ VLAN 20│
│  LAN   │  │  DMZ   │
│.10.0/24│  │.20.0/24│
└────────┘  └────────┘
    │           │
    ▼           ▼
 Pi-hole     Recipes
 Desktop     (nginx)
 etc.
```

### IP Addressing

| VLAN | Name | Subnet | Gateway | Purpose |
|------|------|--------|---------|---------|
| 10 | LAN | 192.168.10.0/24 | 192.168.10.1 | Internal devices |
| 20 | DMZ | 192.168.20.0/24 | 192.168.20.1 | Internet-facing servers |

## Prerequisites

- Proxmox VE installed and running
- Managed switch with 802.1Q VLAN support (or router with VLAN capability)
- Access to router/firewall configuration

## Check VLAN Support

### Managed Switch

Most managed switches support 802.1Q VLANs. Check your switch documentation or web interface for:
- VLAN configuration menu
- 802.1Q or "dot1q" tagging options
- Trunk port configuration

### Unmanaged Switch

If using an unmanaged switch, VLANs are **not supported**. Options:
1. Upgrade to a managed switch
2. Use firewall-only isolation (see Fallback section below)

### Router

Your router must support:
- VLAN interfaces (for inter-VLAN routing)
- Firewall rules between VLANs

Common routers with VLAN support:
- pfSense / OPNsense
- Ubiquiti EdgeRouter / UniFi
- MikroTik
- OpenWrt
- Most enterprise routers

## Proxmox VLAN Bridge Configuration

### Option A: VLAN-Aware Bridge (Recommended)

This allows a single bridge to handle multiple VLANs.

1. **Edit network configuration** via Proxmox web UI or directly:

```bash
# SSH to Proxmox host
nano /etc/network/interfaces
```

2. **Configure vmbr0 as VLAN-aware**:

```
auto lo
iface lo inet loopback

auto enp3s0
iface enp3s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.10.2/24
    gateway 192.168.10.1
    bridge-ports enp3s0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 10 20
```

3. **Apply changes**:

```bash
# Test configuration first
ifreload -a

# Or reboot if major changes
reboot
```

### Option B: Separate Bridge per VLAN

If you prefer dedicated bridges:

```
auto vmbr0
iface vmbr0 inet static
    address 192.168.10.2/24
    gateway 192.168.10.1
    bridge-ports enp3s0
    bridge-stp off
    bridge-fd 0

auto vmbr1
iface vmbr1 inet manual
    bridge-ports enp3s0.20
    bridge-stp off
    bridge-fd 0
```

### VM Network Configuration

When creating the web server VM:

**For VLAN-aware bridge (Option A)**:
- Bridge: `vmbr0`
- VLAN Tag: `20`

**For separate bridge (Option B)**:
- Bridge: `vmbr1`
- VLAN Tag: (none - already tagged)

## Router/Switch VLAN Configuration

### Switch Configuration

Configure the switch port connected to Proxmox as a **trunk port** carrying VLANs 10 and 20:

**Generic example** (varies by switch vendor):

```
# Access the switch CLI or web UI

# Create VLANs
vlan 10
  name LAN
vlan 20
  name DMZ

# Configure trunk port to Proxmox (e.g., port 1)
interface port 1
  switchport mode trunk
  switchport trunk allowed vlan 10,20

# Configure access ports for LAN devices
interface port 2-8
  switchport mode access
  switchport access vlan 10
```

### Router VLAN Interfaces

Create VLAN interfaces on your router. Example for pfSense/OPNsense:

1. Navigate to **Interfaces → Assignments → VLANs**
2. Create VLAN 20 on the LAN interface
3. Assign the VLAN as a new interface (e.g., `OPT1`)
4. Configure the interface:
   - Enable: Yes
   - Description: DMZ
   - IPv4: Static
   - Address: 192.168.20.1/24

### DHCP for DMZ (Optional)

If you want DHCP in the DMZ:

1. Navigate to **Services → DHCP Server → DMZ**
2. Enable DHCP
3. Range: 192.168.20.100 - 192.168.20.199
4. DNS: Point to Pi-hole if accessible, or use public DNS

For servers, use static IPs outside the DHCP range.

## Inter-VLAN Firewall Rules

The key security configuration - control traffic between VLANs.

### Firewall Rule Summary

| Source | Destination | Ports | Action | Purpose |
|--------|-------------|-------|--------|---------|
| LAN (10) | DMZ (20) | Any | Allow | Admin access to DMZ |
| DMZ (20) | LAN (10) | Any | **Block** | Protect LAN from DMZ |
| DMZ (20) | Internet | 80, 443 | Allow | Web server updates |
| Internet | DMZ (20) | 80, 443 | Allow | Incoming web traffic |

### pfSense/OPNsense Example

**DMZ Interface Rules** (applied to traffic FROM DMZ):

1. **Block DMZ to LAN**:
   - Action: Block
   - Interface: DMZ
   - Source: DMZ net
   - Destination: LAN net
   - Description: Block DMZ to LAN

2. **Allow DMZ to Internet**:
   - Action: Pass
   - Interface: DMZ
   - Source: DMZ net
   - Destination: any
   - Description: Allow DMZ outbound

**LAN Interface Rules**:

1. **Allow LAN to DMZ** (usually default allow handles this):
   - Action: Pass
   - Interface: LAN
   - Source: LAN net
   - Destination: DMZ net
   - Description: Allow LAN to DMZ

### Important Notes

- Rules are processed **top to bottom** - order matters
- Place block rules BEFORE allow rules
- Enable logging on block rules for troubleshooting

## Port Forwarding for Web Traffic

Forward incoming web traffic from WAN to the web server.

### NAT/Port Forward Rules

| WAN Port | Destination IP | Destination Port | Protocol |
|----------|----------------|------------------|----------|
| 80 | 192.168.20.10 (recipes) | 80 | TCP |
| 443 | 192.168.20.10 (recipes) | 443 | TCP |

### pfSense/OPNsense Example

1. Navigate to **Firewall → NAT → Port Forward**
2. Add rule for HTTP:
   - Interface: WAN
   - Protocol: TCP
   - Destination port: 80
   - Redirect target IP: 192.168.20.10
   - Redirect target port: 80
3. Add rule for HTTPS:
   - Interface: WAN
   - Protocol: TCP
   - Destination port: 443
   - Redirect target IP: 192.168.20.10
   - Redirect target port: 443

## Verification

### Test VLAN Connectivity

From Proxmox host:
```bash
# Ping the DMZ gateway
ping 192.168.20.1

# Check VLAN interface (if using vmbr0.20)
ip addr show vmbr0.20
```

### Test from Web Server VM

```bash
# Should work - internet access
ping 8.8.8.8

# Should work - DNS (if allowed)
ping google.com

# Should FAIL - LAN access blocked
ping 192.168.10.100
```

### Test from LAN Device

```bash
# Should work - LAN can access DMZ
ping 192.168.20.10
ssh dustin@192.168.20.10
```

### Check Firewall Logs

On your router, check firewall logs for blocked traffic. This helps verify rules are working and troubleshoot connectivity issues.

## Fallback: Firewall-Only Isolation

If VLAN support is unavailable, you can achieve basic isolation using host-based firewalls:

### Architecture Without VLANs

```
┌─────────────────────────────────────────┐
│           192.168.10.0/24               │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  │
│  │ Pi-hole │  │ Desktop │  │Webserver│  │
│  │   .100  │  │   .50   │  │   .20   │  │
│  └─────────┘  └─────────┘  └─────────┘  │
│                               │         │
│              UFW blocks LAN ──┘         │
└─────────────────────────────────────────┘
```

### Web Server UFW Rules (Firewall-Only)

```bash
# Default deny
ufw default deny incoming
ufw default allow outgoing

# Allow SSH only from specific admin IPs
ufw allow from 192.168.10.50 to any port 22  # Your desktop

# Allow web traffic from anywhere
ufw allow 80/tcp
ufw allow 443/tcp

# Block all other LAN traffic
ufw deny from 192.168.10.0/24
```

### Limitations of Firewall-Only Approach

- Relies on web server not being fully compromised
- No protection if attacker gets root access
- No switch-level isolation
- Harder to audit and manage

**Recommendation**: Use VLANs if your hardware supports it.

## Troubleshooting

### VM Cannot Reach Gateway

1. Check VLAN tag is set correctly on VM
2. Verify switch trunk port configuration
3. Check router has VLAN interface configured
4. Verify Proxmox bridge is VLAN-aware

### Cannot SSH to VM from LAN

1. Check inter-VLAN routing is enabled on router
2. Verify firewall allows LAN → DMZ traffic
3. Check VM's UFW allows SSH from LAN

### Web Traffic Not Reaching VM

1. Verify port forwarding rules on router
2. Check WAN firewall allows ports 80/443
3. Verify nginx is running on VM
4. Check VM's UFW allows web traffic

### VLAN Traffic Not Passing

```bash
# On Proxmox, check bridge VLAN configuration
bridge vlan show

# Check if traffic is tagged correctly
tcpdump -i enp3s0 -e vlan
```

## Next Steps

Once VLAN network is configured:
1. Proceed with [Recipes Server VM Setup](webserver-vm-setup.md)
2. Configure Pi-hole DNS for recipes.home
3. Test internal and external access
