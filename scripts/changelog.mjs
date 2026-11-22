#!/usr/bin/env node
// Print the CHANGELOG.md entry of one version, without its heading: the notes of that release.
//
//   node scripts/changelog.mjs 1.0.1

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ROOT } from "./addon-files.mjs";

/** The text under `## <version>` up to the next `## ` heading, or null when there is no such entry. */
export function changelogEntry(version) {
  const lines = fs.readFileSync(path.join(ROOT, "CHANGELOG.md"), "utf8").split(/\r?\n/);
  const start = lines.indexOf(`## ${version}`);
  if (start < 0) return null;
  const length = lines.slice(start + 1).findIndex((line) => line.startsWith("## "));
  return lines.slice(start + 1, length < 0 ? undefined : start + 1 + length).join("\n").trim();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const version = process.argv[2];
  const entry = version && changelogEntry(version);
  if (!entry) {
    console.error(`CHANGELOG.md has no entry "## ${version}"`);
    process.exit(1);
  }
  console.log(entry);
}
