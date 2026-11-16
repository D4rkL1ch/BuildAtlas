local T = ...

-- A preset on the stub tree: 5 Arms points then a Fury one.
local function fakePresets(ns)
	ns.PresetData = { {
		classID = 1, name = "Test build", role = "Damage", author = "Tester", license = "CC0", why = "Because.",
		keys = { "IHS" }, play = { "Press buttons." }, split = "10/1/0", build = ns.DATA_BUILD,
		order = { { 5001, 3 }, { 5002, 2 }, { 5003, 5 }, { 5101, 1 } },
	} }
end

T.test("presets: resolved on the live tree and loaded into the planner", function()
	local ns = T.boot()
	fakePresets(ns)
	local list = ns.Presets.ForClass(1)
	T.eq(#list, 1)
	T.eq(list[1].ranks[101], 3)
	T.eq(list[1].ranks[103], 5)
	T.eq(list[1].valid, true)
	T.stubs.slash("")
	ns.Window.Show("presets")
	local text = T.stubs.visibleText(ns.Window.frame)
	T.contains(text, "Test build")
	T.contains(text, "Tester · CC0")
	T.contains(text, "Press buttons.")
	local load
	for _, w in ipairs(T.stubs.allWidgets()) do
		if w.Label and w.Label.text == "Load into planner" and w:IsShown() then load = w end
	end
	T.stubs.click(load)
	local _, _, ranks = ns.Planner._State()
	T.eq(ranks[103], 5)
	T.eq(ns.Window.current, "planner")
end)

T.test("presets: a talent missing from the tree makes the preset unusable", function()
	local ns = T.boot()
	fakePresets(ns)
	ns.PresetData[1].order[1] = { 999999, 1 }
	local list = ns.Presets.ForClass(1)
	T.eq(list[1].ranks, nil)
	T.eq(list[1].valid, false)
end)

T.test("leveling: path from an order and from a plan", function()
	local ns = T.boot()
	fakePresets(ns)
	local tree = ns.Talents.ReadTree(1)
	local steps = ns.Presets.PathFromOrder(tree, ns.PresetData[1].order)
	T.eq(#steps, 11)
	T.eq(steps[1].level, 10)
	T.eq(steps[1].id, 101)
	T.eq(steps[11].id, 201)
	-- From a plan: always legal, lowest tier first.
	local plan = { [101] = 3, [102] = 2, [103] = 5, [104] = 3 }
	local path = ns.Presets.PathFromPlan(tree, plan)
	T.eq(#path, 13)
	local ranks = {}
	for _, s in ipairs(path) do
		T.ok(ns.Plan.CanIncrease(tree, ranks, s.id), "step " .. s.level .. " legal")
		ranks[s.id] = s.rank
	end
	T.eq(table.concat(ns.Presets.SplitAt(tree, path, 13), "/"), "13/0/0")
end)

T.test("leveling: pane and level-up reminder (never learns)", function()
	local ns = T.boot()
	fakePresets(ns)
	T.stubs.slash("")
	ns.Window.Show("leveling")
	T.contains(T.stubs.visibleText(ns.Window.frame), "LEVELING PATH")
	T.stubs.fire("PLAYER_LEVEL_UP", 12)
	T.stubs.runTimers()
	T.eq(#T.stubs.purchased, 0, "nothing learned")
end)

T.test("stat weights: estimate, parse Pawn and SimC, score items", function()
	local ns = T.boot()
	local SW = ns.StatWeights
	local w = SW.Estimate("Physical", { { stat = "Crit", a = 3, b = 0 } })
	T.ok(w.Crit > 10, "crit nudged up by talents")
	local pawn = SW.ToPawn({ Strength = 1, Crit = 10.5 }, "Test")
	T.eq(pawn, '( Pawn: v1: "Test": Strength=1, CritRating=10.5 )')
	local parsed, name = SW.Parse(pawn)
	T.eq(name, "Test")
	T.eq(parsed.Strength, 1)
	T.eq(parsed.Crit, 10.5)
	local simc = SW.Parse("Strength=2.10, AttackPower=0.95, Hit_Rating=18")
	T.eq(simc["Attack power"], 0.95)
	T.eq(simc.Hit, 18)
	T.eq(SW.Parse("nothing here"), nil)
	T.eq(SW.Score({ ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_CRIT_RATING_SHORT = 1 }, { Strength = 1, Crit = 10 }), 20)
	T.eq(SW.GuessRole({ { stat = "Block", a = 3, b = 0 }, { stat = "Defense", a = 2, b = 0 } }, "WARRIOR"), "Tank")
	T.eq(SW.GuessRole({}, "MAGE"), "Caster")
end)

T.test("gear: upgrades from bags, consumables, enchants, Pawn fallback", function()
	local ns = T.boot()
	T.stubs.slash("")
	local weights = ns.StatWeights.Estimate("Physical", {})
	local ups = ns.Gear.Upgrades(weights)
	T.eq(#ups, 1)
	T.eq(ups[1].link, "item:1:0")
	T.ok(ups[1].pct > 0, "better than the equipped sword")
	local cons = ns.Gear.Consumables("Physical")
	local mongoose
	for _, c in ipairs(cons) do if c.id == 13452 then mongoose = c end end
	T.eq(mongoose.count, 3)
	local missing = ns.Gear.MissingEnchants()
	T.eq(table.concat(missing, ","), "Chest,Main hand")
	local ok, tag = ns.Gear.SendToPawn()
	T.eq(ok, false, "no Pawn in stubs")
	T.contains(tag, "Pawn: v1:")
	ns.Window.Show("gear")
	T.contains(T.stubs.visibleText(ns.Window.frame), "Own estimate (rough)")
end)
