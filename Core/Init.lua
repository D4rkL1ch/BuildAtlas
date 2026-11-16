local addonName, ns = ...

-- Namespace basics ----------------------------------------------------------

ns.name = addonName
-- The packager replaces @project-version@ in the TOC with the release tag; a
-- copy deployed straight from the repo still has the token, so it reads "dev".
local metaVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
if not metaVersion or metaVersion:find("@", 1, true) then
	ns.version = "dev"
else
	ns.version = (metaVersion:gsub("^v", ""))
end
ns.DB_VERSION = 1

-- Localisation table: enUS strings are the keys themselves for now.
ns.L = setmetatable({}, { __index = function(_, key) return key end })

local CHAT_PREFIX = "|cffe0b54aBuild Atlas|r: "

function ns:Print(...)
	print(CHAT_PREFIX .. strjoin(" ", tostringall(...)))
end

-- Client build, e.g. "1.60.1.70862", and the interface number.
function ns:GetClientBuild()
	local version, build, _, interface = GetBuildInfo()
	return version .. "." .. build, interface
end

-- Forever is detected by interface range, not WOW_PROJECT_ID (it changed
-- between builds).
function ns:IsForever()
	local _, interface = self:GetClientBuild()
	return interface and interface >= 16000 and interface < 17000 or false
end

-- Event dispatcher ----------------------------------------------------------
-- Several handlers may listen to the same event; each receives (event, ...).
-- A handler that errors is reported and the others still run.

local function Dispatch(list, name, ...)
	local onError = geterrorhandler()
	for i = 1, #list do
		xpcall(list[i], onError, name, ...)
	end
end

local eventFrame = CreateFrame("Frame")
local handlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then Dispatch(list, event, ...) end
end)

function ns:RegisterEvent(event, handler)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		-- Events unknown to this client must not break loading.
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			handlers[event] = nil
			return false
		end
	end
	list[#list + 1] = handler
	return true
end

-- Internal messages between modules, same calling convention as events.
local messages = {}

function ns:RegisterMessage(name, handler)
	messages[name] = messages[name] or {}
	table.insert(messages[name], handler)
end

function ns:SendMessage(name, ...)
	local list = messages[name]
	if list then Dispatch(list, name, ...) end
end

-- Saved variables -----------------------------------------------------------

local DEFAULT_SETTINGS = {
	scale = 0.8,
	showAddonCompartment = true,
}

local function ApplyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then target[k] = v end
	end
end

local function InitSavedVariables()
	BuildAtlasDB = BuildAtlasDB or {}
	local db = BuildAtlasDB
	db.version = ns.DB_VERSION
	db.settings = db.settings or {}
	ApplyDefaults(db.settings, DEFAULT_SETTINGS)
	db.window = db.window or {}
	ns.db = db

	BuildAtlasCharDB = BuildAtlasCharDB or {}
	local char = BuildAtlasCharDB
	char.version = ns.DB_VERSION
	-- plans[classID][slot] = { treeID = n, ranks = { [nodeID] = rank } }
	char.plans = char.plans or {}
	ns.charDB = char
end

ns:RegisterEvent("ADDON_LOADED", function(_, loaded)
	if loaded ~= addonName then return end
	InitSavedVariables()
	ns:SendMessage("BA_LOADED")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
	ns:SendMessage("BA_LOGIN")
end)

-- Slash commands ------------------------------------------------------------

local commands = {}
local commandHelp = {}

-- Modules add subcommands: ns:AddCommand("probe", fn, "/atlas probe - ...").
function ns:AddCommand(name, fn, help)
	commands[name] = fn
	if help then commandHelp[#commandHelp + 1] = help end
end

SLASH_BUILDATLAS1 = "/atlas"
SLASH_BUILDATLAS2 = "/buildatlas"
SlashCmdList.BUILDATLAS = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then cmd = "show" end
	local fn = commands[cmd]
	if fn then
		fn(rest)
	else
		ns:Print(ns.L["Commands:"])
		for _, line in ipairs(commandHelp) do print("  " .. line) end
	end
end

ns:AddCommand("help", function()
	SlashCmdList.BUILDATLAS("?")
end)
