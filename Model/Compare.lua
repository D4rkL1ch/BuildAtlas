local addonName, ns = ...

-- Build comparison and synergy-map data. Pure: no WoW globals.

local Compare = {}
ns.Compare = Compare

local Plan = ns.Plan

-- Diff of two plans on one tree:
-- { onlyA = { {id, a, b} }, onlyB = { ... }, both = { ... }, sharedPerGroup = { n, ... },
--   spells = { {spell, a, b} }, lean = { {stat, a, b} } }
function Compare.Diff(tree, ranksA, ranksB, graph)
	local out = { onlyA = {}, onlyB = {}, both = {}, sharedPerGroup = {} }
	for i = 1, #tree.groups do out.sharedPerGroup[i] = 0 end
	for _, t in ipairs(Plan.Ordered(tree)) do
		if not t.free then
			local a, b = ranksA[t.id] or 0, ranksB[t.id] or 0
			if a > b then
				table.insert(out.onlyA, { id = t.id, a = a, b = b })
			elseif b > a then
				table.insert(out.onlyB, { id = t.id, a = a, b = b })
			end
			local shared = math.min(a, b)
			if shared > 0 then
				out.sharedPerGroup[t.group] = out.sharedPerGroup[t.group] + shared
				if a == b then table.insert(out.both, { id = t.id, a = a, b = b }) end
			end
		end
	end

	-- Spells each build changes, by number of learned talents touching them.
	local spells = {}
	if graph then
		local function count(ranks, key)
			for _, s in ipairs(graph:BuildSpells(ranks)) do
				spells[s.spell] = spells[s.spell] or { spell = s.spell, a = 0, b = 0 }
				spells[s.spell][key] = s.count
			end
		end
		count(ranksA, "a")
		count(ranksB, "b")
	end
	out.spells = {}
	for _, s in pairs(spells) do out.spells[#out.spells + 1] = s end
	table.sort(out.spells, function(x, y)
		local dx, dy = math.abs(x.a - x.b), math.abs(y.a - y.b)
		if dx ~= dy then return dx > dy end
		if x.a + x.b ~= y.a + y.b then return x.a + x.b > y.a + y.b end
		return x.spell < y.spell
	end)

	out.lean = Compare.Lean(tree, ranksA, ranksB, graph)
	return out
end

-- Stat lean: each learned talent adds (rank / max) to every stat it lists.
-- A rough signal of what a build leans on; not a simulation.
function Compare.Lean(tree, ranksA, ranksB, graph)
	local stats = {}
	local function add(ranks, key)
		for id, t in pairs(tree.talents) do
			local r = ranks[id] or 0
			if r > 0 and graph then
				for _, s in ipairs(graph:Stats(id)) do
					stats[s] = stats[s] or { stat = s, a = 0, b = 0 }
					stats[s][key] = stats[s][key] + r / t.maxRanks
				end
			end
		end
	end
	add(ranksA, "a")
	if ranksB then add(ranksB, "b") end
	local list = {}
	for _, s in pairs(stats) do list[#list + 1] = s end
	table.sort(list, function(x, y)
		if x.a + x.b ~= y.a + y.b then return x.a + x.b > y.a + y.b end
		return x.stat < y.stat
	end)
	return list
end

-- One-line summary, e.g. "A leans Crit and Weapon damage; B leans Block and Armor."
function Compare.Summary(diff, nameA, nameB)
	local leanA, leanB = {}, {}
	for _, s in ipairs(diff.lean) do
		if s.a - s.b >= 1 and #leanA < 2 then leanA[#leanA + 1] = s.stat end
		if s.b - s.a >= 1 and #leanB < 2 then leanB[#leanB + 1] = s.stat end
	end
	if #diff.onlyA == 0 and #diff.onlyB == 0 then return "The builds are identical." end
	local parts = {}
	if #leanA > 0 then parts[#parts + 1] = (nameA or "A") .. " leans " .. table.concat(leanA, " and ") end
	if #leanB > 0 then parts[#parts + 1] = (nameB or "B") .. " leans " .. table.concat(leanB, " and ") end
	if #parts == 0 then return "Same stat lean; the builds differ in which spells they change." end
	return table.concat(parts, "; ") .. "."
end

-- Synergy map columns for a plan (mine = only learned talents).
-- { spells = { {spell, talents = {id...}} }, talents = { id... } }
function Compare.SynergyMap(tree, ranks, graph, mine)
	local spells, talentSet = {}, {}
	for id in pairs(tree.talents) do
		if not mine or (ranks[id] or 0) > 0 then
			for _, m in ipairs(graph:Mods(id)) do
				spells[m.spell] = spells[m.spell] or { spell = m.spell, talents = {} }
				table.insert(spells[m.spell].talents, id)
				talentSet[id] = true
			end
		end
	end
	local list = {}
	for _, s in pairs(spells) do
		table.sort(s.talents)
		list[#list + 1] = s
	end
	table.sort(list, function(a, b)
		if #a.talents ~= #b.talents then return #a.talents > #b.talents end
		return a.spell < b.spell
	end)
	local talents = {}
	for id in pairs(talentSet) do talents[#talents + 1] = id end
	table.sort(talents)
	return { spells = list, talents = talents }
end

-- Proc chains and resource loops of the learned talents, from the notes:
-- { procs = { {id, text} }, loops = { {id, text} } }
function Compare.Chains(tree, ranks, graph)
	local out = { procs = {}, loops = {} }
	for _, t in ipairs(Plan.Ordered(tree)) do
		local note = (ranks[t.id] or 0) > 0 and graph:Note(t.id)
		if note then
			local proc = note:match("Proc chain: ([^.]+%.?)") or note:match("Proc: ([^.]+%.?)")
			local loop = note:match("Resource loop: ([^.]+%.?)") or note:match("Resource: ([^.]+%.?)")
			if proc then table.insert(out.procs, { id = t.id, text = proc }) end
			if loop then table.insert(out.loops, { id = t.id, text = loop }) end
		end
	end
	return out
end
