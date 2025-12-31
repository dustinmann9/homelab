# SSL Certificate Management Strategy

## Overview

This homelab uses a private Certificate Authority (CA) infrastructure to issue SSL/TLS certificates for internal services. This approach provides:

- **No Browser Warnings**: Once the root CA is trusted, all issued certificates are trusted
- **No External Dependencies**: No need for Let's Encrypt or public CAs for internal services
- **Full Control**: Complete control over certificate lifecycle
- **Professional Practice**: Mirrors enterprise PKI implementations
- **Security**: Proper certificate validation without self-signed certificate risks

## CA Hierarchy

### Three-Tier Architecture

```
Root CA (homelab-root-ca)
  └── Intermediate CA (homelab-intermediate-ca)
      └── Server/Service Certificates
          ├── proxmox.homelab.local
          ├── pihole.homelab.local
          ├── storage.homelab.local
          ├── webserver.homelab.local
          └── ... other services
```

### Why This Architecture?

1. **Root CA**:
   - Created once and kept completely offline/air-gapped
   - Private key stored securely (encrypted USB, safe, etc.)
   - Only used to sign the Intermediate CA certificate
   - If compromised, entire PKI must be rebuilt
   - Long validity period (10-20 years)

2. **Intermediate CA**:
   - Used for day-to-day certificate signing
   - Can be kept online on a secure VM or system
   - If compromised, only need to revoke this CA and create a new one
   - Root CA can issue a new intermediate without affecting trust
   - Medium validity period (5-10 years)

3. **Server/Service Certificates**:
   - Short validity period (1-2 years, automate renewal)
   - Specific to each service
   - Easy to revoke and replace

## Directory Structure

Recommended structure for certificate storage:

```
homelab/
├── certs/
│   ├── root-ca/
│   │   ├── private/          # Root CA private key (NEVER commit to git)
│   │   ├── certs/            # Root CA certificate (public)
│   │   └── index.txt         # Certificate database
│   ├── intermediate-ca/
│   │   ├── private/          # Intermediate CA private key (NEVER commit)
│   │   ├── certs/            # Intermediate CA certificate (public)
│   │   ├── csr/              # Certificate signing requests
│   │   └── newcerts/         # Issued certificates
│   └── services/
│       ├── proxmox/
│       ├── pihole/
│       ├── webserver/
│       └── storage/
└── scripts/
    ├── create-root-ca.sh
    ├── create-intermediate-ca.sh
    ├── generate-server-cert.sh
    └── revoke-cert.sh
```

**IMPORTANT**: Add the following to `.gitignore`:
```
certs/*/private/
*.key
*.p12
*.pfx
```

## Certificate Specifications

### Root CA Certificate

- **Common Name (CN)**: Homelab Root CA
- **Organization (O)**: Homelab
- **Validity**: 7300 days (20 years)
- **Key Size**: 4096 bits RSA (or EC P-384)
- **Usage**: Certificate Signing, CRL Signing
- **Basic Constraints**: CA:TRUE, pathlen:1

### Intermediate CA Certificate

- **Common Name (CN)**: Homelab Intermediate CA
- **Organization (O)**: Homelab
- **Validity**: 3650 days (10 years)
- **Key Size**: 4096 bits RSA (or EC P-256)
- **Usage**: Certificate Signing, CRL Signing
- **Basic Constraints**: CA:TRUE, pathlen:0

### Server Certificates

- **Common Name (CN)**: service.homelab.local
- **Subject Alternative Names (SAN)**:
  - DNS:service.homelab.local
  - DNS:service
  - IP:192.168.x.x (if needed)
- **Validity**: 825 days (maximum per modern standards)
- **Key Size**: 2048 bits RSA (or EC P-256)
- **Usage**: Digital Signature, Key Encipherment
- **Extended Usage**: TLS Web Server Authentication

## Procedures

### 1. Create Root CA (One-Time Setup)

