#!/usr/bin/env node
// Builds collected sightings into the data file that ships with the addon
// (src/Tradewright/src/data/Tradewright_SourceData.lua).
//
// In game: /tradewright sources seal, then log out (the client writes saved data when it exits).
// This script then reads TradewrightSourcesDB from every account's SavedVariables/Tradewright.lua
// and hands the files to build-source-data.lua, which does the merge with the addon's own rules.
// On the next login the addon drops from the saved data whatever the shipped file now states.
//
//   node scripts/build-source-data.mjs             # every target in deploy.config.local.json
//   node scripts/build-source-data.mjs forever     # named targets
//   node scripts/build-source-data.mjs --wtf <dir> # one WTF folder instead of the targets

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { wtfDirsFromArgs } from "./migrate-saved-data.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const LUA = process.env.LUA || "lua5.1";

function savedVariableFiles(wtfDir) {
  const accounts = path.join(wtfDir, "Account");
  if (!fs.existsSync(accounts)) return [];
  return fs
    .readdirSync(accounts, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(accounts, entry.name, "SavedVariables", "Tradewright.lua"))
    .filter((file) => fs.existsSync(file));
}

const files = wtfDirsFromArgs(process.argv.slice(2)).flatMap(savedVariableFiles);
if (!files.length) {
  console.error("No SavedVariables/Tradewright.lua found — is the drive mounted, and has the addon been run?");
  process.exit(1);
}
const result = spawnSync(LUA, [path.join(ROOT, "scripts", "build-source-data.lua"), ...files], { cwd: ROOT, stdio: "inherit" });
process.exit(result.status ?? 1);
