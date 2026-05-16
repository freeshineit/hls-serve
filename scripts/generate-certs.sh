#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
# Generate self-signed SSL certificates for local HTTPS + HTTP/2
# ══════════════════════════════════════════════════════════════════

CERT_DIR="${CERT_DIR:-/etc/nginx/certs}"
CERT_FILE="${CERT_DIR}/server.crt"
KEY_FILE="${CERT_DIR}/server.key"
DAYS_VALID="${CERT_DAYS:-3650}"

mkdir -p "$CERT_DIR"

# ── Generate a self-signed certificate ─────────────────────────
openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days "$DAYS_VALID" \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=HLS-Serve/OU=Dev/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

# ── Set permissions ────────────────────────────────────────────
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo "✓ Certificate: $CERT_FILE"
echo "✓ Private key: $KEY_FILE"
echo "✓ Valid for:   $DAYS_VALID days"
echo ""
echo "  SHA256 fingerprint:"
openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256 | sed 's/^/    /'
