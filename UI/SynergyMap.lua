local addonName, ns = ...

-- Synergy map (design/SynergyMap.dc.html): Talents -> Spells -> Stats for the
-- plan shown in the planner. Pick a spell to light up the talents that change
-- it and what it scales with. Proc chains and resource loops underneath.

local UI, L = ns.UI, ns.L
local Compare = ns.Compare

local Map = {}
ns.SynergyMap = Map

local COL_H = 470
local pane
local state = { mine = true, spell = nil }

local function rows(col, create)
	col.rows = UI.Pool(col.Content, create or function(p)
		local b = CreateFrame("Button", nil, p, "BackdropTemplate")
		b:SetHeight(24)
		b.Left = UI.Text(b, 12, "text")
		b.Left:SetPoint("LEFT", 8, 0)
		b.Right = UI.Text(b, 12, "muted", "body", "RIGHT")
		b.Right:SetPoint("RIGHT", -8, 0)
		return b
	end)
end

function Map.Render()
	local current = ns.Planner.Current()
	for _, col in ipairs(pane.cols) do col.rows:ReleaseAll() end
	pane.strips.rows:ReleaseAll()
	if not current then return end
	local tree, ranks, graph = current.tree, current.ranks, current.graph
	pane.mine:SetOn(state.mine)
	pane.all:SetOn(not state.mine)
	pane.subtitle:SetText(L["SYNERGY MAP · "] .. current.label)
	if not graph.hasData then
		pane.intro:SetText(L["No synergy data for this class in this version."])
		return
	end
	pane.intro:SetText(L["Pick a spell to see which talents change it and what it scales with. Links come from the game's spell data plus a hand-checked list of fixes per class."])

	local map = Compare.SynergyMap(tree, ranks, graph, state.mine)
	local selected
	for _, s in ipairs(map.spells) do
		if s.spell == state.spell then selected = s end
	end
	if not selected then
		selected = map.spells[1]
		state.spell = selected and selected.spell
	end
	local lit = {}
	if selected then
		for _, id in ipairs(selected.talents) do lit[id] = true end
	end

	-- Talents column
	local col, y = pane.cols[1], 0
	local talentIDs = map.talents
	table.sort(talentIDs, function(a, b)
		if (lit[a] and 1 or 0) ~= (lit[b] and 1 or 0) then return lit[a] ~= nil end
		return tree.talents[a].name < tree.talents[b].name
	end)
	for _, id in ipairs(talentIDs) do
		local t = tree.talents[id]
		local b = col.rows:Acquire()
		b:SetWidth(col.Content:GetWidth())
		b:SetPoint("TOPLEFT", col.Content, "TOPLEFT", 0, -y)
		b.Left:SetText(t.name)
		b.Right:SetText(("%d/%d"):format(ranks[id] or 0, t.maxRanks))
		UI.SetBackdrop(b, lit[id] and "tealBg" or nil, lit[id] and "tealEdge" or nil)
		UI.SetTextColor(b.Left, lit[id] and "tealText" or ((ranks[id] or 0) > 0 and "text" or "faint"))
		b:SetScript("OnClick", function()
			ns.Planner.Select(id)
			ns.Window.Show("planner")
		end)
		y = y + 26
	end
	col:SetContentHeight(y)

	-- Spells column
	col, y = pane.cols[2], 0
	for _, s in ipairs(map.spells) do
		local b = col.rows:Acquire()
		b:SetWidth(col.Content:GetWidth())
		b:SetPoint("TOPLEFT", col.Content, "TOPLEFT", 0, -y)
		b.Left:SetText(ns.Planner.SpellName(s.spell))
		b.Right:SetText((L["%d talents"]):format(#s.talents))
		local on = s.spell == state.spell
		UI.SetBackdrop(b, on and "goldBg" or "171A21", on and "goldEdge" or "border")
		UI.SetTextColor(b.Left, on and "goldLight" or "text")
		b:SetScript("OnClick", function()
			state.spell = s.spell
			Map.Render()
		end)
		y = y + 26
	end
	col:SetContentHeight(y)

	-- Stats column + effect list for the selected spell
	col, y = pane.cols[3], 0
	if selected then
		local classData = ns.ClassData[current.classID]
		local info = classData.spells[selected.spell] or {}
		local seen = {}
		local function stat(name)
			if seen[name] then return end
			seen[name] = true
			local b = col.rows:Acquire()
			b:SetWidth(col.Content:GetWidth())
			b:SetPoint("TOPLEFT", col.Content, "TOPLEFT", 0, -y)
			b.Left:SetText(name)
			b.Right:SetText("")
			UI.SetBackdrop(b, "1B1E26", "statEdge")
			UI.SetTextColor(b.Left, "statText")
			b:SetScript("OnClick", nil)
			y = y + 26
		end
		for _, s in ipairs(info.scales or {}) do stat(s) end
		for _, id in ipairs(selected.talents) do
			for _, s in ipairs(graph:Stats(id)) do stat(s) end
		end
		y = y + 10
		for _, id in ipairs(selected.talents) do
			local b = col.rows:Acquire()
			b:SetWidth(col.Content:GetWidth())
			b:SetPoint("TOPLEFT", col.Content, "TOPLEFT", 0, -y)
			b.Left:SetText(tree.talents[id].name)
			b.Right:SetText(graph:EffectOn(id, selected.spell) or "")
			UI.SetBackdrop(b, nil, nil)
			UI.SetTextColor(b.Left, "muted")
			b:SetScript("OnClick", nil)
			y = y + 24
		end
	end
	col:SetContentHeight(y)

	-- Proc chains and resource loops of the plan
	local chains = Compare.Chains(tree, ranks, graph)
	local sy = 0
	local function strip(title, list, color)
		local r = pane.strips.rows:Acquire()
		r:SetPoint("TOPLEFT", pane.strips.Content, "TOPLEFT", 0, -sy)
		r.Left:SetText(UI.Colorize(title:upper(), color))
		r.Right:SetText("")
		sy = sy + 22
		if #list == 0 then
			r = pane.strips.rows:Acquire()
			r:SetPoint("TOPLEFT", pane.strips.Content, "TOPLEFT", 0, -sy)
			r.Left:SetText(UI.Colorize(L["none in this plan"], "faint"))
			r.Right:SetText("")
			sy = sy + 22
		end
		for _, c in ipairs(list) do
			r = pane.strips.rows:Acquire()
			r:SetPoint("TOPLEFT", pane.strips.Content, "TOPLEFT", 0, -sy)
			r.Left:SetText(UI.Colorize(tree.talents[c.id].name .. ": ", "text") .. UI.Colorize(c.text, "tealText"))
			r.Right:SetText("")
			sy = sy + 22
		end
		sy = sy + 6
	end
	strip(L["Proc chains"], chains.procs, "teal")
	strip(L["Resource loops"], chains.loops, "gold")
	pane.strips:SetContentHeight(sy)
end

local function build(host)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f

	pane.subtitle = UI.Label(f, "Synergy map")
	pane.subtitle:SetPoint("TOPLEFT", 32, -22)
	pane.mine = UI.Button(f, L["My build only"], "seg", nil, 28)
	pane.all = UI.Button(f, L["All talents"], "seg", nil, 28)
	pane.all:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -14)
	pane.mine:SetPoint("RIGHT", pane.all, "LEFT", 1, 0)
	pane.mine:SetScript("OnClick", function() state.mine = true Map.Render() end)
	pane.all:SetScript("OnClick", function() state.mine = false Map.Render() end)
	pane.intro = UI.Text(f, 12, "muted")
	pane.intro:SetPoint("TOPLEFT", 32, -52)
	pane.intro:SetWidth(1104 - 64)
	pane.intro:SetWordWrap(true)

	pane.cols = {}
	local widths = { 340, 340, 340 }
	local titles = { "Talents", "Spells", "Scales with" }
	local x = 32
	for i, w in ipairs(widths) do
		local label = UI.Label(f, titles[i])
		label:SetPoint("TOPLEFT", x, -90)
		local col = UI.ScrollList(f, w, COL_H)
		col:SetPoint("TOPLEFT", x, -110)
		rows(col)
		pane.cols[i] = col
		x = x + w + 10
	end
	pane.strips = UI.ScrollList(f, 1040, 120, "panelDark", "border")
	pane.strips:SetPoint("TOPLEFT", 32, -(110 + COL_H + 10))
	rows(pane.strips, function(p)
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(1000, 20)
		r.Left = UI.Text(r, 12, "text")
		r.Left:SetPoint("LEFT")
		r.Left:SetWidth(1000)
		r.Right = UI.Text(r, 12, "muted")
		r.Right:SetPoint("RIGHT")
		return r
	end)

	pane.Refresh = Map.Render
	return pane
end

ns.Window.RegisterPane("synergy", build)
