# Build Atlas

A talent planner for **WoW Forever** that explains *why* a build works: which spells each talent changes, what it scales with, how procs chain and resources loop. Around it: compare, apply and share builds, post-fight talent contribution estimates, a dummy benchmark, gear helpers, presets and a leveling path.

Status: **feature complete, in testing**. Not released yet.

## Features

- **Talent planner** (`/batlas`): all three trees of any class, read live from the game. Plan in a scratch slot or per spec without touching your real talents. Tier, point and prerequisite rules with the reason when a rank can't be added or removed. Teal rings show talents that change the same spells as the selected one.
- **Inspector and tooltips**: per-rank values, which spells a talent changes, what it scales with, proc chains and resource loops, and how it differs from Classic. Spell tooltips everywhere list the talents of your build that change that spell.
- **Synergy map**: talents → spells → stats, with your build's proc chains and resource loops.
- **Compare builds**: any two of your specs, plans, an imported build or a preset; talent difference, spells changed, stat lean.
- **Import / export**: Build Atlas string, the game's own loadout string, Wowhead link, SimC profile. Paste anything to import; send builds to party, guild or a friend.
- **Apply**: learns the planned points through the game's own talent system. Only adds points, never in combat, rolls back on any failure.
- **Fight report**: built after combat from the game's damage meter: damage by spell and an estimate of how much came from each talent (each row says how it was estimated).
- **Dummy benchmark**: tag runs with a build, compare averages and ranges on the same gear.
- **Stats & gear**: rough stat weights from your build or pasted Pawn / SimC weights, send to Pawn, bag upgrade check, consumables and enchant checklist.
- **Presets and leveling path**: bundled builds with author and licence, and a point-by-point leveling order with an optional level-up reminder.

Minimap button: click for the planner, Shift-click for the last fight report, right-click for the menu. Commands: `/batlas`, `/batlas report`, `/batlas bench`, `/batlas share`, `/batlas settings`, `/batlas minimap`, `/batlas scale 0.9`.

Combat values are hidden from addons on Forever, so nothing is measured or shown live in combat; windows stay open but read-only, and analysis runs when combat ends.

## Data

Talent semantics come from the game's own data (DB2 tables from wago.tools) via `tools/build_data.py`, plus hand-checked fixes per class in `tools/overrides/`. The bundled data is stamped with the game build; layout and ranks are always read live. Presets live in `tools/presets.json` and are validated against the tree when the data is built.

## Development

- The repo root is the addon root. `tools/deploy.ps1` copies the shipped files into the Forever `Interface\AddOns\BuildAtlas` folder (set `BUILDATLAS_GAME_PATH` to the client folder that contains `Interface`).
- Data: `python tools/fetch_db2.py` then `python tools/build_data.py` (`--summary CLASS [--weak]` to review a class).
- Offline tests with stubbed WoW APIs: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1` (uses the LuaLS binary from the VS Code Lua extension as interpreter).
- Platform facts and open questions: [docs/probe-results.md](docs/probe-results.md). Window designs: [design/](design/).

Free and open source under the GPL-3.0. No ads, no paid features.
