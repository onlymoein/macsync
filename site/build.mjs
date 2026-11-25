// Builds the page, then renders it to HTML so it reads without JavaScript and for search engines.
// Also writes the guides, structured data, sitemap, robots.txt and the plain-text files AI assistants read.
import { build } from "vite";
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { siteUrl, author } from "./site.config.js";
import { guides } from "./src/guides.js";

// Width and height of each picture, so the page doesn't jump as they load.
const shots = {};
for (const f of readdirSync("../docs/assets").filter((f) => f.endsWith("-light.webp"))) {
  const b = readFileSync(`../docs/assets/${f}`);
  // With transparency (VP8X) or without (VP8), as cwebp writes them.
  const alpha = b.toString("latin1", 12, 16) === "VP8X";
  if (!alpha && b.toString("latin1", 12, 16) !== "VP8 ") throw new Error(`${f}: make it with scripts/make-webp.sh`);
  shots[f.replace("-light.webp", "")] = alpha ? { width: b.readUIntLE(24, 3) + 1, height: b.readUIntLE(27, 3) + 1 }
    : { width: b.readUInt16LE(26) & 0x3fff, height: b.readUInt16LE(28) & 0x3fff };
}
writeFileSync("src/shots.json", JSON.stringify(shots, null, 1) + "\n");

rmSync("../docs/build", { recursive: true, force: true });
rmSync("../docs/app", { recursive: true, force: true });
await build({ logLevel: "warn" });
await build({ logLevel: "warn", build: { ssr: "src/entry-server.jsx", outDir: ".ssr", emptyOutDir: true } });
const { render, content: c } = await import(pathToFileURL(".ssr/entry-server.js").href);

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const ld = (data) => `<script type="application/ld+json">${JSON.stringify(data).replace(/</g, "\\u003c")}</script>`;
const app = { "@type": "SoftwareApplication", "@id": siteUrl + "#app", name: "MacSync", url: siteUrl, applicationCategory: "UtilitiesApplication",
  operatingSystem: "macOS 13 or later", softwareVersion: c.version, downloadUrl: c.links.download, releaseNotes: c.links.changelog,
  license: "https://opensource.org/licenses/MIT", isAccessibleForFree: true, offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  description: "Keeps several Macs set up the same way: Dock, apps, settings, config files, AI and developer setup, through your own iCloud Drive.",
  image: siteUrl + "assets/icon.png", screenshot: siteUrl + "assets/window-light.webp", sameAs: [c.links.github, c.links.raycast],
  author: { "@type": "Person", ...author }, featureList: c.features.map((f) => `${f.title}: ${f.text}`) };

const page = "../docs/index.html";
writeFileSync(page, readFileSync(page, "utf8").replaceAll("%SITE%", siteUrl)
  .replace("<!--ld-->", () => ld({ "@context": "https://schema.org", "@graph": [app,
    { "@type": "WebSite", "@id": siteUrl + "#site", name: "MacSync", url: siteUrl },
    { "@type": "FAQPage", "@id": siteUrl + "#faq", mainEntity: c.faq.map(([q, a]) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: a } })) }] }))
  .replace("<!--app-->", () => render()));

