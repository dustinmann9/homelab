#!/bin/bash

# Create Mannsclann Homelab Intermediate CA
# This script creates the Intermediate Certificate Authority
# The Intermediate CA is used for day-to-day certificate signing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_CA_DIR="$PROJECT_DIR/certs/root-ca"
INTERMEDIATE_CA_DIR="$PROJECT_DIR/certs/intermediate-ca"

echo "=========================================="
echo "Mannsclann Homelab Intermediate CA Creation"
echo "=========================================="
echo ""
echo "This will create:"
echo "  - Intermediate CA private key (4096-bit RSA, encrypted)"
echo "  - Intermediate CA certificate (10-year validity)"
echo "  - Certificate chain (Intermediate + Root)"
echo ""
echo "Prerequisites:"
echo "  - Root CA must already exist"
echo "  - Root CA private key must be accessible"
echo ""

# Check if Root CA exists
if [ ! -f "$ROOT_CA_DIR/certs/mannsclann-homelab-root-ca.crt" ]; then
    echo "ERROR: Root CA certificate not found!"
    echo "Please run create-root-ca.sh first."
    exit 1
fi

if [ ! -f "$ROOT_CA_DIR/private/mannsclann-homelab-root-ca.key" ]; then
    echo "ERROR: Root CA private key not found!"
    echo "Please ensure the Root CA has been created."
    exit 1
fi

echo "Root CA found. Proceeding..."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

# Create OpenSSL configuration for Intermediate CA
echo "Creating OpenSSL configuration..."
cat > "$INTERMEDIATE_CA_DIR/openssl.cnf" << 'EOF'
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

# Intermediate CA private key and certificate
private_key       = $dir/private/mannsclann-homelab-intermediate-ca.key
certificate       = $dir/certs/mannsclann-homelab-intermediate-ca.crt

# CRL settings
crlnumber         = $dir/crlnumber
crl               = $dir/crl/mannsclann-homelab-intermediate-ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30

# SHA-256 for signing
default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = 825
preserve          = no
policy            = policy_loose

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
commonName_default              = Mannsclann Homelab Intermediate CA

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
sed -i.bak "s|REPLACE_DIR|$INTERMEDIATE_CA_DIR|g" "$INTERMEDIATE_CA_DIR/openssl.cnf"
rm "$INTERMEDIATE_CA_DIR/openssl.cnf.bak"

# Initialize database files
echo "Initializing certificate database..."
touch "$INTERMEDIATE_CA_DIR/index.txt"
echo 1000 > "$INTERMEDIATE_CA_DIR/serial"
echo 1000 > "$INTERMEDIATE_CA_DIR/crlnumber"

# Generate Intermediate CA private key
echo ""
echo "Generating Intermediate CA private key (4096-bit RSA)..."
echo "You will be prompted to enter a passphrase for the Intermediate CA."
echo ""
openssl genrsa -aes256 -out "$INTERMEDIATE_CA_DIR/private/mannsclann-homelab-intermediate-ca.key" 4096
chmod 400 "$INTERMEDIATE_CA_DIR/private/mannsclann-homelab-intermediate-ca.key"

# Generate Intermediate CA CSR
echo ""
echo "Generating Intermediate CA Certificate Signing Request..."
echo "You will be prompted for the Intermediate CA passphrase and certificate details."
echo ""
openssl req -config "$INTERMEDIATE_CA_DIR/openssl.cnf" -new -sha256 \
    -key "$INTERMEDIATE_CA_DIR/private/mannsclann-homelab-intermediate-ca.key" \
    -out "$INTERMEDIATE_CA_DIR/csr/mannsclann-homelab-intermediate-ca.csr"

# Sign the Intermediate CA CSR with Root CA
echo ""
echo "Signing Intermediate CA certificate with Root CA..."
echo "You will be prompted for the ROOT CA passphrase."
echo ""
openssl ca -config "$ROOT_CA_DIR/openssl.cnf" -extensions v3_intermediate_ca \
    -days 3650 -notext -md sha256 \
    -in "$INTERMEDIATE_CA_DIR/csr/mannsclann-homelab-intermediate-ca.csr" \
    -out "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt"

chmod 444 "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt"

# Create certificate chain
echo ""
echo "Creating certificate chain..."
cat "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt" \
    "$ROOT_CA_DIR/certs/mannsclann-homelab-root-ca.crt" \
    > "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-ca-chain.crt"
chmod 444 "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-ca-chain.crt"

# Verify the certificate chain
echo ""
echo "Verifying certificate chain..."
openssl verify -CAfile "$ROOT_CA_DIR/certs/mannsclann-homelab-root-ca.crt" \
    "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt"

# Display certificate details
echo ""
echo "=========================================="
echo "Intermediate CA Certificate Details:"
echo "=========================================="
openssl x509 -noout -text -in "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt"

echo ""
echo "=========================================="
echo "Intermediate CA Creation Complete!"
echo "=========================================="
echo ""
echo "Files created:"
echo "  Private Key:  $INTERMEDIATE_CA_DIR/private/mannsclann-homelab-intermediate-ca.key"
echo "  Certificate:  $INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt"
echo "  CSR:          $INTERMEDIATE_CA_DIR/csr/mannsclann-homelab-intermediate-ca.csr"
echo "  Chain:        $INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-ca-chain.crt"
echo "  Config:       $INTERMEDIATE_CA_DIR/openssl.cnf"
echo ""
echo "IMPORTANT SECURITY NOTES:"
echo "  1. The Intermediate CA private key is ENCRYPTED with its passphrase"
echo "  2. Store this passphrase in a secure password manager (separate from Root CA)"
echo "  3. Back up the Intermediate CA private key (encrypted)"
echo "  4. This CA will be used for day-to-day certificate signing"
echo "  5. The certificate chain file contains both Intermediate + Root certificates"
echo "  6. You can now store the Root CA private key offline in a secure location"
echo ""
echo "Next steps:"
echo "  - Distribute mannsclann-homelab-root-ca.crt to all clients for trust"
echo "  - Use the Intermediate CA to sign server certificates"
echo ""
