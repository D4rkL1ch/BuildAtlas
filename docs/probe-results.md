# Probe results (milestone M0)

How to run: log in on Forever, `/batlas probe`, fight anything once (a training dummy is fine), wait for the "combat samples recorded" chat line, then `/reload`. The results land in `BuildAtlasDB.probe` (account SavedVariables).

First run: client 1.60.1.70938, level 40 Warrior, 2026-11-16. Out-of-combat parts done; the in-combat stat sample and the after-combat damage meter sample are still pending (no fight between probe and reload).

| # | Question | Answer | Consequence |
|---|---|---|---|
| 1 | Can we read other classes' trees? | **Yes.** `C_ClassTalents.GetTraitTreeForSpec(specID)` returns every tree: Warrior 1491→1117, Paladin 1486→1100, Hunter 1485→1091, Rogue 1488→1111, Priest 1487→1114, Shaman 1489→1082, Mage 1482→1112, Warlock 1490→1116, Druid 1484→1089. Same IDs as the DB2 `TraitTree` rows with `TraitSystemID` 10 (plus Druid 1089 and Shaman 1082, system 0). Tabs come from `GetGroupDisplayInfoByTreeID` (Mage: Arcane 11582, Fire 11594, Frost 11601). | No hard-coded tree table needed. |
| 2 | Does the view loadout work? | **Yes.** `InitializeViewLoadout(1482, 60)` then `GetNodeInfo(-3, node)` returns full node info; the planner's reader built the Mage tree (53 talents, 3 tabs, 7×4). `ViewLoadout` exists. | Other classes are plannable in-game. |
| 3 | `C_Traits.GenerateImportString`? | **Works.** Returns a Blizzard loadout string (e.g. `CMdBLekOoV…`), serialization version 2, tree hash 16 bytes. | We can read and write Blizzard's own loadout format (M3 codec). |
| 4 | LibTalentTree `GetClassTreeID`? | Not loaded; not needed (Q1). | Don't bundle it. |
| 5 | Stats secret in combat? | Out of combat: crit, hit, spell power, AP, stats, haste are plain numbers; `ShouldUnitStatsBeSecret()` false. **`UnitHealth` and `UnitPower` are secret even out of combat.** In combat: pending. | Stat-weight estimates run out of combat only (they do anyway). Never read health/power. |
| 6 | `C_DamageMeter` shape | Available. Sessions list kept across fights (`sessionID`, `name` = enemy, `durationSeconds`), session type enum `Overall 0, Current 1, Expired 2`. Per-player per-spell breakdown is readable out of combat with plain numbers (`spellID`, `totalAmount`, `amountPerSecond`); auto attack is spell 6603. Spell IDs are the cast rank / proc spell (e.g. Deep Wound 412613, Rend 11572). | Fight report works from session history. Attribution needs a rank → base-spell map in the bundled data. |
| 7 | Trait tooltips/descriptions | `C_Traits.GetTraitDescription` and `C_Spell.GetSpellDescription` **returned ""** for a sample talent (Enrage), but the inspector showed text for others: spell data loads lazily. `C_TooltipInfo.GetTraitEntry` exists (lines: "", "Passive"). | Request spell data (`C_Spell.RequestLoadSpellData`) and refresh on `SPELL_DATA_LOAD_RESULT`; fall back to bundled text. |
| 8 | `C_AssistedCombat` | Exists, `IsAvailable()` → false, "WRONG_WORLD_STATE_EXPRESSION". | Info only. |

## Other findings

- **`TraitCondInfo.spentAmountRequired` is what is still missing** in the given config, not the gate: Arms talents read 0 with 31 points in Arms, Fury talents 5…30. Tier gates therefore come from the layout (row × 5), which matches the DB2 `TraitCond` rows.
- Layout from `posX`/`posY` matches the Blizzard talent window (checked in-game, Warrior).
- One spec group at level 40 until dual spec is bought: `GetNumSpecGroups()` = 1.
- Config type 4 (`CamelotCombat`), name = class name; one point currency 3820.
- Prerequisite arrows are `visibleEdges` (e.g. Sweeping Strikes → Mortal Strike).

## Open questions

- [ ] In-combat stat secrecy (Q5) and the after-combat damage meter sample (Q6): fight once after `/batlas probe`, then `/reload`.
- [ ] Milestone talents (11/16/21/31 points): no node with `ranksGranted` seen on Warrior yet.
- [ ] Is "prerequisite maxed" the rule for every edge type?
- [ ] Apply: `C_Traits.PurchaseRank` per rank then `C_Traits.CommitConfig(configID)` on the active combat config; does the commit cast fire `TRAIT_CONFIG_UPDATED` (success) / `CONFIG_COMMIT_FAILED`?
- [ ] Import strings: does the game's own import accept a string exported by Build Atlas (zero tree hash for Wowhead links)?
- [ ] `C_Item.GetItemStats` keys for Forever items (crit/hit may be spell effects rather than stats on Classic items).
- [ ] Enchant ID position in item links (`item:ID:enchant:...`).
- [ ] Pawn: does `PawnImportScale(tag, true)` exist and import the scale?
- [ ] Addon messages: `CHAT_MSG_ADDON` delivery for party, guild and whisper with prefix "BuildAtlas".