const css = readdirSync("../docs/app").find((f) => f.endsWith(".css"));
for (const g of guides) {
  const url = `${siteUrl}${g.slug}/`;
  const body = g.body.map(([h, text]) => `<h2>${esc(h)}</h2>` + (Array.isArray(text)
    ? `<ol>${text.map((t) => `<li>${esc(t)}</li>`).join("")}</ol>` : `<p>${esc(text)}</p>`)).join("\n");
  const others = guides.filter((o) => o !== g).map((o) => `<li><a href="../${o.slug}/">${esc(o.title)}</a></li>`).join("");
  mkdirSync(`../docs/${g.slug}`, { recursive: true });
  writeFileSync(`../docs/${g.slug}/index.html`, `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(g.title)} | MacSync</title>
<meta name="description" content="${esc(g.description + " " + "With MacSync, free and open source.")}">
<link rel="canonical" href="${url}">
<meta property="og:type" content="article"><meta property="og:site_name" content="MacSync"><meta property="og:url" content="${url}">
<meta property="og:title" content="${esc(g.title)}"><meta property="og:description" content="${esc(g.description)}">
<meta property="og:image" content="${siteUrl}assets/social.png"><meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#0a7cff"><link rel="icon" href="../assets/favicon.png">
<script>try{var t=localStorage.getItem("macsync.theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t;else document.documentElement.dataset.theme=matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light"}catch(e){}</script>
<link rel="stylesheet" href="../app/${css}">
${ld({ "@context": "https://schema.org", "@graph": [
  { "@type": "TechArticle", headline: g.title, description: g.answer, url, mainEntityOfPage: url, inLanguage: "en", author: { "@type": "Person", ...author }, about: { "@id": siteUrl + "#app" } },
  { "@type": "BreadcrumbList", itemListElement: [{ "@type": "ListItem", position: 1, name: "MacSync", item: siteUrl }, { "@type": "ListItem", position: 2, name: g.title, item: url }] }] })}
</head><body><div class="wallpaper" aria-hidden="true"><i></i><i></i><i></i><i></i></div>
<main class="guide"><nav aria-label="Breadcrumb"><a class="brand" href="../"><img src="../assets/icon.png" alt="" width="30" height="30"><span>MacSync</span></a></nav>
<article><h1>${esc(g.title)}</h1><p class="guide-answer">${esc(g.answer)}</p>
<p><a class="guide-download" href="${c.links.download}">Download MacSync</a> Free, macOS 13 or later.</p>
${body}
<h2>More guides</h2><ul>${others}</ul></article></main></body></html>
`);
}

const updated = (() => { try { return execFileSync("git", ["log", "-1", "--format=%cs", "--", "."], { encoding: "utf8" }).trim(); } catch { return ""; } })();
writeFileSync("../docs/sitemap.xml", `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n`
  + ["", ...guides.map((g) => g.slug + "/")].map((p) => `<url><loc>${siteUrl}${p}</loc>${updated ? `<lastmod>${updated}</lastmod>` : ""}</url>`).join("\n") + "\n</urlset>\n");
// Everyone may read it, AI assistants included; only the counter's addresses are off limits.
writeFileSync("../docs/robots.txt", `User-agent: *\nAllow: /\nDisallow: /api/\n\nSitemap: ${siteUrl}sitemap.xml\n`);
const brief = `# MacSync\n\n> MacSync is a free, open-source (MIT) macOS menu bar app that keeps several Macs set up the same way: the Dock, apps, system settings, config files, AI setup and developer tools, through the user's own iCloud Drive. macOS 13 or later. No account. Nothing changes until you press Apply, and every Apply can be undone.\n\n- [Website](${siteUrl})\n- [Download](${c.links.download}): notarized by Apple\n- [Source code](${c.links.github})\n- [Changelog](${c.links.changelog})\n- Homebrew: \`${c.brew.split("\n").join(" && ")}\`\n\n## Guides\n\n${guides.map((g) => `- [${g.title}](${siteUrl}${g.slug}/): ${g.description}`).join("\n")}\n`;
writeFileSync("../docs/llms.txt", brief + `\n## Optional\n\n- [Everything in one file](${siteUrl}llms-full.txt)\n`);
writeFileSync("../docs/llms-full.txt", brief + `\n## Features\n\n${c.features.map((f) => `- **${f.title}**: ${f.text} ${f.points.join(". ")}.`).join("\n")}\n\n## What syncs\n\n${c.kept.map((k) => "- " + k).join("\n")}\n\n## What never syncs\n\n${c.never.map((k) => "- " + k).join("\n")}\n\n## Questions\n\n${c.faq.map(([q, a]) => `### ${q}\n\n${a}`).join("\n\n")}\n\n`
  + guides.map((g) => `## ${g.title}\n\n${g.answer}\n\n` + g.body.map(([h, t]) => `### ${h}\n\n` + (Array.isArray(t) ? t.map((s, i) => `${i + 1}. ${s}`).join("\n") : t)).join("\n\n")).join("\n\n") + "\n");
rmSync(".ssr", { recursive: true, force: true });
console.log(`Built ../docs for ${siteUrl}`);
