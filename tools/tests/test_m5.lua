local T = ...

T.test("attribution: effect percent from text and rank texts", function()
	local ns = T.boot()
	local A = ns.Attribution
	T.eq(A.EffectPercent("+12/23/35% periodic damage", 2), 23)
	T.eq(A.EffectPercent("+1% damage per rank", 3), 3)
	T.eq(A.EffectPercent("+5% crit", 1), 5)
	T.eq(A.EffectPercent("more damage with two-handers", 3, { "by 2%.", "by 4%.", "by 6%." }), 6)
	T.eq(A.EffectPercent("named in its effect", 1), nil)
end)

T.test("attribution: direct, modeled and rough rows", function()
	local ns = T.boot()
	local classData = {
		talents = {
			[1] = { name = "Mortal Strike", mods = { { spell = 100, fx = "grants the ability" } }, ranks = { "x" } },
			[2] = { name = "Improved Rend", mods = { { spell = 200, fx = "+12/23/35% periodic damage" } }, ranks = { "a", "b", "c" } },
			[3] = { name = "Cruelty", mods = { { spell = 300, fx = "more melee crits" } }, ranks = { "1%", "2%", "3%", "4%", "5%" } },
			[4] = { name = "Deep Wounds", mods = {}, ranks = { "a" } },
		},
		rankOf = { [201] = 200 }, procOf = { [400] = 4 },
	}
	local fight = { spells = { [100] = 1000, [201] = 1350, [300] = 2000, [400] = 500, [999] = 150 } }
	local est = ns.Attribution.Estimate(fight, classData, { [1] = 1, [2] = 3, [3] = 5, [4] = 1 })
	T.eq(est.total, 5000)
	local byName = {}
	for _, r in ipairs(est.rows) do byName[r.name] = r end
	T.eq(byName["Mortal Strike"].amount, 1000)
	T.eq(byName["Mortal Strike"].method, "Direct")
	T.eq(byName["Deep Wounds"].amount, 500, "proc damage")
	T.eq(math.floor(byName["Improved Rend"].amount + 0.5), 350, "1350 × 0.35/1.35")
	T.eq(byName["Improved Rend"].method, "Modeled")
	T.eq(byName.Cruelty.method, "Rough")
	T.ok(byName.Cruelty.amount > 0 and byName.Cruelty.amount < 200, "rough crit share")
	T.ok(est.share > 0.3 and est.share < 0.5, "share " .. est.share)
end)

T.test("attribution: merge fights and benchmark summary", function()
	local ns = T.boot()
	local m = ns.Attribution.Merge({ { name = "A", spells = { [1] = 10 }, duration = 10, total = 10 }, { name = "B", spells = { [1] = 5, [2] = 5 }, duration = 5, total = 10 } })
	T.eq(m.spells[1], 15)
	T.eq(m.duration, 15)
	T.eq(m.name, "2 fights")
	local groups, overlap = ns.Attribution.BenchSummary({
		{ tag = "X", dps = 400, gear = "g" }, { tag = "X", dps = 420, gear = "g" },
		{ tag = "Y", dps = 380, gear = "g" }, { tag = "Y", dps = 900, gear = "other" },
	}, "g")
	T.eq(groups[1].tag, "X")
	T.eq(groups[1].avg, 410)
	T.eq(groups[2].n, 1, "other gear left out")
	T.eq(overlap, false)
end)

T.test("measure: fight captured after combat with a notice", function()
	local ns = T.boot()
	T.stubs.combat = true
	T.stubs.fire("PLAYER_REGEN_DISABLED")
	T.stubs.combat = false
	T.stubs.fire("PLAYER_REGEN_ENABLED")
	T.stubs.runTimers()
	local f = BuildAtlasCharDB.fights[1]
	T.ok(f, "fight stored")
	T.eq(f.name, "Hogger")
	T.eq(f.spells[5005], 600)
	T.eq(f.duration, 72)
	T.eq(f.talents[5001], 3, "talents keyed by spell")
	T.eq(ns.Measure.Capture(), nil, "same session not captured twice")
	ns.Window.Show("report")
	T.contains(T.stubs.visibleText(ns.Window.frame), "Hogger")
end)

T.test("measure: secret values are never stored", function()
	local ns = T.boot()
	C_DamageMeter.GetCombatSessionSourceFromID = function()
		return { combatSpells = { { spellID = 1, totalAmount = { __secret = true } } } }
	end
	T.eq(ns.Measure.Capture(), nil)
	T.eq(#BuildAtlasCharDB.fights, 0)
end)

T.test("benchmark: armed run recorded, then shown", function()
	local ns = T.boot()
	ns.Measure.Arm(60, "Spec 1 · Arms")
	T.stubs.combat = true
	T.stubs.fire("PLAYER_REGEN_DISABLED")
	T.stubs.combat = false
	T.stubs.fire("PLAYER_REGEN_ENABLED")
	T.stubs.runTimers()
	local runs = ns.Measure.Runs()
	T.eq(#runs, 1)
	T.eq(runs[1].tag, "Spec 1 · Arms")
	T.eq(BuildAtlasCharDB.armed, nil, "disarmed after the run")
	ns.Window.Show("bench")
	local text = T.stubs.visibleText(ns.Window.frame)
	T.contains(text, "Spec 1 · Arms")
	T.contains(text, "Record runs on a second build")
end)
