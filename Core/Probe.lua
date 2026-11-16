local addonName, ns = ...

-- /batlas probe: answers the open platform questions (docs/probe-results.md)
-- by calling the APIs and saving what came back to BuildAtlasDB.probe. The
-- in-combat and after-combat parts run on the next fight by themselves.
-- Debug tool; nothing here changes game state except setting up the view
-- loadout config, which the talent window does too.

local Probe = {}
ns.Probe = Probe

local Secrets = ns.Secrets
local Sanitize = Secrets.Sanitize

local function exists(path)
	local t = _G
	for part in path:gmatch("[^%.]+") do
		if type(t) ~= "table" then return false end
		t = t[part]
	end
	return t ~= nil
end

-- pcall a function and describe the outcome in a storable table.
local function try(fn, ...)
	if type(fn) ~= "function" then return { ok = false, err = "missing" } end
	local results = { pcall(fn, ...) }
	if not results[1] then return { ok = false, err = tostring(results[2]) } end
	local out = { ok = true, n = #results - 1 }
	for i = 2, #results do
		out[i - 1] = Sanitize(results[i], 3)
	end
	return out
end

local function describeValue(v)
	if Secrets.IsSecret(v) then return "secret" end
	return type(v) .. ":" .. tostring(v)
end

local function keysMatching(tbl, pattern)
	local out = {}
	if type(tbl) == "table" then
		for k in pairs(tbl) do
			if type(k) == "string" and k:find(pattern) then out[#out + 1] = k end
		end
	end
	table.sort(out)
	return out
end

-- Q1: tree IDs for every class, and whether another class's nodes are
-- readable with the player's own config.
local function probeTrees(p)
	local out = { specs = {} }
	local activeConfig = ns.Talents.GetActiveConfigID()
	for specID = 1480, 1495 do
		local row = {
			classID = Secrets.Read(nil, C_SpecializationInfo and C_SpecializationInfo.GetClassIDFromSpecID, specID),
			treeID = Secrets.Read(nil, C_ClassTalents and C_ClassTalents.GetTraitTreeForSpec, specID),
		}
		if row.treeID then
			local groups = Secrets.Read({}, C_Traits.GetGroupDisplayInfoByTreeID, row.treeID) or {}
			row.groups = {}
			for _, g in ipairs(groups) do
				row.groups[#row.groups + 1] = { groupID = g.groupID, name = g.displayName, order = g.orderIndex }
			end
			local nodes = Secrets.Read({}, C_Traits.GetTreeNodes, row.treeID) or {}
			row.nodeCount = #nodes
			if activeConfig and nodes[1] then
				local info = Secrets.Read(nil, C_Traits.GetNodeInfo, activeConfig, nodes[1])
				row.firstNodeWithOwnConfig = info and { ID = info.ID, maxRanks = info.maxRanks, posX = info.posX, posY = info.posY, entries = info.entryIDs and #info.entryIDs }
			end
		end
		if row.classID or row.treeID then out.specs[specID] = row end
	end
	p.q1_trees = out
end

-- Q2: view loadout for another class.
local function probeViewLoadout(p)
	local out = {
		InitializeViewLoadout = exists("C_ClassTalents.InitializeViewLoadout"),
		ViewLoadout = exists("C_ClassTalents.ViewLoadout"),
		viewConfigID = ns.Talents.VIEW_CONFIG_ID,
	}
	if InCombatLockdown() then
		out.skipped = "in combat"
	else
		local playerClass = ns.Talents.PlayerClassID()
		local other = playerClass == 8 and ns.ClassByID[1] or ns.ClassByID[8]
		out.otherClass = other.token
		out.init = try(C_ClassTalents and C_ClassTalents.InitializeViewLoadout, other.specID, 60)
		local treeID = Secrets.Read(nil, C_ClassTalents and C_ClassTalents.GetTraitTreeForSpec, other.specID)
		local nodes = treeID and Secrets.Read({}, C_Traits.GetTreeNodes, treeID) or {}
		out.samples = {}
		for i = 1, math.min(3, #nodes) do
			local info = Secrets.Read(nil, C_Traits.GetNodeInfo, ns.Talents.VIEW_CONFIG_ID, nodes[i])
			local entryID = info and info.entryIDs and info.entryIDs[1]
			local entry = entryID and Secrets.Read(nil, C_Traits.GetEntryInfo, ns.Talents.VIEW_CONFIG_ID, entryID)
			local def = entry and entry.definitionID and Secrets.Read(nil, C_Traits.GetDefinitionInfo, entry.definitionID)
			out.samples[i] = {
				nodeID = nodes[i], ID = info and info.ID, maxRanks = info and info.maxRanks, isVisible = info and info.isVisible,
				spellID = def and def.spellID, name = def and def.spellID and Secrets.Read(nil, C_Spell.GetSpellName, def.spellID),
			}
		end
		-- The planner's own reader on the other class, end to end.
		ns.Talents.Invalidate(other.classID)
		local tree, why = ns.Talents.ReadTree(other.classID)
		out.readerResult = tree and { talents = 0, groups = #tree.groups, rows = tree.rows, cols = tree.cols } or why
		if tree then
			for _ in pairs(tree.talents) do out.readerResult.talents = out.readerResult.talents + 1 end
		end
	end
	p.q2_viewLoadout = out
end

-- Q3: import strings.
local function probeImportString(p)
	local configID = ns.Talents.GetActiveConfigID()
	local out = {
		exists = exists("C_Traits.GenerateImportString"),
		serializationVersion = try(C_Traits.GetLoadoutSerializationVersion),
	}
	if configID then
		local r = try(C_Traits.GenerateImportString, configID)
		out.result = r
		local treeID = ns.Talents.GetTreeID(ns.Talents.PlayerClassID())
		if treeID then
			local hash = Secrets.Read(nil, C_Traits.GetTreeHash, treeID)
			out.treeHashLength = hash and #hash
		end
	end
	p.q3_importString = out
end

-- Q4: LibTalentTree (only if another addon loaded it; we don't bundle it).
local function probeLibTalentTree(p)
	local lib = LibStub and LibStub("LibTalentTree-1.0", true)
	local out = { loaded = lib ~= nil }
	if lib and lib.GetClassTreeID then
		out.classTreeIDs = {}
		for _, c in ipairs(ns.Classes) do
			out.classTreeIDs[c.token] = Sanitize(select(2, pcall(lib.GetClassTreeID, lib, c.classID)))
		end
	end
	p.q4_libTalentTree = out
end

-- Q5: character stats. The out-of-combat half runs now; the in-combat half
-- runs ~1 s into the next fight (see below).
local STAT_READS = {
	{ "GetCritChance", function() return GetCritChance() end },
	{ "GetRangedCritChance", function() return GetRangedCritChance() end },
	{ "GetSpellCritChance", function() return GetSpellCritChance() end },
	{ "GetSpellBonusDamage(2)", function() return GetSpellBonusDamage(2) end },
	{ "GetHitModifier", function() return GetHitModifier() end },
	{ "GetHaste", function() return GetHaste() end },
	{ "UnitAttackPower", function() return UnitAttackPower("player") end },
	{ "UnitStat(1)", function() return UnitStat("player", 1) end },
	{ "UnitHealth", function() return UnitHealth("player") end },
	{ "UnitPower", function() return UnitPower("player") end },
	{ "C_Secrets.ShouldUnitStatsBeSecret", function() return C_Secrets.ShouldUnitStatsBeSecret() end },
	{ "C_Secrets.ShouldAurasBeSecret", function() return C_Secrets.ShouldAurasBeSecret() end },
}

local function sampleStats()
	local values = {}
	for _, s in ipairs(STAT_READS) do
		local ok, v = pcall(s[2])
		values[s[1]] = ok and describeValue(v) or ("error: " .. tostring(v))
	end
	return { inCombat = InCombatLockdown() and true or false, time = time(), values = values }
end

-- Q6: C_DamageMeter after a fight.
local function probeDamageMeter()
	local out = { exists = exists("C_DamageMeter"), time = time(), inCombat = InCombatLockdown() and true or false }
	if not out.exists then return out end
	out.available = try(C_DamageMeter.IsDamageMeterAvailable)
	local sessions = Secrets.Read({}, C_DamageMeter.GetAvailableCombatSessions) or {}
	out.sessions = Sanitize(sessions, 3)
	local last = sessions[#sessions]
	local damageDone = Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
	if last and last.sessionID then
		local session = Secrets.Read(nil, C_DamageMeter.GetCombatSessionFromID, last.sessionID, damageDone)
		if session then
			out.lastSession = {
				totalAmount = describeValue(session.totalAmount),
				durationSeconds = describeValue(session.durationSeconds),
				sources = {},
			}
			for i, src in ipairs(session.combatSources or {}) do
				if i > 5 then break end
				out.lastSession.sources[i] = {
					isLocalPlayer = src.isLocalPlayer, classFilename = src.classFilename,
					totalAmount = describeValue(src.totalAmount), amountPerSecond = describeValue(src.amountPerSecond),
					name = describeValue(src.name),
				}
			end
		end
		local guid = UnitGUID("player")
		local mine = Secrets.Read(nil, C_DamageMeter.GetCombatSessionSourceFromID, last.sessionID, damageDone, guid)
		if mine then
			out.playerSpells = { totalAmount = describeValue(mine.totalAmount), spells = {} }
			for i, sp in ipairs(mine.combatSpells or {}) do
				if i > 15 then break end
				out.playerSpells.spells[i] = {
					spellID = describeValue(sp.spellID), totalAmount = describeValue(sp.totalAmount),
					amountPerSecond = describeValue(sp.amountPerSecond),
					name = not Secrets.IsSecret(sp.spellID) and Secrets.Read(nil, C_Spell.GetSpellName, sp.spellID) or nil,
				}
			end
		end
	end
	out.sessionTypeCurrent = Enum.DamageMeterSessionType and Sanitize(Enum.DamageMeterSessionType, 1)
	return out
end

-- Q7: tooltip and description access for trait entries.
local function probeTooltips(p)
	local out = {
		C_TooltipInfo_trait = keysMatching(C_TooltipInfo, "Trait"),
		GetSpellDescription = exists("C_Spell.GetSpellDescription"),
		GetTraitDescription = exists("C_Traits.GetTraitDescription"),
	}
	local tree = ns.Talents.ReadTree(ns.Talents.PlayerClassID())
	if tree then
		local sample
		for _, t in pairs(tree.talents) do
			if t.maxRanks > 1 and t.entryID then sample = t break end
		end
		if sample then
			out.sample = { name = sample.name, spellID = sample.spellID, entryID = sample.entryID }
			out.traitDescRank1 = try(C_Traits.GetTraitDescription, sample.entryID, 1)
			out.traitDescRank2 = try(C_Traits.GetTraitDescription, sample.entryID, 2)
			out.spellDesc = try(C_Spell.GetSpellDescription, sample.spellID)
			if C_TooltipInfo and C_TooltipInfo.GetTraitEntry then
				local r = try(C_TooltipInfo.GetTraitEntry, sample.entryID, 1)
				if r.ok and type(r[1]) == "table" and type(r[1].lines) == "table" then
					local lines = {}
					for i, line in ipairs(r[1].lines) do lines[i] = line.leftText end
					out.tooltipEntry = lines
				else
					out.tooltipEntry = r
				end
			end
		end
	end
	p.q7_tooltips = out
end

-- Q8: assisted combat (info only).
local function probeAssistedCombat(p)
	p.q8_assistedCombat = {
		exists = exists("C_AssistedCombat"),
		functions = keysMatching(C_AssistedCombat, "."),
		isAvailable = C_AssistedCombat and try(C_AssistedCombat.IsAvailable) or nil,
	}
end

-- Raw dump of the player's own tree: layout, gates, edges, costs. Feeds the
-- layout derivation and the M1 data join.
local function probeOwnTree(p)
	local classID = ns.Talents.PlayerClassID()
	local treeID = ns.Talents.GetTreeID(classID)
	local configID = ns.Talents.GetActiveConfigID()
	local out = { classID = classID, treeID = treeID, configID = configID }
	if configID then
		local cfg = Secrets.Read(nil, C_Traits.GetConfigInfo, configID)
		out.config = cfg and { type = cfg.type, name = cfg.name, treeIDs = Sanitize(cfg.treeIDs) }
		out.specConfigs = {
			ns.Talents.GetSpecConfigID(1), ns.Talents.GetSpecConfigID(2),
			active = ns.Talents.GetActiveSpecGroup(), numSpecGroups = ns.Talents.GetNumSpecGroups(),
		}
	end
	if treeID and configID then
		out.currency = Sanitize(Secrets.Read(nil, C_Traits.GetTreeCurrencyInfo, configID, treeID, false), 3)
		local treeInfo = Secrets.Read(nil, C_Traits.GetTreeInfo, configID, treeID)
		out.gates = treeInfo and Sanitize(treeInfo.gates, 3)
		local groups = Secrets.Read({}, C_Traits.GetGroupDisplayInfoByTreeID, treeID) or {}
		local ids = {}
		for _, g in ipairs(groups) do ids[#ids + 1] = g.groupID end
		out.groupCurrency = Sanitize(Secrets.Read(nil, C_Traits.GetGroupCurrencyInfo, configID, ids), 4)
		out.nodes = {}
		for _, nodeID in ipairs(Secrets.Read({}, C_Traits.GetTreeNodes, treeID) or {}) do
			local info = Secrets.Read(nil, C_Traits.GetNodeInfo, configID, nodeID)
			if info and info.ID ~= 0 then
				local entryID = info.entryIDs and info.entryIDs[1]
				local entry = entryID and Secrets.Read(nil, C_Traits.GetEntryInfo, configID, entryID)
				local def = entry and entry.definitionID and Secrets.Read(nil, C_Traits.GetDefinitionInfo, entry.definitionID)
				local conds = {}
				for _, condID in ipairs(info.conditionIDs or {}) do
					local c = Secrets.Read(nil, C_Traits.GetConditionInfo, configID, condID)
					if c then
						conds[#conds + 1] = { id = condID, type = c.type, isGate = c.isGate, spent = c.spentAmountRequired, granted = c.ranksGranted, level = c.playerLevel, met = c.isMet }
					end
				end
				local edges = {}
				for _, e in ipairs(info.visibleEdges or {}) do edges[#edges + 1] = { to = e.targetNode, type = e.type } end
				out.nodes[#out.nodes + 1] = {
					id = nodeID, x = info.posX, y = info.posY, type = info.type, flags = info.flags,
					groups = Sanitize(info.groupIDs), max = info.maxRanks, ranks = info.ranksPurchased,
					visible = info.isVisible, entry = entryID, entryType = entry and entry.type,
					def = entry and entry.definitionID, spell = def and def.spellID,
					name = def and def.spellID and Secrets.Read(nil, C_Spell.GetSpellName, def.spellID),
					conds = #conds > 0 and conds or nil, edges = #edges > 0 and edges or nil,
					cost = Sanitize(Secrets.Read(nil, C_Traits.GetNodeCost, configID, nodeID), 3),
				}
			end
		end
	end
	p.ownTree = out
end

function Probe.Run()
	local build, interface = ns:GetClientBuild()
	local _, classToken = UnitClass("player")
	local p = {
		meta = {
			build = build, interface = interface, projectID = WOW_PROJECT_ID, isForever = ns:IsForever(),
			class = classToken, level = UnitLevel("player"), addonVersion = ns.version,
			date = date("%Y-%m-%d %H:%M"),
		},
	}
	local steps = {
		{ "own tree", probeOwnTree }, { "trees", probeTrees }, { "view loadout", probeViewLoadout },
		{ "import string", probeImportString }, { "LibTalentTree", probeLibTalentTree },
		{ "tooltips", probeTooltips }, { "assisted combat", probeAssistedCombat },
	}
	p.errors = {}
	for _, step in ipairs(steps) do
		local ok, err = pcall(step[2], p)
		if not ok then p.errors[step[1]] = tostring(err) end
	end
	p.q5_stats = { outOfCombat = sampleStats(), inCombat = "pending: enter combat once" }
	p.q6_damageMeter = { now = probeDamageMeter(), afterCombat = "pending: finish a fight" }
	ns.db.probe = p
	-- Ranks may have been read through the view config: drop cached trees.
	ns.Talents.Invalidate()
	Probe.Summarize(p)
end

function Probe.Summarize(p)
	local L = ns.L
	ns:Print(L["Probe saved. Client"], p.meta.build, "interface", p.meta.interface)
	local trees = 0
	for _, row in pairs(p.q1_trees and p.q1_trees.specs or {}) do
		if row.treeID then trees = trees + 1 end
	end
	print(("  Q1 class trees found: %d"):format(trees))
	local v = p.q2_viewLoadout
	print("  Q2 view loadout: " .. (v and (v.skipped or (type(v.readerResult) == "table" and ("works, " .. v.readerResult.talents .. " talents") or tostring(v.readerResult))) or "?"))
	local i = p.q3_importString
	print("  Q3 import string: " .. (i and i.result and (i.result.ok and "works" or ("error " .. tostring(i.result.err))) or "n/a"))
	print("  Q4 LibTalentTree loaded: " .. tostring(p.q4_libTalentTree and p.q4_libTalentTree.loaded))
	print("  Q5/Q6: " .. L["fight something once; results are added after combat."])
	local errs = 0
	for _ in pairs(p.errors) do errs = errs + 1 end
	if errs > 0 then print(("  |cffF0A070%d probe step(s) failed, see BuildAtlasDB.probe.errors|r"):format(errs)) end
	print("  " .. L["/reload to write the results to disk."])
end

-- Combat halves --------------------------------------------------------------

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	local p = ns.db and ns.db.probe
	if not p or type(p.q5_stats) ~= "table" or type(p.q5_stats.inCombat) == "table" then return end
	ns.Util.After(1, function()
		p.q5_stats.inCombat = sampleStats()
	end)
end)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	local p = ns.db and ns.db.probe
	if not p or type(p.q6_damageMeter) ~= "table" or type(p.q6_damageMeter.afterCombat) == "table" then return end
	ns.Util.After(2, function()
		if InCombatLockdown() then return end
		p.q6_damageMeter.afterCombat = probeDamageMeter()
		ns:Print(ns.L["Probe: combat samples recorded. /reload to save them."])
	end)
end)

ns:AddCommand("probe", function(arg)
	if arg == "dm" then
		if not (ns.db and ns.db.probe) then ns:Print("Run /batlas probe first.") return end
		ns.db.probe.q6_damageMeter.manual = probeDamageMeter()
		ns:Print("Damage meter sample recorded.")
		return
	end
	Probe.Run()
end, "/batlas probe - dump talent/API facts to SavedVariables (debug); /batlas probe dm - sample the damage meter now")
