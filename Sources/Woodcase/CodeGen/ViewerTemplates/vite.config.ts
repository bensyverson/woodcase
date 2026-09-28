import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "path";

const parentDir = path.resolve(__dirname, "..");

// Components reference images via url('./images/...') which resolves relative
// to the page origin. Since the viewer runs from a subdirectory, we rewrite
// /images/* requests to serve from the parent package's images directory.
function serveParentImages(): Plugin {
  return {
    name: "serve-parent-images",
    configureServer(server) {
      server.middlewares.use((req, _res, next) => {
        if (req.url?.startsWith("/images/")) {
          req.url = "/@fs" + path.join(parentDir, req.url);
        }
        next();
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), tailwindcss(), serveParentImages()],
  server: {
    fs: {
      // Allow serving files from the parent package directory. Strict mode is
      // disabled because npm workspace hoisting can place dependencies (e.g.
      // fontsource font files) outside the detected workspace root.
      allow: [parentDir],
      strict: false,
    },
  },
});
