local addonName, ns = ...

-- Bundled presets (Data/Presets.lua) and leveling paths. Resolution against
-- a live tree is pure; ForClass reads the tree.

local Presets = {}
ns.Presets = Presets

local Plan = ns.Plan

local function nodeBySpell(tree)
	local map = {}
	for id, t in pairs(tree.talents) do
		if t.spellID then map[t.spellID] = id end
	end
	return map
end

-- Node ranks for a preset on `tree`; nil and the missing spellID when the
-- tree no longer has one of its talents (after a hotfix).
function Presets.Resolve(tree, preset)
	local bySpell = nodeBySpell(tree)
	local ranks = {}
	for _, step in ipairs(preset.order) do
		local id = bySpell[step[1]]
		if not id then return nil, step[1] end
		ranks[id] = step[2]
	end
	return ranks
end

-- Presets of a class, each with .ranks resolved on the live tree and .valid.
function Presets.ForClass(classID)
	local out = {}
	local tree = ns.Talents.ReadTree(classID)
	for _, p in ipairs(ns.PresetData or {}) do
		if p.classID == classID then
			local copy = {}
			for k, v in pairs(p) do copy[k] = v end
			if tree then
				copy.ranks = Presets.Resolve(tree, p)
				copy.valid = copy.ranks ~= nil and Plan.Validate(tree, copy.ranks)
			end
			out[#out + 1] = copy
		end
	end
	return out
end

-- Leveling --------------------------------------------------------------------------

Presets.FIRST_TALENT_LEVEL = 10

-- Steps of a learning order: { {level, nodeID, rank}, ... } one per point.
function Presets.PathFromOrder(tree, order)
	local bySpell = nodeBySpell(tree)
	local steps, have = {}, {}
	for _, step in ipairs(order) do
		local id = bySpell[step[1]]
		if id then
			for r = (have[id] or 0) + 1, step[2] do
				steps[#steps + 1] = { level = Presets.FIRST_TALENT_LEVEL + #steps, id = id, rank = r }
			end
			have[id] = math.max(have[id] or 0, step[2])
		end
	end
	return steps
end

-- A learning order for a plan without one: always a legal next point, lowest
-- tier first, then the tab the plan puts most points in, then node order.
function Presets.PathFromPlan(tree, target)
	local _, targetPerGroup = Plan.Spent(tree, target)
	local ranks, steps = {}, {}
	local ordered = Plan.Ordered(tree)
	while true do
		local best
		for _, t in ipairs(ordered) do
			local want = target[t.id] or 0
			if (ranks[t.id] or 0) < want and Plan.CanIncrease(tree, ranks, t.id) then
				if not best
					or t.tierPoints < best.tierPoints
					or (t.tierPoints == best.tierPoints and (targetPerGroup[t.group] or 0) > (targetPerGroup[best.group] or 0)) then
					best = t
				end
			end
		end
		if not best then break end
		ranks[best.id] = (ranks[best.id] or 0) + 1
		steps[#steps + 1] = { level = Presets.FIRST_TALENT_LEVEL + #steps, id = best.id, rank = ranks[best.id] }
	end
	return steps
end

-- Points per tab after the first n steps.
function Presets.SplitAt(tree, steps, n)
	local ranks = {}
	for i = 1, math.min(n, #steps) do
		ranks[steps[i].id] = steps[i].rank
	end
	local _, perGroup = Plan.Spent(tree, ranks)
	return perGroup
end
