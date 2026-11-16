local T = ...

local function fakeData(ns)
	ns.ClassData[1] = {
		build = ns.DATA_BUILD,
		talents = {
			[5001] = { name = "IHS", max = 3, mods = { { spell = 78, fx = "cheaper" } }, stats = { "Weapon damage" }, ranks = { "a", "b", "c" } },
			[5002] = { name = "Deflection", max = 5, mods = {}, stats = { "Parry" }, ranks = { "1", "2", "3", "4", "5" } },
			[5004] = { name = "Deep Wounds", max = 3, mods = { { spell = 78, fx = "bleeds" }, { spell = 6603, fx = "crits bleed" } }, stats = { "Crit" },
				note = "Proc chain: crit → bleed.", ranks = { "a", "b", "c" } },
			[5101] = { name = "Cruelty", max = 5, mods = { { spell = 6603, fx = "more crits" } }, stats = { "Crit" }, ranks = { "1", "2", "3", "4", "5" } },
			[5201] = { name = "Shield Spec", max = 5, mods = {}, stats = { "Block" }, note = "Resource loop: blocks give Rage.", ranks = { "1", "2", "3", "4", "5" } },
		},
		spells = { [78] = { name = "Heroic Strike", scales = { "Weapon damage" } }, [6603] = { name = "Auto Attack", scales = {} } },
		rankOf = {}, procOf = {},
	}
end

T.test("compare model: diff, spells, lean, summary", function()
	local ns = T.boot()
	fakeData(ns)
	local tree = ns.Talents.ReadTree(1)
	local graph = ns.SynergyGraph.New(tree, ns.ClassData[1])
	local a = { [101] = 3, [102] = 5, [201] = 5 }
	local b = { [101] = 3, [301] = 5 }
	local diff = ns.Compare.Diff(tree, a, b, graph)
	T.eq(#diff.onlyA, 2)
	T.eq(#diff.onlyB, 1)
	T.eq(diff.onlyB[1].id, 301)
	T.eq(diff.sharedPerGroup[1], 3)
	T.eq(diff.spells[1].spell, 6603, "Auto Attack differs most")
	T.eq(diff.spells[1].a, 1)
	T.eq(diff.spells[1].b, 0)
	local summary = ns.Compare.Summary(diff, "A", "B")
	T.contains(summary, "A leans")
	T.contains(summary, "B leans Block")
	T.eq(ns.Compare.Summary(ns.Compare.Diff(tree, a, a, graph)), "The builds are identical.")
end)

T.test("compare model: synergy map columns and chains", function()
	local ns = T.boot()
	fakeData(ns)
	local tree = ns.Talents.ReadTree(1)
	local graph = ns.SynergyGraph.New(tree, ns.ClassData[1])
	local ranks = { [101] = 3, [104] = 1, [301] = 2 }
	local map = ns.Compare.SynergyMap(tree, ranks, graph, true)
	T.eq(map.spells[1].spell, 78)
	T.eq(#map.spells[1].talents, 2)
	local all = ns.Compare.SynergyMap(tree, ranks, graph, false)
	T.eq(#all.talents, 3, "all talents with links")
	local chains = ns.Compare.Chains(tree, ranks, graph)
	T.eq(chains.procs[1].text, "crit → bleed.")
	T.eq(chains.loops[1].text, "blocks give Rage.")
end)

T.test("compare pane: sources and render", function()
	local ns = T.boot()
	fakeData(ns)
	T.stubs.slash("")
	ns.Planner.Change(102, 1)
	ns.Window.Show("compare")
	local list = ns.ComparePane.Sources()
	T.ok(#list >= 3, "live specs and plans")
	local text = T.stubs.visibleText(ns.Window.frame)
	T.contains(text, "ONLY IN A")
	T.contains(text, "Not a simulation")
end)

T.test("synergy pane: picks a spell and lights its talents", function()
	local ns = T.boot()
	fakeData(ns)
	T.stubs.slash("")
	ns.Window.Show("synergy")
	local text = T.stubs.visibleText(ns.Window.frame)
	T.contains(text, "Heroic Strike")
	T.contains(text, "PROC CHAINS")
	T.contains(text, "Weapon damage")
end)
