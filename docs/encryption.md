# HLS Encryption & Decryption 文档

## 概述

本项目使用 **AES-128** 加密算法对 HLS 流进行加密。HLS 加密是在服务器端对 TS/fMP4 分段进行加密，客户端通过获取密钥文件来解密播放。

## 加密架构

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  FFmpeg     │────▶│  Encrypted   │────▶│  Nginx       │
│  (encrypt)  │     │  .ts / .m4s  │     │  (serve)     │
└─────────────┘     └──────────────┘     └──────────────┘
       │                                        │
       ▼                                        ▼
┌─────────────┐                        ┌──────────────┐
│  hls.key    │───────────────────────▶│  /keys/      │
│  (16 bytes) │                        │  endpoint    │
└─────────────┘                        └──────────────┘
```

## 密钥生成

### 1. 生成 AES-128 密钥（16 字节）

```bash
openssl rand -hex 16 > keys/hls.key
```

### 2. 生成初始化向量 (IV)

```bash
openssl rand -hex 16 > keys/hls.iv
```

IV 是可选的。如果不指定，FFmpeg 会使用分段的序列号作为 IV。

### 3. 创建 keyinfo 文件

`keys/hls.keyinfo` 格式：

```
https://localhost/keys/hls.key   ← 密钥 URI（客户端从此 URL 下载密钥）
/path/to/keys/hls.key            ← 密钥文件路径（FFmpeg 本地使用）
0123456789abcdef...              ← IV（32 hex chars = 16 bytes, 可选）
```

每行含义：
- **第 1 行**: 密钥 URI — 写入 m3u8 播放列表的 `#EXT-X-KEY` 标签中，播放器会请求此 URL 获取密钥
- **第 2 行**: 密钥文件本地路径 — FFmpeg 加密时读取的实际密钥文件
- **第 3 行**: 初始化向量 (IV) — 可选；如果缺失则使用分段序列号

## 加密 HLS 生成

使用 FFmpeg 的 `-hls_key_info_file` 参数：

```bash
ffmpeg -i download.mp4 \
    -c:v libx264 -preset fast -crf 23 \
    -c:a aac -b:a 128k -ar 44100 \
    -hls_time 4 \
    -hls_playlist_type vod \
    -hls_segment_type mpegts \
    -hls_key_info_file keys/hls.keyinfo \
    -hls_segment_filename "encrypted/segment_%04d.ts" \
    encrypted/index.m3u8
```

## 生成的 m3u8 播放列表

加密后的播放列表中每个分段前会包含 `#EXT-X-KEY` 标签：

```m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:4
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-KEY:METHOD=AES-128,URI="https://localhost/keys/hls.key",IV=0x0123456789abcdef...
#EXTINF:4.000000,
segment_0001.ts
#EXTINF:4.000000,
segment_0002.ts
...
```

### 标签说明

| 属性 | 说明 |
|------|------|
| `METHOD=AES-128` | 使用 AES-128 对称加密 |
| `URI="..."` | 密钥文件下载地址 |
| `IV=0x...` | 初始化向量（32 位十六进制） |

> **注意**: 如果播放列表中的分段使用不同密钥，`#EXT-X-KEY` 可以出现在任何分段之前。若所有分段共用一个密钥，则在开头声明一次即可。

## Nginx 密钥服务配置

```nginx
location /keys/ {
    alias /var/www/keys/;
    add_header Cache-Control "no-cache, no-store" always;
    add_header Access-Control-Allow-Origin "*" always;
}
```

密钥通过 HTTPS 提供，确保传输安全。

> **生产环境建议**: 
> - 使用短时效 Token 验证请求
> - 限制密钥访问频率（rate limiting）
> - 使用 DRM 方案（如 FairPlay、Widevine）替代简单 AES-128

## 客户端解密流程

```
1. 播放器下载 .m3u8 播放列表
2. 解析 #EXT-X-KEY 标签，获取 METHOD、URI、IV
3. 通过 HTTPS 请求 URI 获取 AES-128 密钥
4. 下载加密的 TS/fMP4 分段
5. 使用 AES-128-CBC 解密分段（密钥 + IV）
6. 将解密后的数据传给解码器
```

### HLS.js 示例

HLS.js 自动处理加密解密：

```javascript
const video = document.getElementById('video');
const hls = new Hls();
hls.loadSource('https://localhost/hls/encrypted/ts/index.m3u8');
hls.attachMedia(video);
hls.on(Hls.Events.MANIFEST_PARSED, () => video.play());
```

### Video.js 示例

```html
<video id="player" controls></video>
<script src="https://cdn.jsdelivr.net/npm/video.js/dist/video.min.js"></script>
<script>
  const player = videojs('player', {
    sources: [{ src: 'https://localhost/hls/encrypted/ts/index.m3u8', type: 'application/vnd.apple.mpegurl' }]
  });
</script>
```

## 手动解密工具

### 使用 OpenSSL 解密单个分段

```bash
# 从 hex 密钥文件中读取密钥
KEY_HEX=$(cat keys/hls.key)
IV_HEX=$(cat keys/hls.iv)

# 解密 TS 分段
openssl aes-128-cbc -d \
    -K "$KEY_HEX" \
    -iv "$IV_HEX" \
    -in encrypted/segment_0001.ts \
    -out decrypted/segment_0001.ts
```

### 批量解密

```bash
#!/bin/bash
KEY_HEX=$(cat keys/hls.key)
IV_HEX=$(cat keys/hls.iv)  # 注意：如果 IV 是分段序列号，需要计算

for f in encrypted/segment_*.ts; do
    base=$(basename "$f")
    # 如果是序列号 IV: seq=$(echo "$base" | grep -oP '\d+'); IV_HEX=$(printf '%032x' "$seq")
    openssl aes-128-cbc -d -K "$KEY_HEX" -iv "$IV_HEX" -in "$f" -out "decrypted/$base"
done
```

## 密钥管理最佳实践

1. **密钥轮换**: 定期更换密钥，防止单一密钥长期暴露
2. **安全传输**: 始终通过 HTTPS 提供密钥，防止中间人攻击
3. **访问控制**: 
   - 使用 Referer 检查
   - Token-based 临时访问
   - IP 白名单
4. **密钥存储**: 
   - 密钥文件设置严格权限（chmod 600）
   - 不要将密钥提交到版本控制（加入 .gitignore）
   - 生产环境使用密钥管理服务 (KMS)
5. **短分段时长**: 减小每个密钥加密的数据量

## HLS 加密 vs DRM

| 特性 | AES-128 加密 | DRM (FairPlay/Widevine) |
|------|-------------|------------------------|
| 复杂度 | 低 | 高 |
| 许可证服务 | 不需要 | 需要 |
| 安全性 | 中（密钥可被截获） | 高（密钥受硬件保护） |
| 浏览器兼容性 | HLS.js / Safari | Safari / Chrome / Edge |
| 适用场景 | 内容保护基本需求 | 高级内容保护 / 付费内容 |

## 文件清单

```
keys/
├── hls.key        # AES-128 密钥（16 字节 hex）
├── hls.iv         # 初始化向量（hex）
└── hls.keyinfo    # FFmpeg keyinfo 文件
```

## 相关命令速查

```bash
# 生成随机密钥
openssl rand -hex 16 > hls.key

# 查看 m3u8 中的加密信息
grep "EXT-X-KEY" encrypted/index.m3u8

# 检查 ffmpeg 是否支持加密
ffmpeg -hide_banner -formats | grep hls

# 查看 ffmpeg 的 hls 选项
ffmpeg -hide_banner -h full | grep -A5 hls_key_info
```
