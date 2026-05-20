#!/bin/bash

# Ensure directories exist
mkdir -p hls/h265/fmp4
mkdir -p hls/h265/ts
mkdir -p hls/h265/cmaf
mkdir -p hls/llhls-hevc/fmp4
mkdir -p hls/llhls-hevc/ts
mkdir -p hls/llhls-hevc/cmaf

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

echo "2.5. Generating CMAF for H265..."
ffmpeg -y -i $INPUT \
  -map 0:v -map 0:a? -c:v copy -c:a copy \
  -f dash \
  -hls_playlist 1 \
  -seg_duration 4 \
  -window_size 0 \
  hls/h265/cmaf/manifest.mpd

if [ -f "hls/h265/cmaf/media_0.m3u8" ]; then
    mv hls/h265/cmaf/media_0.m3u8 hls/h265/cmaf/index.m3u8
fi

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

echo "3.5. Generating LL-HLS CMAF for HEVC..."
ffmpeg -y -i $INPUT \
  -map 0:v -map 0:a? -c:v copy -c:a copy \
  -f dash \
  -hls_playlist 1 \
  -seg_duration 2 \
  -frag_duration 0.5 \
  -window_size 10 \
  -extra_window_size 5 \
  -ldash 1 \
  hls/llhls-hevc/cmaf/manifest.mpd

if [ -f "hls/llhls-hevc/cmaf/media_0.m3u8" ]; then
    mv hls/llhls-hevc/cmaf/media_0.m3u8 hls/llhls-hevc/cmaf/index.m3u8
fi

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
