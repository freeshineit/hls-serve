const express = require("express");
const fs = require("fs");
const path = require("path");
const cors = require("cors");

const app = express();
const RESOURCES_DIR = path.join(__dirname, "resources");
const DEFAULT_PORT = Number(process.env.PORT) || 5000;

app.use(cors({
  origin: "*",
  methods: ["GET", "HEAD", "PUT", "PATCH", "POST", "DELETE", "OPTIONS"],
  allowedHeaders: ["*"],
  exposedHeaders: ["Content-Length", "Content-Range", "Content-Type"],
  credentials: false,
}));

// 确保所有响应都带上 CORS 头（包括静态文件和错误响应）
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Methods", "GET, HEAD, PUT, PATCH, POST, DELETE, OPTIONS");
  res.header("Access-Control-Allow-Headers", "*");
  res.header("Access-Control-Expose-Headers", "Content-Length, Content-Range, Content-Type");
  if (req.method === "OPTIONS") {
    return res.sendStatus(204);
  }
  next();
});

// 递归列举所有资源路径
function listAllResources(dir, base = "") {
  let results = [];
  const list = fs.readdirSync(dir);
  list.forEach((file) => {
    const filePath = path.join(dir, file);
    const relPath = path.join(base, file);
    const stat = fs.statSync(filePath);
    if (stat && stat.isDirectory()) {
      results = results.concat(listAllResources(filePath, relPath));
    } else {
      results.push(relPath);
    }
  });
  return results;
}

function listM3u8Resources() {
  return listAllResources(RESOURCES_DIR).filter((resourcePath) =>
    resourcePath.endsWith(".m3u8"),
  );
}

app.use("/", express.static(RESOURCES_DIR));

function startServer(port) {
  const server = app.listen(port, () => {
    console.log(`Video server running at http://localhost:${port}`);
    const domain = `http://localhost:${port}`;
    const m3u8Paths = listM3u8Resources();
    if (m3u8Paths.length === 0) {
      console.log("No .m3u8 files found under resources");
    } else {
      console.log("Found .m3u8 files under resources:");
      m3u8Paths.forEach((resourcePath) => {
        console.log(domain + "/" + resourcePath.replace(/\\/g, "/"));
      });
    }
  });

  server.on("error", (err) => {
    if (err.code === "EADDRINUSE" && !process.env.PORT) {
      console.warn(`Port ${port} is in use, retrying with ${port + 1}...`);
      startServer(port + 1);
      return;
    }

    console.error("Failed to start video server:", err.message);
    process.exit(1);
  });
}

startServer(DEFAULT_PORT);
