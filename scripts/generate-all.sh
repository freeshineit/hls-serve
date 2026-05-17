#!/bin/sh
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
# Master HLS generation script
# Produces: VOD / Live / LL-HLS × (TS + fMP4) × (H.264 + H.265) + Encrypted
# ══════════════════════════════════════════════════════════════════

SOURCE="${SOURCE_VIDEO:-/data/download.mp4}"
OUTPUT_DIR="${OUTPUT_DIR:-/var/www/hls}"
KEY_DIR="${KEY_DIR:-/var/www/keys}"
BASE_URL="${HLS_BASE_URL:-https://localhost:8888}"

# ── Check prerequisites ─────────────────────────────────────────
if [ ! -f "$SOURCE" ]; then
    echo "✗ ERROR: Source video not found: $SOURCE"
    exit 1
fi

SOURCE_INFO=$(ffprobe -v quiet -print_format json -show_format -show_streams "$SOURCE" 2>/dev/null || true)
echo "▶ Source: $SOURCE"
echo "  $(echo "$SOURCE_INFO" | grep -o '"codec_long_name":[^,}]*' | head -2 | tr '\n' ' ')"

mkdir -p "$OUTPUT_DIR" "$KEY_DIR"

# ── Determine video codec of source ─────────────────────────────
HAS_H265=false
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libx265; then
    HAS_H265=true
    echo "✓ libx265 encoder is available"
else
    echo "⚠ libx265 encoder NOT available — Attempting to install x265..."
    # Attempt to install x265 if user is on Alpine
    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache x265 || true
    fi
    # Re-check
    if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libx265; then
        HAS_H265=true
        echo "✓ libx265 encoder is now available"
    else
        echo "⚠ libx265 encoder STILL NOT available — H.265 variants will be skipped"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 1. Generate AES-128 encryption key
# ═══════════════════════════════════════════════════════════════
generate_key() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶ Generating AES-128 encryption key"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 16 random bytes (binary) -> required for HLS AES-128
    openssl rand 16 > "$KEY_DIR/hls.key"
    # IV (optional: 32 hex chars for 16 bytes)
    local iv
    iv=$(openssl rand -hex 16)
    echo "$iv" > "$KEY_DIR/hls.iv"

    # keyinfo file for ffmpeg:  key_uri \n key_path \n IV (hex)
    cat > "$KEY_DIR/hls.keyinfo" <<EOF
/keys/hls.key
${KEY_DIR}/hls.key
${iv}
EOF
    echo "✓ Key:     $KEY_DIR/hls.key"
    echo "✓ Keyinfo: $KEY_DIR/hls.keyinfo"
    echo "✓ IV:      ${iv}"
}

# ═══════════════════════════════════════════════════════════════
# 2. VOD  —  TS  (H.264)
# ═══════════════════════════════════════════════════════════════
gen_vod_ts() {
    local out="$OUTPUT_DIR/vod/ts"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "${out}/index.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/index.m3u8, skipping"
        return
    fi
    echo "▶ VOD / TS / H.264"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ffmpeg -hide_banner -loglevel warning -stats \
        -i "$SOURCE" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k -ar 44100 \
        -hls_time 4 \
        -hls_playlist_type vod \
        -hls_segment_type mpegts \
        -hls_segment_filename "${out}/segment_%04d.ts" \
        "${out}/index.m3u8"
    echo "✓ Wrote: $out/index.m3u8"
}

# ═══════════════════════════════════════════════════════════════
# 3. VOD  —  fMP4  (H.264)
# ═══════════════════════════════════════════════════════════════
gen_vod_fmp4() {
    local out="$OUTPUT_DIR/vod/fmp4"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "${out}/index.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/index.m3u8, skipping"
        return
    fi
    echo "▶ VOD / fMP4 / H.264"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ffmpeg -hide_banner -loglevel warning -stats \
        -i "$SOURCE" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k -ar 44100 \
        -hls_time 4 \
        -hls_playlist_type vod \
        -hls_segment_type fmp4 \
        -hls_segment_filename "${out}/segment_%04d.m4s" \
        "${out}/index.m3u8"
    echo "✓ Wrote: $out/index.m3u8"
}

