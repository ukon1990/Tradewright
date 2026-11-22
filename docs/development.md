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

builds `dist/Tradewright-<version>.zip`: the six addon folders with the same files a deploy copies (no tests, no docs; licence files included).

The version is kept in `package.json`. `npm run release` writes it into every TOC, and the addon reads it from its TOC when it loads, so it is never typed anywhere else. `npm test` fails when a TOC differs.

To release a version:

1. Add its entry (`## 1.0.1`) at the top of `CHANGELOG.md`. That entry becomes the release notes.
2. `npm run release -- 1.0.1` sets the version, runs `npm test`, commits the version files with the changelog and creates the tag `v1.0.1`. Other uncommitted work is left alone. Without a version it releases the one `package.json` already has. Nothing is pushed.
3. Smoke test in game on Forever and on retail: loads without errors, full scan, profession scan, Crafts tab, one post and one cancel. Repeat the Crafts tab and a mailbox visit with the client set to another language.
4. `git push origin HEAD v1.0.1`. The Release workflow tests, packages and attaches the zip to a GitHub release.
5. Upload the zip on CurseForge, or let the workflow do it (below).

If the smoke test fails before the push: `git tag -d v1.0.1`, fix, and run the release command again.

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

## Enchant scrolls

An enchant makes no item of its own; the addon values it as the scroll it makes on an Enchanting Vellum. Which scroll that is comes from a shipped list, built from the game's own `SpellEffect` table (downloaded from wago.tools). Rebuild it when a patch adds enchants:

```bash
npm run enchants:build
```

Enchants with crafting quality (Dragonflight and later) are not in the list; the game reports their scrolls as recipe outputs.
