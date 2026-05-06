# Network Sensor Setup — Suricata, Zeek, and Filebeat

## Overview

This guide sets up the passive network sensor (VM 102) that mirrors all home
network traffic, runs intrusion detection and protocol analysis, and ships
structured logs to the Elastic Stack VM.

See `docs/nsm-architecture.md` for the full system design.

---

## Prerequisites

- Elastic Stack VM (VM 103) is up and running first — Filebeat needs a destination
- TL-SG108PE SPAN port configured (see [Switch Configuration](#switch-span-port-configuration))
- VM 102 created in Proxmox with two NICs (see [Proxmox VM Setup](#proxmox-vm-setup))

---

## Switch SPAN Port Configuration

On the TL-SG108PE web interface (`http://<switch-ip>`):

1. Navigate to **Monitoring → Port Mirroring**
2. Set **Mirroring Port** (destination): Port 8
3. Set **Mirrored Port** (source): Port 1 (the port connected to the DSR-250 router)
4. Set **Mode**: Ingress/Egress (capture both directions)
5. Click **Apply**

Connect port 8 on the switch to the second NIC (eth1) on the sensor VM.

---

## Proxmox VM Setup

### Create VM 102

In Proxmox web UI or via CLI:

```bash
# Basic VM creation
qm create 102 \
  --name network-sensor \
  --memory 4096 \
  --cores 2 \
  --sockets 1 \
  --net0 virtio,bridge=vmbr0 \
  --net1 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:60 \
  --ide2 local:iso/ubuntu-22.04-server.iso,media=cdrom \
  --boot order=ide2 \
  --ostype l26
```

- **net0** (eth0): management NIC — bridged to vmbr0, will get 192.168.10.30
- **net1** (eth1): monitor NIC — bridged to vmbr0, receives SPAN traffic

### Ubuntu Installation

Install Ubuntu 22.04 LTS Server (minimal install). During setup:
- Set static IP on eth0: `192.168.10.30/24`, gateway `192.168.10.1`, DNS `192.168.10.8` (Pi-hole)
- Do NOT configure eth1 (leave unconfigured)
- Enable OpenSSH server
- No additional snaps needed

### Post-Install: Configure Monitor Interface

After first boot, configure eth1 for promiscuous mode with no IP:

```bash
# Edit netplan config
sudo nano /etc/netplan/00-installer-config.yaml
```

Add eth1 stanza:
```yaml
network:
  ethernets:
    eth0:
      addresses: [192.168.10.30/24]
      routes:
        - to: default
          via: 192.168.10.1
      nameservers:
        addresses: [192.168.10.8]
    eth1:
      dhcp4: false
      # No addresses — monitor interface only
  version: 2
```

```bash
sudo netplan apply

# Bring eth1 up in promiscuous mode
sudo ip link set eth1 promisc on
sudo ip link set eth1 up

# Make promiscuous mode persistent across reboots
sudo nano /etc/systemd/system/promisc-eth1.service
```

```ini
[Unit]
Description=Set eth1 promiscuous mode
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set eth1 promisc on
ExecStart=/sbin/ip link set eth1 up
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable promisc-eth1.service
```

### Base System Prep

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget gnupg2 software-properties-common apt-transport-https
```

---

## Suricata Installation

### Install

```bash
# Add Suricata OISF PPA (latest stable release)
sudo add-apt-repository ppa:oisf/suricata-stable -y
sudo apt update
sudo apt install -y suricata suricata-update
```

### Configure

```bash
sudo nano /etc/suricata/suricata.yaml
```

Key settings to change (search for each):

```yaml
# Set the home network — used for rule directionality
vars:
  address-groups:
    HOME_NET: "[192.168.10.0/24]"
    EXTERNAL_NET: "!$HOME_NET"

# Set the capture interface
af-packet:
  - interface: eth1       # monitor NIC
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

# EVE JSON output — this is what Filebeat reads
outputs:
  - eve-log:
      enabled: yes
      filename: /var/log/suricata/eve.json
      types:
        - alert:
            payload: yes
            payload-buffer-size: 4kb
            http-body: yes
            http-body-printable: yes
            tagged-packets: yes
            xff:
              enabled: no
        - http:
            extended: yes
        - dns:
            version: 2
        - tls:
            extended: yes
        - files:
            force-magic: yes
        - flow
```

Also disable the default `pcap` capture if present and ensure `af-packet` is
the active capture method.

### Update Rules

```bash
# Pull the free Emerging Threats Open ruleset
sudo suricata-update

# List available free rule sources
sudo suricata-update list-sources

# Enable additional recommended free sources
sudo suricata-update enable-source et/open
sudo suricata-update enable-source ptresearch/attackdetection

# Apply updates (re-run to refresh rules — do this daily via cron)
sudo suricata-update
```

### Local Rules for Parental Controls

```bash
sudo nano /etc/suricata/rules/local.rules
```

```
# Example: flag DNS queries to known gaming/distraction sites
alert dns any any -> any any (msg:"[PARENTAL] DNS query tiktok.com"; dns.query; content:"tiktok.com"; nocase; sid:9000001; rev:1;)
alert dns any any -> any any (msg:"[PARENTAL] DNS query reddit.com"; dns.query; content:"reddit.com"; nocase; sid:9000002; rev:1;)

# Flag VPN/proxy usage attempts (ET Open covers most, but add specifics)
alert dns any any -> any any (msg:"[PARENTAL] DNS query protonvpn.com"; dns.query; content:"protonvpn.com"; nocase; sid:9000010; rev:1;)
```

Register local rules in `suricata.yaml`:
```yaml
rule-files:
  - suricata.rules
  - local.rules
```

### Enable and Start

```bash
sudo systemctl enable suricata
sudo systemctl start suricata

# Verify it's running and listening on eth1
sudo suricata --list-runmodes
sudo tail -f /var/log/suricata/suricata.log
```

Test: `sudo tail -f /var/log/suricata/eve.json` — you should see flow and dns
events within seconds if SPAN traffic is arriving.

### Daily Rule Updates via Cron

```bash
sudo crontab -e
```

Add:
```
0 3 * * * /usr/bin/suricata-update && /bin/systemctl reload suricata
```

---

## Zeek Installation

### Install

```bash
# Add Zeek repository
echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_22.04/ /' \
  | sudo tee /etc/apt/sources.list.d/zeek.list

curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_22.04/Release.key \
  | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/zeek.gpg > /dev/null

sudo apt update
sudo apt install -y zeek
```

Zeek installs to `/opt/zeek/`. Add to PATH:

```bash
echo 'export PATH=/opt/zeek/bin:$PATH' | sudo tee /etc/profile.d/zeek.sh
source /etc/profile.d/zeek.sh
```

### Configure

**Node configuration** — tells Zeek which interface to monitor:

```bash
sudo nano /opt/zeek/etc/node.cfg
```

```ini
[zeek]
type=standalone
host=localhost
interface=eth1
```

**Network configuration** — tells Zeek what counts as local:

```bash
sudo nano /opt/zeek/etc/networks.cfg
```

```
192.168.10.0/24   Home Network
```

**Local scripts** — enable useful built-in detection packages:

```bash
sudo nano /opt/zeek/share/zeek/site/local.zeek
```

Ensure these are present (most are enabled by default):

```zeek
@load base/protocols/conn
@load base/protocols/dns
@load base/protocols/http
@load base/protocols/ssl
@load base/protocols/ftp
@load policy/misc/detect-traceroute
@load policy/protocols/ssl/validate-certs
@load policy/protocols/dns/detect-external-names
```

### Deploy and Start

```bash
# Deploy and start
sudo zeekctl deploy

# Check status
sudo zeekctl status

# Logs are written to:
ls /opt/zeek/logs/current/
# conn.log  dns.log  http.log  ssl.log  weird.log  notice.log  ...
```

### Auto-Restart via Cron

Zeek's `zeekctl` needs periodic rotation and crash recovery:

Create `/etc/cron.d/zeek`:
```
0 * * * * root /opt/zeek/bin/zeekctl cron > /dev/null
```

Stdout is suppressed to avoid hourly cron emails — stderr is kept so crashes still notify.

### Make Zeek Start on Boot

```bash
sudo nano /etc/systemd/system/zeek.service
```

```ini
[Unit]
Description=Zeek Network Security Monitor
After=network.target

[Service]
Type=forking
ExecStart=/opt/zeek/bin/zeekctl start
ExecStop=/opt/zeek/bin/zeekctl stop
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable zeek
```

---

## Filebeat Installation

Filebeat ships Suricata and Zeek logs to Elasticsearch. It has built-in modules
for both that handle log parsing automatically.

### Install

```bash
# Add Elastic repository (use same version as your Elasticsearch install)
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
sudo apt install -y filebeat
```

### Configure

```bash
sudo nano /etc/filebeat/filebeat.yml
```

Replace the `output.elasticsearch` section and add credentials:

```yaml
output.elasticsearch:
  hosts: ["https://192.168.10.31:9200"]
  username: "filebeat_writer"       # created on Elastic Stack VM
  password: "CHANGEME"
  ssl.certificate_authorities:
    - /etc/filebeat/certs/http_ca.crt   # copied from Elastic Stack VM

setup.kibana:
  host: "https://192.168.10.31:5601"
  username: "elastic"
  password: "CHANGEME"
  ssl.certificate_authorities:
    - /etc/filebeat/certs/http_ca.crt

# Disable default log input — modules handle inputs
filebeat.inputs: []
```

### Enable Modules

```bash
sudo filebeat modules enable suricata zeek
```

Configure the Suricata module:

```bash
sudo nano /etc/filebeat/modules.d/suricata.yml
```

```yaml
- module: suricata
  eve:
    enabled: true
    var.paths: ["/var/log/suricata/eve.json"]
```

Configure the Zeek module:

```bash
sudo nano /etc/filebeat/modules.d/zeek.yml
```

```yaml
- module: zeek
  capture_loss:
    enabled: true
  connection:
    enabled: true
    var.paths: ["/opt/zeek/logs/current/conn.log"]
  dns:
    enabled: true
    var.paths: ["/opt/zeek/logs/current/dns.log"]
  http:
    enabled: true
    var.paths: ["/opt/zeek/logs/current/http.log"]
  ssl:
    enabled: true
    var.paths: ["/opt/zeek/logs/current/ssl.log"]
  notice:
    enabled: true
    var.paths: ["/opt/zeek/logs/current/notice.log"]
  weird:
    enabled: true
    var.paths: ["/opt/zeek/logs/current/weird.log"]
  files:
    enabled: true
    var.paths: ["/opt/zeek/logs/current/files.log"]
```

### Copy CA Certificate from Elastic Stack VM

Elasticsearch 8.x enables TLS by default. Copy the CA cert to the sensor:

```bash
# On the Elastic Stack VM, find the CA cert:
# /etc/elasticsearch/certs/http_ca.crt

# On the sensor VM, create the cert directory and copy it:
sudo mkdir -p /etc/filebeat/certs
# scp elastic-stack-vm:/etc/elasticsearch/certs/http_ca.crt /etc/filebeat/certs/
```

### Load Dashboards and Start

```bash
# This loads pre-built Kibana dashboards for Suricata and Zeek
sudo filebeat setup --dashboards

# Enable and start
sudo systemctl enable filebeat
sudo systemctl start filebeat

# Monitor for errors
sudo journalctl -u filebeat -f
```

---

## Validation

### Confirm SPAN Traffic is Arriving

```bash
# Should see non-zero RX packets on eth1
ip -s link show eth1

# Or use tcpdump to verify traffic content
sudo tcpdump -i eth1 -c 20 -nn
```

### Confirm Suricata is Processing

```bash
sudo tail -f /var/log/suricata/eve.json | python3 -m json.tool | head -50
```

You should see `"event_type":"flow"` and `"event_type":"dns"` entries.

### Confirm Zeek is Logging

```bash
tail -f /opt/zeek/logs/current/dns.log
```

You should see DNS queries from devices on your network.

### Confirm Filebeat is Shipping

```bash
sudo journalctl -u filebeat --since "5 minutes ago" | grep -i "events"
```

Look for lines like `"Published N events to elasticsearch"`.

---

## Troubleshooting

**No traffic on eth1:**
- Verify SPAN port is configured on the switch
- Check the cable from switch port 8 to the VM's second NIC
- In Proxmox, confirm net1 is bridged to vmbr0 (not a separate bridge)
- Check `ip link show eth1` — should show UP and promiscuous (`PROMISC`)

**Suricata not starting:**
- Check `sudo journalctl -u suricata -b` for errors
- Validate config: `sudo suricata -T -c /etc/suricata/suricata.yaml`

**Filebeat connection refused:**
- Confirm Elasticsearch is running on VM 103: `curl -k https://192.168.10.31:9200`
- Verify credentials and CA cert path in filebeat.yml
- Check Elasticsearch firewall allows port 9200 from 192.168.10.30
