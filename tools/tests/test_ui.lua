local T = ...

local function open()
	local ns = T.boot()
	T.stubs.slash("")
	return ns, ns.Window.frame
end

T.test("ui: /atlas opens the planner with the live tree", function()
	local ns, frame = open()
	T.ok(frame and frame:IsShown(), "window shown")
	local text = T.stubs.visibleText(frame)
	T.contains(text, "Arms")
	T.contains(text, "Protection")
	T.contains(text, "5 / 0 / 0", "scratch starts from the active spec")
	T.contains(text, "5 of 51 points spent")
	T.contains(text, "Matches Spec 1")
	T.contains(text, "No synergy data")
	local state = ns.Planner._State()
	T.eq(state.selected, 101, "first learned talent selected")
	T.stubs.slash("")
	T.eq(frame:IsShown(), false, "/atlas toggles")
end)

T.test("ui: plus/minus change the plan, not the game", function()
	local ns, frame = open()
	ns.Planner.Select(102)
	ns.Planner.Change(102, 1)
	local _, _, ranks = ns.Planner._State()
	T.eq(ranks[102], 3)
	T.contains(T.stubs.visibleText(frame), "Differs from Spec 1 by 1 points")
	T.eq(T.stubs.ranks[7001][102], 2, "live config untouched")
	-- Saved per class and slot.
	T.eq(BuildAtlasCharDB.plans[1].scratch.ranks[102], 3)
end)

T.test("ui: blocked changes explain why", function()
	local ns = open()
	ns.Planner.Change(105, 1)
	T.contains(table.concat(T.stubs.uiErrors or {}, "\n"), "Needs 30 points in Arms")
end)

T.test("ui: read-only in combat", function()
	local ns, frame = open()
	T.stubs.combat = true
	T.stubs.fire("PLAYER_REGEN_DISABLED")
	ns.Planner.Change(102, 1)
	local _, _, ranks = ns.Planner._State()
	T.eq(ranks[102], 2)
	T.contains(T.stubs.visibleText(frame), "In combat")
	T.stubs.runTimers()
end)

T.test("ui: spec 2 slot loads that spec's talents", function()
	local ns, frame = open()
	ns.Planner.SetSlot("spec2")
	T.contains(T.stubs.visibleText(frame), "0 / 0 / 5")
	T.contains(T.stubs.visibleText(frame), "Spec 2 · Protection")
	ns.Planner.SetSlot("scratch")
	T.contains(T.stubs.visibleText(frame), "5 / 0 / 0")
end)

T.test("ui: synergy data drives rings, strip and inspector", function()
	local ns = T.boot()
	ns.ClassData = { [1] = { build = "1.60.1.70862", talents = {
		[5001] = { mods = { { spell = 78, fx = "-1 rage per rank" } }, stats = { "Strength" } },
		[5004] = { mods = { { spell = 78, fx = "crit procs" } }, note = "Proc chain" },
	} } }
	T.stubs.slash("")
	local frame = ns.Window.frame
	ns.Planner.Select(101)
	local text = T.stubs.visibleText(frame)
	T.contains(text, "Spell78")
	T.contains(text, "SYNERGIZES WITH")
	T.contains(text, "Not taken")
	T.contains(text, "matches client")
	ns.Planner.FocusSpell(78)
	T.contains(T.stubs.visibleText(frame), "2 talents across all trees")
end)

T.test("ui: other class without a tree shows the reason", function()
	local ns, frame = open()
	ns.Planner.SetClass(9)
	T.contains(T.stubs.visibleText(frame), "Couldn't find the talent tree")
	ns.Planner.SetClass(1)
	T.contains(T.stubs.visibleText(frame), "Arms")
end)

T.test("ui: addon compartment entry registered", function()
	T.boot()
	T.eq(#AddonCompartmentFrame.registered, 1)
end)
