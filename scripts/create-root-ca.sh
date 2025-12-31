#!/bin/bash

# Create Mannsclann Homelab Root CA
# This script creates the root Certificate Authority for the homelab
# IMPORTANT: Store the Root CA private key securely offline after creation!

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_CA_DIR="$PROJECT_DIR/certs/root-ca"

echo "=========================================="
echo "Mannsclann Homelab Root CA Creation"
echo "=========================================="
echo ""
echo "This will create:"
echo "  - Root CA private key (4096-bit RSA, encrypted)"
echo "  - Root CA certificate (20-year validity)"
echo ""
echo "IMPORTANT: You will be prompted for a passphrase to encrypt the private key."
echo "           This passphrase should be STRONG (20+ characters)."
echo "           Store this passphrase in a secure password manager."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

# Create OpenSSL configuration for Root CA
echo "Creating OpenSSL configuration..."
cat > "$ROOT_CA_DIR/openssl.cnf" << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
# Directory and file locations
dir               = REPLACE_DIR
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand

# Root CA private key and certificate
private_key       = $dir/private/mannsclann-homelab-root-ca.key
certificate       = $dir/certs/mannsclann-homelab-root-ca.crt

# CRL settings
crlnumber         = $dir/crlnumber
crl               = $dir/crl/mannsclann-homelab-root-ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30

# SHA-256 for signing
default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = 3650
preserve          = no
policy            = policy_strict

[ policy_strict ]
# Policy for Root CA - strict requirements
countryName             = optional
stateOrProvinceName     = optional
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ policy_loose ]
# Policy for Intermediate CA - more relaxed
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

# Defaults
countryName_default             = US
0.organizationName_default      = Mannsclann Homelab
commonName_default              = Mannsclann Homelab Root CA

[ v3_ca ]
# Extensions for Root CA certificate
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
# Extensions for Intermediate CA certificate
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
# Extensions for client certificates
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "Mannsclann Homelab Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ server_cert ]
# Extensions for server certificates
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "Mannsclann Homelab Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ crl_ext ]
# Extension for CRLs
authorityKeyIdentifier=keyid:always

[ ocsp ]
# Extension for OCSP signing certificates
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

# Replace placeholder with actual directory
sed -i.bak "s|REPLACE_DIR|$ROOT_CA_DIR|g" "$ROOT_CA_DIR/openssl.cnf"
rm "$ROOT_CA_DIR/openssl.cnf.bak"

# Initialize database files
echo "Initializing certificate database..."
touch "$ROOT_CA_DIR/index.txt"
echo 1000 > "$ROOT_CA_DIR/serial"

# Generate Root CA private key
echo ""
echo "Generating Root CA private key (4096-bit RSA)..."
echo "You will be prompted to enter a passphrase."
echo ""
openssl genrsa -aes256 -out "$ROOT_CA_DIR/private/mannsclann-homelab-root-ca.key" 4096
chmod 400 "$ROOT_CA_DIR/private/mannsclann-homelab-root-ca.key"

# Generate Root CA certificate
echo ""
echo "Generating Root CA certificate (20-year validity)..."
echo "You will be prompted to enter the passphrase again, then certificate details."
echo ""
openssl req -config "$ROOT_CA_DIR/openssl.cnf" \
    -key "$ROOT_CA_DIR/private/mannsclann-homelab-root-ca.key" \
    -new -x509 -days 7300 -sha256 -extensions v3_ca \
    -out "$ROOT_CA_DIR/certs/mannsclann-homelab-root-ca.crt"

chmod 444 "$ROOT_CA_DIR/certs/mannsclann-homelab-root-ca.crt"

# Verify the certificate
echo ""
echo "=========================================="
echo "Root CA Certificate Details:"
echo "=========================================="
openssl x509 -noout -text -in "$ROOT_CA_DIR/certs/mannsclann-homelab-root-ca.crt"

echo ""
echo "=========================================="
echo "Root CA Creation Complete!"
echo "=========================================="
echo ""
echo "Files created:"
echo "  Private Key: $ROOT_CA_DIR/private/mannsclann-homelab-root-ca.key"
echo "  Certificate: $ROOT_CA_DIR/certs/mannsclann-homelab-root-ca.crt"
echo "  Config:      $ROOT_CA_DIR/openssl.cnf"
echo ""
echo "IMPORTANT SECURITY NOTES:"
echo "  1. The Root CA private key is ENCRYPTED with your passphrase"
echo "  2. Store the passphrase in a secure password manager"
echo "  3. Back up the private key to encrypted USB drive"
echo "  4. Store the backup in a physically secure location"
echo "  5. The private key should be kept OFFLINE after creating the Intermediate CA"
echo "  6. The certificate (*.crt) is public and will be committed to git"
echo ""
