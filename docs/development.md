# Developing Tradewright

How to set up the tools, run the tests and copy the addons into your game folders. Rules for contributors and agents are in [AGENTS.md](../AGENTS.md).

## Setup

| Tool | Used for | Arch | Other |
| --- | --- | --- | --- |
| Node.js | `npm` scripts, deploy | `sudo pacman -S nodejs npm` | [nodejs.org](https://nodejs.org) |
| Python 3 | test and lint runners | `sudo pacman -S python` | system package |
| Lua 5.1 (`lua5.1`) | offline tests | `sudo pacman -S lua51` | Debian/Ubuntu: `sudo apt install lua5.1` |
| luacheck | lint | `sudo pacman -S luacheck` | Debian/Ubuntu: `sudo apt install lua-check`; anywhere: `luarocks install luacheck` |

On Arch, all at once:

```bash
sudo pacman -S --needed nodejs npm python lua51 luacheck
```

If luacheck lives somewhere off `PATH`, point to it with `LUACHECK=/path/to/luacheck`.

## Test and lint

```bash
npm test
```

This runs the offline Lua tests and then lint. No WoW client is needed.

```bash
npm run lint
```

Lint only: luacheck, plus limits of 700 lines per file, 40 lines per function, complexity 10 and 5 parameters.

Existing debt is frozen in `scripts/lint-baseline.json`, so lint fails only on new or worse code. After a cleanup that lowers debt, lock it in:

```bash
npm run lint:baseline
```

## Deploy to the game

Target AddOns folders are per machine: copy `deploy.config.local.example.json` to `deploy.config.local.json` (untracked) and fill in your paths, e.g. `{"targets": {"forever": "/path/to/_forever_/Interface/AddOns"}}`.

```bash
npm run deploy:dry
```

```bash
npm run deploy:local
```

`deploy:local` copies the addons into every AddOns folder you configured; `deploy:forever` and `deploy:retail` copy to a single one. In game, `/reload` picks up changed files. New `.lua` files or TOC changes need a full client restart. `/tw` (or `/tradewright`) opens the UI.

## Release

```bash
npm run package
```

builds `dist/Tradewright-<version>.zip`: the six addon folders with the same files a deploy copies (no tests, no docs; licence files included). The version comes from `package.json`; every TOC must carry the same `## Version` (`npm test` checks it).

To release a version:

1. Set the version in `package.json` and in every TOC, and add its entry at the top of `CHANGELOG.md`.
2. `npm test`, then smoke test in game on Forever and on retail: loads without errors, full scan, profession scan, Crafts tab, one post and one cancel. Repeat the Crafts tab and a mailbox visit with the client set to another language.
3. Commit, tag `v<version>` and push the tag. The Release workflow tests, packages and attaches the zip to a GitHub release.
4. Upload the zip on CurseForge, or let the workflow do it (below).

One-time CurseForge setup:

- Create the project. Check that a file can be marked for the Forever game version as well as retail.
- Credit and link CraftSim in the description: the Midnight specialization data is derived from it (see `src/Tradewright_Professions/THIRD-PARTY-NOTICES.md`).
- Add `## X-Curse-Project-ID: <id>` to the four `Tradewright*.toc` files of the core addon, so the CurseForge app recognises an installed copy.
- For automatic uploads, set the repository variables `CF_PROJECT_ID` and `CF_GAME_VERSION_IDS` (comma-separated ids from `https://wow.curseforge.com/api/game/versions`) and the secret `CF_API_KEY`. Until then the workflow skips the upload.

## Coming from AuctionHelper

The pack used to be called AuctionHelper, and the game keeps saved data per addon folder name. With the game closed, move the data over once, then deploy (which also removes the old `AuctionHelper*` folders):

```bash
npm run migrate:saved-data -- --dry-run
```

```bash
npm run migrate:saved-data
```

```bash
npm run deploy:local
```

The old `AuctionHelper*.lua` saved-data files are left in place as a backup.

## Shipped sightings

The addon records vendors, trainers and loot sources as you play. To build what you have collected into the data file that ships with the addon, run `/tradewright sources seal` in game, log out, and then:

```bash
npm run sources:build
```
