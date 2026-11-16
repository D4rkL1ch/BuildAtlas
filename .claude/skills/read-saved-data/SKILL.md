---
name: read-saved-data
description: Read Build Atlas's SavedVariables (BuildAtlasDB, account-wide; BuildAtlasCharDB, per character) from the WoW Forever client folder to see what the addon recorded in-game, e.g. /atlas probe results, settings, window position, saved plans. Use after the user ran /atlas probe, when debugging something that works in tests but not in-game, or when the user asks what the addon has saved.
---

# Read the saved data

## Find the files

The game path comes only from `BUILDATLAS_GAME_PATH`, in this session or at user level. Never guess a path or use one from memory. If it isn't set, stop and tell the user how to set it (see the `deploy-and-check` skill, step 4).

```powershell
$p = $env:BUILDATLAS_GAME_PATH
if (-not $p) { $p = [Environment]::GetEnvironmentVariable('BUILDATLAS_GAME_PATH', 'User') }
Get-ChildItem -LiteralPath (Join-Path $p 'WTF\Account') -Recurse -Filter 'BuildAtlas.lua' -ErrorAction SilentlyContinue |
    Select-Object FullName, Length, LastWriteTime
```

- `WTF\Account\<ACCOUNT>\SavedVariables\BuildAtlas.lua` holds `BuildAtlasDB` (settings, window, `probe`).
- `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\BuildAtlas.lua` holds `BuildAtlasCharDB` (`plans[classID][slot] = { treeID, ranks = { [nodeID] = rank } }`).

If there are several accounts or characters, ask which one.

## Is it current?

The client writes the files only on `/reload`, logout or exit, never during play. Compare `LastWriteTime` with what the user describes (and with `Get-Date`). If the file is older than the thing to check (a probe run, a fight after the probe, a plan change), ask the user to `/reload` first, then read it again.

## Read it

It's a Lua table dump, one key per line. Read it as text; never run it. Pull out one table at a time:

```bash
sed -n '/^\["probe"\]/,/^},/p' "<file>" | head -400
```

Probe layout (`Core/Probe.lua`): `meta`, `errors`, `ownTree` (raw nodes: position, groups, conditions, edges, cost), `q1_trees` … `q8_assistedCombat`. `q5_stats.inCombat` and `q6_damageMeter.afterCombat` stay `"pending: …"` strings until the user fought once after probing and reloaded.

When the probe answers a question, write it into `docs/probe-results.md` (answer, evidence, what it means for the design) and tell the user.

## Rules

- Read-only. Never edit the files: the game overwrites them on logout, and the user may be logged in.
- They contain the account folder name and character names. Don't copy them into the repo, commits, artifacts, or tests. Quote only what's needed to explain the finding.
