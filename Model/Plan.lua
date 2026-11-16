local addonName, ns = ...

-- Pure planning rules. No WoW globals: testable offline.
--
-- A tree (see Model/Talents.lua) looks like:
--   tree.maxPoints = 51
--   tree.groups[i] = { groupID, name, icon }          -- the three tabs
--   tree.talents[nodeID] = {
--     id, group (index into groups), row, col (0-based),
--     maxRanks, tierPoints (points in the group needed to learn it),
--     prereqs = { nodeID, ... } (each must be maxed first),
--     free = true for nodes granted without spending points (milestones),
--   }
-- A plan is a table of ranks: ranks[nodeID] = n. Missing means 0.

local Plan = {}
ns.Plan = Plan

local function rankOf(ranks, id)
	return ranks[id] or 0
end

-- Points spent: total and per group index. Free nodes don't count.
function Plan.Spent(tree, ranks)
	local perGroup = {}
	for i = 1, #tree.groups do perGroup[i] = 0 end
	local total = 0
	for id, t in pairs(tree.talents) do
		local r = rankOf(ranks, id)
		if r > 0 and not t.free then
			perGroup[t.group] = (perGroup[t.group] or 0) + r
			total = total + r
		end
	end
	return total, perGroup
end

-- Points spent in `group` on talents whose tier requirement is below
-- `tierPoints`, i.e. the rows above it.
local function spentAbove(tree, ranks, group, tierPoints)
	local n = 0
	for id, t in pairs(tree.talents) do
		if t.group == group and not t.free and t.tierPoints < tierPoints then
			n = n + rankOf(ranks, id)
		end
	end
	return n
end

-- Whether the talent can go up one rank. On false, also returns a reason
-- ("free", "maxed", "points", "tier", "prereq") and a detail (points needed
-- for "tier", the prerequisite nodeID for "prereq").
function Plan.CanIncrease(tree, ranks, id)
	local t = tree.talents[id]
	if not t then return false, "unknown" end
	if t.free then return false, "free" end
	local r = rankOf(ranks, id)
	if r >= t.maxRanks then return false, "maxed" end
	local total, perGroup = Plan.Spent(tree, ranks)
	if total >= tree.maxPoints then return false, "points" end
	if (perGroup[t.group] or 0) < t.tierPoints then return false, "tier", t.tierPoints end
	for _, pid in ipairs(t.prereqs or {}) do
		local p = tree.talents[pid]
		if p and not p.free and rankOf(ranks, pid) < p.maxRanks then
			return false, "prereq", pid
		end
	end
	return true
end

-- Whether the talent can go down one rank without breaking the plan: every
-- learned talent deeper in the same group must still have enough points in
-- the rows above it, and no learned talent may depend on this one.
-- On false, returns a reason ("free", "empty", "tier", "prereq") and the
-- nodeID that would break.
function Plan.CanDecrease(tree, ranks, id)
	local t = tree.talents[id]
	if not t then return false, "unknown" end
	if t.free then return false, "free" end
	local r = rankOf(ranks, id)
	if r <= 0 then return false, "empty" end
	for oid, o in pairs(tree.talents) do
		if oid ~= id and rankOf(ranks, oid) > 0 and not o.free then
			if o.group == t.group and o.tierPoints > t.tierPoints then
				if spentAbove(tree, ranks, o.group, o.tierPoints) - 1 < o.tierPoints then
					return false, "tier", oid
				end
			end
			for _, pid in ipairs(o.prereqs or {}) do
				if pid == id then return false, "prereq", oid end
			end
		end
	end
	return true
end

function Plan.Increase(tree, ranks, id)
	if not Plan.CanIncrease(tree, ranks, id) then return false end
	ranks[id] = rankOf(ranks, id) + 1
	return true
end

function Plan.Decrease(tree, ranks, id)
	if not Plan.CanDecrease(tree, ranks, id) then return false end
	local r = rankOf(ranks, id) - 1
	ranks[id] = r > 0 and r or nil
	return true
end

-- For the "locked" look: an unlearned talent whose tier isn't reached yet.
-- `perGroup` (from Plan.Spent) may be passed to save recounting.
function Plan.IsLocked(tree, ranks, id, perGroup)
	local t = tree.talents[id]
	if not t or rankOf(ranks, id) > 0 then return false end
	if not perGroup then
		local _
		_, perGroup = Plan.Spent(tree, ranks)
	end
	return (perGroup[t.group] or 0) < t.tierPoints
end

-- Free (milestone) nodes are granted, not bought: treat them as learned
-- once their tier is reached.
function Plan.IsGranted(tree, ranks, id, perGroup)
	local t = tree.talents[id]
	if not t or not t.free then return false end
	return not Plan.IsLocked(tree, ranks, id, perGroup)
end

-- Points that differ between two plans: sum of |rank difference| over
-- talents in the tree (free nodes excluded).
function Plan.Diff(tree, a, b)
	local n = 0
	for id, t in pairs(tree.talents) do
		if not t.free then
			local d = rankOf(a, id) - rankOf(b, id)
			n = n + (d < 0 and -d or d)
		end
	end
	return n
end

-- Copy of `ranks` keeping only talents of `tree` with a valid rank.
function Plan.Clean(tree, ranks)
	local out = {}
	for id, r in pairs(ranks or {}) do
		local t = tree.talents[id]
		if t and not t.free and type(r) == "number" and r > 0 then
			out[id] = math.min(r, t.maxRanks)
		end
	end
	return out
end

-- Whether the plan obeys every rule (e.g. one loaded from storage after a
-- tree hotfix). Returns false and the first offending nodeID otherwise.
function Plan.Validate(tree, ranks)
	local total = Plan.Spent(tree, ranks)
	if total > tree.maxPoints then return false, nil, "points" end
	for id, t in pairs(tree.talents) do
		local r = rankOf(ranks, id)
		if r > 0 and not t.free then
			if r > t.maxRanks then return false, id, "maxed" end
			if spentAbove(tree, ranks, t.group, t.tierPoints) < t.tierPoints then return false, id, "tier" end
			for _, pid in ipairs(t.prereqs or {}) do
				local p = tree.talents[pid]
				if p and not p.free and rankOf(ranks, pid) < p.maxRanks then return false, id, "prereq" end
			end
		end
	end
	return true
end

-- Talents in display order: group, row, col.
function Plan.Ordered(tree)
	local list = {}
	for _, t in pairs(tree.talents) do list[#list + 1] = t end
	table.sort(list, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		if a.row ~= b.row then return a.row < b.row end
		if a.col ~= b.col then return a.col < b.col end
		return a.id < b.id
	end)
	return list
end
