FROM nginx:alpine

LABEL maintainer="hls-serve"
LABEL description="HLS Streaming Server with Nginx + FFmpeg (HLS/VOD/Live/LL-HLS/TS/fMP4/H.264/H.265/Encryption)"

# Install ffmpeg + openssl on Alpine (much faster than Debian)
RUN apk add --no-cache \
    ffmpeg \
    openssl \
    curl \
    ca-certificates \
    && mkdir -p /var/www/hls \
    && mkdir -p /var/www/web \
    && mkdir -p /var/www/keys \
    && mkdir -p /etc/nginx/certs \
    && mkdir -p /data

# Remove default nginx config
RUN rm -f /etc/nginx/http.d/default.conf 2>/dev/null || true \
    && rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true

# Copy configuration
COPY conf/nginx.conf /etc/nginx/nginx.conf

# Copy scripts
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Copy web assets
COPY web/ /var/www/web/

# Copy source video
COPY download.mp4 /data/download.mp4

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -k -f https://localhost/ || exit 1

ENTRYPOINT ["entrypoint.sh"]
