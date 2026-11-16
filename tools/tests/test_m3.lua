local T = ...

local function openPlanner()
	local ns = T.boot()
	T.stubs.slash("")
	return ns
end

T.test("share: export tabs produce strings that import back", function()
	local ns = openPlanner()
	local current = ns.Planner.Current()
	T.ok(current, "current plan")
	for _, fmt in ipairs({ "atlas", "blizzard", "wowhead", "simc" }) do
		local text = ns.Share.Export(current, fmt)
		T.ok(text and #text > 10, fmt .. " export")
		local result, err = ns.Share.Import(text)
		T.ok(result, fmt .. " import: " .. tostring(err))
		T.eq(result.classID, 1)
		for id, r in pairs(current.ranks) do T.eq(result.ranks[id], r, fmt .. " node " .. id) end
	end
end)

T.test("share: pane shows export, detects import, loads scratch", function()
	local ns = openPlanner()
	ns.Window.Show("share")
	local frame = ns.Window.frame
	T.contains(T.stubs.visibleText(frame), "EXPORT · Warrior · Scratch plan")
	local text = ns.Share.Export(ns.Planner.Current(), "atlas")
	-- Change the plan, then import the old string back into scratch.
	ns.Planner.Change(102, 1)
	ns.Share.SetImportText(text)
	T.contains(T.stubs.visibleText(frame), "Detected: Build Atlas · Warrior")
	ns.Window.Show("share")
	ns.Share.SetImportText(text)
	local loadButton
	for _, w in ipairs(T.stubs.allWidgets()) do
		if w.Label and w.Label.text == "Load into scratch plan" then loadButton = w end
	end
	T.stubs.click(loadButton)
	local _, _, ranks = ns.Planner._State()
	T.eq(ranks[102], 2, "import restored the old rank")
	T.eq(ns.Window.current, "planner")
end)

T.test("share: unsupported and broken input explained", function()
	local ns = openPlanner()
	local r, err = ns.Share.Import("https://talentsforever.com/warrior/xyz")
	T.eq(r, nil)
	T.contains(err, "aren't supported yet")
	r, err = ns.Share.Import("!!!")
	T.contains(err, "Not a talent string")
end)

T.test("share: send over addon channel, not in instances", function()
	local ns = openPlanner()
	T.ok(ns.Share.Send("GUILD"), "sent")
	local msg = T.stubs.sentAddon[1]
	T.eq(msg[1], "BuildAtlas")
	T.ok(msg[2]:find("^BA1:1:"), msg[2])
	T.eq(msg[3], "GUILD")
	T.stubs.instance = true
	T.eq(ns.Share.Send("GUILD"), false)
	T.eq(#T.stubs.sentAddon, 1)
end)

T.test("share: received build shows a notice that opens it", function()
	local ns = openPlanner()
	local text = ns.Share.Export(ns.Planner.Current(), "atlas")
	T.stubs.fire("CHAT_MSG_ADDON", "BuildAtlas", text, "GUILD", "Friend-Realm")
	T.eq(BuildAtlasDB.received[1].from, "Friend-Realm")
	T.stubs.fire("CHAT_MSG_ADDON", "BuildAtlas", "garbage", "GUILD", "Other")
	T.eq(#BuildAtlasDB.received, 1, "junk ignored")
end)

T.test("apply: learns only the missing ranks and commits", function()
	local ns = openPlanner()
	ns.Planner.Change(102, 1) -- 3/5
	ns.Planner.Change(102, 1) -- 4/5
	ns.ApplyDialog.Open()
	local a = ns.ApplyDialog.Analyze(ns.Planner.Current())
	T.eq(#a.blockers, 0, "no blockers: " .. table.concat(a.blockers, "; "))
	T.eq(a.addPoints, 2)
	ns.ApplyDialog.Run(a)
	T.eq(#T.stubs.purchased, 2)
	T.eq(T.stubs.committed, 7001)
	T.eq(ns.ApplyDialog._Job().state, "saving")
	T.stubs.fire("TRAIT_CONFIG_UPDATED", 7001)
	T.eq(ns.ApplyDialog._Job().state, "success")
end)

T.test("apply: refuses removals, combat, staged changes; rolls back failures", function()
	local ns = openPlanner()
	ns.Planner.Change(102, -1) -- below the live rank: needs a trainer reset
	local a = ns.ApplyDialog.Analyze(ns.Planner.Current())
	T.contains(table.concat(a.blockers, "\n"), "removes 1 points")
	ns.Planner.Change(102, 1)
	ns.Planner.Change(102, 1)
	T.stubs.staged = true
	T.stubs.combat = true
	a = ns.ApplyDialog.Analyze(ns.Planner.Current())
	local text = table.concat(a.blockers, "\n")
	T.contains(text, "in combat")
	T.contains(text, "unsaved changes")
	T.stubs.staged, T.stubs.combat = false, false
	T.stubs.refuseCommit = true
	a = ns.ApplyDialog.Analyze(ns.Planner.Current())
	ns.ApplyDialog.Run(a)
	T.eq(T.stubs.rolledBack, 7001)
	T.eq(ns.ApplyDialog._Job().state, "failed")
end)

T.test("apply: level limit learns the first points in tier order", function()
	local ns = openPlanner()
	T.stubs.unspent = 1
	ns.Planner.Change(102, 1)
	ns.Planner.Change(201, 1)
	local a = ns.ApplyDialog.Analyze(ns.Planner.Current())
	T.contains(table.concat(a.notes, "\n"), "Only 1 points")
	ns.ApplyDialog.Run(a)
	T.eq(#T.stubs.purchased, 1)
end)
