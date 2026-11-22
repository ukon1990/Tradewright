#!/usr/bin/env node
// Copy every addon folder in src/ into the configured WoW AddOns folders,
// replacing the previously deployed copy (so deleted files disappear too).
//
//   node scripts/deploy.mjs                 # all targets
//   node scripts/deploy.mjs forever retail  # named targets
//   node scripts/deploy.mjs --dry-run       # show what would happen
//
// Targets are per machine: they live in the untracked deploy.config.local.json
// (see deploy.config.local.example.json), merged over deploy.config.json.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function readJson(file) {
  const full = path.join(ROOT, file);
  return fs.existsSync(full) ? JSON.parse(fs.readFileSync(full, "utf8")) : {};
}

const config = readJson("deploy.config.json");
const local = readJson("deploy.config.local.json");
const targets = { ...config.targets, ...local.targets };
const sourceDir = path.join(ROOT, config.source ?? "src");
// Folders the pack used to ship under an earlier name. Left in place they would load next to
// the current ones, so every deploy removes them.
const retired = config.retired ?? [];

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

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const wanted = args.filter((a) => !a.startsWith("--"));
const names = wanted.length ? wanted : Object.keys(targets);

if (!Object.keys(targets).length) {
  console.error("No deploy targets set. Copy deploy.config.local.example.json to deploy.config.local.json and fill in your AddOns folders.");
  process.exit(1);
}
const unknown = names.filter((n) => !targets[n]);
if (unknown.length) {
  console.error(`Unknown target(s): ${unknown.join(", ")}. Known: ${Object.keys(targets).join(", ")}`);
  process.exit(1);
}

const addons = fs
  .readdirSync(sourceDir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(sourceDir, d.name, `${d.name}.toc`)))
  .map((d) => d.name);

if (!addons.length) {
  console.error(`No addon folders (with <name>/<name>.toc) found in ${sourceDir}`);
  process.exit(1);
}

let failed = false;
for (const name of names) {
  const addonsDir = targets[name];
  console.log(`\n[${name}] ${addonsDir}${dryRun ? "  (dry run)" : ""}`);
  if (!fs.existsSync(addonsDir)) {
    console.error(`  ✗ AddOns folder not found — is the drive mounted?`);
    failed = true;
    continue;
  }
  for (const addon of addons) {
    const from = path.join(sourceDir, addon);
    const to = path.join(addonsDir, addon);
    if (!dryRun) {
      fs.rmSync(to, { recursive: true, force: true });
      fs.cpSync(from, to, {
        recursive: true,
        filter: (src) => src === from || !isExcluded(path.basename(src)),
      });
    }
    console.log(`  ✓ ${addon}`);
  }
  for (const addon of retired) {
    const old = path.join(addonsDir, addon);
    if (!fs.existsSync(old)) continue;
    if (!dryRun) fs.rmSync(old, { recursive: true, force: true });
    console.log(`  − ${addon} (retired, removed)`);
  }
}

process.exit(failed ? 1 : 0);
