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
- **Configuration**: RAID5
- **Usable Capacity**: ~3 TB (accounting for RAID5 parity)
- **Notes**: Currently part of desktop RAID5 setup, will be migrated to server

### RAID Configuration

**RAID5 Details:**
- **Drives**: 4 x 1TB HDDs
- **Parity**: Single parity drive equivalent
- **Usable Space**: 3 TB
- **Fault Tolerance**: Can tolerate 1 drive failure
- **Performance**: Good read performance, moderate write performance
- **Use Case**: Network storage and backup

## Network

Details TBD:
- Network interface specifications
- Planned network topology
- VLAN configuration (if applicable)

## Virtualization Platform

- **Platform**: Proxmox VE
- **Version**: TBD (will be latest stable at time of installation)

## Migration Notes

The 4 x 1TB RAID5 array is currently in use on desktop and will need to be:
1. Backed up before migration
2. Physically moved to the server
3. Imported/reconfigured in Proxmox
4. Verified for data integrity

## Future Expansion Considerations

- Additional RAM (Proxmox can use more for VM allocation)
- SSD cache for RAID array (ZFS L2ARC or similar)
- Backup drives (external or additional internal)
- Network cards (if additional networking features needed)
