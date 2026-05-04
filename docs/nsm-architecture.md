# Network Security Monitoring (NSM) Architecture

## Overview

Two-VM architecture separating the detection layer (sensor) from the storage and
visualization layer (Elastic Stack). This mirrors production NSM deployments and
provides a hands-on learning environment for the Elastic Stack.

**Use case**: Detect inappropriate or suspicious traffic on the home network,
with initial focus on monitoring a specific device (daughter's gaming laptop).

---

## Architecture Diagram

```
                        HOME NETWORK (192.168.10.0/24)
┌─────────────────────────────────────────────────────────────────┐
│                                                                   │
│  [DSR-250 Router] ──── [TL-SG108PE Switch]                       │
│         │                      │                                  │
│         │              ┌───────┴────────┐                        │
│         │         Port 1-7          Port 8 (SPAN destination)    │
│         │           (normal)              │                       │
│         │                                 │                       │
│   [Internet]    [Gaming Laptop]    [Network Sensor VM]           │
│                 192.168.10.xx      eth0: 192.168.10.30 (mgmt)    │
│                                    eth1: no IP (monitor)          │
│                                          │                        │
│                                          │ EVE JSON / Zeek logs   │
│                                          ▼ (via Filebeat)         │
│                                   [Elastic Stack VM]              │
│                                   192.168.10.31                   │
│                                   Elasticsearch + Kibana          │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Traffic Capture Method: SPAN Port

The TL-SG108PE managed switch supports **port mirroring** (SPAN):

- **Mirror source**: Port 1 (router uplink) — captures all traffic in/out of the network
- **Mirror destination**: Port 8 (connects to sensor VM's monitor NIC)
- The sensor NIC operates in **promiscuous mode** with no IP address — it
  silently receives a copy of all traffic without participating in the network

> The sensor is entirely passive. It cannot inject traffic or affect connectivity.
> If the sensor VM goes down, the network continues working normally.

---

## VM Topology

| VM | ID | IP | vCPU | RAM | Storage | OS |
|----|----|----|------|-----|---------|-----|
| Network Sensor | 102 | 192.168.10.30 | 2 | 4 GB | 60 GB SSD | Debian 13 (Trixie) |
| Elastic Stack | 103 | 192.168.10.31 | 2 | 10 GB | 100 GB SSD | Debian 13 (Trixie) |

### Network Sensor NICs
| Interface | Purpose | IP | Notes |
|-----------|---------|-----|-------|
| eth0 | Management | 192.168.10.30/24 | SSH, Filebeat outbound |
| eth1 | Monitor | none | Promiscuous mode, SPAN destination |

---

## Component Roles

### Network Sensor VM (102)

| Component | Role |
|-----------|------|
| **Suricata** | Signature-based IDS — matches traffic against rule sets, generates alerts for known-bad patterns (malware C2, adult content categories, P2P, etc.) |
| **Zeek** | Protocol analyzer — generates structured logs for every connection, DNS query, HTTP request, TLS handshake, and file transfer. No signatures; behavioral visibility |
| **Filebeat** | Log shipper — tails Suricata EVE JSON and Zeek logs, enriches with metadata, forwards to Elasticsearch over the management interface |

### Elastic Stack VM (103)

| Component | Role |
|-----------|------|
| **Elasticsearch** | Distributed search/analytics engine — indexes and stores all logs. Handles queries from Kibana |
| **Kibana** | Web UI — dashboards, search (Discover), alerting (Watcher/Rules), and data exploration |
| **Logstash** | Optional ingest pipeline — useful for parsing/transforming logs. For this setup, Filebeat modules handle parsing directly, so Logstash is not required initially |

---

## Data Flow

```
eth1 (promiscuous) ──► Suricata ──► /var/log/suricata/eve.json ──┐
                   └──► Zeek    ──► /var/log/zeek/current/*.log ──┤
                                                                   │
                                                         Filebeat (reads logs)
                                                                   │
                                                                   ▼
                                                      Elasticsearch (indexes)
                                                                   │
                                                                   ▼
                                                      Kibana (dashboards/alerts)
```

### Log Types Generated

**Suricata (eve.json — single structured JSON stream):**
- `alert` — rule matches (the primary signal)
- `dns` — all DNS queries/responses
- `http` — HTTP requests and responses
- `tls` — TLS handshake metadata (SNI, cert info)
- `flow` — connection summaries (src/dst IP, port, bytes, duration)
- `fileinfo` — file transfers detected

**Zeek (separate log files per protocol):**
- `conn.log` — every TCP/UDP/ICMP connection
- `dns.log` — DNS queries and answers
- `http.log` — HTTP with full URI, user-agent, response codes
- `ssl.log` — TLS connections with SNI (server name) and cert details
- `weird.log` — protocol anomalies and unusual behavior
- `notice.log` — Zeek's own detection notices

---

## Rule Sets

### Suricata — Emerging Threats Open (ET Open)
- Free, no registration required
- Updated daily
- Covers: malware, exploit kits, P2P, adult content categories, cryptocurrency mining,
  VPN/proxy detection, known-bad IPs
- Managed via `suricata-update` (built into Suricata)

### Custom Rules for Parental Controls
Location: `/etc/suricata/rules/local.rules`

Examples:
```
# Alert on DNS queries for specific domains
alert dns any any -> any any (msg:"DNS query for tiktok.com"; dns.query; content:"tiktok.com"; nocase; sid:9000001; rev:1;)

# Alert on HTTP to known gaming distraction sites during school hours (requires time-based rules)
alert http any any -> any 80 (msg:"HTTP to steam community"; http.host; content:"steamcommunity.com"; sid:9000002; rev:1;)
```

---

## RAM Allocation Impact

With these two VMs added, the full homelab RAM picture is:

| VM | RAM |
|----|-----|
| Proxmox host | 4 GB |
| Pi-hole (CT 100) | 2 GB |
| Recipes Server (VM 101) | 3 GB |
| Network Sensor (VM 102) | 4 GB |
| Elastic Stack (VM 103) | 10 GB |
| Network Storage (planned) | 2 GB |
| **Total** | **25 GB** |

This fits within 32 GB. Ubuntu Dev VM is deferred — there is no headroom.

### Elasticsearch JVM Heap

Set explicitly to **4 GB** in `/etc/elasticsearch/jvm.options.d/heap.options`:
```
-Xms4g
-Xmx4g
```

This leaves ~6 GB for the OS, Kibana (~1 GB), and filesystem cache (Elasticsearch
benefits significantly from OS-level page cache).

---

## Related Documentation

- `docs/network-sensor-setup.md` — Suricata, Zeek, and Filebeat installation
- `docs/elastic-stack-setup.md` — Elasticsearch and Kibana installation
- `docs/vlan-network-setup.md` — Future VLAN 20 isolation for the gaming laptop
- Switch SPAN port configuration: TL-SG108PE web UI → Monitoring → Port Mirroring
