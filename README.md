# HLS Streaming Server

基于 **Docker + Nginx + FFmpeg** 的全功能 HLS 流媒体服务器。

## 功能矩阵

| 功能 | 支持 |
|------|------|
| **HLS VOD** (点播) | ✅ TS + fMP4 |
| **HLS Live** (直播/Event) | ✅ TS + fMP4，滑动窗口 |
| **LL-HLS** (低延迟) | ✅ TS + fMP4，HTTP/2 阻塞重载 |
| **H.264** 编码 | ✅ 所有变体 |
| **H.265 / HEVC** 编码 | ✅ TS + fMP4（需 libx265） |
| **AES-128 加密** | ✅ 完整加密/解密支持 |
| **HTTPS + HTTP/2** | ✅ 自签名证书，本地可信 |
| **CORS 跨域** | ✅ 所有 HLS 资源 |
| **Web 演示页** | ✅ HLS.js 内嵌播放器 |
| **Docker 部署** | ✅ 一键启动 |

## 快速开始

### 前置要求

- Docker 20.10+
- Docker Compose 2.0+
- 至少 2GB 可用磁盘空间

### 1. 启动服务

```bash
cd hls-serve
docker-compose up -d --build
```

首次启动会自动：
1. 生成自签名 SSL 证书
2. 使用 FFmpeg 从 `download.mp4` 生成所有 HLS 变体
3. 启动 Nginx（监听 80/443 端口）

> ⚠️ 首次生成 HLS 内容需要 **3-8 分钟**（取决于视频长度和 H.265 编码性能）。后续重启直接使用已生成的内容。

### 2. 访问

打开浏览器访问 **https://localhost:8888/** （忽略证书警告）

```
https://localhost:8888/                  → Web 演示页
https://localhost:8888/hls/              → HLS 内容根目录
https://localhost:8888/hls/master.m3u8   → 多码率主播放列表
https://localhost:8888/health            → 健康检查
```

### 3. 停止

```bash
docker-compose down
```

## 目录结构

```
hls-serve/
├── Dockerfile                  # Docker 镜像定义
├── docker-compose.yml          # 服务编排
├── download.mp4                # 源视频文件
├── conf/
│   └── nginx.conf              # Nginx 配置（HTTP/2 + CORS + SSL）
├── scripts/
│   ├── entrypoint.sh           # 容器启动脚本
│   ├── generate-certs.sh       # 自签名证书生成
│   └── generate-all.sh         # HLS 全量生成脚本
├── web/
│   └── index.html              # 演示页面（HLS.js 播放器）
├── docs/
│   └── encryption.md           # HLS 加密文档
├── hls/                        # [生成] HLS 分段输出目录
├── keys/                       # [生成] AES-128 密钥
└── certs/                      # [生成] SSL 证书
```

## HLS 流地址列表

### VOD (点播)

| 描述 | 地址 |
|------|------|
| VOD · TS · H.264 | `/hls/vod/ts/index.m3u8` |
| VOD · fMP4 · H.264 | `/hls/vod/fmp4/index.m3u8` |

### Live (Event Playlist, 滑动窗口)

| 描述 | 地址 |
|------|------|
| Live · TS · H.264 | `/hls/live/ts/index.m3u8` |
| Live · fMP4 · H.264 | `/hls/live/fmp4/index.m3u8` |

### LL-HLS (低延迟)

| 描述 | 地址 |
|------|------|
| LL-HLS · TS · H.264 | `/hls/llhls/ts/index.m3u8` |
| LL-HLS · fMP4 · H.264 | `/hls/llhls/fmp4/index.m3u8` |

> LL-HLS 使用 2 秒分段 + HTTP/2 阻塞播放列表重载实现低延迟。

### H.265 / HEVC

| 描述 | 地址 |
|------|------|
| VOD · TS · H.265 | `/hls/h265/ts/index.m3u8` |
| VOD · fMP4 · H.265 | `/hls/h265/fmp4/index.m3u8` |

