#!/bin/sh
set -euo pipefail

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           HLS Streaming Server  —  starting up              ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# ── Generate self-signed certificates ──────────────────────────
if [ ! -f /etc/nginx/certs/server.crt ] || [ ! -f /etc/nginx/certs/server.key ]; then
    echo ""
    echo "▶ Generating self-signed SSL certificates …"
    generate-certs.sh
else
    echo ""
    echo "✓ SSL certificates already exist, skipping generation."
fi

# ── Generate HLS content ───────────────────────────────────────
echo ""
echo "▶ HLS content not found — generating all variants …"
echo "  (this may take a few minutes depending on video length)"
generate-all.sh
touch /var/www/hls/.generated
echo ""
echo "✓ HLS generation complete."


# ── Verify critical files exist ────────────────────────────────
echo ""
echo "▶ Verifying HLS structure …"
for f in "/var/www/hls/vod/ts/index.m3u8" "/var/www/hls/vod/fmp4/index.m3u8"; do
    if [ -f "$f" ]; then
        echo "  ✓ $f"
    else
        echo "  ✗ MISSING: $f"
    fi
done

# ── Print summary ──────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Server is ready!                                           ║"
echo "║                                                            ║"
echo "║  Demo page:  https://localhost:8888/                       ║"
echo "║  HLS root:   https://localhost:8888/hls/                   ║"
echo "║  Health:     https://localhost:8888/health                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Start Nginx ────────────────────────────────────────────────
exec nginx -g "daemon off;"
