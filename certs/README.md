# Mannsclann Homelab Certificate Authority

This directory contains the Certificate Authority (CA) infrastructure for the Mannsclann Homelab.

## CA Hierarchy

```
Mannsclann Homelab Root CA (2025-2045)
  └── Mannsclann Homelab Intermediate CA (2025-2035)
      └── Service Certificates
```

## Root CA

**Certificate Details:**
- **Common Name**: Mannsclann Homelab Root CA
- **Organization**: Mannsclann Homelab
- **Country**: US
- **Validity**: December 31, 2025 - December 26, 2045 (20 years)
- **Key Size**: 4096-bit RSA
- **Serial Number**: Self-signed
- **Location**: `root-ca/certs/mannsclann-homelab-root-ca.crt`

**Private Key:**
- **Location**: `root-ca/private/mannsclann-homelab-root-ca.key` (NOT in git)
- **Protection**: File permissions 400 (read-only by owner)
- **Encryption**: Unencrypted (consider adding passphrase protection for production use)

**Purpose:**
- Sign Intermediate CA certificate only
- Should be kept offline after Intermediate CA is created
- Only use when creating new Intermediate CAs

## Intermediate CA

**Certificate Details:**
- **Common Name**: Mannsclann Homelab Intermediate CA
- **Organization**: Mannsclann Homelab
- **Country**: US
- **Issuer**: Mannsclann Homelab Root CA
- **Validity**: December 31, 2025 - December 29, 2035 (10 years)
- **Key Size**: 4096-bit RSA
- **Serial Number**: 4096 (0x1000)
- **Location**: `intermediate-ca/certs/mannsclann-homelab-intermediate-ca.crt`

**Private Key:**
- **Location**: `intermediate-ca/private/mannsclann-homelab-intermediate-ca.key` (NOT in git)
- **Protection**: File permissions 400 (read-only by owner)
- **Encryption**: Unencrypted (consider adding passphrase protection for production use)

**Certificate Chain:**
- **Location**: `intermediate-ca/certs/mannsclann-homelab-ca-chain.crt`
- **Contents**: Intermediate CA cert + Root CA cert
- **Use**: Deploy with server certificates for full chain validation

**Purpose:**
- Sign server/service certificates
- Used for day-to-day certificate operations
- Can be kept online on secure system

## Certificate Chain Verification

The certificate chain has been verified:

```bash
openssl verify -CAfile root-ca/certs/mannsclann-homelab-root-ca.crt \
    intermediate-ca/certs/mannsclann-homelab-intermediate-ca.crt
```

Result: ✅ OK

## Directory Structure

```
certs/
├── root-ca/
│   ├── private/                    # Private keys (NOT in git)
│   │   └── mannsclann-homelab-root-ca.key
│   ├── certs/                      # Public certificates (in git)
│   │   └── mannsclann-homelab-root-ca.crt
│   ├── newcerts/                   # Issued certificates database
│   ├── index.txt                   # Certificate database
│   ├── serial                      # Serial number counter
│   └── openssl.cnf                 # OpenSSL configuration
│
├── intermediate-ca/
│   ├── private/                    # Private keys (NOT in git)
│   │   └── mannsclann-homelab-intermediate-ca.key
│   ├── certs/                      # Public certificates (in git)
│   │   ├── mannsclann-homelab-intermediate-ca.crt
│   │   └── mannsclann-homelab-ca-chain.crt
│   ├── csr/                        # Certificate signing requests (NOT in git)
│   │   └── mannsclann-homelab-intermediate-ca.csr
│   ├── newcerts/                   # Issued certificates database
│   ├── index.txt                   # Certificate database
│   ├── serial                      # Serial number counter
│   ├── crlnumber                   # CRL number counter
│   └── openssl.cnf                 # OpenSSL configuration
│
└── services/                       # Service certificates (created as needed)
    ├── proxmox/
    ├── pihole/
    ├── webserver/
    └── storage/
```

## Trust Distribution

To trust certificates issued by this CA, clients must trust the Root CA certificate.

### Install Root CA on macOS:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \
    root-ca/certs/mannsclann-homelab-root-ca.crt
```

### Install Root CA on Linux:

```bash
sudo cp root-ca/certs/mannsclann-homelab-root-ca.crt /usr/local/share/ca-certificates/mannsclann-homelab-root-ca.crt
sudo update-ca-certificates
```

### Install Root CA on Windows:

1. Double-click the certificate file
2. Click "Install Certificate"
3. Select "Local Machine"
4. Place in "Trusted Root Certification Authorities"

## Security Notes

⚠️ **IMPORTANT SECURITY CONSIDERATIONS:**

1. **Private Keys**: The private keys are NOT encrypted with passphrases
   - For production use, consider regenerating with passphrase protection
   - Use `openssl genrsa -aes256` for encrypted keys

2. **Root CA Private Key**: Should be moved to offline storage
   - Copy to encrypted USB drive
   - Store in physically secure location
   - Remove from online systems after Intermediate CA is created

3. **Backups**: Create encrypted backups of:
   - Both private keys
   - Certificate database files
   - OpenSSL configuration files

4. **File Permissions**: Verify private key permissions are restrictive:
   ```bash
   chmod 400 root-ca/private/*.key
   chmod 400 intermediate-ca/private/*.key
   ```

## Next Steps

1. **Distribute Root CA**: Install root CA certificate on all client devices
2. **Generate Service Certificates**: Create certificates for each service
3. **Backup**: Create encrypted backups of CA infrastructure
4. **Secure Root CA**: Move Root CA private key to offline storage

## Issuing Server Certificates

To issue a server certificate, you'll use the Intermediate CA. A script will be created for this purpose:

```bash
./scripts/generate-server-cert.sh <service-name> <fqdn> [ip-address]
```

Example:
```bash
./scripts/generate-server-cert.sh proxmox proxmox.homelab.local 192.168.1.10
```

## Certificate Inventory

| Service | Common Name | Status | Issued Date | Expiry Date | Serial |
|---------|-------------|--------|-------------|-------------|--------|
| Root CA | Mannsclann Homelab Root CA | Active | 2025-12-31 | 2045-12-26 | Self-signed |
| Intermediate CA | Mannsclann Homelab Intermediate CA | Active | 2025-12-31 | 2035-12-29 | 0x1000 |

## References

See [docs/ssl-certificate-management.md](../docs/ssl-certificate-management.md) for complete CA management strategy and procedures.