**Prerequisites**:
- Secure, offline system (or air-gapped VM)
- Strong passphrase for private key

**Steps**:
1. Generate Root CA private key (4096-bit RSA, encrypted)
2. Create Root CA certificate (self-signed, 20-year validity)
3. Store private key securely offline
4. Export Root CA certificate for distribution

**Script**: `scripts/create-root-ca.sh`

**Storage**:
- Private key: Encrypted USB drive, physically secured
- Certificate: Can be stored in repository (public information)

### 2. Create Intermediate CA (One-Time Setup)

**Prerequisites**:
- Root CA private key accessible
- Root CA certificate

**Steps**:
1. Generate Intermediate CA private key (4096-bit RSA, encrypted)
2. Create Certificate Signing Request (CSR)
3. Sign CSR with Root CA private key
4. Create certificate chain (Intermediate + Root)
5. Store Intermediate CA private key securely (can be online)

**Script**: `scripts/create-intermediate-ca.sh`

**Storage**:
- Private key: Secure system (Proxmox host or dedicated VM), encrypted
- Certificate: Can be stored in repository

### 3. Generate Server Certificate

**For each service requiring SSL certificate**:

**Steps**:
1. Generate private key for service (2048-bit RSA)
2. Create CSR with proper CN and SAN entries
3. Sign CSR with Intermediate CA
4. Create certificate bundle (Server + Intermediate + Root)
5. Deploy to service

**Script**: `scripts/generate-server-cert.sh`

**Example**:
```bash
./scripts/generate-server-cert.sh proxmox.homelab.local 192.168.1.10
```

**Output**:
- `certs/services/proxmox/proxmox.key` - Private key
- `certs/services/proxmox/proxmox.crt` - Certificate
- `certs/services/proxmox/proxmox-chain.crt` - Full chain
- `certs/services/proxmox/proxmox.csr` - CSR (for records)

### 4. Certificate Renewal

**Recommended**: Renew certificates 30 days before expiration

**Steps**:
1. Generate new CSR (can reuse private key or generate new one)
2. Sign with Intermediate CA
3. Deploy new certificate
4. Restart service

**Automation**: Can be automated with scripts and cron jobs

### 5. Certificate Revocation

**If a certificate is compromised**:

**Steps**:
1. Add certificate to Certificate Revocation List (CRL)
2. Update CRL distribution
3. Generate and deploy replacement certificate

**Script**: `scripts/revoke-cert.sh`

## Trust Distribution

### Client Trust Configuration

For clients to trust your certificates, they must trust the Root CA:

#### Windows
1. Import Root CA certificate
2. Place in "Trusted Root Certification Authorities" store
3. Can be deployed via Group Policy in domain environments

#### macOS
1. Import Root CA certificate into Keychain
2. Set to "Always Trust" for SSL
3. Requires admin password

#### Linux
1. Copy Root CA certificate to `/usr/local/share/ca-certificates/`
2. Run `update-ca-certificates`

#### iOS/iPadOS
1. Email or host Root CA certificate
2. Install profile
3. Trust in Settings → General → About → Certificate Trust Settings

#### Android
1. Settings → Security → Install from storage
2. Select Root CA certificate
3. Name and confirm

#### Browsers (Firefox)
Firefox uses its own certificate store:
1. Settings → Privacy & Security → Certificates → View Certificates
2. Import Root CA certificate
3. Trust for websites

## Security Best Practices

### Private Key Protection

1. **Root CA Private Key**:
   - Encrypt with strong passphrase (20+ characters)
   - Store offline on encrypted USB drive
   - Keep in physically secure location (safe, lockbox)
   - Create encrypted backup stored separately
   - Never store on internet-connected systems

2. **Intermediate CA Private Key**:
   - Encrypt with strong passphrase
   - Store on secure system with restricted access
   - Regular encrypted backups
   - Can be online but should be on hardened system

