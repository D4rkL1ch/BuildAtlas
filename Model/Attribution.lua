local addonName, ns = ...

-- Estimates how much of a fight's damage came from talents. Pure: no WoW
-- globals. Always an estimate; each row says how it was made:
--   Direct  - the spell exists because of the talent (granted ability, proc
--             damage such as Deep Wound): all of its damage counts.
--   Modeled - the talent adds X% damage to a spell that was recorded:
--             damage × bonus / (1 + bonus).
--   Rough   - the talent adds crit chance or crit damage, which can't be
--             observed in combat: assumes a 20% base crit rate.

local Attribution = {}
ns.Attribution = Attribution

local BASE_CRIT = 0.20

-- The numbers that change between rank texts, e.g. { "20%", "40%", "60%" }.
-- Nil when the texts differ in more than one place or not at all.
function Attribution.RankValues(rankTexts)
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

-- Value of a talent effect at `rank`, in percent, from its effect text
-- ("+12/23/35% periodic damage", "+1% damage per rank", "+5% crit") or, when
-- the text has no number, from the talent's rank descriptions.
function Attribution.EffectPercent(fx, rank, rankTexts)
	if fx then
		local series = fx:match("([%d%.]+/[%d%./]+)%%")
		if series then
			local values = {}
			for v in series:gmatch("[%d%.]+") do values[#values + 1] = tonumber(v) end
			return values[math.min(rank, #values)]
		end
		local single, perRank = fx:match("([%d%.]+)%%"), fx:find("per rank", 1, true)
		if single then return tonumber(single) * (perRank and rank or 1) end
	end
	if rankTexts and rankTexts[rank] then
		-- The number that changes between ranks, e.g. "by 6%".
		local values = Attribution.RankValues(rankTexts)
		local v = values and values[rank]
		if v and v:find("%%") then return tonumber((v:gsub("%%", ""))) end
	end
end

local function kindOf(fx)
	fx = (fx or ""):lower()
	if fx:find("grants the ability", 1, true) then return "direct" end
	if fx:find("crit damage", 1, true) then return "critdamage" end
	if fx:find("crit", 1, true) then return "crit" end
	if fx:find("damage", 1, true) and not fx:find("taken", 1, true) then return "damage" end
end

-- fight.spells = { [spellID] = amount }; talentRanks = { [talentSpellID] = rank }.
-- Returns { rows = { {talent, name, amount, share, method} } (largest first),
--           total = n, fromTalents = n, share = 0..1 }.
function Attribution.Estimate(fight, classData, talentRanks)
	local rowsByTalent = {}
	local function add(talent, amount, method)
		if amount <= 0 then return end
		local row = rowsByTalent[talent]
		if not row then
			local td = classData.talents[talent]
			row = { talent = talent, name = td and td.name or tostring(talent), amount = 0, method = method }
			rowsByTalent[talent] = row
		end
		row.amount = row.amount + amount
		-- The weakest method used for the row is the one shown.
		if method == "Rough" or (method == "Modeled" and row.method == "Direct") then row.method = method end
	end

	local total = 0
	for _, amount in pairs(fight.spells) do total = total + amount end

	-- Which learned talents touch which spell (base spell keys).
	local touching = {}
	for talent, rank in pairs(talentRanks) do
		local td = classData.talents[talent]
		if td and rank > 0 then
			for _, m in ipairs(td.mods) do
				touching[m.spell] = touching[m.spell] or {}
				table.insert(touching[m.spell], { talent = talent, rank = rank, fx = m.fx, td = td })
			end
		end
	end

	for spellID, amount in pairs(fight.spells) do
		local procTalent = classData.procOf and classData.procOf[spellID]
		if procTalent and (talentRanks[procTalent] or 0) > 0 then
			add(procTalent, amount, "Direct")
		else
			local key = classData.rankOf and classData.rankOf[spellID] or spellID
			local remaining = amount
			for _, t in ipairs(touching[key] or {}) do
				local kind = kindOf(t.fx)
				if kind == "direct" then
					add(t.talent, remaining, "Direct")
					remaining = 0
				elseif kind == "damage" then
					local pct = Attribution.EffectPercent(t.fx, t.rank, t.td.ranks)
					if pct and pct > 0 then
						local bonus = pct / 100
						add(t.talent, remaining * bonus / (1 + bonus), "Modeled")
					end
				elseif kind == "crit" then
					local pct = Attribution.EffectPercent(t.fx, t.rank, t.td.ranks)
					if pct and pct > 0 then
						local extra = math.min(pct / 100, 1) -- crit chance added; a crit doubles the hit
						add(t.talent, remaining * extra / (1 + BASE_CRIT + extra), "Rough")
					end
				elseif kind == "critdamage" then
					local pct = Attribution.EffectPercent(t.fx, t.rank, t.td.ranks)
					if pct and pct > 0 then
						local extra = BASE_CRIT * pct / 100
						add(t.talent, remaining * extra / (1 + BASE_CRIT + extra), "Rough")
					end
				end
			end
		end
	end

	local rows, fromTalents = {}, 0
	for _, row in pairs(rowsByTalent) do
		row.share = total > 0 and row.amount / total or 0
		fromTalents = fromTalents + row.amount
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b)
		if a.amount ~= b.amount then return a.amount > b.amount end
		return a.talent < b.talent
	end)
	fromTalents = math.min(fromTalents, total)
	return { rows = rows, total = total, fromTalents = fromTalents, share = total > 0 and fromTalents / total or 0 }
end

-- Merge fights: spells summed, durations summed.
function Attribution.Merge(fights)
	local merged = { spells = {}, duration = 0, total = 0, names = {} }
	for _, f in ipairs(fights) do
		for id, amount in pairs(f.spells) do merged.spells[id] = (merged.spells[id] or 0) + amount end
		merged.duration = merged.duration + (f.duration or 0)
		merged.total = merged.total + (f.total or 0)
		merged.names[#merged.names + 1] = f.name
		merged.ranks = merged.ranks or f.ranks
		merged.classID = merged.classID or f.classID
	end
	merged.name = #fights == 1 and fights[1].name or (#fights .. " fights")
	return merged
end

-- Benchmark --------------------------------------------------------------------------

-- runs = { {tag, dps, gear} }. Groups by tag over runs with `gear` (nil = any).
-- Returns { {tag, avg, min, max, n} } best first, plus whether the two best overlap.
function Attribution.BenchSummary(runs, gear)
	local byTag, order = {}, {}
	for _, r in ipairs(runs) do
		if not gear or r.gear == gear then
			local g = byTag[r.tag]
			if not g then
				g = { tag = r.tag, sum = 0, n = 0, min = math.huge, max = 0 }
				byTag[r.tag] = g
				order[#order + 1] = g
			end
			g.sum, g.n = g.sum + r.dps, g.n + 1
			g.min, g.max = math.min(g.min, r.dps), math.max(g.max, r.dps)
		end
	end
	for _, g in ipairs(order) do g.avg = g.sum / g.n end
	table.sort(order, function(a, b) return a.avg > b.avg end)
	local overlap = order[2] and order[2].max >= order[1].min or false
	return order, overlap
end
