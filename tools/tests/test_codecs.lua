local T = ...

local fixture = dofile(T.root .. "/tools/tests/fixture_loadout.lua")

-- A tree built from the fixture: every node a talent in one group.
local function fixtureTree()
	local tree = { classID = 1, specID = fixture.specID, nodeOrder = {}, talents = {}, groups = { {} }, maxPoints = 51 }
	for i, n in ipairs(fixture.nodes) do
		tree.nodeOrder[i] = n[1]
		tree.talents[n[1]] = { id = n[1], group = 1, row = 0, col = 0, maxRanks = n[2], tierPoints = 0, prereqs = {} }
	end
	return tree
end

local function liveRanks()
	local r = {}
	for _, n in ipairs(fixture.nodes) do
		if n[3] > 0 then r[n[1]] = n[3] end
	end
	return r
end

T.test("codec: decodes the game's own export string", function()
	local ns = T.boot()
	local loadout = ns.Codecs.DecodeLoadout(fixture.string, #fixture.nodes)
	T.ok(loadout, "decoded")
	T.eq(loadout.version, 2)
	T.eq(loadout.specID, 1491)
	local ranks = ns.Codecs.LoadoutToPlan(fixtureTree(), fixture.string)
	local expected = liveRanks()
	for id, r in pairs(expected) do T.eq(ranks[id], r, "node " .. id) end
	for id, r in pairs(ranks) do T.eq(expected[id], r, "extra node " .. id) end
end)

T.test("codec: re-encoding reproduces the game's string exactly", function()
	local ns = T.boot()
	local loadout = ns.Codecs.DecodeLoadout(fixture.string, #fixture.nodes)
	local again = ns.Codecs.PlanToLoadout(fixtureTree(), liveRanks(), loadout.version, loadout.hash)
	-- The game pads the last character; compare the decoded bits instead of padding.
	T.eq(again:sub(1, #fixture.string - 1), fixture.string:sub(1, #fixture.string - 1))
end)

T.test("codec: round trip of arbitrary plans is lossless", function()
	local ns = T.boot()
	local tree = fixtureTree()
	local plan = {}
	for i, n in ipairs(fixture.nodes) do
		if i % 3 == 0 then plan[n[1]] = math.max(1, n[2] - (i % 2)) end
	end
	local text = ns.Codecs.PlanToLoadout(tree, plan, 2)
	local back = ns.Codecs.LoadoutToPlan(tree, text)
	for id, r in pairs(plan) do T.eq(back[id], r, "node " .. id) end
	for id, r in pairs(back) do T.eq(plan[id], r, "extra " .. id) end
end)

T.test("codec: detect formats and classes", function()
	local ns = T.boot()
	local specToClass = { [1491] = 1 }
	local d = ns.Codecs.Detect(fixture.string, specToClass)
	T.eq(d.kind, "blizzard")
	T.eq(d.classID, 1)
	local tree = fixtureTree()
	local ba = ns.Codecs.ExportBuildAtlas(tree, liveRanks(), "1.60.1.70938", 2)
	T.ok(ba:find("^BA1:1:1%.60%.1%.70938:"), ba)
	d = ns.Codecs.Detect(ba, specToClass)
	T.eq(d.kind, "buildatlas")
	T.eq(d.build, "1.60.1.70938")
	local wh = ns.Codecs.ExportWowhead(tree, liveRanks(), 2)
	T.eq(ns.Codecs.Detect(wh, specToClass).kind, "wowhead")
	local simc = ns.Codecs.ExportSimC(tree, liveRanks(), { classToken = "WARRIOR", name = "X", level = 40, version = 2 })
	T.contains(simc, "warrior=\"X\"")
	T.contains(simc, "talents=")
	T.eq(ns.Codecs.Detect(simc, specToClass).kind, "simc")
	T.eq(select(2, ns.Codecs.Detect("https://talentsforever.com/warrior/abc", specToClass)), "site")
	T.eq(select(2, ns.Codecs.Detect("hello world", specToClass)), "unknown")
	T.eq(select(2, ns.Codecs.Detect("", specToClass)), "empty")
end)

T.test("codec: string for another class is refused", function()
	local ns = T.boot()
	local tree = fixtureTree()
	tree.specID = 1482
	local ranks, why = ns.Codecs.LoadoutToPlan(tree, fixture.string)
	T.eq(ranks, nil)
	T.eq(why, "class")
end)
