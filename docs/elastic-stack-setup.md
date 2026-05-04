# Elastic Stack Setup — Elasticsearch and Kibana

## Overview

This guide sets up the Elastic Stack VM (VM 103) that receives logs from the
network sensor, indexes them in Elasticsearch, and provides dashboards and
alerting through Kibana.

This is the storage and visualization layer of the NSM architecture. See
`docs/nsm-architecture.md` for the full system design.

---

## Prerequisites

- VM 103 created in Proxmox (2 vCPU, 10 GB RAM, 100 GB SSD)
- Debian 13 (Trixie) installed with static IP 192.168.10.31
- Network sensor VM (102) set up afterward — it needs Elasticsearch credentials

---

## Proxmox VM Setup

```bash
qm create 103 \
  --name elastic-stack \
  --memory 10240 \
  --cores 2 \
  --sockets 1 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:100 \
  --ide2 local:iso/ubuntu-22.04-server.iso,media=cdrom \
  --boot order=ide2 \
  --ostype l26
```

### Debian Installation

Install Debian 13 (Trixie) — same process as the Recipes Server VM:
- Hostname: `elastic`
- Skip desktop environment; select SSH server + standard utilities
- User: `dustin`

Post-install, configure static IP in `/etc/network/interfaces`:
```
auto lo
iface lo inet loopback

auto ens18
iface ens18 inet static
    address 192.168.10.31/24
    gateway 192.168.10.1
```

Configure DNS:
```bash
# /etc/resolv.conf
nameserver 192.168.10.8
nameserver 1.1.1.1
```

```bash
sudo systemctl restart networking
```

### Base System Prep

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget gnupg2 apt-transport-https sudo
sudo usermod -aG sudo dustin
```

---

## Elasticsearch Installation

### Add Elastic Repository

```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
sudo apt install -y elasticsearch
```

> **Save the auto-generated `elastic` superuser password** printed during
> installation. It looks like:
> ```
> The generated password for the elastic built-in superuser is: <PASSWORD>
> ```
> If you miss it: `sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic`

### Configure

```bash
sudo nano /etc/elasticsearch/elasticsearch.yml
```

```yaml
cluster.name: homelab-nsm
node.name: elastic-stack-01

# Listen on all interfaces (VM is on trusted home network)
network.host: 0.0.0.0
http.port: 9200

# Single-node cluster
discovery.type: single-node

# Path settings (defaults are fine)
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
```

> **Gotcha**: The default `elasticsearch.yml` includes a `cluster.initial_master_nodes`
> line. This conflicts with `discovery.type: single-node` and causes a fatal boot error.
> Comment it out or delete it.

> Security (TLS + authentication) is **enabled by default** in Elasticsearch 8.x.
> Do not disable it — the TLS certs are auto-generated and Filebeat is configured
> to use them.

### Tune JVM Heap

Elasticsearch defaults to 50% of system RAM for heap. On a 10 GB VM that would
be 5 GB — acceptable, but set it explicitly to keep it predictable:

```bash
sudo nano /etc/elasticsearch/jvm.options.d/heap.options
```

```
-Xms4g
-Xmx4g
```

4 GB heap is sufficient for home network log volumes. This leaves ~6 GB for the
OS, Kibana, and the filesystem page cache (which Elasticsearch uses heavily for
read performance).

### Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch

# Confirm it's running (takes ~30 seconds on first start)
sudo systemctl status elasticsearch

# Verify the API is responding
sudo curl -k -u elastic:<PASSWORD> https://localhost:9200
```

Expected response:
```json
{
  "name" : "elastic-stack-01",
  "cluster_name" : "homelab-nsm",
  "tagline" : "You Know, for Search"
}
```

---

## Kibana Installation

```bash
sudo apt install -y kibana
```

### Configure

```bash
sudo nano /etc/kibana/kibana.yml
```

