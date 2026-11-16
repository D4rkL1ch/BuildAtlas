---@diagnostic disable: undefined-global, lowercase-global, undefined-field, duplicate-set-field
-- Minimal WoW API stubs for offline tests. Not shipped.

local M = {}

local frames = {}

-- Widgets share one method table. Methods record what tests read back; the
-- rest are no-ops. Unknown methods error, so a typo in UI code fails tests.
local W = {}
local widgetMT = { __index = W }

local function noop() end
for _, name in ipairs({
	"SetSize", "SetWidth", "SetHeight", "SetAllPoints", "SetToplevel", "SetFrameStrata", "SetScale",
	"SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving",
	"StopMovingOrSizing", "SetJustifyH", "SetWordWrap", "RegisterForClicks", "SetTexCoord",
	"SetFont", "SetTextColor", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
	"SetDesaturated", "SetThickness", "SetStartPoint", "SetEndPoint", "SetFrameLevel",
	"AddLine", "AddDoubleLine", "SetOwner", "GenerateMenu", "SetShadowColor", "SetShadowOffset",
}) do W[name] = noop end

local function newWidget(kind, parent)
	local w = setmetatable({ kind = kind, parent = parent, events = {}, scripts = {}, shown = true, points = {}, enabled = true }, widgetMT)
	frames[#frames + 1] = w
	return w
end

function W:RegisterEvent(e)
	if M.unknownEvents[e] then error("unknown event " .. e) end
	self.events[e] = true
end
function W:UnregisterEvent(e) self.events[e] = nil end
function W:SetScript(name, fn) self.scripts[name] = fn end
function W:HookScript(name, fn)
	local old = self.scripts[name]
	self.scripts[name] = function(...)
		if old then old(...) end
		fn(...)
	end
end
function W:GetParent() return self.parent end
function W:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function W:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function W:SetShown(shown) if shown then self:Show() else self:Hide() end end
function W:IsShown()
	local w = self
	while w do
		if not w.shown then return false end
		w = w.parent
	end
	return true
end
function W:SetPoint(...) self.points[#self.points + 1] = { ... } end
function W:ClearAllPoints() self.points = {} end
function W:GetPoint(i)
	local p = self.points[i or 1]
	if not p then return nil end
	return p[1], p[2], p[3], p[4], p[5]
end
function W:SetEnabled(enabled) self.enabled = enabled and true or false end
function W:IsEnabled() return self.enabled end
function W:SetText(text) self.text = text end
function W:GetText() return self.text end
function W:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function W:SetTexture(t) self.texture = t end
function W:SetAlpha(a) self.alpha = a end
function W:GetAlpha() return self.alpha or 1 end
function W:CreateTexture() return newWidget("Texture", self) end
function W:CreateFontString() return newWidget("FontString", self) end
function W:CreateLine() return newWidget("Line", self) end
function W:GetFrameLevel() return 1 end
function W:GetStringWidth() return #(self.text or "") * 6 end
function W:GetWidth() return self.width or 100 end
function W:GetHeight() return self.height or 20 end
function W:GetStringHeight()
	local _, breaks = (self.text or ""):gsub("\n", "")
	return self.text and self.text ~= "" and (breaks + 1) * 14 or 0
end
function W:SetWidth(w) self.width = w end
function W:SetHeight(h) self.height = h end
function W:SetSize(w, h) self.width, self.height = w, h end

-- Click a button like the player would.
function M.click(w, button)
	if w.enabled == false then return end
	if w.scripts.OnClick then w.scripts.OnClick(w, button or "LeftButton") end
end

function M.allWidgets() return frames end

-- Visible font string texts under (and including) `root`, joined by newlines.
function M.visibleText(root)
	local out = {}
	for _, w in ipairs(frames) do
		if w.kind == "FontString" and w.text and w:IsShown() then
			local p = w
			while p and p ~= root do p = p.parent end
			if p == root then out[#out + 1] = w.text end
		end
	end
	return table.concat(out, "\n")
end

function M.fire(event, ...)
	for i = 1, #frames do
		local f = frames[i]
		if f.events[event] and f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end

function M.slash(msg)
	return SlashCmdList.BUILDATLAS(msg)
end

-- Fake trait tree -------------------------------------------------------------
-- Three groups side by side on one canvas: 600 units between columns and
-- rows, 3000 between group origins. Node: { id, g, row, col, max, spell,
-- name, conds = { condID }, edges = { targetNodeID } }.

M.TREE_ID = 1117
M.GROUPS = {
	{ groupID = 11650, displayName = "Arms", orderIndex = 0, icon = 1 },
	{ groupID = 11657, displayName = "Fury", orderIndex = 1, icon = 2 },
	{ groupID = 11670, displayName = "Protection", orderIndex = 2, icon = 3 },
}
M.CONDITIONS = {
	[9001] = { condID = 9001, spentAmountRequired = 30, isGate = true, isMet = false, isAlwaysMet = false, isSufficient = false, type = 1 },
	[9002] = { condID = 9002, spentAmountRequired = 10, ranksGranted = 1, isGate = false, isMet = false, isAlwaysMet = false, isSufficient = false, type = 2 },
}

local function defaultNodes()
	return {
		{ id = 101, g = 1, row = 0, col = 0, max = 3, spell = 5001, name = "Improved Heroic Strike" },
		{ id = 102, g = 1, row = 0, col = 1, max = 5, spell = 5002, name = "Deflection" },
		{ id = 103, g = 1, row = 1, col = 1, max = 5, spell = 5003, name = "Tactical Mastery", edges = { 104 } },
		{ id = 104, g = 1, row = 2, col = 1, max = 3, spell = 5004, name = "Deep Wounds" },
		{ id = 105, g = 1, row = 6, col = 1, max = 1, spell = 5005, name = "Mortal Strike", conds = { 9001 } },
		{ id = 201, g = 2, row = 0, col = 2, max = 5, spell = 5101, name = "Cruelty" },
		{ id = 202, g = 2, row = 1, col = 1, max = 5, spell = 5102, name = "Unbridled Wrath" },
		{ id = 301, g = 3, row = 0, col = 1, max = 5, spell = 5201, name = "Shield Specialization" },
		{ id = 302, g = 3, row = 2, col = 3, max = 1, spell = 5202, name = "Defiance Milestone", conds = { 9002 } },
	}
end

local function nodeByID(id)
	for _, n in ipairs(M.nodes) do
		if n.id == id then return n end
	end
end

local function installTraits()
	C_Traits = {
		GetTreeNodes = function(treeID)
			if treeID ~= M.TREE_ID and not M.otherTrees[treeID] then return {} end
			local ids = {}
			for _, n in ipairs(M.nodes) do ids[#ids + 1] = n.id end
			table.sort(ids)
			return ids
		end,
		GetNodeInfo = function(configID, nodeID)
			local n = nodeByID(nodeID)
			if not n or (configID ~= M.activeConfig and configID ~= M.spec2Config and configID ~= -3) then
				return { ID = 0, entryIDs = {}, groupIDs = {}, conditionIDs = {}, visibleEdges = {}, maxRanks = 0, ranksPurchased = 0, posX = 0, posY = 0 }
			end
			local edges = {}
			for _, to in ipairs(n.edges or {}) do edges[#edges + 1] = { targetNode = to, type = 2, visualStyle = 1, isActive = false } end
			local ranks = M.ranks[configID] or {}
			return {
				ID = n.id, posX = 1000 + (n.g - 1) * 3000 + n.col * 600, posY = 1200 + n.row * 600,
				entryIDs = { n.id * 10 }, groupIDs = { M.GROUPS[n.g].groupID }, conditionIDs = n.conds or {},
				visibleEdges = edges, maxRanks = n.max, ranksPurchased = ranks[n.id] or 0, isVisible = true,
				type = 0, flags = 0,
			}
		end,
		GetEntryInfo = function(_, entryID)
			local n = nodeByID(math.floor(entryID / 10))
			return n and { definitionID = n.id * 100, maxRanks = n.max, type = 1, isAvailable = true, conditionIDs = {} }
		end,
		GetDefinitionInfo = function(defID)
			local n = nodeByID(math.floor(defID / 100))
			return { spellID = n and n.spell }
		end,
		GetConditionInfo = function(_, condID) return M.CONDITIONS[condID] end,
		GetGroupDisplayInfoByTreeID = function(treeID)
			if treeID ~= M.TREE_ID and not M.otherTrees[treeID] then return {} end
			local out = {}
			for i = #M.GROUPS, 1, -1 do out[#out + 1] = M.GROUPS[i] end -- unsorted on purpose
			return out
		end,
		GetTraitDescription = function(entryID, rank)
			local n = nodeByID(math.floor(entryID / 10))
			return n and (n.name .. " rank " .. rank .. " text") or ""
		end,
		GetConfigInfo = function(configID) return { ID = configID, type = 4, name = "Camelot", treeIDs = { M.TREE_ID } } end,
		GetTreeCurrencyInfo = function() return { { traitCurrencyID = 3820, quantity = 10, maxQuantity = 51, spent = 41 } } end,
		GetTreeInfo = function() return { ID = M.TREE_ID, gates = {} } end,
		GetGroupCurrencyInfo = function() return {} end,
		GetNodeCost = function() return { { ID = 3820, amount = 1 } } end,
		GenerateImportString = function() return "BAAAAAAAexample" end,
		GetLoadoutSerializationVersion = function() return 2 end,
		GetTreeHash = function() return { 1, 2, 3 } end,
	}
	C_ClassTalents = {
		GetActiveConfigID = function() return M.activeConfig end,
		GetTraitTreeForSpec = function(specID)
			if specID == 1491 then return M.TREE_ID end
			return M.otherTreeBySpec[specID]
		end,
		InitializeViewLoadout = function(specID, level) M.viewLoadout = { specID, level } end,
		ViewLoadout = function() end,
	}
	C_SpecializationInfo = {
		GetActiveSpecGroup = function() return M.activeSpecGroup end,
		GetCombatConfigIDForSpecGroup = function(g)
			if g == 1 then return M.activeConfig end
			if g == 2 and M.numSpecGroups >= 2 then return M.spec2Config end
		end,
		GetClassIDFromSpecID = function(specID) return specID == 1491 and 1 or nil end,
	}
end

M.unknownEvents = {}

function M.reset()
	frames = {}
	M.printed = {}
	M.errors = {}
	M.combat = false
	M.shift = false
	M.classID = 1
	M.nodes = defaultNodes()
	M.activeConfig = 7001
	M.spec2Config = 7002
	M.numSpecGroups = 2
	M.activeSpecGroup = 1
	M.ranks = { [7001] = { [101] = 3, [102] = 2 }, [7002] = { [301] = 5 } }
	M.otherTrees, M.otherTreeBySpec = {}, {}
	M.viewLoadout = nil
	M.timers = {}
	SlashCmdList = {}
	UISpecialFrames = {}
	installTraits()
	BuildAtlasDB, BuildAtlasCharDB = nil, nil
	C_Spell = {
		GetSpellName = function(id) return "Spell" .. id end,
		GetSpellTexture = function(id) return 100000 + id end,
		GetSpellDescription = function(id) return "desc " .. id end,
	}
	C_DamageMeter = {
		IsDamageMeterAvailable = function() return true, "" end,
		GetAvailableCombatSessions = function() return { { sessionID = 1, name = "Hogger", durationSeconds = 72 } } end,
		GetCombatSessionFromID = function() return { combatSources = { { isLocalPlayer = true, classFilename = "WARRIOR", totalAmount = 1000, amountPerSecond = 14, name = "Tester" } }, totalAmount = 1000, maxAmount = 1000, durationSeconds = 72 } end,
		GetCombatSessionSourceFromID = function() return { combatSpells = { { spellID = 5005, totalAmount = 600, amountPerSecond = 8 } }, totalAmount = 1000, maxAmount = 600 } end,
	}
	C_Secrets = {
		ShouldUnitStatsBeSecret = function() return M.combat end,
		ShouldAurasBeSecret = function() return M.combat end,
	}
	AddonCompartmentFrame = { registered = {}, RegisterAddon = function(self, data) table.insert(self.registered, data) end }
	issecretvalue = function(v) return type(v) == "table" and v.__secret == true end
end

function M.runTimers()
	while #M.timers > 0 do
		local t = table.remove(M.timers, 1)
		t()
	end
end

-- Globals -------------------------------------------------------------------

unpack = unpack or table.unpack
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tostringall(...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	return unpack(t, 1, select("#", ...))
end
function date(fmt, t) return os.date("!" .. fmt, t) end
time = os.time

function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	M.printed[#M.printed + 1] = table.concat(parts, " ")
end

function geterrorhandler() return function(err) M.errors[#M.errors + 1] = err end end

function CreateFrame(kind, name, parent, template)
	if kind == "DropdownButton" then error("no dropdown in stubs") end
	local w = newWidget(kind, parent)
	w.template = template
	if name then _G[name] = w end
	return w
end
UIParent = newWidget("Frame")
GameTooltip = newWidget("GameTooltip")
UIErrorsFrame = { AddMessage = function(_, msg) M.uiErrors = M.uiErrors or {} table.insert(M.uiErrors, msg) end }

C_Timer = { After = function(_, fn) table.insert(M.timers, fn) end }

function GetBuildInfo() return "1.60.1", "70862", "Nov 10 2026", 16001 end
function InCombatLockdown() return M.combat end
function IsShiftKeyDown() return M.shift end
function UnitClass() return "Warrior", "WARRIOR", M.classID end
function UnitLevel() return 60 end
function UnitGUID() return "Player-1-0001" end
function GetClassInfo(classID)
	local names = { [1] = "Warrior", [2] = "Paladin", [3] = "Hunter", [4] = "Rogue", [5] = "Priest", [7] = "Shaman", [8] = "Mage", [9] = "Warlock", [11] = "Druid" }
	return names[classID]
end
function GetNumSpecGroups() return M.numSpecGroups end
function GetCritChance() return M.combat and { __secret = true } or 5.2 end
function UnitHealth() return M.combat and { __secret = true } or 1000 end
WOW_PROJECT_ID = 18
Enum = { DamageMeterType = { DamageDone = 0 }, DamageMeterSessionType = { Overall = 0, Current = 1 } }
C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }

M.reset()
return M
