# Hardware Specifications

## Server Hardware

### CPU
- **Processor**: Intel Core i7 (Ivy Bridge)
- **Cores**: 4 cores
- **Generation**: 3rd Generation (Ivy Bridge architecture, circa 2012-2013)
- **Notes**: Older generation but suitable for homelab workloads

### Memory
- **RAM**: 32 GB
- **Notes**: Upgraded specifically for virtualization workloads

### Storage

#### System/Boot Drive
- **Type**: SSD
- **Capacity**: 250 GB
- **Purpose**: Proxmox OS installation and VM storage

#### Data Drives
- **Type**: Magnetic HDD
- **Quantity**: 4 drives
- **Capacity**: 1 TB each (4 TB total raw capacity)
- **Configuration**: RAID5 (mdadm software RAID)
- **Usable Capacity**: ~2.73 TB
- **Mount Point**: `/data`
- **Filesystem**: ext4
- **Status**: Operational

### RAID Configuration

**RAID5 Details:**
- **Drives**: 4 x 1TB HDDs (`/dev/sda1`, `/dev/sdb1`, `/dev/sdc1`, `/dev/sdd1`)
- **Array Device**: `/dev/md0`
- **Array UUID**: `a61c0a48:4efa2e85:ca4c0148:94dcbc02`
- **Filesystem UUID**: `63e2b5f9-7259-4333-83d3-4fd06a278773`
- **Parity**: Single parity drive equivalent
- **Usable Space**: 2.73 TB
- **Fault Tolerance**: Can tolerate 1 drive failure
- **Performance**: Good read performance, moderate write performance
- **Use Case**: Network storage and backup
- **Original Creation**: August 11, 2012 (migrated from `server2`)

## Network

Details TBD:
- Network interface specifications
- Planned network topology
- VLAN configuration (if applicable)

## Virtualization Platform

- **Platform**: Proxmox VE
- **Version**: Proxmox VE 8.x (chosen over v9 for stability)

## Migration Notes

The 4 x 1TB RAID5 array was successfully migrated from `server2` to Proxmox:
1. ~~Backed up before migration~~
2. ~~Physically moved to the server~~
3. ~~Imported/reconfigured in Proxmox~~
4. ~~Verified for data integrity~~

**Migration completed**: February 2026. See [raid-storage-setup.md](raid-storage-setup.md) for setup details.

## Future Expansion Considerations

- Additional RAM (Proxmox can use more for VM allocation)
- SSD cache for RAID array (ZFS L2ARC or similar)
- Backup drives (external or additional internal)
- Network cards (if additional networking features needed)