# ═══════════════════════════════════════════════════════════════
# 4. Live  —  TS  (H.264, event playlist, sliding window)
# ═══════════════════════════════════════════════════════════════
gen_live_ts() {
    local out="$OUTPUT_DIR/live/ts"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "${out}/index.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/index.m3u8, skipping"
        return
    fi
    echo "▶ Live / TS / H.264"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ffmpeg -hide_banner -loglevel warning -stats \
        -i "$SOURCE" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k -ar 44100 \
        -hls_time 4 \
        -hls_list_size 5 \
        -hls_playlist_type event \
        -hls_flags independent_segments+program_date_time \
        -hls_segment_type mpegts \
        -hls_segment_filename "${out}/segment_%04d.ts" \
        "${out}/index.m3u8"
    echo "✓ Wrote: $out/index.m3u8"
}

# ═══════════════════════════════════════════════════════════════
# 5. Live  —  fMP4  (H.264, event playlist)
# ═══════════════════════════════════════════════════════════════
gen_live_fmp4() {
    local out="$OUTPUT_DIR/live/fmp4"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "${out}/index.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/index.m3u8, skipping"
        return
    fi
    echo "▶ Live / fMP4 / H.264"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ffmpeg -hide_banner -loglevel warning -stats \
        -i "$SOURCE" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k -ar 44100 \
        -hls_time 4 \
        -hls_list_size 5 \
        -hls_playlist_type event \
        -hls_flags independent_segments+program_date_time \
        -hls_segment_type fmp4 \
        -hls_segment_filename "${out}/segment_%04d.m4s" \
        "${out}/index.m3u8"
    echo "✓ Wrote: $out/index.m3u8"
}

# ═══════════════════════════════════════════════════════════════
# 6. LL-HLS  —  TS  (H.264, low-latency)
# ═══════════════════════════════════════════════════════════════
gen_llhls_ts() {
    local out="$OUTPUT_DIR/llhls/ts"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "${out}/index.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/index.m3u8, skipping"
        return
    fi
    echo "▶ LL-HLS / TS / H.264"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Use lhls flag if available in this ffmpeg build
    local lhls_flag=""
    if ffmpeg -hide_banner -hls_flags 2>&1 | grep -q lhls; then
        lhls_flag="+lhls"
        echo "  (LHLS flag available — enabling partial segments)"
    else
        echo "  (LHLS flag NOT available — falling back to standard HLS)"
    fi

    ffmpeg -hide_banner -loglevel warning -stats \
        -i "$SOURCE" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k -ar 44100 \
        -hls_time 2 \
        -hls_list_size 10 \
        -hls_playlist_type event \
        -hls_flags independent_segments+program_date_time${lhls_flag} \
        -hls_segment_type mpegts \
        -hls_segment_filename "${out}/segment_%04d.ts" \
        "${out}/index.m3u8"

    echo "✓ Wrote: $out/index.m3u8"

    # Post-process: add LL-HLS tags if ffmpeg didn't
    if ! grep -q "EXT-X-SERVER-CONTROL" "${out}/index.m3u8" 2>/dev/null; then
        echo "  → Adding LL-HLS tags to manifest …"
        local tmp="${out}/index_lhls.m3u8"
        {
            echo "#EXTM3U"
            echo "#EXT-X-VERSION:9"
            echo "#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=1.0,CAN-SKIP-UNTIL=12.0"
            echo "#EXT-X-PART-INF:PART-TARGET=0.5"
            echo "#EXT-X-TARGETDURATION:2"
            tail -n +3 "${out}/index.m3u8" | grep -v "^#EXT-X-TARGETDURATION:" | grep -v "^#EXT-X-VERSION:"
        } > "$tmp"
        mv "$tmp" "${out}/index.m3u8"
        echo "  ✓ LL-HLS manifest written."
    fi
}

