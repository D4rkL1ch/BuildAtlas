local addonName, ns = ...

-- Tooltips (design/Tooltip.dc.html):
--  * TalentTooltip.Fill: the planner's talent tooltip (rank values, synergy
--    block, change vs Classic, Ctrl for IDs).
--  * Spell tooltips anywhere (action bars, spellbook): a "changed by N
--    talents" block for the player's current build. Shift lists all.
-- Spell tooltips read a precomputed index (rebuilt out of combat when talents
-- change), so nothing queries the talent API while a tooltip is drawn.

local L = ns.L
local Plan = ns.Plan

local TalentTooltip = {}
ns.TalentTooltip = TalentTooltip

local GOLD, MUTED, TEAL, GREEN, ORANGE, WHITE = { 0.88, 0.71, 0.29 }, { 0.71, 0.73, 0.77 }, { 0.31, 0.76, 0.71 }, { 0.56, 0.83, 0.63 }, { 0.94, 0.63, 0.44 }, { 1, 1, 1 }

local function add(tt, text, color, wrap)
	tt:AddLine(text, color[1], color[2], color[3], wrap)
end

local function addPair(tt, left, right, lc, rc)
	tt:AddDoubleLine(left, right, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
end

-- The numbers that change between rank texts, e.g. { "20%", "40%", "60%" }.
-- Nil when the texts differ in more than one place or not at all.
function TalentTooltip.RankValues(rankTexts)
	if not rankTexts or #rankTexts < 2 then return nil end
	local pattern = "[%d%.]+%%?"
	local tokens = {}
	for i, text in ipairs(rankTexts) do
		tokens[i] = {}
		for n in text:gmatch(pattern) do table.insert(tokens[i], n) end
	end
	local col
	for j = 1, #tokens[1] do
		for i = 2, #tokens do
			if tokens[i][j] ~= tokens[1][j] then
				if col and col ~= j then return nil end
				col = j
			end
		end
	end
	if not col then return nil end
	local out = {}
	for i = 1, #tokens do out[i] = tokens[i][col] or "?" end
	return out
end

-- Fills GameTooltip (already owned/anchored) for a talent of `tree` under
-- the plan `ranks`, with the synergy graph `graph`.
function TalentTooltip.Fill(tt, tree, ranks, graph, t, spellName)
	local r = ranks[t.id] or 0
	local data = ns.Talents.Data(t)
	addPair(tt, t.name, t.free and L["Granted"] or (L["Rank %d/%d"]):format(r, t.maxRanks), WHITE, GOLD)
	local group = tree.groups[t.group]
	local tier = math.floor(t.tierPoints / ns.POINTS_PER_TIER) + 1
	local reqLine = (group and group.name or "?") .. " · " .. L["tier"] .. " " .. tier
	if t.tierPoints > 0 then reqLine = reqLine .. " · " .. (L["requires %d points in %s"]):format(t.tierPoints, group and group.name or "?") end
	add(tt, reqLine, MUTED)
	local desc = ns.Talents.Describe(t, r)
	if desc then add(tt, desc, { 0.9, 0.9, 0.9 }, true) end

	local values = data and TalentTooltip.RankValues(data.ranks)
	if values then
		local parts = {}
		for i, v in ipairs(values) do
			local s = v
			if i == r then
				s = "|cffe0b54a" .. v .. "|r"
			elseif i == r + 1 then
				s = "|cff8fd3a0" .. v .. "|r"
			end
			parts[i] = s
		end
		add(tt, L["Ranks: "] .. table.concat(parts, " / "), MUTED)
	elseif r > 0 and r < t.maxRanks then
		local nextDesc = ns.Talents.Describe(t, r + 1)
		if nextDesc then add(tt, L["Next rank: "] .. nextDesc, GREEN, true) end
	end

	if graph and graph.hasData then
		local mods = graph:Mods(t.id)
		local related = graph:Related(t.id)
		local stats = graph:Stats(t.id)
		if #mods > 0 or #related > 0 or #stats > 0 then
			tt:AddLine(" ")
			add(tt, L["SYNERGY"], TEAL)
		end
		if #mods > 0 then
			local names = {}
			for i, m in ipairs(mods) do
				if i > 5 then names[#names + 1] = (L["+%d more"]):format(#mods - 5) break end
				names[#names + 1] = spellName(m.spell)
			end
			addPair(tt, L["Changes"], table.concat(names, ", "), MUTED, WHITE)
		end
		local boosted = {}
		for _, rel in ipairs(related) do
			local o = tree.talents[rel.id]
			local orank = ranks[rel.id] or 0
			if o and orank > 0 then boosted[#boosted + 1] = ("%s %d/%d"):format(o.name, orank, o.maxRanks) end
		end
		if #boosted > 0 then addPair(tt, L["Works with"], table.concat(boosted, ", "), MUTED, GREEN) end
		if #stats > 0 then addPair(tt, L["Scales with"], table.concat(stats, " · "), MUTED, { 0.73, 0.78, 0.94 }) end
		local note = graph:Note(t.id)
		if note then add(tt, note, TEAL, true) end
	end

	if data and data.classic then
		tt:AddLine(" ")
		add(tt, L["CHANGED VS CLASSIC"], MUTED)
		add(tt, data.classic, data.classic == "Same as Classic." and MUTED or ORANGE, true)
	end

	local req = r < t.maxRanks and not t.free and select(2, Plan.CanIncrease(tree, ranks, t.id))
	if req == "tier" or req == "prereq" then
		local _, _, detail = Plan.CanIncrease(tree, ranks, t.id)
		local text = req == "tier" and (L["Needs %d points in %s"]):format(detail, group and group.name or "?")
			or (L["Needs %s maxed"]):format(tree.talents[detail].name)
		add(tt, text, ORANGE, true)
	end

	if IsControlKeyDown() then
		tt:AddLine(" ")
		add(tt, ("spell %s · node %d · entry %s"):format(tostring(t.spellID), t.id, tostring(t.entryID)), MUTED)
		if graph then
			for _, m in ipairs(graph:Mods(t.id)) do
				add(tt, ("  %s (%s): %s"):format(spellName(m.spell), tostring(m.spell), m.fx), MUTED)
			end
		end
	else
		add(tt, L["Hold Ctrl: spell IDs and raw effects"] .. "  ·  " .. L["Data "] .. tostring(ns.DATA_BUILD), { 0.55, 0.57, 0.63 })
	end
end

-- Spell tooltips ------------------------------------------------------------------

-- index[baseSpell] = { { name, fx, rank, max }, ... } for the active spec.
local index, indexClass
TalentTooltip._index = function() return index end

function TalentTooltip.RebuildIndex()
	if InCombatLockdown() then return end
	local classID = ns.Talents.PlayerClassID()
	local data = ns.ClassData and ns.ClassData[classID]
	local tree = data and ns.Talents.ReadTree(classID)
	if not tree then
		index = nil
		return
	end
	local ranks = tree.readRanks or {}
	local out = {}
	for id, t in pairs(tree.talents) do
		local r = ranks[id] or 0
		local td = t.spellID and data.talents[t.spellID]
		if r > 0 and td then
			for _, m in ipairs(td.mods) do
				out[m.spell] = out[m.spell] or {}
				table.insert(out[m.spell], { name = t.name, fx = m.fx, rank = r, max = t.maxRanks })
			end
		end
	end
	for _, list in pairs(out) do
		table.sort(list, function(a, b) return a.name < b.name end)
	end
	index, indexClass = out, classID
end

local function onSpellTooltip(tt, tooltipData)
	if not index or not tooltipData or (ns.db and ns.db.settings.spellTooltips == false) then return end
	if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
	local spellID = tooltipData.id
	if spellID == nil or ns.Secrets.IsSecret(spellID) or type(spellID) ~= "number" then return end
	local data = ns.ClassData[indexClass]
	local key = data.rankOf[spellID] or spellID
	local list = index[key]
	if not list or #list == 0 then return end
	tt:AddLine(" ")
	add(tt, (L["Build Atlas · changed by %d talents"]):format(#list), TEAL)
	local shown = IsShiftKeyDown() and #list or math.min(#list, 3)
	for i = 1, shown do
		local e = list[i]
		addPair(tt, ("%s %d/%d"):format(e.name, e.rank, e.max), e.fx, WHITE, MUTED)
	end
	if shown < #list then add(tt, (L["+%d more (Shift to expand)"]):format(#list - shown), MUTED) end
end

ns:RegisterMessage("BA_LOGIN", function()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, onSpellTooltip)
	end
	ns.Util.After(3, TalentTooltip.RebuildIndex)
end)

local function rebuildSoon()
	ns.Util.After(0.5, TalentTooltip.RebuildIndex)
end
ns:RegisterEvent("TRAIT_CONFIG_UPDATED", rebuildSoon)
ns:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED", rebuildSoon)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if not index then rebuildSoon() end
end)
