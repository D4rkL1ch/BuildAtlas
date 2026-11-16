local addonName, ns = ...

-- Notices at the top centre of the screen (design/Launcher.dc.html). They
-- stack, fade after 8 seconds and can carry one action link.

local UI, L = ns.UI, ns.L

local Toasts = {}
ns.Toasts = Toasts

local WIDTH, GAP, LIFETIME = 360, 8, 8
local DOTS = { info = "teal", warn = "orange", muted = "faint" }

local anchor
local active = {}
local frames = {}

local function layout()
	local y = 0
	for _, toast in ipairs(active) do
		toast:ClearAllPoints()
		toast:SetPoint("TOP", anchor, "TOP", 0, -y)
		y = y + toast:GetHeight() + GAP
	end
end

local function release(toast)
	for i, t in ipairs(active) do
		if t == toast then table.remove(active, i) break end
	end
	toast:Hide()
	layout()
end

local function create(parent)
	local t = UI.Panel(parent, "window", "4A5163")
	t:SetWidth(WIDTH)
	t:EnableMouse(true)
	t.Dot = t:CreateTexture(nil, "ARTWORK")
	t.Dot:SetSize(10, 10)
	t.Dot:SetPoint("TOPLEFT", 14, -16)
	t.Title = UI.Text(t, 13, "text", "heading")
	t.Title:SetPoint("TOPLEFT", 34, -12)
	t.Title:SetPoint("RIGHT", -14, 0)
	t.Body = UI.Text(t, 12, "muted")
	t.Body:SetWordWrap(true)
	t.Body:SetPoint("TOPLEFT", t.Title, "BOTTOMLEFT", 0, -4)
	t.Body:SetWidth(WIDTH - 48)
	t.Action = CreateFrame("Button", nil, t)
	t.Action:SetHeight(18)
	t.Action.Label = UI.Text(t.Action, 12, "gold", "heading")
	t.Action.Label:SetPoint("LEFT")
	t:SetScript("OnMouseUp", function(self) release(self) end)
	return t
end

-- kind: "info" (teal), "warn" (orange), "muted" (grey). action: optional
-- { text = "Open report", run = fn }. Returns the toast frame.
function Toasts.Show(kind, title, body, action)
	if ns.db and ns.db.settings.toasts == false then return end
	if not anchor then
		anchor = CreateFrame("Frame", nil, UIParent)
		anchor:SetSize(WIDTH, 10)
		anchor:SetPoint("TOP", UIParent, "TOP", 0, -120)
		anchor:SetFrameStrata("DIALOG")
	end
	-- Same title already shown: refresh it instead of stacking a copy.
	for _, t in ipairs(active) do
		if t.Title:GetText() == title then release(t) break end
	end
	local t
	for _, f in ipairs(frames) do
		if not f:IsShown() then t = f break end
	end
	if not t then
		t = create(anchor)
		frames[#frames + 1] = t
	end
	t:Show()
	t.Dot:SetColorTexture(UI.RGB(UI.Hex(DOTS[kind] or "teal")))
	UI.SetBackdrop(t, "window", kind == "warn" and "6B3A22" or "4A5163")
	t.Title:SetText(title)
	t.Body:SetText(body or "")
	local h = 12 + 18 + 4 + t.Body:GetStringHeight() + 12
	if action then
		t.Action:Show()
		t.Action.Label:SetText(action.text)
		t.Action:SetWidth(t.Action.Label:GetStringWidth() + 4)
		t.Action:ClearAllPoints()
		t.Action:SetPoint("TOPLEFT", t.Body, "BOTTOMLEFT", 0, -6)
		t.Action:SetScript("OnClick", function()
			release(t)
			action.run()
		end)
		h = h + 24
	else
		t.Action:Hide()
	end
	t:SetHeight(h)
	t:SetAlpha(1)
	table.insert(active, 1, t)
	layout()
	local token = {}
	t.token = token
	ns.Util.After(LIFETIME, function()
		if t.token == token and t:IsShown() then release(t) end
	end)
	return t
end

-- Data build vs client build (once per client build).
local function buildNumber(v)
	return tonumber((v or ""):match("(%d+)$")) or 0
end

ns:RegisterMessage("BA_LOGIN", function()
	local client = ns:GetClientBuild()
	if not ns.DATA_BUILD or ns.db.notifiedBuild == client then return end
	if buildNumber(client) > buildNumber(ns.DATA_BUILD) then
		ns.db.notifiedBuild = client
		ns.Util.After(5, function()
			Toasts.Show("warn", L["Talent data is older than your game"],
				(L["Data %s, client %s. Tree layout is read live; per-rank numbers may be off until the addon updates."]):format(
					ns.DATA_BUILD:match("(%d+)$"), client:match("(%d+)$")))
		end)
	end
end)

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if ns.Window and ns.Window.IsShown() then
		Toasts.Show("muted", L["Paused in combat"], L["Windows stay open but read-only. Analysis runs when combat ends."])
	end
end)