```yaml
server.port: 5601
server.host: "0.0.0.0"
server.name: "homelab-kibana"

# Kibana connects to Elasticsearch — enrollment token handles this (see below)
# elasticsearch.hosts is set automatically by the enrollment process
```

### Enroll Kibana with Elasticsearch

Elasticsearch 8.x uses an enrollment token to securely connect Kibana:

```bash
# Generate enrollment token on this same machine
sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana
```

Copy the token, then run the Kibana setup:

```bash
sudo /usr/share/kibana/bin/kibana-setup --enrollment-token <TOKEN>
```

### Enable and Start

```bash
sudo systemctl enable kibana
sudo systemctl start kibana

# Kibana takes 1-2 minutes to initialize
sudo journalctl -u kibana -f
# Wait for: "Kibana is now available"
```

Access Kibana at `https://192.168.10.31:5601` (or `http://` — check your config).

Log in with `elastic` / `<PASSWORD>`.

---

## Create Filebeat User

Rather than using the `elastic` superuser for Filebeat, create a dedicated user
with only the permissions it needs.

In Kibana, navigate to **Stack Management → Security → Users**, or use the API:

```bash
# Create role for Filebeat
curl -k -u elastic:<PASSWORD> -X POST https://localhost:9200/_security/role/filebeat_writer \
  -H 'Content-Type: application/json' \
  -d '{
    "cluster": ["monitor", "manage_index_templates", "manage_ilm", "manage_pipeline"],
    "indices": [
      {
        "names": ["filebeat-*", "logs-*"],
        "privileges": ["write", "create", "create_index", "manage", "auto_configure"]
      }
    ]
  }'

# Create user assigned to that role
curl -k -u elastic:<PASSWORD> -X POST https://localhost:9200/_security/user/filebeat_writer \
  -H 'Content-Type: application/json' \
  -d '{
    "password": "CHOOSE_A_STRONG_PASSWORD",
    "roles": ["filebeat_writer"],
    "full_name": "Filebeat Writer"
  }'
```

> Use this password in the sensor VM's `filebeat.yml` `output.elasticsearch.password`.

---

## Copy CA Certificate to Sensor VM

Filebeat on the sensor needs the Elasticsearch CA cert to verify TLS:

```bash
# On the Elastic Stack VM, the cert is at:
cat /etc/elasticsearch/certs/http_ca.crt

# Copy to sensor VM (run from sensor VM or use scp):
scp dustin@192.168.10.31:/etc/elasticsearch/certs/http_ca.crt \
    /tmp/elastic_http_ca.crt

sudo mv /tmp/elastic_http_ca.crt /etc/filebeat/certs/http_ca.crt
```

---

## Index Lifecycle Management (ILM)

Suricata and Zeek generate continuous log data. ILM automatically rolls over and
deletes old indices to keep disk usage bounded.

Filebeat's `setup` command creates default ILM policies. To customize the
retention period:

In Kibana: **Stack Management → Index Lifecycle Policies → filebeat**

Recommended settings for a 100 GB disk:
- **Hot phase**: Roll over at 10 GB or 7 days
- **Delete phase**: Delete after 30 days

Or via API:

```bash
curl -k -u elastic:<PASSWORD> -X PUT https://localhost:9200/_ilm/policy/filebeat \
  -H 'Content-Type: application/json' \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "actions": {
            "rollover": {
              "max_size": "10gb",
              "max_age": "7d"
            }
          }
        },
        "delete": {
          "min_age": "30d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'
```

---

## Kibana: Key Views for NSM

### Pre-Built Dashboards (loaded by Filebeat)

After running `sudo filebeat setup --dashboards` on the sensor VM, these
dashboards appear in Kibana under **Analytics → Dashboards**:

