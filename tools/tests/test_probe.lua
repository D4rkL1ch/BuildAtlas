local T = ...

T.test("probe: runs every step and saves results", function()
	local ns = T.boot()
	T.stubs.slash("probe")
	local p = BuildAtlasDB.probe
	T.ok(p, "saved")
	local step, err = next(p.errors)
	T.eq(step, nil, "failed step: " .. tostring(err))
	T.eq(p.meta.build, "1.60.1.70862")
	T.eq(p.meta.isForever, true)
	T.eq(p.q1_trees.specs[1491].treeID, 1117)
	T.eq(#p.q1_trees.specs[1491].groups, 3)
	T.eq(p.q3_importString.result.ok, true)
	T.eq(p.ownTree.treeID, 1117)
	T.eq(#p.ownTree.nodes, 9)
	T.eq(p.q5_stats.outOfCombat.values.GetCritChance, "number:5.2")
	T.contains(table.concat(T.stubs.printed, "\n"), "Probe saved")
	local _ = ns
end)

T.test("probe: in-combat and after-combat samples fill in", function()
	T.boot()
	T.stubs.slash("probe")
	T.stubs.combat = true
	T.stubs.fire("PLAYER_REGEN_DISABLED")
	T.stubs.runTimers()
	local stats = BuildAtlasDB.probe.q5_stats.inCombat
	T.eq(stats.values.GetCritChance, "secret", "secret stat detected")
	T.eq(stats.values.UnitHealth, "secret")
	T.stubs.combat = false
	T.stubs.fire("PLAYER_REGEN_ENABLED")
	T.stubs.runTimers()
	local dm = BuildAtlasDB.probe.q6_damageMeter.afterCombat
	T.eq(dm.playerSpells.spells[1].spellID, "number:5005")
	T.eq(dm.lastSession.sources[1].isLocalPlayer, true)
end)

T.test("probe: secret values never reach SavedVariables", function()
	local ns = T.boot()
	local clean = ns.Secrets.Sanitize({ a = { __secret = true }, b = { c = 1 }, f = print })
	T.eq(clean.a, "<secret>")
	T.eq(clean.b.c, 1)
	T.eq(clean.f, "<function>")
	T.eq(ns.Secrets.Read("fallback", function() return { __secret = true } end), "fallback")
	T.eq(ns.Secrets.Read("fallback", function() error("boom") end), "fallback")
end)
