# Build Atlas — implementation handoff

> For: the Claude Code agent implementing this addon in VS Code.
> Owner: the user (solo developer). Working name: **Build Atlas** (sibling of the user's ReagentAtlas addon).
> Design reference: `design/*.dc.html` in this folder (HTML prototypes of every window; open in a browser or read the markup/logic). Sample data in them is placeholder Warrior data, **not** real Forever values.

---

## 1. What we're building

A **WoW Forever** theorycrafting addon whose core is an in-game talent planner that **explains why a build works**: which spells each talent changes, which stats it scales with, proc chains and resource loops. Around that sit build compare/apply/share, post-fight talent contribution estimates, a dummy benchmark, stat/gear/consumable helpers, community presets and a leveling path.

**Positioning:** at least five Forever talent planners already exist (Talents Forever, zTalentPlanner, Forever Talents, Talented Forever, Talent Calculator Forever). Don't compete as a plain planner — the **synergy graph** is the differentiator. Interoperate with existing link formats instead of inventing a closed ecosystem.

---

## 2. Platform facts (read before writing code)

- **WoW Forever** = Blizzard's Classic+ game (launched 4 Nov 2026). Client **1.60.1**, `## Interface: 16001`. Internal game type **"Camelot"**; `_Camelot.toc` / `_Forever.toc` suffixes and `[AllowLoadGameType camelot]` work.
- It runs the **modern Mainline (12.1.5-era) API**, *not* the Classic Era API. Lua 5.1.
  - Gone: `GetSpellInfo`, `GetItemInfo`, `UnitAura`, `GetTalentInfo`, `GetNumTalentTabs`, `CombatLogGetCurrentEventInfo`.
  - Use: `C_Spell`, `C_Item`, `C_UnitAuras`, `C_Traits`, `C_ClassTalents`, `C_TooltipInfo`, `C_DamageMeter`.
- Detect Forever by **interface range (16000–16999) or API probing**, not `WOW_PROJECT_ID` (it changed between builds: 1 → 18).
- **Talents:** classic 3-tree, 51 points at 60, rebuilt on the retail trait engine.
  - `C_ClassTalents.GetActiveConfigID()` → config of type `Enum.TraitConfigType.CamelotCombat` (4), **one tree per class** (Warrior tree 1117, Rogue 1111; others unknown).
  - The three tabs are **trait groups**: `C_Traits.GetGroupDisplayInfoByTreeID` (Warrior: Arms 11650, Fury 11657, Prot 11670).
  - One point currency (3820); per-tab points via `C_Traits.GetGroupCurrencyInfo`.
  - `GetSpecializationInfo` returns the whole class as one "spec" (new spec IDs, e.g. Warrior 1491) — **retail spec tables are wrong here**.
  - Milestone talents at 11/16/21/31 points in a tree.
  - Trees are being hotfixed (changed 3–4 and 10–11 Nov) → **build-stamp all bundled data.**
- **Dual spec** unlocks at level 40 (50g). Talent reset at trainer: 1g first, rises after (later steps unconfirmed). No retail-style loadouts; Blizzard's loadout dropdown is hidden.
- **Midnight "addon disarmament" applies to Forever:**
  - `COMBAT_LOG_EVENT_UNFILTERED` never fires for addons.
  - In combat, auras (incl. your own) are often **secret**; reading them while tainted throws. Check `C_Secrets.ShouldAurasBeSecret()` / `C_Secrets.GetSpellAuraSecrecy`.
  - `UnitHealth` etc. are secret in combat (display-only via StatusBar).
  - `C_DamageMeter`: values secret in combat, **per-spell breakdowns readable out of combat** → this is our measurement source.
  - Guard every combat-time value with `issecretvalue()`; do all analysis on `PLAYER_REGEN_ENABLED`.
- **Blizzard addon policy:** free only, no premium tier, no ads/donation prompts, no obfuscated code.

---

## 3. Probe first (Milestone 0 — before building features)

Many facts above come from community notes. Write a `/batlas probe` debug command that dumps results to SavedVariables, and run it in game. Report findings back to the user before building on them.

1. Can we read **other classes' trees**? Try `C_Traits.GetTreeNodes(treeID)` → `GetNodeInfo` → `GetEntryInfo` → `GetDefinitionInfo` for each class tree ID. Discover the full nine-class tree-ID table.
2. Does `C_ClassTalents.InitializeViewLoadout` / `ViewLoadout` work?
3. Does `C_Traits.GenerateImportString` exist / work?
4. Does **LibTalentTree-1.0** `GetClassTreeID` return values on the live build (it returned nil on beta)?
5. Do character stats (`GetCritChance`, `GetSpellBonusDamage`, …) go secret in combat?
6. Exact shape of `C_DamageMeter` out-of-combat data (per-spell, per-session, per-fight).
7. Tooltip access: `C_TooltipInfo` for trait entries; `C_Spell.GetSpellDescription`.
8. Is `C_AssistedCombat` enabled on Forever (info only; we won't build a rotation helper).

Record results in `docs/probe-results.md`.

---

## 4. Architecture

### 4.1 Offline data pipeline (`tools/`, Python)
- Pull DB2 CSVs for the current Forever build from **wago.tools** (`https://wago.tools/db2/<Table>/csv?build=1.60.1.<build>`): `Spell`, `SpellName`, `SpellEffect`, `SpellClassOptions`, `SpellMisc`, `SkillLineAbility`, and the Trait* tables.
- Derive per talent/rank:
  - **Modifier edges** (talent → spell): spell-modifier auras use `EffectMiscValue` (modified property: damage, cost, cast time, cooldown, crit, duration…) + `EffectSpellClassMask_0..3` matched against each spell's `SpellClassOptions` family/mask. Verify aura IDs on Forever data.
  - **Proc chains:** proc-trigger auras + `EffectTriggerSpell` (recurse).
  - **Resource loops:** energize effects + cost modifiers on the same spells.
  - **Stat scaling:** school, `EffectBonusCoefficient`, `BonusCoefficientFromAP`; talents granting hit/crit/stat conversions.
  - **Per-rank values:** resolve tooltip tokens (`$s1`, `$d`, `$o` …, see wowdev.wiki) from data — never parse English tooltip text.
- Also emit a **Classic Era diff** per talent (for the "Changed vs Classic" tooltip section).
- Merge a hand-written per-class **override file** (`tools/overrides/<class>.yaml`) for conditional synergies, scripted/dummy auras, pet and set-bonus semantics, and corrections.
- Output: `Data/Data_<build>.lua` (one table per class), stamped with the build number. Keep it diff-friendly and deterministic.

### 4.2 Runtime (Lua)
- **Source of truth for layout and ranks = live `C_Traits`.** Join to bundled data by spell ID / definition ID. If client build ≠ data build, show the "data is older than your game" notice (see Launcher design) and mark per-rank numbers as possibly stale.
- Never open Blizzard panels (talents, character, bags) from addon code — causes taint and secret-value errors. Let the player open them.
- Never call protected functions in combat. Gate anything mutating behind `InCombatLockdown()`.
- Windows stay open but **read-only in combat**; analysis runs on `PLAYER_REGEN_ENABLED`.

### 4.3 Suggested repo layout
Mirror the user's ReagentAtlas setup (private GitLab under the TwinUnicorns group, `glab`; develop in repo, deploy into the Forever `AddOns` folder). Confirm the repo path/name with the user before creating it.

```
BuildAtlas/
  BuildAtlas.toc            # Interface 16001, AllowLoadGameType camelot
  Core/        Init.lua  Events.lua  Probe.lua  Secrets.lua (issecretvalue guards)  Util.lua
  Data/        Data_<build>.lua  Presets.lua  Consumables.lua
  Model/       Talents.lua (C_Traits reader)  Plan.lua  SynergyGraph.lua  Attribution.lua
               StatWeights.lua  Codecs/ (BuildAtlas.lua, Wowhead.lua, TalentsForever.lua, WowForeverTalent.lua, Method.lua, SimC.lua, MythicSim.lua)
  UI/          Theme.lua  Window.lua  NavRail.lua  Planner.lua  Inspector.lua  TooltipHooks.lua
               SynergyMap.lua  Compare.lua  ApplyDialog.lua  Share.lua  FightReport.lua
               Benchmark.lua  Gear.lua  Presets.lua  Leveling.lua  Launcher.lua  Toasts.lua
  Libs/        (LibStub, LibDataBroker, LibDBIcon, AceSerializer/LibDeflate if used — check licenses)
  tools/       fetch_db2.py  build_data.py  overrides/
  docs/        probe-results.md
  tests/       (busted specs for pure-Lua model/codec code)
```

---

## 5. UI spec (one window per design file)

Shared look (see `design/Main.dc.html` `<style>` block for exact values): dark panels `#14161B`/`#181B22`, border `#2C313D`, text `#E7E4DA`, muted `#A3A7B3`, gold accent `#E0B54A` (titles, maxed talents, primary buttons), teal `#4FC3B5` (synergy highlights), orange `#F0A070` (warnings), blue `#6AA8FF` (build A / info). Headings: Cinzel-like serif; body sans; numbers mono — use bundled/allowed fonts or the game's fonts as closest match. One main window (1280×800 design size, scalable, movable, remembers position) with a left **nav rail** switching panes; dialogs and tooltips are separate frames.

| # | Design file | Pane | Key behaviour |
|---|---|---|---|
| 1 | `Main.dc.html` | **Talent planner + inspector** | Class dropdown (all 9 classes), plan slot toggle (Scratch / Spec 1 / Spec 2). Three trees, 4×7 grid, rank badges, states: unlearned/partial/maxed/locked (tier = 5 pts per row), selected (white ring), **related (teal ring = shares a modified spell with selected talent)**. Click selects; +/− in inspector changes rank; tier and 51-point limits enforced. Inspector: name, tier, rank, current/next rank text, *Modifies* (spell rows → click enters **spell view**: all talents touching that spell), *Scales with* chips, proc/loop note, *Synergizes with* list (computed, marks "In build"/"Not taken"). Strip under trees: "Spells this build modifies ×count". Footer: point split, diff vs active spec, Reset / Compare / Share / **Apply to Spec N**. Data-build badge in title bar. The prototype's `renderVals()` shows the intended highlight logic. |
| 2 | `Tooltip.dc.html` | **Tooltip hooks** | Talent tooltip: per-rank value tiles (current/next), synergy block (triggered by / boosted by / scales with), "Changed vs Classic", Ctrl → spell IDs + raw effects. Also append a "changed by N talents" block to **action-bar spell tooltips** (Shift expands). |
| 3 | `SynergyMap.dc.html` | **Synergy map** | Columns Talents → Spells → Stats; select a spell to highlight its talents and stats; toggle My build / All talents; proc-chain and resource-loop strips. |
| — | `NavRail.dc.html` | Nav rail | Groups Plan / Measure / Gear & share; out-of-combat status; version. |
| 4 | `Compare.dc.html` | **Compare A vs B** | Pick any two of: Spec 1, Spec 2, scratch, preset, imported. Talent diff, spells-changed counts, stat-lean bars (labelled "not a simulation"), one-line summary, jump to planner/benchmark. |
| 5 | `Apply.dc.html` | **Apply dialog** | States: ready (list of points to learn), blocked (in combat / Blizzard talent window has unsaved changes / plan needs removals → trainer reset), saving (cast progress), success, failed (rolled back). Only **adds** points: `C_Traits.PurchaseRank` per rank → `C_ClassTalents.CommitConfig()`; handle `CONFIG_COMMIT_FAILED`; `C_Traits.RollbackConfig` on cancel/failure. Never auto-refund. |
| 6 | `Share.dc.html` | **Import / export** | Export tabs: Build Atlas string (versioned, build-stamped), Wowhead link, Talents Forever link, SimC profile, MythicSim profile. Read-only edit box + "Select all" (no clipboard API — user presses Ctrl+C). Import: paste box with auto-detect + tree-version check → load as scratch or as compare B. Send to party/guild/player via addon messages — **disabled inside instances**. |
| 7 | `FightReport.dc.html` | **Fight report** | Recent fights list (from `C_DamageMeter` after combat; merge selection). KPIs: damage, duration, DPS, "% from talents (est.)". By-spell bars. **Talent contribution table** with method tag: *Modeled* (`damage × bonus/(1+bonus)` from graph), *Rough* (crit/proc-based, can't observe in combat), *Direct* (ability granted by talent). Always labelled as estimates. |
| 8 | `Benchmark.dc.html` | **Dummy benchmark** | Arm a run (1/2/3/5 min), tag it with a build; starts on first hit, results captured after combat. Averages + ranges per build, overlap warning, run history with delete; exclude runs whose gear snapshot differs. No live numbers during the run. |
| 9 | `Launcher.dc.html` | **Launcher + toasts** | LibDBIcon minimap button (click = planner, shift-click = last report), menu, `/batlas`, `/batlas report`, `/batlas bench`. Toasts: fight report ready, data older than client, paused in combat. |
| 10 | `Gear.dc.html` | **Stats & gear** | Stat weights from: own estimate (coefficients + talents, rough), Pawn scale, or pasted sim weights. "Send to Pawn" if Pawn is loaded (integrate, don't compete). Upgrade check over bags/bank with % vs equipped + one-line talent-aware note (`C_Item.GetItemStats`, `C_TooltipComparison`). Consumables/enchants/gems checklist from curated table keyed to class+build, counts across bags/bank/alts. |
| 11 | `Presets.dc.html` | **Presets** | Bundled community builds filtered by role, each with author + licence (e.g. CC BY 4.0), tree version, "why it works", key talents, out-of-combat "how to play" steps. Load into planner / compare / see synergies. No web access from Lua — presets ship with releases. |
| 12 | `Leveling.dc.html` | **Leveling path** | 51 level tiles (10–60): learned/current/milestone/selected; detail panel; optional level-up reminder (never auto-learns in combat). Dual-spec plan card (unlock at 40, 50g). |

---

## 6. Milestones & acceptance

- **M0 Probe** — `/batlas probe` + `docs/probe-results.md`. *Done when* the user has the answers to §3.
- **M1 Data pipeline** — `tools/` produces `Data_<build>.lua` for Warrior with modifier edges, per-rank values, scaling, Classic diff; overrides merged. *Done when* spot checks of 10 talents match in-game tooltips.
- **M2 Planner MVP** — window shell, nav rail, planner, inspector, spell view, tooltip hooks, launcher, build-mismatch notice. Warrior first, then all 9 classes. *Done when* you can plan any class without respec and the teal highlights match the graph.
- **M3 Share & apply** — codecs (own string + Wowhead + Talents Forever + wowforevertalent + Method import), export tabs, addon-message sharing, apply dialog with all states. *Done when* round-trip export→import is lossless and applying works out of combat and is refused in combat.
- **M4 Compare + Synergy map.**
- **M5 Measure** — `C_DamageMeter` capture after combat, fight report with attribution, benchmark.
- **M6 Gear & presets & leveling** — stat weights, Pawn bridge, upgrade check, consumables, presets, leveling path, SimC/MythicSim export.

Each milestone: a GitLab MR, changelog entry, and a short note for the user listing anything unverified.

---

## 7. Out of scope (don't build)

- In-combat rotation/priority helper (conflicts with Blizzard's "no competitive advantage" rule + secret values). Out-of-combat "how to play" text is fine.
- Live proc/aura uptime tracking (secret auras). Blizzard's Cooldown Manager covers display.
- Inspecting other players' builds (unverified on Forever) — revisit after probing.
- Anything paid, ads, donation prompts, obfuscation.
- Auto-refunding talents.

---

## 8. Engineering rules

- Pure model code (`Model/`, `Codecs/`) must not touch WoW globals → unit-testable with busted.
- Every combat-time read goes through `Secrets.lua` (`issecretvalue` guard) and fails soft.
- SavedVariables: `BuildAtlasDB` (account: settings, presets user-added, benchmark history) and `BuildAtlasCharDB` (plans, fight history capped to N).
- Taint hygiene: no hooking secure Blizzard templates for frames we own; never open Blizzard panels from code.
- Localisation-ready strings (`L["..."]`), enUS first.
- Check licences before vendoring any library or porting logic (SimC is GPL — use as reference only unless the licence fits).

---

## 9. Reference sources

- ForeverPlusPlus API notes — github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md
- forever-addon-kit — github.com/Thunderz96/forever-addon-kit
- LibTalentTree-1.0 — github.com/NumyAddon/LibTalentTree-1.0
- wago.tools DB2 exports — wago.tools/db2/SpellEffect/csv?build=1.60.1.70374 (swap table/build)
- wowdev.wiki/Spells (tooltip tokens, effect semantics)
- simc-forever — github.com/simulationcraft/simc-forever (effect modelling reference)
- Prior art to study/interoperate with: Talents Forever, zTalentPlanner, Forever Talents, Talented Forever (CurseForge); Wowhead Forever talent calc; talentsforever.com; wowforevertalent.com; method.gg Forever calc.
- Blizzard UI Add-On Development Policy (free, no ads, no obfuscation).
