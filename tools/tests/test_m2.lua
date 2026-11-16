local T = ...

-- Fake class data matching the stub tree (spells 5001...).
local function fakeData(ns)
	ns.ClassData[1] = {
		build = ns.DATA_BUILD,
		talents = {
			[5001] = { name = "Improved Heroic Strike", max = 3, mods = { { spell = 78, fx = "−1 Rage cost per rank" } }, stats = { "Weapon damage" },
				ranks = { "Reduces the cost by 1 Rage.", "Reduces the cost by 2 Rage.", "Reduces the cost by 3 Rage." }, classic = "Same as Classic." },
			[5002] = { name = "Deflection", max = 5, mods = { { spell = 78, fx = "more parries" } }, stats = { "Parry" }, ranks = { "1%", "2%", "3%", "4%", "5%" } },
			[5004] = { name = "Deep Wounds", max = 3, mods = { { spell = 78, fx = "crits bleed" } }, stats = { "Crit" }, note = "Proc chain", ranks = { "20%", "40%", "60%" }, classic = "New in Forever." },
		},
		spells = { [78] = { name = "Heroic Strike", scales = { "Weapon damage" } } },
		rankOf = { [285] = 78 },
		procOf = {},
	}
end

T.test("tooltip: rank values pulled from rank texts", function()
	local ns = T.boot()
	local v = ns.TalentTooltip.RankValues({ "bleed for 20% over 12 sec", "bleed for 40% over 12 sec", "bleed for 60% over 12 sec" })
	T.eq(table.concat(v, ","), "20%,40%,60%")
	T.eq(ns.TalentTooltip.RankValues({ "a 1 b 2", "a 2 b 3" }), nil, "two columns change")
	T.eq(ns.TalentTooltip.RankValues({ "same" }), nil)
end)

T.test("tooltip: planner talent tooltip has synergy and classic blocks", function()
	local ns = T.boot()
	fakeData(ns)
	T.stubs.slash("")
	local frame = ns.Window.frame
	local node
	for _, w in ipairs(T.stubs.allWidgets()) do
		if w.nodeID == 101 and w:IsShown() then node = w end
	end
	T.ok(node, "node button")
	node.scripts.OnEnter(node)
	local text = T.stubs.tooltipText()
	T.contains(text, "Spell5001 | Rank 3/3")
	T.contains(text, "SYNERGY")
	T.contains(text, "Changes | Heroic Strike")
	T.contains(text, "Works with | Spell5002 2/5")
	T.contains(text, "CHANGED VS CLASSIC")
	T.contains(text, "Hold Ctrl")
	T.stubs.ctrl = true
	node.scripts.OnEnter(node)
	T.contains(T.stubs.tooltipText(), "spell 5001 · node 101")
	local _ = frame
end)

T.test("tooltip: spell tooltips list talents of the current build", function()
	local ns = T.boot()
	fakeData(ns)
	T.stubs.runTimers()
	local text = T.stubs.showSpellTooltip(285) -- a Heroic Strike rank
	T.contains(text, "changed by 2 talents")
	T.contains(text, "Spell5002 2/5 | more parries")
	T.contains(text, "Spell5001 3/3 | −1 Rage cost per rank")
	T.eq(T.stubs.showSpellTooltip(9999), "Spell 9999", "unrelated spell untouched")
	BuildAtlasDB.settings.spellTooltips = false
	T.eq(T.stubs.showSpellTooltip(285), "Spell 285", "setting off")
end)

T.test("toasts: stack, dedupe, expire, action", function()
	local ns = T.boot()
	local ran = false
	local t1 = ns.Toasts.Show("info", "Fight report ready", "Hogger · 412 DPS", { text = "Open report", run = function() ran = true end })
	ns.Toasts.Show("warn", "Other", "x")
	ns.Toasts.Show("info", "Fight report ready", "again")
	T.ok(t1:IsShown(), "re-used for the same title")
	T.stubs.click(t1.Action)
	T.ok(ran, "action ran")
	T.eq(t1:IsShown(), false, "closed after action")
end)

T.test("toasts: data older than client noticed once", function()
	local ns = T.boot()
	-- Stub client 70862 is older than the data (70938): no notice.
	T.stubs.runTimers()
	T.eq(BuildAtlasDB.notifiedBuild, nil)
	ns.DATA_BUILD = "1.60.1.70000"
	T.stubs.fire("PLAYER_LOGIN")
	T.stubs.runTimers()
	T.eq(BuildAtlasDB.notifiedBuild, "1.60.1.70862")
end)

T.test("launcher: minimap button and slash commands", function()
	local ns = T.boot()
	T.stubs.slash("minimap")
	T.eq(BuildAtlasDB.settings.minimapIcon, false)
	T.stubs.slash("minimap")
	T.eq(BuildAtlasDB.settings.minimapIcon, true)
	ns.Launcher.Click("LeftButton")
	T.ok(ns.Window.IsShown(), "click opens the planner")
	T.eq(ns.Window.current, "planner")
	T.stubs.shift = true
	ns.Launcher.Click("LeftButton")
	T.eq(ns.Window.current, "report")
end)
