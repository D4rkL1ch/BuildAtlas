local addonName, ns = ...

-- Export formats and import auto-detection. Pure Lua: callers pass the tree
-- (Model/Talents.lua shape plus nodeOrder and specID) and the client build.
--
-- Build Atlas string:  BA1:<classID>:<build>:<Blizzard loadout string>
--   versioned and build-stamped; the loadout part carries the node data.
-- Blizzard string:     the loadout string itself (talent window import).
-- Wowhead link:        https://www.wowhead.com/forever/talent-calc/blizzard/<loadout>
-- SimC profile:        a minimal profile with talents=<loadout>.

local Codecs = ns.Codecs or {}
ns.Codecs = Codecs

Codecs.WOWHEAD_PREFIX = "https://www.wowhead.com/forever/talent-calc/blizzard/"

function Codecs.ExportBuildAtlas(tree, ranks, build, version, hash)
	return ("BA1:%d:%s:%s"):format(tree.classID, build or "?", Codecs.PlanToLoadout(tree, ranks, version, hash))
end

function Codecs.ExportWowhead(tree, ranks, version)
	return Codecs.WOWHEAD_PREFIX .. Codecs.PlanToLoadout(tree, ranks, version)
end

-- classToken e.g. "WARRIOR"; name and level of the character.
function Codecs.ExportSimC(tree, ranks, info)
	local lines = {
		("%s=\"%s\""):format((info.classToken or "warrior"):lower(), info.name or "BuildAtlas"),
		("level=%d"):format(info.level or 60),
	}
	if info.race then lines[#lines + 1] = "race=" .. info.race:lower():gsub("%s", "_") end
	lines[#lines + 1] = "talents=" .. Codecs.PlanToLoadout(tree, ranks, info.version)
	return table.concat(lines, "\n")
end

-- Detects the format of pasted text. Returns { kind, loadout, classID,
-- build, specID } or nil and a reason.
--   kind: "buildatlas", "wowhead", "simc", "blizzard"
function Codecs.Detect(text, specToClass)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil, "empty" end
	local result
	local classID, build, loadout = text:match("^BA1:(%d+):([^:]*):(%S+)$")
	if classID then
		result = { kind = "buildatlas", loadout = loadout, classID = tonumber(classID), build = build }
	elseif text:find("talent-calc/blizzard/", 1, true) then
		result = { kind = "wowhead", loadout = text:match("talent%-calc/blizzard/([%w%+/]+)") }
	elseif text:find("talents=", 1, true) then
		result = { kind = "simc", loadout = text:match("talents=([%w%+/]+)") }
	elseif text:match("^[%w%+/]+$") then
		result = { kind = "blizzard", loadout = text }
	elseif text:find("://", 1, true) then
		return nil, "site"
	else
		return nil, "unknown"
	end
	if not result.loadout or result.loadout == "" then return nil, "unknown" end
	local specID, version = Codecs.LoadoutSpecID(result.loadout)
	if not specID then return nil, "short" end
	result.specID, result.version = specID, version
	result.classID = result.classID or (specToClass and specToClass[specID])
	if not result.classID then return nil, "spec" end
	return result
end
