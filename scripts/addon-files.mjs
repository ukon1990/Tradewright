// What an addon folder ships: shared by deploy.mjs (copy into the game) and package.mjs (release zip),
// so a release holds exactly the files a local deploy does.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export function readJson(file) {
  const full = path.join(ROOT, file);
  return fs.existsSync(full) ? JSON.parse(fs.readFileSync(full, "utf8")) : {};
}

export const config = readJson("deploy.config.json");
export const sourceDir = path.join(ROOT, config.source ?? "src");

// "*.md" → suffix match, "LICENSE*" → prefix match, ".*" → any dotfile, anything else → exact name.
const matches = (pattern, name) => {
  if (pattern === ".*") return name.startsWith(".");
  if (pattern.startsWith("*")) return name.endsWith(pattern.slice(1));
  if (pattern.endsWith("*")) return name.startsWith(pattern.slice(0, -1));
  return name === pattern;
};
const exclude = config.exclude ?? [];
// Licence and third-party notice files must ship with the addon whatever their extension,
// so `include` wins over `exclude`. It cannot rescue a file inside an excluded folder.
const include = config.include ?? [];
const isExcluded = (name) =>
  !include.some((p) => matches(p, name)) && exclude.some((p) => matches(p, name));

/** Names of the addon folders in src/ (a folder with <name>/<name>.toc). */
export function listAddons() {
  return fs
    .readdirSync(sourceDir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && fs.existsSync(path.join(sourceDir, d.name, `${d.name}.toc`)))
    .map((d) => d.name);
}

/** Replace `<intoDir>/<addon>` with the shipped files of that addon. */
export function copyAddon(addon, intoDir) {
  const from = path.join(sourceDir, addon);
  const to = path.join(intoDir, addon);
  fs.rmSync(to, { recursive: true, force: true });
  fs.cpSync(from, to, {
    recursive: true,
    filter: (src) => src === from || !isExcluded(path.basename(src)),
  });
}
