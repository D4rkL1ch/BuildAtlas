# Probe results (milestone M0)

How to run: log in on Forever, `/batlas probe`, fight anything once (a training dummy is fine), wait for the "combat samples recorded" chat line, then `/reload`. The results land in `BuildAtlasDB.probe` (account SavedVariables).

Status: **in-game run pending**. The column "From Blizzard source" is what the Forever branch of Blizzard's UI code (Gethe/wow-ui-source, `forever` branch) already shows; the in-game run confirms or corrects it.

| # | Question | From Blizzard source | In game |
|---|---|---|---|
| 1 | Can we read other classes' trees? Full tree-ID table? | `C_ClassTalents.GetTraitTreeForSpec(specID)` exists. Forever spec IDs are one per class: Mage 1482, Druid 1484, Hunter 1485, Paladin 1486, Priest 1487, Rogue 1488, Shaman 1489, Warlock 1490, Warrior 1491 (`Blizzard_ClassTalentUtil.lua`, `SpecializationVisuals`). `C_Traits.GetTreeNodes(treeID)` needs no config; `GetNodeInfo` needs one. | pending (`q1_trees`) |
| 2 | Do `InitializeViewLoadout` / `ViewLoadout` work? | Both documented. View config ID is `Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID` = -3. The planner uses this path for other classes. | pending (`q2_viewLoadout`) |
| 3 | Does `C_Traits.GenerateImportString` exist / work? | Documented (`configID` → string), plus `GenerateInspectImportString(target)` and `GetLoadoutSerializationVersion`. | pending (`q3_importString`) |
| 4 | LibTalentTree `GetClassTreeID` on live? | Not bundled. Probe only checks if another addon loaded it. With Q1 working we may not need it. | pending (`q4_libTalentTree`) |
| 5 | Do character stats go secret in combat? | `C_Secrets.ShouldUnitStatsBeSecret()` exists (no arguments). | pending (`q5_stats.inCombat`) |
| 6 | `C_DamageMeter` out-of-combat data shape | `GetAvailableCombatSessions()` → `{sessionID, name, durationSeconds}`; `GetCombatSessionFromID(id, Enum.DamageMeterType.DamageDone)` → `combatSources[]` (`isLocalPlayer`, `totalAmount`, `amountPerSecond`; `name`/`sourceGUID` conditionally secret); `GetCombatSessionSourceFromID(id, type, guid)` → `combatSpells[]` (`spellID`, `totalAmount`, `amountPerSecond`, `overkillAmount`, …). | pending (`q6_damageMeter.afterCombat`) |
| 7 | Tooltip access for trait entries | `C_Traits.GetTraitDescription(entryID, rank)` is documented: per-rank text without tooltip scanning. The planner uses it. | pending (`q7_tooltips`) |
| 8 | `C_AssistedCombat` enabled? | Info only. | pending (`q8_assistedCombat`) |

## Also confirmed from Blizzard source

- Each spec group (dual spec) has its own combat config: `C_SpecializationInfo.GetCombatConfigIDForSpecGroup(1|2)`; active group from `C_SpecializationInfo.GetActiveSpecGroup()`. Dual spec unlocked when `GetNumSpecGroups() > 1`.
- Tab headers: `C_Traits.GetGroupDisplayInfoByTreeID(treeID)` (`groupID`, `displayName`, `icon`, `orderIndex`) and per-tab points from `C_Traits.GetGroupCurrencyInfo(configID, groupIDs)[i].currencyInfos[1].spent`.
- Inspect works on Forever (`INSPECT_READY` handled in the Camelot talent frame): "inspecting other players" is possible later.
- No loadouts (`LoadSystem` hidden), no PvP talents.

## Open questions

- [ ] Layout: the planner turns `posX`/`posY` into a 4-column grid per tab. Check that columns line up with the Blizzard talent window (`ownTree.nodes` has the raw positions).
- [ ] Tier gates: does each node carry a condition with `spentAmountRequired`, or only some (fallback is row × 5)?
- [ ] Milestone talents (11/16/21/31 points): how are they represented? Nodes with a `ranksGranted` condition are treated as free and auto-granted.
- [ ] Do prerequisites show up as `visibleEdges`, and is "source maxed" the rule?
- [ ] `GetSpellCritChance` arguments on Forever (retail takes none).
