# Build Atlas

A talent planner for **WoW Forever** that explains *why* a build works: which spells each talent changes, what it scales with, how procs chain and resources loop. Around it: compare, apply and share builds, post-fight talent contribution estimates, a dummy benchmark, gear helpers, community presets and a leveling path.

Status: **early proof of concept**. Not released.

## What works now

- `/atlas` opens the planner: all three trees of your class, read live from the game.
- Plan in a scratch slot or per spec (Spec 1 / Spec 2). Planning never changes your real talents.
- Tier, 51-point and prerequisite rules, with the reason when a rank can't be added or removed.
- Inspector with the game's own per-rank text.
- Other classes through the class menu (out of combat), if the client allows it.
- `/atlas probe` dumps platform facts to SavedVariables (developer tool).

Controls: click a talent to inspect it, Shift-click to add a rank, right-click to remove one, or use + / − in the inspector.

## Roadmap

| Milestone | Content |
|---|---|
| M0 | Probe the platform (`/atlas probe`, [docs/probe-results.md](docs/probe-results.md)) |
| M1 | Data pipeline: which spells each talent modifies, per-rank values, Classic diff |
| M2 | Planner, inspector, synergy highlights, tooltip hooks, minimap button |
| M3 | Import/export (own string, Wowhead, Talents Forever, …), apply dialog |
| M4 | Compare builds, synergy map |
| M5 | Fight report and dummy benchmark from the damage meter |
| M6 | Stat weights, Pawn bridge, upgrades, consumables, presets, leveling path |

The window designs are in [design/](design/) (HTML prototypes; sample data is placeholder).

## Development

- The repo root is the addon root. `tools/deploy.ps1` copies the shipped files into the Forever `Interface\AddOns\BuildAtlas` folder (set `BUILDATLAS_GAME_PATH` to the client folder that contains `Interface`).
- Offline tests with stubbed WoW APIs: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1` (uses the LuaLS binary from the VS Code Lua extension as interpreter).

Free and open source under the GPL-3.0. No ads, no paid features.
