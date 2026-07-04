import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// sqlite-wasm must not be pre-bundled (it loads its own .wasm at runtime).
export default defineConfig({
  plugins: [react()],
  base: "./",
  optimizeDeps: {
    exclude: ["@sqlite.org/sqlite-wasm"],
  },
  worker: {
    format: "es",
  },
});
