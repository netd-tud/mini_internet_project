import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: {
    emptyOutDir: true,
    outDir: "../server/routing_project_server/static/hilbert",
    rollupOptions: {
      input: "src/main.tsx",
      output: {
        entryFileNames: "hilbert.js",
        chunkFileNames: "chunks/[name].js",
        assetFileNames: (assetInfo) => {
          if (assetInfo.name?.endsWith(".css")) {
            return "hilbert.css";
          }
          return "assets/[name][extname]";
        }
      }
    }
  }
});
