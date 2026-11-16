local addonName, ns = ...

-- Reads talent trees from the live trait engine (C_Traits). Layout and ranks
-- always come from the client; bundled data only adds meaning on top.
--
-- Forever: one trait tree per class, the three classic tabs are trait groups
-- (C_Traits.GetGroupDisplayInfoByTreeID), and each spec group (dual spec) has
-- its own combat config (C_SpecializationInfo.GetCombatConfigIDForSpecGroup).

local Talents = {}
ns.Talents = Talents

local Secrets = ns.Secrets
local Read = Secrets.Read

local VIEW_CONFIG_ID = (Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID) or -3
Talents.VIEW_CONFIG_ID = VIEW_CONFIG_ID

local cache = {}

function Talents.Invalidate(classID)
	if classID then cache[classID] = nil else wipe(cache) end
end

function Talents.PlayerClassID()
	local _, _, classID = UnitClass("player")
	return classID
end

function Talents.GetActiveConfigID()
	return C_ClassTalents and Read(nil, C_ClassTalents.GetActiveConfigID)
end

function Talents.GetNumSpecGroups()
	return Read(1, GetNumSpecGroups) or 1
end

function Talents.GetActiveSpecGroup()
	local api = C_SpecializationInfo
	return (api and Read(nil, api.GetActiveSpecGroup)) or Read(1, GetActiveSpecGroup) or 1
end

-- Config holding the player's committed talents for spec group 1 or 2.
function Talents.GetSpecConfigID(specGroup)
	local api = C_SpecializationInfo
	local id = api and Read(nil, api.GetCombatConfigIDForSpecGroup, specGroup)
	if not id and specGroup == Talents.GetActiveSpecGroup() then
		id = Talents.GetActiveConfigID()
	end
	return id
end

function Talents.GetTreeID(classID)
	local class = ns.ClassByID[classID]
	local treeID = class and C_ClassTalents and Read(nil, C_ClassTalents.GetTraitTreeForSpec, class.specID)
	if not treeID and classID == Talents.PlayerClassID() then
		local configID = Talents.GetActiveConfigID()
		local info = configID and Read(nil, C_Traits.GetConfigInfo, configID)
		treeID = info and info.treeIDs and info.treeIDs[1]
	end
	return treeID
end

-- Config to read node info with. The player's own class uses the active
-- config; other classes use the "view loadout" config, which must be set up
-- first and only works out of combat.
function Talents.GetReadConfigID(classID)
	if classID == Talents.PlayerClassID() then
		local id = Talents.GetActiveConfigID()
		if id then return id end
		return nil, "noconfig"
	end
	if InCombatLockdown() then return nil, "combat" end
	local class = ns.ClassByID[classID]
	if not class or not (C_ClassTalents and C_ClassTalents.InitializeViewLoadout) then return nil, "noview" end
	local ok = pcall(C_ClassTalents.InitializeViewLoadout, class.specID, GetMaxLevelForPlayerExpansion and Read(60, GetMaxLevelForPlayerExpansion) or 60)
	if not ok then return nil, "noview" end
	return VIEW_CONFIG_ID
end

-- Layout ---------------------------------------------------------------------

local function minGap(sortedValues)
	local gap
	for i = 2, #sortedValues do
		local d = sortedValues[i] - sortedValues[i - 1]
		if d > 1 and (not gap or d < gap) then gap = d end
	end
	return gap
end

