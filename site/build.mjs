// Builds the page, then renders it to HTML so it reads without JavaScript and for search engines.
import { build } from "vite";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

rmSync("../docs/build", { recursive: true, force: true });
rmSync("../docs/app", { recursive: true, force: true });
await build({ logLevel: "warn" });
await build({ logLevel: "warn", build: { ssr: "src/entry-server.jsx", outDir: ".ssr", emptyOutDir: true } });
const { render } = await import(pathToFileURL(".ssr/entry-server.js").href);
const page = "../docs/index.html";
writeFileSync(page, readFileSync(page, "utf8").replace("<!--app-->", render()));
rmSync(".ssr", { recursive: true, force: true });
console.log("Built ../docs/index.html");
