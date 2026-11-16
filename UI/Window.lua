local addonName, ns = ...

-- Main window: title bar, nav rail on the left, one pane at a time on the
-- right. Design size 1280x800 (design/Main.dc.html), scaled by the "scale"
-- setting, movable, remembers its position, closes with Escape.

local UI = ns.UI
local L = ns.L

local Window = {}
ns.Window = Window

local WIDTH, HEIGHT = 1280, 800
local TITLE_H, RAIL_W = 56, 176

-- Nav rail entries (design/NavRail.dc.html). `milestone` marks panes not
-- built yet.
local NAV = {
	{ label = "Plan", items = {
		{ key = "planner", label = "Talent planner" },
		{ key = "synergy", label = "Synergy map" },
		{ key = "compare", label = "Compare builds" },
		{ key = "presets", label = "Presets" },
		{ key = "leveling", label = "Leveling path" },
	} },
	{ label = "Measure", items = {
		{ key = "report", label = "Fight report" },
		{ key = "bench", label = "Benchmark" },
	} },
	{ label = "Gear & share", items = {
		{ key = "gear", label = "Stats & gear" },
		{ key = "share", label = "Import / export" },
	} },
}

local panes = {}       -- key -> { build = fn(host) -> pane }
local built = {}       -- key -> pane object (has .frame, optional :Refresh())
local frame, host, navButtons, statusDot, statusText, placeholder

function Window.RegisterPane(key, build)
	panes[key] = { build = build }
end

local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	ns.db.window.point, ns.db.window.relPoint, ns.db.window.x, ns.db.window.y = point, relPoint, x, y
end

local function restorePosition()
	local w = ns.db.window
	frame:ClearAllPoints()
	if w.point then
		frame:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
	else
		frame:SetPoint("CENTER")
	end
end

local function updateCombatStatus()
	if not statusText then return end
	local inCombat = InCombatLockdown()
	statusDot:SetColorTexture(UI.RGB(inCombat and UI.colors.orange or UI.colors.greenNode))
	statusText:SetText(inCombat and L["In combat · read-only"] or L["Out of combat"])
	UI.SetTextColor(statusText, inCombat and "orange" or "green")
end

local function buildNavRail(parent)
	local rail = UI.Panel(parent, "rail", nil)
	rail:SetPoint("TOPLEFT", 0, -TITLE_H)
	rail:SetPoint("BOTTOMLEFT", 0, 0)
	rail:SetWidth(RAIL_W)
	local edge = rail:CreateTexture(nil, "ARTWORK")
	edge:SetColorTexture(UI.RGB(UI.colors.border))
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetWidth(1)

	navButtons = {}
	local y = -12
	for _, group in ipairs(NAV) do
		local label = UI.Text(rail, 10, "faint", "heading")
		label:SetText(L[group.label]:upper())
		label:SetPoint("TOPLEFT", 20, y - 12)
		y = y - 30
		for _, item in ipairs(group.items) do
			local b = CreateFrame("Button", nil, rail, "BackdropTemplate")
			b:SetSize(RAIL_W - 20, 36)
			b:SetPoint("TOPLEFT", 10, y)
			b.Label = UI.Text(b, 13, "C4C7CF", "body")
			b.Label:SetPoint("LEFT", 12, 0)
			b.Label:SetText(L[item.label])
			b.key = item.key
			b:SetScript("OnClick", function() Window.Show(item.key) end)
			b:SetScript("OnEnter", function(self)
				if Window.current ~= self.key then UI.SetBackdrop(self, "1A1D24", nil) end
				if item.milestone then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(L[item.label], 1, 1, 1)
					GameTooltip:AddLine(L["Not built yet (milestone "] .. item.milestone .. ").", 0.85, 0.85, 0.85, true)
					GameTooltip:Show()
				end
			end)
			b:SetScript("OnLeave", function(self)
				GameTooltip:Hide()
				Window.UpdateNav()
			end)
			if item.milestone then b.Label:SetAlpha(0.5) end
			navButtons[#navButtons + 1] = b
			y = y - 38
		end
	end

	statusDot = rail:CreateTexture(nil, "ARTWORK")
	statusDot:SetSize(8, 8)
	statusDot:SetPoint("BOTTOMLEFT", 20, 40)
	statusText = UI.Text(rail, 12, "green")
	statusText:SetPoint("LEFT", statusDot, "RIGHT", 8, 0)
	local _, interface = ns:GetClientBuild()
	local version = UI.Text(rail, 10, "faint")
	version:SetPoint("BOTTOMLEFT", 20, 18)
	version:SetText(("v%s · interface %s"):format(ns.version, tostring(interface)))
	updateCombatStatus()
end

function Window.UpdateNav()
	for _, b in ipairs(navButtons or {}) do
		local on = b.key == Window.current
		if on then
			UI.SetBackdrop(b, "goldBg", "goldEdge")
			UI.SetTextColor(b.Label, "goldLight")
		else
			UI.SetBackdrop(b, nil, nil)
			UI.SetTextColor(b.Label, "C4C7CF")
		end
	end
end

local function createFrame()
	frame = CreateFrame("Frame", "BuildAtlasMainFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetScale(ns.db.settings.scale or 0.8)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	UI.SetBackdrop(frame, "window", "3A3F4C")
	restorePosition()
	-- Escape closes it like Blizzard panels.
	table.insert(UISpecialFrames, "BuildAtlasMainFrame")

	local title = UI.Panel(frame, "bar", nil)
	title:SetPoint("TOPLEFT", 1, -1)
	title:SetPoint("TOPRIGHT", -1, -1)
	title:SetHeight(TITLE_H - 1)
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function() frame:StartMoving() end)
	title:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		savePosition()
	end)
	local line = title:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(UI.RGB(UI.colors.border))
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(1)
	frame.TitleBar = title

	local name = UI.Text(title, 20, "gold", "title")
	name:SetText("Build Atlas")
	name:SetPoint("LEFT", 20, 0)

	local sep = title:CreateTexture(nil, "ARTWORK")
	sep:SetColorTexture(UI.RGB(UI.colors.border))
	sep:SetSize(1, 24)
	sep:SetPoint("LEFT", name, "RIGHT", 16, 0)

	-- Panes put their own controls here (class dropdown, plan slots...).
	frame.TitleTools = CreateFrame("Frame", nil, title)
	frame.TitleTools:SetPoint("TOPLEFT", sep, "TOPRIGHT", 16, 4)
	frame.TitleTools:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT", -320, 0)

	local close = UI.Button(title, "×", "mini")
	close:SetPoint("RIGHT", -16, 0)
	close:SetScript("OnClick", function() frame:Hide() end)

	frame.DataBadge = UI.Panel(title, "greenBadge", "greenEdge")
	frame.DataBadge:SetHeight(22)
	frame.DataBadge:SetPoint("RIGHT", close, "LEFT", -12, 0)
	frame.DataBadge.Text = UI.Text(frame.DataBadge, 11, "green")
	frame.DataBadge.Text:SetPoint("CENTER")

	buildNavRail(frame)

	host = CreateFrame("Frame", nil, frame)
	host:SetPoint("TOPLEFT", RAIL_W, -TITLE_H)
	host:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.Host = host

	placeholder = CreateFrame("Frame", nil, host)
	placeholder:SetAllPoints()
	placeholder.Text = UI.Text(placeholder, 14, "muted", "body", "CENTER")
	placeholder.Text:SetPoint("CENTER")
	placeholder:Hide()

	frame:SetScript("OnShow", function() Window.Refresh() end)
	Window.frame = frame
	Window.UpdateDataBadge()
