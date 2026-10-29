// Bundles the pages into dist/: node build.mjs  (needs the island's esbuild from ../../node_modules)
import { build } from "../../node_modules/esbuild/lib/main.js";
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
mkdirSync(join(here, "dist"), { recursive: true });
for (const [entry, out] of [["main.ts", "mochi.js"], ["answer.ts", "answer.js"]]) {
  await build({
    entryPoints: [join(here, entry)],
    outfile: join(here, "dist", out),
    bundle: true,
    format: "iife",
    target: "safari15",
    minify: true,
    logLevel: "info",
  });
}
for (const page of ["index.html", "answer.html"]) copyFileSync(join(here, page), join(here, "dist", page));
