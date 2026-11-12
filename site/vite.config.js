import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { readFileSync } from "node:fs";

// The version the app itself reports, read from its source so the page never falls behind.
const swift = readFileSync(new URL("../Sources/MacSyncCore/Environment.swift", import.meta.url), "utf8");
const version = swift.match(/appVersion = "([0-9.]+)"/)?.[1] ?? "";

// Builds into ../docs, which GitHub Pages serves. docs/assets (pictures) is left alone.
export default defineConfig({
  base: "./",
  plugins: [react()],
  define: { __MACSYNC_VERSION__: JSON.stringify(version) },
  publicDir: false,
  build: { outDir: "../docs", emptyOutDir: false, assetsDir: "app" },
});
