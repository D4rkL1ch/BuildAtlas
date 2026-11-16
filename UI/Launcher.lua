local addonName, ns = ...

-- Ways to open things (design/Launcher.dc.html): a minimap button (no
-- library needed), the addon compartment, and slash commands.
-- Click: planner. Shift-click: last fight report. Right-click: menu.

local L = ns.L

local Launcher = {}
ns.Launcher = Launcher

local ICON = "Interface\\Icons\\INV_Misc_Book_11"
local DEFAULT_ANGLE = 200
local RADIUS_OFFSET = 5

local button

local MENU = {
	{ text = "Talent planner", hint = "click", run = function() ns.Window.Show("planner") end },
	{ text = "Last fight report", hint = "shift-click", run = function() ns.Window.Show("report") end },
	{ text = "Arm benchmark", run = function() ns.Window.Show("bench") end },
	{ text = "Import / export", run = function() ns.Window.Show("share") end },
	{ separator = true },
	{ text = "Settings", run = function() Launcher.OpenSettings() end },
}

function Launcher.OpenSettings()
	if ns.SettingsCategory and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.SettingsCategory:GetID())
	end
end

local function openMenu(owner)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			root:CreateTitle("Build Atlas")
			for _, item in ipairs(MENU) do
				if item.separator then
					root:CreateDivider()
				else
					root:CreateButton(L[item.text], item.run)
				end
			end
		end)
	else
		ns.Window.Toggle("planner")
	end
end

function Launcher.Click(mouseButton, owner)
	if mouseButton == "RightButton" then
		openMenu(owner or button)
	elseif IsShiftKeyDown() then
		ns.Window.Show("report")
	else
		ns.Window.Toggle("planner")
	end
end

local function showHint(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine("Build Atlas")
	GameTooltip:AddLine(L["Click: talent planner"], 1, 1, 1)
	GameTooltip:AddLine(L["Shift-click: last fight report"], 1, 1, 1)
	GameTooltip:AddLine(L["Right-click: menu"], 1, 1, 1)
	GameTooltip:AddLine("/batlas · /batlas report · /batlas bench", 0.55, 0.57, 0.63)
	GameTooltip:Show()
end

local function place()
	local angle = math.rad(ns.db.settings.minimapAngle or DEFAULT_ANGLE)
	local radius = Minimap:GetWidth() / 2 + RADIUS_OFFSET
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
	local cx, cy = Minimap:GetCenter()
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.settings.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
	place()
end

local function createButton()
	button = CreateFrame("Button", nil, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER")
	icon:SetTexture(ICON)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	button:SetScript("OnClick", function(self, mouseButton) Launcher.Click(mouseButton, self) end)
	button:SetScript("OnEnter", showHint)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	place()
end

function Launcher.UpdateShown()
	if button then button:SetShown(ns.db.settings.minimapIcon ~= false) end
end

ns:RegisterMessage("BA_LOGIN", function()
	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon({
			text = "Build Atlas",
			icon = ICON,
			notCheckable = true,
			func = function(owner, inputData) Launcher.Click(inputData and inputData.buttonName, owner) end,
			funcOnEnter = showHint,
			funcOnLeave = function() GameTooltip:Hide() end,
		})
	end
	if Minimap then
		createButton()
		Launcher.UpdateShown()
	end
end)

ns:AddCommand("report", function() ns.Window.Show("report") end, "/batlas report - last fight report")
ns:AddCommand("bench", function() ns.Window.Show("bench") end, "/batlas bench - dummy benchmark")
ns:AddCommand("share", function() ns.Window.Show("share") end, "/batlas share - import / export builds")
ns:AddCommand("minimap", function()
	ns.db.settings.minimapIcon = ns.db.settings.minimapIcon == false
	Launcher.UpdateShown()
end, "/batlas minimap - show or hide the minimap button")
ns:AddCommand("settings", function() Launcher.OpenSettings() end, "/batlas settings - options")
