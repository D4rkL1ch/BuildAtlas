local addonName, ns = ...

-- Compare A vs B (design/Compare.dc.html): any two of the live specs, the
-- plan slots, an imported build and the bundled presets of the class shown
-- in the planner. Talent diff, spells changed, stat lean (not a simulation).

local UI, L = ns.UI, ns.L
local Compare, Talents = ns.Compare, ns.Talents

local ComparePane = {}
ns.ComparePane = ComparePane

local COL_W, COL_H = 330, 520
local pane
local state = { a = nil, b = nil }

-- Sources for the class in the planner: { key, label, ranks }.
function ComparePane.Sources()
	local current = ns.Planner.Current()
	if not current then return {}, nil end
	local tree = current.tree
	local list = {}
	local plans = ns.charDB.plans[current.classID] or {}
	local function add(key, label, ranks)
		if ranks then
			local _, perGroup = ns.Plan.Spent(tree, ranks)
			list[#list + 1] = { key = key, label = ("%s · %s"):format(label, table.concat(perGroup, "/")), ranks = ranks }
		end
	end
	if tree.isPlayerClass then
		local active = Talents.GetActiveSpecGroup()
		for g = 1, Talents.GetNumSpecGroups() do
			local live = current.specRanks and current.specRanks[g]
			add("live" .. g, (L["Spec %d (live)"]):format(g) .. (g == active and L[" · active"] or ""), live)
		end
	end
	add("scratch", L["Scratch plan"], plans.scratch and plans.scratch.ranks)
	add("spec1", L["Spec 1 plan"], plans.spec1 and plans.spec1.ranks)
	add("spec2", L["Spec 2 plan"], plans.spec2 and plans.spec2.ranks)
	local imported = ns.charDB.imported
	if imported and imported.classID == current.classID then add("imported", L["Imported"], imported.ranks) end
	for i, preset in ipairs(ns.Presets and ns.Presets.ForClass(current.classID) or {}) do
		add("preset" .. i, L["Preset · "] .. preset.name, preset.ranks)
	end
	return list, current
end

local function find(list, key)
	for _, s in ipairs(list) do
		if s.key == key then return s end
	end
end

local function defaults(list)
	if not find(list, state.a) then state.a = list[1] and list[1].key end
	if not find(list, state.b) or state.b == state.a then
		state.b = nil
		for _, s in ipairs(list) do
			if s.key ~= state.a then state.b = s.key break end
		end
	end
end

-- Rendering --------------------------------------------------------------------

local function rowText(col, y, left, right, color, rightColor)
	local row = col.rows:Acquire()
	row:SetPoint("TOPLEFT", col.Content, "TOPLEFT", 0, -y)
	row.Left:SetText(left)
	row.Right:SetText(right or "")
	UI.SetTextColor(row.Left, color or "text")
	UI.SetTextColor(row.Right, rightColor or "gold")
	return y + 22
end

local function header(col, y, text, color)
	return rowText(col, y, UI.Colorize(text:upper(), color or "faint"), "")
end

function ComparePane.Render()
	local list, current = ComparePane.Sources()
	for _, col in ipairs(pane.cols) do col.rows:ReleaseAll() col.bars:ReleaseAll() end
	if not current or #list < 2 then
		pane.summary:SetText(L["Need two builds of the same class to compare. Make a plan, import one, or pick a preset."])
		pane.ddA:Refresh()
		pane.ddB:Refresh()
		return
	end
	defaults(list)
	pane.ddA:Refresh()
	pane.ddB:Refresh()
	local A, B = find(list, state.a), find(list, state.b)
	local tree, graph = current.tree, current.graph
	local diff = Compare.Diff(tree, A.ranks, B.ranks, graph)

	-- Talent difference
	local col, y = pane.cols[1], 0
	y = header(col, y, L["Only in A"], "blue")
	for _, d in ipairs(diff.onlyA) do
		y = rowText(col, y, tree.talents[d.id].name, d.b > 0 and ("%d → %d"):format(d.b, d.a) or tostring(d.a), "text", "blue")
	end
	if #diff.onlyA == 0 then y = rowText(col, y, L["nothing"], "", "faint") end
	y = y + 8
	y = header(col, y, L["Only in B"], "gold")
	for _, d in ipairs(diff.onlyB) do
		y = rowText(col, y, tree.talents[d.id].name, d.a > 0 and ("%d → %d"):format(d.a, d.b) or tostring(d.b), "text", "gold")
	end
	if #diff.onlyB == 0 then y = rowText(col, y, L["nothing"], "", "faint") end
	y = y + 8
	local shared = {}
	for i, g in ipairs(tree.groups) do
		if diff.sharedPerGroup[i] > 0 then shared[#shared + 1] = ("%d %s"):format(diff.sharedPerGroup[i], g.name) end
	end
	y = rowText(col, y, L["Shared: "] .. (#shared > 0 and table.concat(shared, ", ") or L["none"]), "", "muted")
	col:SetContentHeight(y)

	-- Spells changed
	col, y = pane.cols[2], 0
	y = rowText(col, y, UI.Colorize(L["SPELL"], "faint"), UI.Colorize("A", "blue") .. "    " .. UI.Colorize("B", "gold"))
	for _, s in ipairs(diff.spells) do
		local name = ns.Planner.SpellName(s.spell)
		y = rowText(col, y, name, UI.Colorize(tostring(s.a), "blue") .. "    " .. UI.Colorize(tostring(s.b), "gold"))
	end
	if #diff.spells == 0 then y = rowText(col, y, L["No synergy data for this class."], "", "faint") end
	col:SetContentHeight(y)

	-- Stat lean bars
	col, y = pane.cols[3], 0
	local maxV = 0.01
	for _, s in ipairs(diff.lean) do maxV = math.max(maxV, s.a, s.b) end
	local barW = COL_W - 60
	for i, s in ipairs(diff.lean) do
		if i > 12 then break end
		y = rowText(col, y, s.stat, "", "text")
		for _, side in ipairs({ { "a", "blue" }, { "b", "gold" } }) do
			local bar = col.bars:Acquire()
			bar:SetPoint("TOPLEFT", col.Content, "TOPLEFT", 0, -y)
			bar:SetWidth(math.max(2, barW * s[side[1]] / maxV))
			bar:SetColorTexture(UI.RGB(UI.colors[side[2]]))
			y = y + 9
		end
		y = y + 6
	end
	y = rowText(col, y + 4, L["Weighted count of talent stats. Not a simulation."], "", "faint")
	col:SetContentHeight(y)

	pane.summary:SetText(Compare.Summary(diff, "A", "B"))
	pane.labelA:SetText("A: " .. A.label)
	pane.labelB:SetText("B: " .. B.label)
end

local function build(host)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f

	local function items()
		local list = ComparePane.Sources()
		return list
	end
	local labelA = UI.Text(f, 14, "blue", "heading")
	labelA:SetText("A")
	labelA:SetPoint("TOPLEFT", 32, -26)
	pane.ddA = UI.Dropdown(f, 300, items, function() return state.a end, function(k) state.a = k ComparePane.Render() end)
	pane.ddA:SetPoint("LEFT", labelA, "RIGHT", 10, 0)
	local swap = UI.Button(f, "⇄", "mini", 34, 30)
	swap:SetPoint("LEFT", pane.ddA, "RIGHT", 12, 0)
	swap:SetScript("OnClick", function()
		state.a, state.b = state.b, state.a
		ComparePane.Render()
	end)
	local labelB = UI.Text(f, 14, "gold", "heading")
	labelB:SetText("B")
	labelB:SetPoint("LEFT", swap, "RIGHT", 16, 0)
	pane.ddB = UI.Dropdown(f, 300, items, function() return state.b end, function(k) state.b = k ComparePane.Render() end)
	pane.ddB:SetPoint("LEFT", labelB, "RIGHT", 10, 0)

	pane.cols = {}
	local titles = { "Talent difference", "Spells changed (talent count)", "Stat lean" }
	for i, title in ipairs(titles) do
		local label = UI.Label(f, title)
		label:SetPoint("TOPLEFT", 32 + (i - 1) * (COL_W + 16), -72)
		local col = UI.ScrollList(f, COL_W, COL_H)
		col:SetPoint("TOPLEFT", 32 + (i - 1) * (COL_W + 16), -94)
		col.rows = UI.Pool(col.Content, function(p)
			local row = CreateFrame("Frame", nil, p)
			row:SetSize(COL_W - 44, 20)
			row.Left = UI.Text(row, 12, "text")
			row.Left:SetPoint("LEFT")
			row.Right = UI.Text(row, 12, "gold", "body", "RIGHT")
			row.Right:SetPoint("RIGHT")
			return row
		end)
		col.bars = UI.Pool(col.Content, function(p)
			local bar = p:CreateTexture(nil, "ARTWORK")
			bar:SetHeight(7)
			return bar
		end)
		pane.cols[i] = col
	end

	pane.labelA = UI.Text(f, 12, "blue")
	pane.labelA:SetPoint("TOPLEFT", 32, -632)
	pane.labelB = UI.Text(f, 12, "gold")
	pane.labelB:SetPoint("LEFT", pane.labelA, "RIGHT", 24, 0)
	pane.summary = UI.Text(f, 14, "text", "heading")
	pane.summary:SetPoint("TOPLEFT", 32, -660)
	pane.summary:SetWidth(1104 - 64 - 360)
	pane.summary:SetWordWrap(true)

	local toPlanner = UI.Button(f, L["Open B in planner"], "default")
	toPlanner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 24)
	toPlanner:SetScript("OnClick", function()
		local list, current = ComparePane.Sources()
		local B = find(list, state.b)
		if B and current then
			ns.Planner.LoadInto(current.classID, B.ranks, "scratch")
			ns.Window.Show("planner")
		end
	end)
	local toBench = UI.Button(f, L["Benchmark…"], "default")
	toBench:SetPoint("RIGHT", toPlanner, "LEFT", -10, 0)
	toBench:SetScript("OnClick", function() ns.Window.Show("bench") end)

	pane.Refresh = ComparePane.Render
	return pane
end

ns.Window.RegisterPane("compare", build)
