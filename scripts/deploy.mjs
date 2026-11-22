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
import { config, copyAddon, listAddons, readJson, sourceDir } from "./addon-files.mjs";

const local = readJson("deploy.config.local.json");
const targets = { ...config.targets, ...local.targets };
// Folders the pack used to ship under an earlier name. Left in place they would load next to
// the current ones, so every deploy removes them.
const retired = config.retired ?? [];

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

const addons = listAddons();

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
    if (!dryRun) copyAddon(addon, addonsDir);
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
