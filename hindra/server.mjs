// Serves MacSync's website and counts installs. Node 22.13+ and nothing else.
//
//   POST /api/count     {id, version, macOS, replaces?}: at most once a day per Mac. Macs that sync share an id. 204.
//   GET  /api/installs  the totals. Needs "Authorization: Bearer $STATS_TOKEN".
//   GET  /healthz       200 when the database answers.
//
// No cookies, no IP addresses kept, no request logs. DATA_DIR must be a persistent volume.
import { createServer } from "node:http";
import { createHash, timingSafeEqual } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { createReadStream, mkdirSync, statSync } from "node:fs";
import { extname, join, normalize, resolve, sep } from "node:path";

const ROOT = resolve(process.env.SITE_DIR ?? "site");
const DATA = resolve(process.env.DATA_DIR ?? "data");
const TOKEN = process.env.STATS_TOKEN ?? "";
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".webp": "image/webp",
  ".svg": "image/svg+xml", ".json": "application/json", ".txt": "text/plain; charset=utf-8", ".md": "text/markdown; charset=utf-8",
  ".xml": "application/xml", ".sig": "application/octet-stream", ".ico": "image/x-icon" };

mkdirSync(DATA, { recursive: true });
const db = new DatabaseSync(join(DATA, "installs.db"));
db.exec(`PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS installs (id TEXT PRIMARY KEY, first TEXT NOT NULL, last TEXT NOT NULL, version TEXT NOT NULL, macos TEXT NOT NULL);
  CREATE INDEX IF NOT EXISTS installs_last ON installs(last);`);
const upsert = db.prepare(`INSERT INTO installs VALUES (?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET last = excluded.last, version = excluded.version, macos = excluded.macos`);
const count = (sql, ...args) => db.prepare(sql).get(...args).n;
const day = (ago = 0) => new Date(Date.now() - ago * 86_400_000).toISOString().slice(0, 10);

// New numbers one address may add in an hour, kept in memory only, so a script can't inflate the count cheaply.
const seen = new Map();
let hour = 0;
function allowed(req) {
  const now = Math.floor(Date.now() / 3_600_000);
  if (now !== hour) { seen.clear(); hour = now; }
  // The last address is the one our own proxy added; earlier ones can be made up. With Cloudflare in
  // front, set CLIENT_IP_HEADER=cf-connecting-ip.
  const header = req.headers[process.env.CLIENT_IP_HEADER ?? "x-forwarded-for"];
  const ip = header?.split(",").at(-1).trim() || req.socket.remoteAddress;
  const n = (seen.get(ip) ?? 0) + 1;
  seen.set(ip, n);
  return n <= 60;
}

function body(req, max = 512) {
  return new Promise((done, fail) => {
    let text = "";
    req.setEncoding("utf8");
    req.on("data", (part) => { text += part; if (text.length > max) { fail(new Error("too big")); req.destroy(); } });
    req.on("end", () => done(text));
    req.on("error", fail);
  });
}

async function addInstall(req, res) {
  if (!allowed(req)) return res.writeHead(429).end();
  let m;
  try { m = JSON.parse(await body(req)); } catch { return res.headersSent || res.destroyed ? undefined : res.writeHead(400).end(); }
  const uuid = (v) => typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(v);
  const ok = m && uuid(m.id) && (m.replaces === undefined || uuid(m.replaces))
    && typeof m.version === "string" && /^\d{1,3}(\.\d{1,4}){1,3}$/.test(m.version)
    && typeof m.macOS === "string" && /^\d{2}$/.test(m.macOS);
  if (!ok) return res.writeHead(400).end();
  // A Mac that joined others: its old number becomes theirs, keeping the earlier first day.
  const old = m.replaces && m.replaces !== m.id ? db.prepare("DELETE FROM installs WHERE id = ? RETURNING first").get(m.replaces) : undefined;
  upsert.run(m.id, old?.first ?? day(), day(), m.version, m.macOS);
  if (old) db.prepare("UPDATE installs SET first = min(first, ?) WHERE id = ?").run(old.first, m.id);
  res.writeHead(204).end();
}

function totals(req, res) {
  const hash = (s) => createHash("sha256").update(s).digest();
  const given = req.headers.authorization?.replace(/^Bearer /, "") ?? "";
  if (!TOKEN || !timingSafeEqual(hash(given), hash(TOKEN))) return res.writeHead(401).end();
  const group = (column) => Object.fromEntries(db.prepare(`SELECT ${column} AS k, count(*) AS n FROM installs GROUP BY k ORDER BY n DESC`).all().map((r) => [r.k, r.n]));
  const out = {
    uniqueInstalls: count("SELECT count(*) AS n FROM installs"),
    activeLast7Days: count("SELECT count(*) AS n FROM installs WHERE last > ?", day(7)),
    activeLast30Days: count("SELECT count(*) AS n FROM installs WHERE last > ?", day(30)),
    newLast7Days: count("SELECT count(*) AS n FROM installs WHERE first > ?", day(7)),
    newLast30Days: count("SELECT count(*) AS n FROM installs WHERE first > ?", day(30)),
    byVersion: group("version"), byMacOS: group("macos"),
  };
  res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" }).end(JSON.stringify(out, null, 2) + "\n");
}

function file(req, res, path) {
  let full;
  try { full = normalize(join(ROOT, decodeURIComponent(path))); } catch { return res.writeHead(400).end(); }
  if (full !== ROOT && !full.startsWith(ROOT + sep)) return res.writeHead(404).end();
  let info;
  try {
    info = statSync(full);
    if (info.isDirectory()) { full = join(full, "index.html"); info = statSync(full); }
  } catch { return res.writeHead(404, { "Content-Type": "text/plain" }).end("Not found\n"); }
  const etag = `"${info.size.toString(36)}-${Math.floor(info.mtimeMs).toString(36)}"`;
  const headers = {
    "Content-Type": TYPES[extname(full)] ?? "application/octet-stream", ETag: etag,
    // Built files carry a hash in their name; everything else may change with the next build.
    "Cache-Control": path.startsWith("/app/") ? "public, max-age=31536000, immutable" : path.startsWith("/assets/") ? "public, max-age=86400" : "public, max-age=300",
  };
  if (req.headers["if-none-match"] === etag) return res.writeHead(304, headers).end();
  res.writeHead(200, { ...headers, "Content-Length": info.size });
  if (req.method === "HEAD") return res.end();
  createReadStream(full).on("error", () => res.destroy()).pipe(res);
}

createServer((req, res) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
  res.setHeader("X-Frame-Options", "SAMEORIGIN");
  const path = req.url.split("?")[0];
  if (path === "/api/count") return req.method === "POST" ? void addInstall(req, res).catch(() => res.headersSent || res.writeHead(500).end()) : res.writeHead(405, { Allow: "POST" }).end();
  if (req.method !== "GET" && req.method !== "HEAD") return res.writeHead(405).end();
  if (path === "/api/installs") return totals(req, res);
  if (path === "/healthz") { try { count("SELECT 1 AS n"); return res.writeHead(200).end("ok\n"); } catch { return res.writeHead(500).end(); } }
  file(req, res, path);
}).listen(Number(process.env.PORT ?? 3000), "0.0.0.0", () => console.log("MacSync site is up"));
for (const s of ["SIGTERM", "SIGINT"]) process.on(s, () => { db.close(); process.exit(0); });
