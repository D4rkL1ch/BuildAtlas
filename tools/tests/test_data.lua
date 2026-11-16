local T = ...

-- Checks on the generated Data/TalentData.lua (tools/build_data.py).

T.test("data: every class has talents with ranks and a build stamp", function()
	local ns = T.boot()
	T.ok(ns.DATA_BUILD and ns.DATA_BUILD:match("^1%.60%.%d+%.%d+$"), "build stamp " .. tostring(ns.DATA_BUILD))
	for _, c in ipairs(ns.Classes) do
		local data = ns.ClassData[c.classID]
		T.ok(data, c.token .. " data")
		T.eq(data.build, ns.DATA_BUILD)
		local n, linked = 0, 0
		for _, t in pairs(data.talents) do
			n = n + 1
			T.ok(t.name and t.max and t.max >= 1, c.token .. " talent fields")
			T.eq(#t.ranks, t.max, c.token .. " " .. t.name .. " rank texts")
			if #t.mods > 0 then linked = linked + 1 end
			for _, m in ipairs(t.mods) do
				T.ok(data.spells[m.spell], c.token .. " " .. t.name .. ": spell " .. tostring(m.spell) .. " has an entry")
			end
		end
		T.ok(n >= 45, c.token .. " has " .. n .. " talents")
		T.ok(linked / n > 0.6, c.token .. " links " .. linked .. "/" .. n)
	end
end)

T.test("data: warrior spot checks against in-game tooltips", function()
	local ns = T.boot()
	local w = ns.ClassData[1]
	-- Improved Heroic Strike: -1 rage per rank (3 ranks).
	local ihs = w.talents[12282]
	T.eq(ihs.mods[1].spell, 78)
	T.contains(ihs.mods[1].fx, "1 Rage cost per rank")
	T.eq(ihs.ranks[3], "Reduces the cost of your Heroic Strike ability by 3 Rage.")
	-- Cruelty: 1% per rank via the rank curve, not 5% per rank.
	T.contains(w.talents[12320].ranks[1], "by 1%")
	T.contains(w.talents[12320].ranks[5], "by 5%")
	-- Improved Rend: non-linear curve.
	T.contains(w.talents[12286].mods[1].fx, "12/23/35%")
	-- Deep Wound damage (what the damage meter reports) belongs to Deep Wounds.
	T.eq(w.procOf[412613], 12834)
	-- Rend ranks map to one spell.
	T.eq(w.rankOf[11572], 772)
	-- Auto attack is keyed by the meter's spell ID.
	T.eq(w.spells[6603].name, "Auto Attack")
end)

T.test("data: synergy graph on real warrior data", function()
	local ns = T.boot()
	-- A tree with the real spell IDs of a few Arms talents.
	local tree = { groups = { {} }, talents = {
		[1] = { id = 1, spellID = 12834 }, -- Deep Wounds
		[2] = { id = 2, spellID = 16493 }, -- Impale
		[3] = { id = 3, spellID = 12290 }, -- Improved Overpower
		[4] = { id = 4, spellID = 12320 }, -- Cruelty
	} }
	local g = ns.SynergyGraph.New(tree, ns.ClassData[1])
	local rel = g:RelatedSet(3)
	T.ok(rel[1], "Improved Overpower relates to Deep Wounds via Overpower")
	T.ok(rel[2], "and to Impale")
	T.ok(g:RelatedSet(4)[1], "Cruelty relates to Deep Wounds via Auto Attack")
end)