local function distinctSorted(values)
	local seen, out = {}, {}
	for _, v in ipairs(values) do
		if not seen[v] then
			seen[v] = true
			out[#out + 1] = v
		end
	end
	table.sort(out)
	return out
end

-- Turns canvas positions into grid cells. `nodes` is a list of
-- { id, group, posX, posY }; sets row and col (0-based) on each and returns
-- the grid size (rows, cols). Rows are shared by all groups (the tabs sit
-- side by side on one canvas); columns count from each group's left edge.
-- Pure: testable offline.
function Talents.DeriveLayout(nodes)
	if #nodes == 0 then return 0, 0 end
	local ys, minY = {}, math.huge
	local xsByGroup, minXByGroup = {}, {}
	for _, n in ipairs(nodes) do
		ys[#ys + 1] = n.posY
		if n.posY < minY then minY = n.posY end
		xsByGroup[n.group] = xsByGroup[n.group] or {}
		table.insert(xsByGroup[n.group], n.posX)
		if not minXByGroup[n.group] or n.posX < minXByGroup[n.group] then minXByGroup[n.group] = n.posX end
	end
	local stepY = minGap(distinctSorted(ys)) or 1
	local stepX
	for _, xs in pairs(xsByGroup) do
		local g = minGap(distinctSorted(xs))
		if g and (not stepX or g < stepX) then stepX = g end
	end
	stepX = stepX or 1
	local rows, cols = 0, 0
	for _, n in ipairs(nodes) do
		n.row = math.floor((n.posY - minY) / stepY + 0.5)
		n.col = math.floor((n.posX - minXByGroup[n.group]) / stepX + 0.5)
		if n.row + 1 > rows then rows = n.row + 1 end
		if n.col + 1 > cols then cols = n.col + 1 end
	end
	return rows, cols
end

-- Reading ---------------------------------------------------------------------

local function readGroups(treeID)
	local infos = Read(nil, C_Traits.GetGroupDisplayInfoByTreeID, treeID) or {}
	local groups = {}
	for _, info in ipairs(infos) do
		groups[#groups + 1] = { groupID = info.groupID, name = info.displayName, icon = info.icon, order = info.orderIndex or 0 }
	end
	table.sort(groups, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.groupID < b.groupID
	end)
	return groups
end

local function readDefinition(configID, entryID)
	local entry = entryID and Read(nil, C_Traits.GetEntryInfo, configID, entryID)
	local def = entry and entry.definitionID and Read(nil, C_Traits.GetDefinitionInfo, entry.definitionID)
	local spellID = def and (def.spellID or def.overriddenSpellID)
	local name = def and def.overrideName
	if (not name or name == "") and spellID then name = Read(nil, C_Spell.GetSpellName, spellID) end
	local icon = def and def.overrideIcon
	if not icon and spellID then icon = Read(nil, C_Spell.GetSpellTexture, spellID) end
	return spellID, name, icon, entry and entry.maxRanks
end

-- Gate (points needed in the group) and whether the node is granted for free.
local function readConditions(configID, conditionIDs)
	local tierPoints, granted
	for _, condID in ipairs(conditionIDs or {}) do
		local cond = Read(nil, C_Traits.GetConditionInfo, configID, condID)
		if cond then
			if cond.spentAmountRequired and cond.spentAmountRequired > 0 then
				tierPoints = math.max(tierPoints or 0, cond.spentAmountRequired)
			end
			if cond.ranksGranted and cond.ranksGranted > 0 then granted = true end
		end
	end
	return tierPoints, granted
end

-- Builds the tree for a class (see Model/Plan.lua for its shape). Returns
-- nil and a reason ("notree", "noconfig", "combat", "noview", "empty") when
-- the client can't provide it.
function Talents.ReadTree(classID)
	if cache[classID] then return cache[classID] end
	if not (C_Traits and C_Traits.GetTreeNodes) then return nil, "notree" end
	local treeID = Talents.GetTreeID(classID)
	if not treeID then return nil, "notree" end
	local configID, why = Talents.GetReadConfigID(classID)
	if not configID then return nil, why end

	local groups = readGroups(treeID)
	local groupIndex = {}
	for i, g in ipairs(groups) do groupIndex[g.groupID] = i end

	local talents, nodes, liveRanks = {}, {}, {}
	local gatesFound = false
	for _, nodeID in ipairs(Read(nil, C_Traits.GetTreeNodes, treeID) or {}) do
		local info = Read(nil, C_Traits.GetNodeInfo, configID, nodeID)
		if info and info.ID and info.ID ~= 0 and not info.subTreeID then
			local group
			for _, gid in ipairs(info.groupIDs or {}) do
				if groupIndex[gid] then group = groupIndex[gid] break end
			end
			if group then
				local entryID = info.entryIDs and info.entryIDs[1]
				local spellID, name, icon, entryMax = readDefinition(configID, entryID)
				local tierPoints, granted = readConditions(configID, info.conditionIDs)
				if tierPoints then gatesFound = true end
				local t = {
					id = nodeID, group = group, posX = info.posX or 0, posY = info.posY or 0,
					maxRanks = (info.maxRanks and info.maxRanks > 0) and info.maxRanks or entryMax or 1,
					entryID = entryID, spellID = spellID, name = name or ("Node " .. nodeID), icon = icon,
					tierPoints = tierPoints, free = granted or nil, prereqs = {},
				}
				talents[nodeID] = t
				nodes[#nodes + 1] = t
				if (info.ranksPurchased or 0) > 0 then liveRanks[nodeID] = info.ranksPurchased end
				t.outEdges = {}
				for _, edge in ipairs(info.visibleEdges or {}) do
					t.outEdges[#t.outEdges + 1] = edge.targetNode
				end
			end
		end
	end
	if #nodes == 0 then return nil, "empty" end

	-- Out-edges point at the dependent node: it needs this one maxed.
	for _, t in pairs(talents) do
		for _, target in ipairs(t.outEdges) do
			local dep = talents[target]
			if dep then dep.prereqs[#dep.prereqs + 1] = t.id end
		end
		t.outEdges = nil
	end

	local rows, cols = Talents.DeriveLayout(nodes)
	for _, t in pairs(talents) do
		if not t.tierPoints then t.tierPoints = t.row * ns.POINTS_PER_TIER end
	end

	local tree = {
		classID = classID, treeID = treeID, groups = groups, talents = talents,
		rows = rows, cols = math.max(cols, 4), maxPoints = ns.MAX_TALENT_POINTS,
		gatesFromData = gatesFound,
		-- Ranks of the config used to read: the active spec for the player's class.
		readRanks = liveRanks,
		isPlayerClass = classID == Talents.PlayerClassID(),
	}
	cache[classID] = tree
	return tree
end

-- Committed ranks of a config (e.g. a spec group), or nil.
function Talents.ReadRanks(tree, configID)
	if not configID then return nil end
	local ranks = {}
	for id, t in pairs(tree.talents) do
		if not t.free then
			local info = Read(nil, C_Traits.GetNodeInfo, configID, id)
			local r = info and info.ranksPurchased
			if r and r > 0 then ranks[id] = r end
		end
	end
	return ranks
end

-- Rank description from the client (rank 1 when unlearned).
function Talents.Describe(t, rank)
	if not t.entryID then return nil end
	local text = Read(nil, C_Traits.GetTraitDescription, t.entryID, math.max(1, rank))
	if (not text or text == "") and t.spellID then
		text = Read(nil, C_Spell.GetSpellDescription, t.spellID)
	end
	return text
end