| Dashboard | What to look for |
|-----------|-----------------|
| `[Suricata] Alert Overview` | Alert volume, top signatures, top source IPs |
| `[Suricata] Events` | Per-event detail, protocol breakdown |
| `[Zeek] Connection Summary` | Top talkers, unusual ports, long-duration connections |
| `[Zeek] DNS` | All DNS queries — key for seeing what sites are being visited |
| `[Zeek] HTTP` | Full URLs requested over HTTP |
| `[Zeek] SSL` | TLS connections by SNI (reveals HTTPS destinations) |

### Discover: Key Queries for Parental Monitoring

Navigate to **Analytics → Discover**, select the `filebeat-*` index pattern.

**See all Suricata alerts (parental rule hits):**
```
event.module: suricata AND event.dataset: suricata.eve AND event.kind: alert
```

**See all DNS queries from a specific device (by IP):**
```
event.module: zeek AND event.dataset: zeek.dns AND source.ip: 192.168.10.XX
```

**See what HTTPS sites a device visited (via TLS SNI):**
```
event.module: zeek AND event.dataset: zeek.ssl AND source.ip: 192.168.10.XX
```

**Find any VPN or proxy connection attempts:**
```
event.module: suricata AND rule.category: "Potentially Bad Traffic"
```

### Setting Up Alerts

Kibana alerting (called **Rules**) can email or notify when specific conditions
are met.

Navigate to **Stack Management → Rules → Create Rule → Elasticsearch query**:

Example: alert when any `[PARENTAL]` Suricata rule fires:

- **Index**: `filebeat-*`
- **Query**: `{"match": {"rule.name": "[PARENTAL]"}}`
- **Condition**: `count() > 0` over last 5 minutes
- **Action**: Email notification (requires configuring SMTP in kibana.yml — see
  `docs/email-relay.md` if available, or use Gmail SMTP)

---

## Kibana Concepts: Learning Reference

Understanding these concepts maps directly to enterprise Elastic deployments:

| Concept | What It Is | Enterprise Analog |
|---------|------------|------------------|
| **Index** | A collection of documents (like a DB table) | A log data stream |
| **Index Pattern** | A wildcard mapping to query across indices | `filebeat-*` covers all Filebeat indices |
| **Mapping** | Schema defining field types in an index | Column definitions in a DB |
| **ILM Policy** | Rules for rolling over and deleting old indices | Log retention policy |
| **Ingest Pipeline** | Server-side transform/enrich on ingestion | ETL pipeline |
| **KQL** | Kibana Query Language for filtering documents | SQL WHERE clause analog |
| **Lens** | Visual drag-and-drop dashboard builder | BI tool interface |
| **Watcher/Rules** | Alerting engine — runs queries on a schedule | SIEM alert rules |

---

## Storage Monitoring

Monitor disk usage on the 100 GB volume:

```bash
# Check Elasticsearch index sizes
curl -k -u elastic:<PASSWORD> \
  "https://localhost:9200/_cat/indices?v&s=store.size:desc&h=index,store.size,docs.count"

# Overall disk usage
df -h /var/lib/elasticsearch
```

If disk usage approaches 85%, Elasticsearch will go into read-only mode
(flood-stage watermark). Adjust ILM to delete older data sooner if needed.

---

## Troubleshooting

**Kibana shows "Kibana server is not ready yet":**
- Elasticsearch may still be starting: `sudo systemctl status elasticsearch`
- Check logs: `sudo journalctl -u kibana -b --no-pager | tail -30`

**Filebeat data not appearing in Kibana:**
- Check Filebeat status on sensor VM: `sudo journalctl -u filebeat -f`
- Verify index was created: `curl -k -u elastic:<PASSWORD> https://localhost:9200/_cat/indices?v`
- Confirm index pattern `filebeat-*` exists in Kibana Stack Management

**Elasticsearch out of disk space / read-only:**
```bash
# Temporarily clear read-only block while you free space
curl -k -u elastic:<PASSWORD> -X PUT https://localhost:9200/_all/_settings \
  -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'
```

Then delete old indices or adjust ILM retention.