end

-- Title-bar badge: bundled data build vs the client build.
function Window.UpdateDataBadge(dataBuild)
	if not frame then return end
	local client = ns:GetClientBuild()
	local badge = frame.DataBadge
	if not dataBuild then
		badge.Text:SetText(L["No synergy data · client "] .. client)
		UI.SetBackdrop(badge, "2A1E16", "6B3A22")
		UI.SetTextColor(badge.Text, "orange")
	elseif dataBuild == client then
		badge.Text:SetText(L["Data "] .. dataBuild .. L[" · matches client"])
		UI.SetBackdrop(badge, "greenBadge", "greenEdge")
		UI.SetTextColor(badge.Text, "green")
	else
		badge.Text:SetText(L["Data "] .. dataBuild .. L[" · client "] .. client)
		UI.SetBackdrop(badge, "2A1E16", "6B3A22")
		UI.SetTextColor(badge.Text, "orange")
	end
	badge:SetWidth(badge.Text:GetStringWidth() + 16)
end

function Window.Show(key)
	if not frame then createFrame() end
	key = key or Window.current or "planner"
	Window.current = key
	for k, pane in pairs(built) do
		if k ~= key then pane.frame:Hide() end
	end
	local def = panes[key]
	if def then
		placeholder:Hide()
		if not built[key] then built[key] = def.build(host, frame) end
		built[key].frame:Show()
	else
		placeholder:Show()
		placeholder.Text:SetText(L["This section isn't built yet. See the roadmap in the README."])
	end
	Window.UpdateNav()
	frame:Show()
	Window.Refresh()
end

function Window.Toggle(key)
	if frame and frame:IsShown() and (not key or key == Window.current) then
		frame:Hide()
	else
		Window.Show(key)
	end
end

function Window.IsShown()
	return frame and frame:IsShown() or false
end

function Window.Refresh()
	if not frame or not frame:IsShown() then return end
	updateCombatStatus()
	local pane = built[Window.current]
	if pane and pane.Refresh then pane:Refresh() end
end

function Window.SetScale(scale)
	ns.db.settings.scale = scale
	if frame then frame:SetScale(scale) end
end

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() Window.Refresh() end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() Window.Refresh() end)

ns:AddCommand("show", function() Window.Toggle("planner") end, "/batlas - open or close the talent planner")
ns:AddCommand("scale", function(arg)
	local n = tonumber(arg)
	if not n or n < 0.4 or n > 1.5 then
		ns:Print(L["Usage: /batlas scale 0.4-1.5 (now "] .. tostring(ns.db.settings.scale) .. ")")
		return
	end
	Window.SetScale(n)
end, "/batlas scale <0.4-1.5> - window size")
ns:AddCommand("reset", function()
	wipe(ns.db.window)
	if frame then restorePosition() end
	ns:Print(L["Window position reset."])
end, "/batlas reset - move the window back to the center")
