#!/usr/bin/env node
// Build the release zip: dist/Tradewright-<version>.zip with every addon folder at its root,
// holding the same files a local deploy copies.
//
//   node scripts/package.mjs

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { ROOT, TOC_VERSION, copyAddon, listAddons, listTocs, readJson } from "./addon-files.mjs";

const version = readJson("package.json").version;
const addons = listAddons();

// `npm run release` keeps these equal. A zip named 1.0.0 whose TOCs say something else would show the wrong version in game.
const wrong = [];
for (const toc of listTocs()) {
  const found = fs.readFileSync(toc, "utf8").match(TOC_VERSION)?.[1];
  if (found !== version) wrong.push(`${path.basename(toc)}: ${found ?? "no version"}`);
}
if (wrong.length) {
  console.error(`package.json says ${version}, but:\n  ${wrong.join("\n  ")}`);
  process.exit(1);
}

const dist = path.join(ROOT, "dist");
const staging = path.join(dist, "staging");
const zip = path.join(dist, `Tradewright-${version}.zip`);
fs.rmSync(staging, { recursive: true, force: true });
fs.mkdirSync(staging, { recursive: true });
for (const addon of addons) copyAddon(addon, staging);
fs.rmSync(zip, { force: true });
execFileSync("zip", ["-r", "-q", "-X", zip, ...addons], { cwd: staging, stdio: "inherit" });
fs.rmSync(staging, { recursive: true, force: true });

console.log(`${path.relative(ROOT, zip)}  (${addons.length} addons, ${(fs.statSync(zip).size / 1024).toFixed(0)} kB)`);
