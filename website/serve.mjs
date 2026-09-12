import http from "node:http";
import path from "node:path";
import { readFile } from "node:fs/promises";
import { root } from "./build.mjs";

const port = Number(process.env.VIBE_WEBSITE_PORT || 4173);
const base = "/vibe-controller";
const types = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".webp": "image/webp",
  ".json": "application/json",
  ".xml": "application/xml",
  ".txt": "text/plain",
  ".woff2": "font/woff2",
};
http
  .createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://localhost:${port}`);
      if (url.pathname === "/" || url.pathname === base) {
        res.writeHead(302, { Location: `${base}/` });
        res.end();
        return;
      }
      if (!url.pathname.startsWith(`${base}/`)) throw new Error("Not found");
      const relative =
        decodeURIComponent(url.pathname.slice(base.length + 1)) || "index.html";
      const file = path.resolve(root, "dist", relative);
      if (!file.startsWith(path.join(root, "dist") + path.sep))
        throw new Error("Invalid path");
      const content = await readFile(file);
      res.writeHead(200, {
        "Content-Type": types[path.extname(file)] || "application/octet-stream",
        "Cache-Control": "no-store",
      });
      res.end(content);
    } catch {
      if (!res.headersSent)
        res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("Not found");
    }
  })
  .listen(port, "127.0.0.1", () =>
    console.log(`Preview: http://127.0.0.1:${port}${base}/`),
  );
