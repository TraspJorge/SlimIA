// Bundles the page into dist/: node build.mjs  (needs the island's esbuild from ../../node_modules)
import { build } from "../../node_modules/esbuild/lib/main.js";
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
mkdirSync(join(here, "dist"), { recursive: true });
await build({
  entryPoints: [join(here, "main.ts")],
  outfile: join(here, "dist", "mochi.js"),
  bundle: true,
  format: "iife",
  target: "safari15",
  minify: true,
  logLevel: "info",
});
copyFileSync(join(here, "index.html"), join(here, "dist", "index.html"));
