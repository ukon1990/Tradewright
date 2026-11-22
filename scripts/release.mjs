#!/usr/bin/env node
// Prepare a release: write the version into package.json and every TOC, test, commit and tag.
// Nothing is pushed; pushing the tag is what starts the Release workflow.
//
//   npm run release -- 1.0.1
//   npm run release            the version package.json already has

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { ROOT, TOC_VERSION, listTocs, readJson } from "./addon-files.mjs";
import { changelogEntry } from "./changelog.mjs";

const run = (command, args, options = {}) =>
  execFileSync(command, args, { cwd: ROOT, encoding: "utf8", ...options });
const git = (...args) => run("git", args).trim();
const fail = (message) => {
  console.error(message);
  process.exit(1);
};

// package.json holds the version; every other place is written from it here.
const version = process.argv[2] ?? readJson("package.json").version;
const tag = `v${version}`;
const packageJson = path.join(ROOT, "package.json");
const versionFiles = [packageJson, ...listTocs()];

if (!/^\d+\.\d+\.\d+$/.test(version ?? "")) fail("Usage: npm run release -- [major.minor.patch]");
if (git("tag", "--list", tag)) fail(`Tag ${tag} already exists.`);
if (!changelogEntry(version)) fail(`Add an entry "## ${version}" to CHANGELOG.md first.`);
// The commit takes these files whole, so unfinished work in them would be released with it.
const unfinished = git("status", "--porcelain", "--", ...versionFiles);
if (unfinished) fail(`Commit or stash the changes in these files first:\n${unfinished}`);

const write = (file, pattern, replacement) => {
  const before = fs.readFileSync(file, "utf8");
  if (!pattern.test(before)) fail(`${path.relative(ROOT, file)} has no version line.`);
  fs.writeFileSync(file, before.replace(pattern, replacement));
};
write(packageJson, /^(\s*"version":\s*")[^"]*(")/m, `$1${version}$2`);
for (const toc of versionFiles.slice(1)) write(toc, TOC_VERSION, `## Version: ${version}`);

try {
  run("npm", ["test"], { stdio: "inherit" });
} catch {
  git("checkout", "--", ...versionFiles);
  fail("\nTests failed: the version was not changed and nothing was committed.");
}

const committed = [...versionFiles, path.join(ROOT, "CHANGELOG.md")];
// Naming the files commits only them, whatever else is changed or staged.
// Nothing to commit when the version was already in place and its changelog entry committed.
if (git("status", "--porcelain", "--", ...committed)) {
  git("commit", "--quiet", "--message", `Release ${version}`, "--", ...committed);
}
git("tag", tag);

const other = git("status", "--porcelain");
console.log(`\nTagged ${tag}.`);
if (other) console.log("Uncommitted work is not part of the release; the tests above ran with it present.");
console.log(`Smoke test in game, then publish:\n  git push origin HEAD ${tag}`);