3. **Server Private Keys**:
   - Appropriate file permissions (600 or 400)
   - Owned by service user
   - Never commit to version control
   - Backed up encrypted

### Passphrase Management

- Use password manager for passphrase storage
- Minimum 20 characters for CA keys
- Different passphrases for Root vs Intermediate CA
- Document passphrase recovery process

### Certificate Database

- Maintain index of all issued certificates
- Track serial numbers, issuance dates, expiration dates
- Record certificate purposes and deployed locations
- Regular audits of active certificates

### Monitoring

- Calendar reminders for certificate expiration
- Automated monitoring if possible
- 30-day renewal window before expiration

## Disaster Recovery

### Backup Strategy

**Critical Items to Backup**:
1. Root CA private key (encrypted, offline)
2. Intermediate CA private key (encrypted)
3. All CA certificates
4. Certificate database/index
5. OpenSSL configuration files

**Backup Locations**:
- Primary: Encrypted USB drive (physically secured)
- Secondary: Encrypted cloud storage (for CA certificates only, not private keys)
- Tertiary: Encrypted external drive (off-site)

### Recovery Procedures

**If Root CA is Lost**:
- Complete PKI rebuild required
- All certificates must be reissued
- All clients must trust new Root CA
- **Prevention is critical**

**If Intermediate CA is Lost**:
- Use Root CA to issue new Intermediate CA
- Revoke old Intermediate CA
- Reissue server certificates with new Intermediate CA
- Update certificate chains on all services

**If Server Certificate is Lost**:
- Generate new CSR
- Sign with Intermediate CA
- Deploy new certificate

## Implementation Checklist

- [ ] Create directory structure
- [ ] Update `.gitignore` to exclude private keys
- [ ] Create Root CA (offline process)
- [ ] Securely store Root CA private key
- [ ] Create Intermediate CA
- [ ] Create certificate generation scripts
- [ ] Generate first test certificate
- [ ] Distribute Root CA to test clients
- [ ] Verify trust chain
- [ ] Document all passphrases securely
- [ ] Set up backup procedures
- [ ] Create certificate inventory spreadsheet
- [ ] Set renewal reminders

## Services Requiring Certificates

### Planned Certificates

1. **Proxmox Host**: `proxmox.homelab.local`
2. **Pi-hole**: `pihole.homelab.local`
3. **Web Server**: `webserver.homelab.local`, `www.homelab.local`
4. **Network Storage**: `storage.homelab.local`
5. **Network Monitor**: `monitor.homelab.local`

### Certificate Inventory Template

| Service | Common Name | SANs | Issued Date | Expiry Date | Serial | Status |
|---------|-------------|------|-------------|-------------|--------|--------|
| Proxmox | proxmox.homelab.local | IP:192.168.1.10 | TBD | TBD | TBD | Pending |
| Pi-hole | pihole.homelab.local | IP:192.168.1.11 | TBD | TBD | TBD | Pending |

## Tools and Software

### OpenSSL
Primary tool for CA operations:
- Certificate generation
- CSR creation and signing
- Key generation
- Certificate inspection

### Alternative Tools
- **easy-rsa**: Simplified CA management
- **cfssl**: CloudFlare's PKI toolkit
- **step-ca**: Smallstep CA (can run as service)
- **XCA**: GUI tool for certificate management

### Recommended Approach
Start with OpenSSL scripts for full control and learning, consider automation tools later for production use.

## References

- [OpenSSL Certificate Authority Guide](https://jamielinux.com/docs/openssl-certificate-authority/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [RFC 5280 - Internet X.509 PKI Certificate](https://tools.ietf.org/html/rfc5280)
- [CA/Browser Forum Baseline Requirements](https://cabforum.org/baseline-requirements-documents/)

## Next Steps

1. Review and approve this strategy
2. Create implementation scripts
3. Set up directory structure
4. Create Root CA (offline ceremony)
5. Create Intermediate CA
6. Generate first certificates for Proxmox installation
