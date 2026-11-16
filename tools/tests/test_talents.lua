local T = ...

T.test("talents: layout derived from canvas positions", function()
	local ns = T.boot()
	local nodes = {
		{ id = 1, group = 1, posX = 1000, posY = 1200 },
		{ id = 2, group = 1, posX = 1600, posY = 1800 },
		{ id = 3, group = 1, posX = 2800, posY = 4800 },
		{ id = 4, group = 2, posX = 5200, posY = 1200 },
		{ id = 5, group = 2, posX = 4600, posY = 2400 },
	}
	local rows, cols = ns.Talents.DeriveLayout(nodes)
	T.eq(nodes[2].row, 1)
	T.eq(nodes[2].col, 1)
	T.eq(nodes[3].row, 6)
	T.eq(nodes[3].col, 3)
	T.eq(nodes[4].col, 1, "group 2 counts from its own left edge")
	T.eq(nodes[5].col, 0)
	T.eq(rows, 7)
	T.eq(cols, 4)
end)

T.test("talents: reads the player's tree from C_Traits", function()
	local ns = T.boot()
	local tree = ns.Talents.ReadTree(1)
	T.ok(tree, "tree")
	T.eq(tree.treeID, 1117)
	T.eq(#tree.groups, 3)
	T.eq(tree.groups[1].name, "Arms", "groups sorted by order")
	local ms = tree.talents[105]
	T.eq(ms.name, "Spell5005")
	T.eq(ms.row, 6)
	T.eq(ms.col, 1)
	T.eq(ms.tierPoints, 30, "gate from condition")
	T.eq(tree.talents[103].tierPoints, 5, "fallback row * 5")
	T.eq(tree.talents[104].prereqs[1], 103, "edge becomes prerequisite")
	T.eq(tree.talents[302].free, true, "granted node")
	T.eq(tree.talents[302].tierPoints, 10)
	T.eq(tree.readRanks[101], 3)
	T.eq(tree.isPlayerClass, true)
	T.eq(ns.Talents.ReadTree(1), tree, "cached")
end)

T.test("talents: spec configs give each spec's ranks", function()
	local ns = T.boot()
	local tree = ns.Talents.ReadTree(1)
	local r2 = ns.Talents.ReadRanks(tree, ns.Talents.GetSpecConfigID(2))
	T.eq(r2[301], 5)
	T.eq(r2[101], nil)
end)

T.test("talents: another class goes through the view loadout", function()
	local ns = T.boot()
	T.stubs.otherTreeBySpec[1482] = 1200
	T.stubs.otherTrees[1200] = true
	local tree = ns.Talents.ReadTree(8)
	T.ok(tree, "mage tree")
	T.eq(T.stubs.viewLoadout[1], 1482)
	T.eq(tree.isPlayerClass, false)
end)

T.test("talents: other classes refused in combat, missing tree reported", function()
	local ns = T.boot()
	T.stubs.otherTreeBySpec[1482] = 1200
	T.stubs.otherTrees[1200] = true
	T.stubs.combat = true
	local tree, why = ns.Talents.ReadTree(8)
	T.eq(tree, nil)
	T.eq(why, "combat")
	T.stubs.combat = false
	tree, why = ns.Talents.ReadTree(9)
	T.eq(tree, nil)
	T.eq(why, "notree")
end)

T.test("talents: no active config yet", function()
	local ns = T.boot()
	T.stubs.activeConfig = nil
	local tree, why = ns.Talents.ReadTree(1)
	T.eq(tree, nil)
	T.eq(why, "noconfig")
end)
