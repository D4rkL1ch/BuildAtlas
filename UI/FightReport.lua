local addonName, ns = ...

-- Fight report (design/FightReport.dc.html). Built after combat from the
-- game's damage meter. Talent contribution is always an estimate and every
-- row says how it was made.

local UI, L = ns.UI, ns.L
local Measure, Attribution = ns.Measure, ns.Attribution

local Report = {}
ns.FightReport = Report

local pane
local state = { selected = {}, merged = nil }

local METHOD_COLORS = { Direct = "green", Modeled = "teal", Rough = "orange" }

local function selectedFights()
	local list = {}
	for i, f in ipairs(ns.charDB.fights or {}) do
		if state.selected[f.id] then list[#list + 1] = f end
		if i > 30 then break end
	end
	return list
end

local function fmtNumber(n)
	if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
	if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

function Report.Render()
	local fights = ns.charDB.fights or {}
	pane.list.rows:ReleaseAll()
	pane.spells.rows:ReleaseAll()
	pane.table.rows:ReleaseAll()
	if #fights == 0 then
		pane.empty:Show()
		pane.body:Hide()
		return
	end
	pane.empty:Hide()
	pane.body:Show()
	if not next(state.selected) then state.selected[fights[1].id] = true end

	-- Recent fights
	local y = 0
	for _, f in ipairs(fights) do
		local b = pane.list.rows:Acquire()
		b:SetPoint("TOPLEFT", pane.list.Content, "TOPLEFT", 0, -y)
		b.Left:SetText(f.name)
		b.Sub:SetText(("%s · %.0f DPS · %s"):format(Measure.Clock(f.duration), f.dps, date("%H:%M", f.time)))
		local on = state.selected[f.id]
		UI.SetBackdrop(b, on and "goldBg" or "171A21", on and "goldEdge" or "border")
		b:SetScript("OnClick", function()
			if IsShiftKeyDown() then
				state.selected[f.id] = not state.selected[f.id] or nil
			else
				state.selected = { [f.id] = true }
			end
			Report.Render()
		end)
		y = y + 46
	end
	pane.list:SetContentHeight(y)

	local chosen = selectedFights()
	if #chosen == 0 then chosen = { fights[1] } end
	local fight = #chosen == 1 and chosen[1] or Attribution.Merge(chosen)
	if #chosen > 1 then
		fight.dps = fight.total / math.max(fight.duration, 1)
		fight.talents = chosen[1].talents
		fight.build = chosen[1].build
	end
	local est = Measure.Estimate(fight)
	pane.heading:SetText(L["FIGHT REPORT · "] .. (fight.build or "") .. " · " .. fight.name)
	pane.kpi[1]:SetText(fmtNumber(fight.total))
	pane.kpi[2]:SetText(Measure.Clock(fight.duration))
	pane.kpi[3]:SetText(("%.0f"):format(fight.dps))
	pane.kpi[4]:SetText(("%d%%"):format(math.floor(est.share * 100 + 0.5)))

	-- By spell
	local classData = ns.ClassData and ns.ClassData[fight.classID]
	local bySpell = {}
	for id, amount in pairs(fight.spells) do
		local key = classData and classData.rankOf[id] or id
		bySpell[key] = (bySpell[key] or 0) + amount
	end
	local list = {}
	for id, amount in pairs(bySpell) do list[#list + 1] = { id = id, amount = amount } end
	table.sort(list, function(a, b) return a.amount > b.amount end)
	y = 0
	local maxAmount = list[1] and list[1].amount or 1
	for i, s in ipairs(list) do
		if i > 14 then break end
		local r = pane.spells.rows:Acquire()
		r:SetPoint("TOPLEFT", pane.spells.Content, "TOPLEFT", 0, -y)
		local info = classData and classData.spells[s.id]
		local proc = classData and classData.procOf[s.id] and classData.talents[classData.procOf[s.id]]
		local name = (info and info.name) or (proc and proc.name) or ns.Secrets.Read(nil, C_Spell.GetSpellName, s.id) or ("Spell " .. s.id)
		r.Left:SetText(name)
		r.Right:SetText(("%s · %d%%"):format(fmtNumber(s.amount), math.floor(s.amount / fight.total * 100 + 0.5)))
		r.Bar:SetWidth(math.max(2, (pane.spells.Content:GetWidth() - 4) * s.amount / maxAmount))
		y = y + 30
	end
	pane.spells:SetContentHeight(y)

	-- Talent contribution
	y = 0
	for _, row in ipairs(est.rows) do
		local r = pane.table.rows:Acquire()
		r:SetPoint("TOPLEFT", pane.table.Content, "TOPLEFT", 0, -y)
		r.Name:SetText(row.name)
		r.Amount:SetText(fmtNumber(row.amount))
		r.Share:SetText(("%.1f%%"):format(row.share * 100))
		r.Method:SetText(L[row.method])
		UI.SetTextColor(r.Method, METHOD_COLORS[row.method] or "muted")
		y = y + 24
	end
	if #est.rows == 0 then
		local r = pane.table.rows:Acquire()
		r:SetPoint("TOPLEFT", pane.table.Content, "TOPLEFT", 0, 0)
		r.Name:SetText(L["No talent contribution found for this fight."])
		r.Amount:SetText("") r.Share:SetText("") r.Method:SetText("")
		y = 24
	end
	pane.table:SetContentHeight(y)
end

local function build(host)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f

	pane.empty = UI.Text(f, 14, "muted", "body", "CENTER")
	pane.empty:SetPoint("CENTER")
	pane.empty:SetText(L["No fights recorded yet. Fight something; the report is built when combat ends."])

	local body = CreateFrame("Frame", nil, f)
	body:SetAllPoints()
	pane.body = body

	local listLabel = UI.Label(body, "Recent fights")
	listLabel:SetPoint("TOPLEFT", 24, -20)
	pane.list = UI.ScrollList(body, 260, 560)
	pane.list:SetPoint("TOPLEFT", 24, -42)
	pane.list.rows = UI.Pool(pane.list.Content, function(p)
		local b = CreateFrame("Button", nil, p, "BackdropTemplate")
		b:SetSize(220, 42)
		b.Left = UI.Text(b, 12, "text")
		b.Left:SetPoint("TOPLEFT", 8, -6)
		b.Sub = UI.Text(b, 11, "muted")
		b.Sub:SetPoint("TOPLEFT", 8, -24)
		return b
	end)
	local hint = UI.Text(body, 11, "faint")
	hint:SetPoint("TOPLEFT", pane.list, "BOTTOMLEFT", 0, -8)
	hint:SetText(L["Shift-click to select several fights and merge them."])

	pane.heading = UI.Label(body, "Fight report")
	pane.heading:SetPoint("TOPLEFT", 304, -20)
	pane.kpi = {}
	local titles = { "Damage", "Duration", "DPS", "From talents (est.)" }
	for i, title in ipairs(titles) do
		local box = UI.Panel(body, "panel", "border")
		box:SetSize(180, 64)
		box:SetPoint("TOPLEFT", 304 + (i - 1) * 192, -42)
		local t = UI.Text(box, 11, "muted", "heading")
		t:SetText(L[title]:upper())
		t:SetPoint("TOPLEFT", 12, -10)
		local v = UI.Text(box, 20, i == 4 and "teal" or "gold", "heading")
		v:SetPoint("BOTTOMLEFT", 12, 10)
		pane.kpi[i] = v
	end

	local spellsLabel = UI.Label(body, "By spell")
	spellsLabel:SetPoint("TOPLEFT", 304, -124)
	pane.spells = UI.ScrollList(body, 360, 470)
	pane.spells:SetPoint("TOPLEFT", 304, -146)
	pane.spells.rows = UI.Pool(pane.spells.Content, function(p)
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(320, 28)
		r.Left = UI.Text(r, 12, "text")
		r.Left:SetPoint("TOPLEFT")
		r.Right = UI.Text(r, 12, "muted", "body", "RIGHT")
		r.Right:SetPoint("TOPRIGHT")
		r.Bar = r:CreateTexture(nil, "ARTWORK")
		r.Bar:SetHeight(5)
		r.Bar:SetPoint("BOTTOMLEFT", 0, 4)
		r.Bar:SetColorTexture(UI.RGB(UI.colors.gold))
		return r
	end)

	local tableLabel = UI.Label(body, "Talent contribution")
	tableLabel:SetPoint("TOPLEFT", 680, -124)
	local formula = UI.Text(body, 11, "faint")
	formula:SetPoint("LEFT", tableLabel, "RIGHT", 10, 0)
	formula:SetText(L["estimate = spell damage × talent share"])
	pane.table = UI.ScrollList(body, 400, 400)
	pane.table:SetPoint("TOPLEFT", 680, -146)
	pane.table.rows = UI.Pool(pane.table.Content, function(p)
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(360, 22)
		r.Name = UI.Text(r, 12, "text")
		r.Name:SetPoint("LEFT")
		r.Name:SetWidth(170)
		r.Amount = UI.Text(r, 12, "gold", "body", "RIGHT")
		r.Amount:SetPoint("LEFT", 170, 0)
		r.Amount:SetWidth(60)
		r.Share = UI.Text(r, 12, "muted", "body", "RIGHT")
		r.Share:SetPoint("LEFT", 236, 0)
		r.Share:SetWidth(52)
		r.Method = UI.Text(r, 11, "teal", "heading")
		r.Method:SetPoint("LEFT", 300, 0)
		return r
	end)
	local note = UI.Text(body, 11, "faint")
	note:SetPoint("TOPLEFT", pane.table, "BOTTOMLEFT", 0, -8)
	note:SetWidth(400)
	note:SetWordWrap(true)
	note:SetText(L["Direct: the damage exists because of the talent. Modeled: the talent's % bonus on recorded spell damage. Rough: crit-based talents the addon can't watch in combat (assumes 20% crit). All estimates."])

	pane.Refresh = Report.Render
	return pane
end

ns.Window.RegisterPane("report", build)

ns:RegisterMessage("BA_FIGHT", function(_, fight)
	state.selected = { [fight.id] = true }
	if pane and pane.frame:IsShown() then Report.Render() end
end)
