# Homelab Server Documentation

This repository contains documentation, configurations, and scripts for my Proxmox-based homelab server setup. The goal is to create a reproducible, well-documented infrastructure that can be rebuilt from scratch if needed.

## Overview

This homelab uses Proxmox VE as the virtualization platform to partition hardware resources across multiple use cases:

1. **Web Server VM** - Hosting personal web applications
2. **Ubuntu Development VM** - Ad-hoc development and testing environment
3. **Pi-hole** - Network-wide ad blocking and DNS management
4. **Network Storage** - Centralized file storage using RAID5
5. **Network Monitoring** - Traffic monitoring and parental controls

## Hardware Specifications

See [docs/hardware-specs.md](docs/hardware-specs.md) for detailed hardware information.

## VM Architecture

See [docs/vm-architecture.md](docs/vm-architecture.md) for the planned VM layout and resource allocation.

## SSL Certificate Management

See [docs/ssl-certificate-management.md](docs/ssl-certificate-management.md) for the complete SSL/TLS certificate strategy using a private Certificate Authority infrastructure (Mannsclann Homelab Root CA → Mannsclann Homelab Intermediate CA → Service Certificates).

## Directory Structure

```
homelab/
├── certs/          # SSL certificates and CA infrastructure
│   ├── root-ca/    # Root Certificate Authority
│   ├── intermediate-ca/  # Intermediate Certificate Authority
│   └── services/   # Service certificates
├── docs/           # Documentation files
├── specs/          # VM specifications and configs
├── scripts/        # Automation and setup scripts
└── README.md       # This file
```

## Getting Started

Documentation for initial Proxmox installation and configuration will be added as the setup progresses.

## Goals

- **Reproducibility**: All setup steps documented to enable rebuild from scratch
- **Documentation**: Clear documentation of all configurations and decisions
- **Automation**: Scripts to automate common tasks where possible
- **Version Control**: Track all changes to configurations and setup

## Status

Project Status: Initial Setup - Planning Phase