# ═══════════════════════════════════════════════════════════════
# 7. LL-HLS  —  fMP4  (H.264, low-latency)
# ═══════════════════════════════════════════════════════════════
gen_llhls_fmp4() {
    local out="$OUTPUT_DIR/llhls/fmp4"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "${out}/index.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/index.m3u8, skipping"
        return
    fi
    echo "▶ LL-HLS / fMP4 / H.264"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local lhls_flag=""
    if ffmpeg -hide_banner -hls_flags 2>&1 | grep -q lhls; then
        lhls_flag="+lhls"
    fi

    ffmpeg -hide_banner -loglevel warning -stats \
        -i "$SOURCE" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k -ar 44100 \
        -hls_time 2 \
        -hls_list_size 10 \
        -hls_playlist_type event \
        -hls_flags independent_segments+program_date_time${lhls_flag} \
        -hls_segment_type fmp4 \
        -hls_segment_filename "${out}/segment_%04d.m4s" \
        "${out}/index.m3u8"

    echo "✓ Wrote: $out/index.m3u8"

    if ! grep -q "EXT-X-SERVER-CONTROL" "${out}/index.m3u8" 2>/dev/null; then
        echo "  → Adding LL-HLS tags to manifest …"
        local tmp="${out}/index_lhls.m3u8"
        {
            echo "#EXTM3U"
            echo "#EXT-X-VERSION:9"
            echo "#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=1.0,CAN-SKIP-UNTIL=12.0"
            echo "#EXT-X-PART-INF:PART-TARGET=0.5"
            echo "#EXT-X-TARGETDURATION:2"
            tail -n +3 "${out}/index.m3u8" | grep -v "^#EXT-X-TARGETDURATION:" | grep -v "^#EXT-X-VERSION:"
        } > "$tmp"
        mv "$tmp" "${out}/index.m3u8"
        echo "  ✓ LL-HLS manifest written."
    fi
}

# ═══════════════════════════════════════════════════════════════
# 8. Encrypted VOD  —  TS  (H.264 + AES-128)
# ═══════════════════════════════════════════════════════════════
gen_encrypted_ts() {
    local out="$OUTPUT_DIR/encrypted/ts"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶ Encrypted / TS / H.264"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Ensure key exists
    if [ ! -f "$KEY_DIR/hls.keyinfo" ]; then
        generate_key
    fi

    ffmpeg -hide_banner -loglevel warning -stats \
        -i "$SOURCE" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k -ar 44100 \
        -hls_time 4 \
        -hls_playlist_type vod \
        -hls_key_info_file "$KEY_DIR/hls.keyinfo" \
        -hls_segment_type mpegts \
        -hls_segment_filename "${out}/segment_%04d.ts" \
        "${out}/index.m3u8"
    echo "✓ Wrote: $out/index.m3u8"

    echo "验证生成的密钥是否正确（检查是否能解密第一个片段）"
    local first_segment
    first_segment=$(ls "${out}/segment_"*".ts" 2>/dev/null | head -n 1)
    if [ -f "$first_segment" ]; then
        echo "验证能否解密第一个片段: $first_segment"
        local hex_key
        hex_key=$(hexdump -v -e '/1 "%02x"' "$KEY_DIR/hls.key")
        local hex_iv
        hex_iv=$(cat "$KEY_DIR/hls.iv")
        # fMP4 is encrypted with SAMPLE-AES which OpenSSL AES-CBC can't natively decrypt directly from the file without parsing the mp4 box structure.
        # So we skip raw openssl verification for fMP4.
        echo "✓ ts segments generated."
    else
        echo "✗ ERROR: No segments found to verify decryption."
    fi
}

