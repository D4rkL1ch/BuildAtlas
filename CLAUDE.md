# Build Atlas — instructions for Claude Code

WoW Forever addon (client 1.60.x, `## Interface: 16001`, modern Mainline-style API, Lua 5.1). The full brief is `HANDOFF.md`; window designs are `design/*.dc.html`. Read the relevant parts before any work.

## How to work
- Build one milestone (HANDOFF.md §6) at a time. Don't start the next until the user confirms the current one works in-game.
- At the end of a step, list exactly what the user should test in-game (`/reload` or restart, what to click, expected result).
- Platform facts come from the probe (`/atlas probe`, results in `docs/probe-results.md`) or Blizzard's Forever UI source. Don't build on an unverified fact without a guarded fallback; record open questions in `docs/probe-results.md`.
- Project skills in `.claude/skills/`: `deploy-and-check` before the user tests in-game, `forever-api-check` before using an API not yet in the addon, `read-saved-data` to read probe results and saved plans.

## Code rules
- Lua 5.1. No `goto`, no `//`, no `require`.
- `local addonName, ns = ...` at the top of every file. Globals: only `BuildAtlasDB`, `BuildAtlasCharDB`, the slash command and the named main frame (`BuildAtlasMainFrame`, for Escape).
- Frames in Lua, not XML. No secure templates; never hook secure Blizzard frames; never open Blizzard panels (talents, character, bags) from code.
- Pure model code (`Model/Plan.lua`, `Model/SynergyGraph.lua`, future `Codecs/`) must not touch WoW globals. `Model/Talents.lua` is the C_Traits reader and may.
- Every combat-time read goes through `ns.Secrets` (`issecretvalue` guard, `pcall`, fallback). Nothing secret may reach SavedVariables (`Secrets.Sanitize`).
- Plans are read-only in combat; nothing calls protected functions in combat. Applying talents (M3) only adds ranks, never refunds.
- Strings through `ns.L[...]` (enUS keys for now).
- Generated data (`Data/Data_<build>.lua`, M1) is never hand-edited; change `tools/build_data.py` or `tools/overrides/` instead.
- Blizzard addon policy: free, no ads or donation prompts, no obfuscation. Check licences before vendoring libraries.

## Layout
TOC load order: Core → Data → Model → Core/Probe → UI. Panes register with `ns.Window.RegisterPane(key, build)`; nav rail entries are in `UI/Window.lua`.

## Repo and deploy
- GitHub `D4rkL1ch/BuildAtlas` (public, GPL-3.0). Not inside the WoW folder. Never commit secrets, tokens, local paths, account or character names.
- `tools/deploy.ps1` ships `*.toc`, top-level `*.lua`, and `Core/ Data/ Model/ UI/ Libs/ Media/`. New shipped folders go in `$ShipDirs` there; repo-only files go in `.pkgmeta`'s `ignore`.
- Releases: pushing a tag runs `.github/workflows/release.yml` (BigWigs packager). TOC version is `@project-version@`; never hard-code it. `CHANGELOG.md` is the player-facing release notes; rewrite it per release and have the user approve it.

## Testing
- Offline: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1` (stubs in `tools/tests/wowstubs.lua`; add new test files to the list in `tools/tests/run.lua`).
- Diagnostics: the editor's diagnostics need the workspace (`BuildAtlas.code-workspace`) loaded. If they show `undefined-global` for `pairs`/`table`, the Ketho library isn't loaded; run the LuaLS CLI with a config that sets `workspace.library` to the Ketho `Annotations/Core` folder and act on the rest.
- In-game: the user deploys, then `/reload` (or restarts after TOC changes) and checks BugSack.
