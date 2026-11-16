local T = ...

local function fixture()
	local tree = {
		groups = { {}, {} },
		talents = {
			[1] = { id = 1, spellID = 11 }, -- Impale
			[2] = { id = 2, spellID = 12 }, -- Cruelty
			[3] = { id = 3, spellID = 13 }, -- Toughness (no data)
			[4] = { id = 4, spellID = 14 }, -- Deep Wounds
		},
	}
	local data = {
		talents = {
			[11] = { mods = { { spell = 100, fx = "+10% crit damage" }, { spell = 101, fx = "+10% crit damage" } }, stats = { "Crit" } },
			[12] = { mods = { { spell = 100, fx = "+1% crit" }, { spell = 102, fx = "+1% crit" } }, stats = { "Crit" }, note = "More crits" },
			[14] = { mods = { { spell = 101, fx = "procs" } } },
		},
	}
	return tree, data
end

T.test("synergy: related talents share a modified spell", function()
	local ns = T.loadModel()
	local tree, data = fixture()
	local g = ns.SynergyGraph.New(tree, data)
	T.eq(g.hasData, true)
	local rel = g:Related(1)
	T.eq(#rel, 2)
	T.eq(rel[1].id, 2)
	T.eq(rel[1].via[1], 100)
	T.eq(rel[2].id, 4)
	T.eq(rel[2].via[1], 101)
	T.eq(#g:Related(3), 0, "talent without data")
	T.eq(g:RelatedSet(2)[1], true)
end)

T.test("synergy: spell view and effects", function()
	local ns = T.loadModel()
	local g = ns.SynergyGraph.New(fixture())
	local list = g:TalentsTouching(100)
	T.eq(#list, 2)
	T.eq(g:EffectOn(2, 102), "+1% crit")
	T.eq(g:EffectOn(2, 101), nil)
	T.eq(g:Note(2), "More crits")
	T.eq(g:Stats(1)[1], "Crit")
end)

T.test("synergy: build spells counts learned talents only", function()
	local ns = T.loadModel()
	local g = ns.SynergyGraph.New(fixture())
	local spells = g:BuildSpells({ [1] = 2, [2] = 5 })
	T.eq(spells[1].spell, 100)
	T.eq(spells[1].count, 2)
	T.eq(#spells, 3)
end)

T.test("synergy: no data is empty, not an error", function()
	local ns = T.loadModel()
	local tree = fixture()
	local g = ns.SynergyGraph.New(tree, nil)
	T.eq(g.hasData, false)
	T.eq(#g:Mods(1), 0)
	T.eq(#g:BuildSpells({ [1] = 1 }), 0)
end)