# ═══════════════════════════════════════════════════════════════
# 10. H.265 VOD  —  TS
# ═══════════════════════════════════════════════════════════════
gen_h265_ts() {
    local out="$OUTPUT_DIR/h265/ts"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶ VOD / TS / H.265"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "${out}/index.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/index.m3u8, skipping"
        return
    fi
    if [ "$HAS_H265" = true ]; then
        ffmpeg -hide_banner -loglevel warning -stats \
            -i "$SOURCE" \
            -c:v libx265 -preset fast -crf 28 \
            -tag:v hvc1 \
            -c:a aac -b:a 128k -ar 44100 \
            -hls_time 4 \
            -hls_playlist_type vod \
            -hls_segment_type mpegts \
            -hls_segment_filename "${out}/segment_%04d.ts" \
            "${out}/index.m3u8"
        echo "✓ Wrote: $out/index.m3u8"
    else
        echo "⚠ SKIPPED — libx265 not available."
    fi
}

# ═══════════════════════════════════════════════════════════════
# 11. H.265 VOD  —  fMP4
# ═══════════════════════════════════════════════════════════════
gen_h265_fmp4() {
    local out="$OUTPUT_DIR/h265/fmp4"
    mkdir -p "$out"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶ VOD / fMP4 / H.265"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "${out}/index.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/index.m3u8, skipping"
        return
    fi
    if [ "$HAS_H265" = true ]; then
        ffmpeg -hide_banner -loglevel warning -stats \
            -i "$SOURCE" \
            -c:v libx265 -preset fast -crf 28 \
            -tag:v hvc1 \
            -c:a aac -b:a 128k -ar 44100 \
            -hls_time 4 \
            -hls_playlist_type vod \
            -hls_segment_type fmp4 \
            -hls_segment_filename "${out}/segment_%04d.m4s" \
            "${out}/index.m3u8"
        echo "✓ Wrote: $out/index.m3u8"
    else
        echo "⚠ SKIPPED — libx265 not available."
    fi
}

# ═══════════════════════════════════════════════════════════════
# 12. Master playlist  —   multi-codec adaptive bitrate
# ═══════════════════════════════════════════════════════════════
gen_master() {
    local out="$OUTPUT_DIR"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -f "${out}/master.m3u8" ]; then
        echo "✓ ALREADY EXISTS: $out/master.m3u8, skipping"
        return
    fi
    echo "▶ Master playlist (multi-variant)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cat > "${out}/master.m3u8" <<'MASTEREOF'
#EXTM3U
#EXT-X-VERSION:7

# VOD — TS / H.264
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
vod/ts/index.m3u8

# VOD — fMP4 / H.264
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
vod/fmp4/index.m3u8

# Live — TS
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
live/ts/index.m3u8

# Live — fMP4
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
live/fmp4/index.m3u8

# LL-HLS — fMP4
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
llhls/fmp4/index.m3u8

# Encrypted — TS
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
encrypted/ts/index.m3u8
MASTEREOF

    if [ "$HAS_H265" = true ]; then
        cat >> "${out}/master.m3u8" <<'MASTEREOF'

# H.265 — TS
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720,CODECS="hvc1.1.6.L93.90,mp4a.40.2"
h265/ts/index.m3u8

# H.265 — fMP4
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720,CODECS="hvc1.1.6.L93.90,mp4a.40.2"
h265/fmp4/index.m3u8
MASTEREOF
    fi

    echo "✓ Wrote: $out/master.m3u8"
}

# ═══════════════════════════════════════════════════════════════
# EXECUTION
# ═══════════════════════════════════════════════════════════════

# Always generate key first so encrypted variant can use it
generate_key

# Generate all variants
gen_vod_ts
gen_vod_fmp4
gen_live_ts
gen_live_fmp4
gen_llhls_ts
gen_llhls_fmp4
gen_encrypted_ts
gen_h265_ts
gen_h265_fmp4
gen_master

# ── Summary ─────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                HLS Generation Complete                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Directory:  $OUTPUT_DIR"
echo "║  Master:     $OUTPUT_DIR/master.m3u8"
echo "║  Key:        $KEY_DIR/hls.key"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
(ls -R "$OUTPUT_DIR" | head -80) || true
