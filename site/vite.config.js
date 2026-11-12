import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Builds into ../docs, which GitHub Pages serves. docs/assets (pictures) is left alone.
export default defineConfig({
  base: "./",
  plugins: [react()],
  publicDir: false,
  build: { outDir: "../docs", emptyOutDir: false, assetsDir: "app" },
});
