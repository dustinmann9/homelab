#!/bin/bash

# generate-server-cert.sh
# Generate SSL/TLS server certificate signed by Mannsclann Homelab Intermediate CA
#
# Usage: ./generate-server-cert.sh <service-name> <common-name> <ip-address> [additional-sans]
#
# Arguments:
#   service-name    : Name for the service directory (e.g., webserver, proxmox)
#   common-name     : Primary domain name (e.g., server.local, proxmox.home)
#   ip-address      : IP address of the server (e.g., 192.168.10.2)
#   additional-sans : Optional additional SANs, comma-separated (e.g., "www.local,api.local")
#
# Example: ./generate-server-cert.sh webserver server.local 192.168.10.2
# Example: ./generate-server-cert.sh webserver server.local 192.168.10.2 "www.local,api.local"

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_DIR/certs"
INTERMEDIATE_CA_DIR="$CERTS_DIR/intermediate-ca"
SERVICES_DIR="$CERTS_DIR/services"

# Check arguments
if [ $# -lt 3 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo "Usage: $0 <service-name> <common-name> <ip-address> [additional-sans]"
    echo "Example: $0 webserver server.local 192.168.10.2"
    exit 1
fi

SERVICE_NAME="$1"
COMMON_NAME="$2"
IP_ADDRESS="$3"
ADDITIONAL_SANS="${4:-}"

# Extract short hostname from common name (everything before first dot)
SHORT_HOSTNAME="${COMMON_NAME%%.*}"

# Service directory
SERVICE_DIR="$SERVICES_DIR/$SERVICE_NAME"

# Certificate parameters
COUNTRY="US"
STATE="WA"
LOCALITY="Issaquah"
ORGANIZATION="Mannsclann Homelab"
OU="Technology Services"
EMAIL="dustin.mann9@gmail.com"
VALIDITY_DAYS=825  # Maximum allowed by modern standards

echo -e "${GREEN}=== Mannsclann Homelab Server Certificate Generator ===${NC}"
echo ""
echo "Service Name:     $SERVICE_NAME"
echo "Common Name:      $COMMON_NAME"
echo "Short Hostname:   $SHORT_HOSTNAME"
echo "IP Address:       $IP_ADDRESS"
echo "Organization:     $ORGANIZATION"
echo "Validity:         $VALIDITY_DAYS days"
echo ""

# Check if intermediate CA exists
if [ ! -f "$INTERMEDIATE_CA_DIR/private/mannsclann-homelab-intermediate-ca.key" ]; then
    echo -e "${RED}Error: Intermediate CA private key not found${NC}"
    echo "Expected location: $INTERMEDIATE_CA_DIR/private/mannsclann-homelab-intermediate-ca.key"
    exit 1
fi

if [ ! -f "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt" ]; then
    echo -e "${RED}Error: Intermediate CA certificate not found${NC}"
    echo "Expected location: $INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt"
    exit 1
fi

# Create service directory
echo -e "${YELLOW}Creating service directory...${NC}"
mkdir -p "$SERVICE_DIR"

# Generate private key
echo -e "${YELLOW}Generating private key...${NC}"
openssl genrsa -out "$SERVICE_DIR/${SERVICE_NAME}.key" 2048
chmod 600 "$SERVICE_DIR/${SERVICE_NAME}.key"
echo -e "${GREEN}✓ Private key created: $SERVICE_DIR/${SERVICE_NAME}.key${NC}"

# Build Subject Alternative Names
SAN="DNS:$COMMON_NAME"
if [ "$SHORT_HOSTNAME" != "$COMMON_NAME" ]; then
    SAN="$SAN,DNS:$SHORT_HOSTNAME"
fi
SAN="$SAN,IP:$IP_ADDRESS"

# Add additional SANs if provided
if [ -n "$ADDITIONAL_SANS" ]; then
    # Split comma-separated SANs and add them
    IFS=',' read -ra SANS <<< "$ADDITIONAL_SANS"
    for san in "${SANS[@]}"; do
        san=$(echo "$san" | xargs)  # Trim whitespace
        if [[ "$san" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            SAN="$SAN,IP:$san"
        else
            SAN="$SAN,DNS:$san"
        fi
    done
fi

echo "Subject Alternative Names: $SAN"

# Create CSR configuration
CSR_CONFIG="$SERVICE_DIR/${SERVICE_NAME}.cnf"
cat > "$CSR_CONFIG" <<EOF
[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
req_extensions      = v3_req

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = $COUNTRY
stateOrProvinceName_default     = $STATE
localityName_default            = $LOCALITY
0.organizationName_default      = $ORGANIZATION
organizationalUnitName_default  = $OU
emailAddress_default            = $EMAIL

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
EOF

# Add SANs to config file
IFS=',' read -ra SAN_ARRAY <<< "$SAN"
DNS_INDEX=1
IP_INDEX=1
for san in "${SAN_ARRAY[@]}"; do
    if [[ "$san" =~ ^DNS: ]]; then
        echo "DNS.$DNS_INDEX = ${san#DNS:}" >> "$CSR_CONFIG"
        DNS_INDEX=$((DNS_INDEX + 1))
    elif [[ "$san" =~ ^IP: ]]; then
        echo "IP.$IP_INDEX = ${san#IP:}" >> "$CSR_CONFIG"
        IP_INDEX=$((IP_INDEX + 1))
    fi
done

# Create CSR
echo -e "${YELLOW}Creating Certificate Signing Request...${NC}"
openssl req -new \
    -key "$SERVICE_DIR/${SERVICE_NAME}.key" \
    -out "$SERVICE_DIR/${SERVICE_NAME}.csr" \
    -config "$CSR_CONFIG" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$OU/CN=$COMMON_NAME/emailAddress=$EMAIL"
echo -e "${GREEN}✓ CSR created: $SERVICE_DIR/${SERVICE_NAME}.csr${NC}"

# Sign the certificate with Intermediate CA
echo -e "${YELLOW}Signing certificate with Intermediate CA...${NC}"
echo -e "${YELLOW}(You may be prompted for the Intermediate CA passphrase)${NC}"

# Change to intermediate CA directory for signing
cd "$INTERMEDIATE_CA_DIR"

openssl ca \
    -batch \
    -config openssl.cnf \
    -extensions server_cert \
    -days $VALIDITY_DAYS \
    -notext \
    -md sha256 \
    -in "$SERVICE_DIR/${SERVICE_NAME}.csr" \
    -out "$SERVICE_DIR/${SERVICE_NAME}.crt" \
    -extfile "$CSR_CONFIG" \
    -extensions v3_req

echo -e "${GREEN}✓ Certificate signed: $SERVICE_DIR/${SERVICE_NAME}.crt${NC}"

# Create certificate chain (server cert + intermediate + root)
echo -e "${YELLOW}Creating certificate chain...${NC}"

cat "$SERVICE_DIR/${SERVICE_NAME}.crt" \
    "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt" \
    "$CERTS_DIR/root-ca/certs/mannsclann-homelab-root-ca.crt" \
    > "$SERVICE_DIR/${SERVICE_NAME}-fullchain.crt"

echo -e "${GREEN}✓ Full chain created: $SERVICE_DIR/${SERVICE_NAME}-fullchain.crt${NC}"

# Create chain without root CA (intermediate only)
cat "$SERVICE_DIR/${SERVICE_NAME}.crt" \
    "$INTERMEDIATE_CA_DIR/certs/mannsclann-homelab-intermediate-ca.crt" \
    > "$SERVICE_DIR/${SERVICE_NAME}-chain.crt"

echo -e "${GREEN}✓ Chain created: $SERVICE_DIR/${SERVICE_NAME}-chain.crt${NC}"

# Display certificate information
echo ""
echo -e "${GREEN}=== Certificate Details ===${NC}"
openssl x509 -in "$SERVICE_DIR/${SERVICE_NAME}.crt" -noout -text | grep -A 2 "Subject:"
openssl x509 -in "$SERVICE_DIR/${SERVICE_NAME}.crt" -noout -text | grep -A 5 "X509v3 Subject Alternative Name"
openssl x509 -in "$SERVICE_DIR/${SERVICE_NAME}.crt" -noout -dates

# Summary
echo ""
echo -e "${GREEN}=== Certificate Generation Complete! ===${NC}"
echo ""
echo "Certificate files created in: $SERVICE_DIR"
echo ""
echo "Files:"
echo "  • Private Key:       ${SERVICE_NAME}.key"
echo "  • Certificate:       ${SERVICE_NAME}.crt"
echo "  • Chain (+ int):     ${SERVICE_NAME}-chain.crt"
echo "  • Full chain (all):  ${SERVICE_NAME}-fullchain.crt"
echo "  • CSR:               ${SERVICE_NAME}.csr"
echo "  • Config:            ${SERVICE_NAME}.cnf"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Copy ${SERVICE_NAME}.key and ${SERVICE_NAME}-chain.crt to your server"
echo "  2. Configure your web server to use these files"
echo "  3. Restart your web server"
echo ""
echo -e "${YELLOW}Server Configuration Examples:${NC}"
echo ""
echo "  Apache:"
echo "    SSLCertificateFile      /path/to/${SERVICE_NAME}-chain.crt"
echo "    SSLCertificateKeyFile   /path/to/${SERVICE_NAME}.key"
echo ""
echo "  Nginx:"
echo "    ssl_certificate         /path/to/${SERVICE_NAME}-chain.crt;"
echo "    ssl_certificate_key     /path/to/${SERVICE_NAME}.key;"
echo ""
echo "  Proxmox:"
echo "    cat ${SERVICE_NAME}.key ${SERVICE_NAME}-chain.crt > /etc/pve/local/pveproxy-ssl.pem"
echo "    systemctl restart pveproxy"
echo ""
