local addonName, ns = ...

-- Presets (design/Presets.dc.html): bundled builds of the class shown in the
-- planner, each crediting its author and licence. Load into the planner,
-- compare, or see the synergies. Presets ship with releases; no web access.

local UI, L = ns.UI, ns.L
local Presets = ns.Presets

local PresetsPane = {}
ns.PresetsPane = PresetsPane

local ROLES = { "All", "Damage", "Tank", "Healer" }
local pane
local state = { role = "All", selected = 1 }

local function currentClass()
	local current = ns.Planner.Current()
	return current and current.classID or ns.Talents.PlayerClassID()
end

local function filtered()
	local out = {}
	for _, p in ipairs(Presets.ForClass(currentClass())) do
		if state.role == "All" or p.role == state.role then out[#out + 1] = p end
	end
	return out
end

local function loadSelected(slot)
	local list = filtered()
	local p = list[state.selected]
	if not p or not p.ranks then return nil end
	ns.Planner.LoadInto(p.classID, p.ranks, slot or "scratch")
	return p
end

function PresetsPane.Render()
	for _, b in ipairs(pane.roles) do b:SetOn(b.role == state.role) end
	local list = filtered()
	pane.list.rows:ReleaseAll()
	pane.heading:SetText(L["PRESETS · "] .. ns.Planner.ClassName(currentClass()))
	local y = 0
	for i, p in ipairs(list) do
		local b = pane.list.rows:Acquire()
		b:SetPoint("TOPLEFT", pane.list.Content, "TOPLEFT", 0, -y)
		b.Left:SetText(p.name)
		b.Right:SetText(p.split)
		b.Sub:SetText(("%s · %s · %s"):format(L[p.role], p.author, p.license) .. (p.valid and "" or UI.Colorize(L[" · doesn't fit the current tree"], "orange")))
		local on = i == state.selected
		UI.SetBackdrop(b, on and "goldBg" or "171A21", on and "goldEdge" or "border")
		b:SetScript("OnClick", function() state.selected = i PresetsPane.Render() end)
		y = y + 52
	end
	pane.list:SetContentHeight(y)
	if #list == 0 then
		pane.detail:Hide()
		pane.none:Show()
		return
	end
	pane.none:Hide()
	pane.detail:Show()
	if state.selected > #list then state.selected = 1 end
	local p = list[state.selected]
	pane.role:SetText(L[p.role]:upper())
	pane.name:SetText(p.name)
	pane.meta:SetText((L["%s · by %s · %s · tree version %s"]):format(p.split, p.author, p.license, (p.build or ""):match("(%d+)$") or "?"))
	pane.why:SetText(p.why)
	pane.keys:SetText(table.concat(p.keys or {}, " · "))
	local steps = {}
	for i, s in ipairs(p.play or {}) do steps[i] = i .. ". " .. s end
	pane.play:SetText(table.concat(steps, "\n"))
	for _, b in ipairs(pane.actions) do b:SetEnabledState(p.valid and true or false) end
end

local function build(host)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f

	pane.heading = UI.Label(f, "Presets")
	pane.heading:SetPoint("TOPLEFT", 24, -20)
	pane.roles = {}
	local x = 24
	for _, role in ipairs(ROLES) do
		local b = UI.Button(f, L[role], "seg", nil, 28)
		b.role = role
		b:SetPoint("TOPLEFT", x, -44)
		b:SetScript("OnClick", function() state.role = role state.selected = 1 PresetsPane.Render() end)
		x = x + b:GetWidth() - 1
		pane.roles[#pane.roles + 1] = b
	end
	pane.list = UI.ScrollList(f, 360, 540)
	pane.list:SetPoint("TOPLEFT", 24, -84)
	pane.list.rows = UI.Pool(pane.list.Content, function(p)
		local b = CreateFrame("Button", nil, p, "BackdropTemplate")
		b:SetSize(320, 48)
		b.Left = UI.Text(b, 13, "text", "heading")
		b.Left:SetPoint("TOPLEFT", 10, -8)
		b.Right = UI.Text(b, 12, "gold", "body", "RIGHT")
		b.Right:SetPoint("TOPRIGHT", -10, -8)
		b.Sub = UI.Text(b, 11, "muted")
		b.Sub:SetPoint("TOPLEFT", 10, -28)
		return b
	end)
	local note = UI.Text(f, 11, "faint")
	note:SetPoint("TOPLEFT", pane.list, "BOTTOMLEFT", 0, -8)
	note:SetWidth(360)
	note:SetWordWrap(true)
	note:SetText(L["Bundled with the addon and updated with each release. Each preset credits its author and licence."])

	pane.none = UI.Text(f, 13, "muted")
	pane.none:SetPoint("TOPLEFT", 410, -90)
	pane.none:SetWidth(640)
	pane.none:SetWordWrap(true)
	pane.none:SetText(L["No presets for this class yet. Community builds are added with their author's permission in future releases; meanwhile, import a build on the Import / export page."])

	local d = CreateFrame("Frame", nil, f)
	d:SetPoint("TOPLEFT", 410, -20)
	d:SetPoint("BOTTOMRIGHT", -24, 20)
	pane.detail = d
	pane.role = UI.Text(d, 11, "teal", "heading")
	pane.role:SetPoint("TOPLEFT", 0, 0)
	pane.name = UI.Text(d, 22, "white", "title")
	pane.name:SetPoint("TOPLEFT", 0, -18)
	pane.meta = UI.Text(d, 12, "muted")
	pane.meta:SetPoint("TOPLEFT", 0, -50)
	local function section(title, yy)
		local l = UI.Label(d, title)
		l:SetPoint("TOPLEFT", 0, yy)
		local t = UI.Text(d, 13, "text")
		t:SetPoint("TOPLEFT", 0, yy - 20)
		t:SetWidth(640)
		t:SetWordWrap(true)
		return t
	end
	pane.why = section("Why it works", -84)
	pane.keys = section("Key talents", -200)
	UI.SetTextColor(pane.keys, "tealText")
	pane.play = section("How to play it (read before you pull)", -260)

	local load = UI.Button(d, L["Load into planner"], "primary")
	load:SetPoint("BOTTOMRIGHT", 0, 0)
	load:SetScript("OnClick", function()
		if loadSelected("scratch") then ns.Window.Show("planner") end
	end)
	local compare = UI.Button(d, L["Compare"], "default")
	compare:SetPoint("RIGHT", load, "LEFT", -10, 0)
	compare:SetScript("OnClick", function() ns.Window.Show("compare") end)
	local synergy = UI.Button(d, L["See synergies"], "default")
	synergy:SetPoint("RIGHT", compare, "LEFT", -10, 0)
	synergy:SetScript("OnClick", function()
		if loadSelected("scratch") then ns.Window.Show("synergy") end
	end)
	pane.actions = { load, compare, synergy }

	pane.Refresh = PresetsPane.Render
	return pane
end

ns.Window.RegisterPane("presets", build)
