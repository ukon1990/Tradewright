#!/usr/bin/env node
// One-time move of saved data from the pack's old name (AuctionHelper) to Tradewright.
//
// The game keeps an addon's saved data in WTF/Account/<account>/SavedVariables/<AddonFolder>.lua,
// so the renamed folders would start empty. For every account this script
//   - copies AuctionHelper*.lua to Tradewright*.lua with the saved-variable names renamed, and
//   - renames the pack's entries in each character's AddOns.txt, so the modules that were
//     enabled stay enabled.
// The old AuctionHelper*.lua files are left untouched as the backup.
//
// Run it with the game closed: the client rewrites these files when it exits.
//
//   node scripts/migrate-saved-data.mjs             # every target in deploy.config.json
//   node scripts/migrate-saved-data.mjs forever     # named targets
//   node scripts/migrate-saved-data.mjs --dry-run   # show what would happen
//   node scripts/migrate-saved-data.mjs --force     # overwrite Tradewright*.lua that already exist
//   node scripts/migrate-saved-data.mjs --wtf <dir> # one WTF folder instead of the targets

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OLD = "AuctionHelper";
const NEW = "Tradewright";

function readJson(file) {
  const full = path.join(ROOT, file);
  return fs.existsSync(full) ? JSON.parse(fs.readFileSync(full, "utf8")) : {};
}

// Only the names the game itself writes are renamed: the variable assignments at the start of
// a line and the folder-name keys under meta.familyLoaded. Everything else in the data
// (export payloads, history text) is copied as it is.
export function renameSavedVariables(text) {
  return text
    .replace(new RegExp(`^${OLD}(\\w*) = `, "gm"), `${NEW}$1 = `)
    .replace(new RegExp(`^\\["${OLD}(_\\w+)?"\\] = (\\d+),`, "gm"), `["${NEW}$1"] = $2,`);
}

export function renameEnabledAddons(text) {
  return text.replace(new RegExp(`^${OLD}(_\\w+)?: `, "gm"), `${NEW}$1: `);
}

function subdirs(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => path.join(dir, d.name));
}

function migrateSavedVariables(accountDir, opts) {
  const dir = path.join(accountDir, "SavedVariables");
  if (!fs.existsSync(dir)) return;
  for (const file of fs.readdirSync(dir)) {
    if (!file.startsWith(OLD) || !file.endsWith(".lua")) continue;
    const target = path.join(dir, NEW + file.slice(OLD.length));
    if (fs.existsSync(target) && !opts.force) {
      console.log(`  · ${file}: ${path.basename(target)} already exists, skipped (--force overwrites)`);
      continue;
    }
    if (!opts.dryRun) {
      fs.writeFileSync(target, renameSavedVariables(fs.readFileSync(path.join(dir, file), "utf8")));
    }
    console.log(`  ✓ ${file} → ${path.basename(target)}`);
  }
}

// AddOns.txt sits in WTF/Account/<account>/<realm>/<character>/.
function migrateEnabledAddons(accountDir, opts) {
  for (const realmDir of subdirs(accountDir)) {
    for (const characterDir of subdirs(realmDir)) {
      const file = path.join(characterDir, "AddOns.txt");
      if (!fs.existsSync(file)) continue;
      const before = fs.readFileSync(file, "utf8");
      const after = renameEnabledAddons(before);
      if (after === before) continue;
      if (!opts.dryRun) {
        fs.copyFileSync(file, `${file}.pre-tradewright`);
        fs.writeFileSync(file, after);
      }
      console.log(`  ✓ ${path.relative(accountDir, file)}: enabled modules renamed`);
    }
  }
}

function migrate(wtfDir, opts) {
  console.log(`\n${wtfDir}${opts.dryRun ? "  (dry run)" : ""}`);
  const accounts = subdirs(path.join(wtfDir, "Account"));
  if (!accounts.length) {
    console.error("  ✗ no Account folders found — is the drive mounted?");
    return false;
  }
  for (const accountDir of accounts) {
    migrateSavedVariables(accountDir, opts);
    migrateEnabledAddons(accountDir, opts);
  }
  return true;
}

export function wtfDirsFromArgs(args) {
  const wtfFlag = args.indexOf("--wtf");
  if (wtfFlag >= 0) return [path.resolve(args[wtfFlag + 1])];
  const targets = { ...readJson("deploy.config.json").targets, ...readJson("deploy.config.local.json").targets };
  const wanted = args.filter((a) => !a.startsWith("--"));
  const names = wanted.length ? wanted : Object.keys(targets);
  const unknown = names.filter((n) => !targets[n]);
  if (unknown.length) {
    console.error(`Unknown target(s): ${unknown.join(", ")}. Known: ${Object.keys(targets).join(", ")}`);
    process.exit(1);
  }
  // A target is <game>/Interface/AddOns; WTF sits next to Interface.
  return names.map((n) => path.resolve(targets[n], "..", "..", "WTF"));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const opts = { dryRun: args.includes("--dry-run"), force: args.includes("--force") };
  const results = wtfDirsFromArgs(args).map((dir) => migrate(dir, opts));
  process.exit(results.every(Boolean) ? 0 : 1);
}
