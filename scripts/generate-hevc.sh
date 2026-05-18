#!/bin/bash

# Ensure directories exist
mkdir -p hls/h265/fmp4
mkdir -p hls/h265/ts
mkdir -p hls/llhls-hevc/fmp4
mkdir -p hls/llhls-hevc/ts

INPUT="hevc.mp4"

if [ ! -f "$INPUT" ]; then
    echo "Error: Input file $INPUT not found."
    exit 1
fi

echo "1. Generating HLS TS for H265..."
ffmpeg -y -i $INPUT \
  -c:v copy -c:a copy \
  -f hls \
  -hls_time 10 \
  -hls_playlist_type vod \
  -hls_segment_filename "hls/h265/ts/segment_%04d.ts" \
  hls/h265/ts/index.m3u8

echo "2. Generating HLS fMP4 for H265..."
ffmpeg -y -i $INPUT \
  -c:v copy -c:a copy \
  -f hls \
  -hls_time 4 \
  -hls_playlist_type vod \
  -hls_segment_type fmp4 \
  -hls_segment_filename "hls/h265/fmp4/segment_%04d.m4s" \
  hls/h265/fmp4/index.m3u8

echo "3. Generating LL-HLS fMP4 for HEVC..."
ffmpeg -y -i $INPUT \
  -c:v copy -c:a copy \
  -f hls \
  -hls_time 2 \
  -hls_playlist_type event \
  -hls_segment_type fmp4 \
  -hls_flags independent_segments+split_by_time \
  -hls_segment_filename "hls/llhls-hevc/fmp4/segment_%04d.m4s" \
  hls/llhls-hevc/fmp4/index.m3u8

echo "4. Generating LL-HLS TS for HEVC..."
ffmpeg -y -i $INPUT \
  -c:v copy -c:a copy \
  -f hls \
  -hls_time 2 \
  -hls_playlist_type event \
  -hls_flags independent_segments+split_by_time \
  -hls_segment_filename "hls/llhls-hevc/ts/segment_%04d.ts" \
  hls/llhls-hevc/ts/index.m3u8

echo "Done!"
