#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="Rebecca-Dev"

# Check if already exists
if security find-identity -p codesigning -v 2>&1 | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists"
    security find-identity -p codesigning -v | grep "$CERT_NAME"
    exit 0
fi

echo "Creating self-signed code signing certificate: $CERT_NAME"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

P12_PASS="cu-dev-cert-$(date +%s)"

# Generate self-signed certificate with code signing extended key usage
openssl req -new -newkey rsa:2048 -x509 \
    -keyout "$TEMP_DIR/key.pem" \
    -out "$TEMP_DIR/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=$CERT_NAME" \
    -addext "extendedKeyUsage=codeSigning"

# Convert to p12 with non-empty password
openssl pkcs12 -export \
    -out "$TEMP_DIR/cert.p12" \
    -inkey "$TEMP_DIR/key.pem" \
    -in "$TEMP_DIR/cert.pem" \
    -passout "pass:$P12_PASS"

# Import to login keychain
security import "$TEMP_DIR/cert.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign

# Trust the certificate
security add-trusted-cert -d -r trustRoot \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    "$TEMP_DIR/cert.pem"

echo "Certificate '$CERT_NAME' created and trusted for code signing"
