local addonName, ns = ...

-- Talent -> spell -> stat graph. Pure: no WoW globals.
--
-- Bundled class data (written by tools/build_data.py, milestone M1) joins to
-- the live tree by the talent's spellID:
--   data.talents[talentSpellID] = {
--     mods  = { { spell = spellID, fx = "+1% crit per rank" }, ... },
--     stats = { "Crit", ... },
--     note  = "Proc chain: ...",
--   }
-- Two talents are related when they modify at least one spell in common.

local SynergyGraph = {}
SynergyGraph.__index = SynergyGraph
ns.SynergyGraph = SynergyGraph

local EMPTY = {}

function SynergyGraph.New(tree, data)
	local g = setmetatable({ tree = tree, byTalent = {}, bySpell = {}, hasData = false }, SynergyGraph)
	local talentsData = data and data.talents or EMPTY
	for id, t in pairs(tree.talents) do
		local d = t.spellID and talentsData[t.spellID]
		if d then
			g.hasData = true
			g.byTalent[id] = d
			for _, m in ipairs(d.mods or EMPTY) do
				local list = g.bySpell[m.spell]
				if not list then
					list = {}
					g.bySpell[m.spell] = list
				end
				list[#list + 1] = id
			end
		end
	end
	for _, list in pairs(g.bySpell) do table.sort(list) end
	return g
end

function SynergyGraph:Mods(id)
	local d = self.byTalent[id]
	return d and d.mods or EMPTY
end

function SynergyGraph:Stats(id)
	local d = self.byTalent[id]
	return d and d.stats or EMPTY
end

function SynergyGraph:Note(id)
	local d = self.byTalent[id]
	return d and d.note
end

-- Talents (nodeIDs, ascending) that modify `spell`.
function SynergyGraph:TalentsTouching(spell)
	return self.bySpell[spell] or EMPTY
end

-- The effect text `id` has on `spell`, if any.
function SynergyGraph:EffectOn(id, spell)
	for _, m in ipairs(self:Mods(id)) do
		if m.spell == spell then return m.fx end
	end
end

-- Talents sharing a modified spell with `id`:
-- { { id = nodeID, via = { spell, ... } }, ... } ordered by nodeID.
function SynergyGraph:Related(id)
	local via = {}
	for _, m in ipairs(self:Mods(id)) do
		for _, other in ipairs(self:TalentsTouching(m.spell)) do
			if other ~= id then
				via[other] = via[other] or {}
				local list = via[other]
				local seen = false
				for _, s in ipairs(list) do
					if s == m.spell then seen = true break end
				end
				if not seen then list[#list + 1] = m.spell end
			end
		end
	end
	local out = {}
	for other, spells in pairs(via) do out[#out + 1] = { id = other, via = spells } end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- Set of nodeIDs related to `id` (for ring highlights).
function SynergyGraph:RelatedSet(id)
	local set = {}
	for _, r in ipairs(self:Related(id)) do set[r.id] = true end
	return set
end

-- Spells the plan modifies, with how many learned talents touch each:
-- { { spell = spellID, count = n }, ... } most-modified first.
function SynergyGraph:BuildSpells(ranks)
	local counts = {}
	for id in pairs(self.byTalent) do
		if (ranks[id] or 0) > 0 then
			for _, m in ipairs(self:Mods(id)) do
				counts[m.spell] = (counts[m.spell] or 0) + 1
			end
		end
	end
	local out = {}
	for spell, n in pairs(counts) do out[#out + 1] = { spell = spell, count = n } end
	table.sort(out, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.spell < b.spell
	end)
	return out
end