> 需要 Docker 镜像中的 FFmpeg 包含 libx265 编码器。若不可用则自动跳过。

### 加密 (AES-128)

| 描述 | 地址 |
|------|------|
| Encrypted · TS · H.264 | `/hls/encrypted/ts/index.m3u8` |

> 密钥地址: `/keys/hls.key` | 加密文档: [docs/encryption.md](docs/encryption.md)

### 主播放列表

| 描述 | 地址 |
|------|------|
| 多码率 Master | `/hls/master.m3u8` |

## 技术架构

```
┌─────────────────────────────────────────────────────┐
│                   Docker Container                   │
│                                                     │
│  ┌──────────┐    ┌──────────────┐    ┌───────────┐  │
│  │  FFmpeg  │───▶│  HLS Segments │───▶│  Nginx    │  │
│  │  Encoder │    │  (TS / fMP4)  │    │  HTTP/2   │  │
│  └──────────┘    └──────────────┘    └───────────┘  │
│                                            │        │
│       ┌──────────┐                        │        │
│       │  OpenSSL │──▶ TLS Cert ──────────▶│        │
│       └──────────┘                        │        │
│                                           ▼        │
│                              ┌───────────────────┐  │
│                              │  :443  HTTPS+HTTP/2│  │
│                              │  :80   → redirect  │  │
│                              └───────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## 配置说明

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HLS_BASE_URL` | `https://localhost:8888` | 用于加密密钥 URI |
| `SOURCE_VIDEO` | `/data/download.mp4` | 源视频路径 |
| `OUTPUT_DIR` | `/var/www/hls` | HLS 输出目录 |
| `KEY_DIR` | `/var/www/keys` | 密钥输出目录 |
| `CERT_DAYS` | `3650` | 证书有效期（天） |

### Nginx 配置

Nginx 配置位于 `conf/nginx.conf`，支持：

- **TLS 1.2 / 1.3**
- **HTTP/2** (`listen 443 ssl http2`)
- **服务端口**: `8888` (映射到容器 `443`)
- **CORS** 全局启用
- **HLS 缓存策略**: `.m3u8` 2秒缓存，`.ts`/`.m4s` 不缓存
- **Byte-Range** 支持（LL-HLS 部分分段）
- **Gzip** 对播放列表压缩

## HLS 加密

详见 [docs/encryption.md](docs/encryption.md)，包含：

- AES-128 密钥生成
- FFmpeg 加密分段
- OpenSSL 手动解密工具
- 客户端播放示例（HLS.js / Video.js）
- 密钥管理最佳实践

## 客户端播放

### HLS.js (推荐)

```javascript
const video = document.getElementById('video');
const hls = new Hls({ lowLatencyMode: true });
hls.loadSource('https://localhost:8888/hls/llhls/fmp4/index.m3u8');
hls.attachMedia(video);
```

### Safari 原生

```html
<video src="https://localhost:8888/hls/vod/fmp4/index.m3u8" controls></video>
```

### ffplay

```bash
ffplay https://localhost:8888/hls/vod/ts/index.m3u8
```

## 自定义源视频

将你的 `.mp4` 文件放到项目根目录命名为 `download.mp4`，然后重新构建：

```bash
docker-compose down
rm -rf hls/* keys/* certs/*
docker-compose up -d --build
```

## 故障排查

```bash
# 查看日志
docker-compose logs -f

# 进入容器
docker exec -it hls-server bash

# 验证 SSL 证书
openssl s_client -connect localhost:8888 -servername localhost </dev/null

# 测试 HTTP/2
curl -k --http2 -I https://localhost:8888/

# 测试 CORS
curl -k -H "Origin: http://example.com" -I https://localhost:8888/hls/vod/ts/index.m3u8

# 手动运行生成脚本
docker exec -it hls-server generate-all.sh
```

## License

MIT
