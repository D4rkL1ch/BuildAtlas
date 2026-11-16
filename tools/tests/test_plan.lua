local T = ...

-- A small 2-group tree: group 1 has a talent per tier, group 2 one talent.
local function makeTree()
	local function t(id, group, row, max, prereqs, extra)
		local node = { id = id, group = group, row = row, col = 0, maxRanks = max, tierPoints = row * 5, prereqs = prereqs or {} }
		for k, v in pairs(extra or {}) do node[k] = v end
		return node
	end
	return {
		maxPoints = 51,
		groups = { { name = "A" }, { name = "B" } },
		talents = {
			[1] = t(1, 1, 0, 5),
			[2] = t(2, 1, 0, 5),
			[3] = t(3, 1, 1, 5),
			[4] = t(4, 1, 2, 3, { 3 }),
			[5] = t(5, 1, 3, 1, nil, { free = true }),
			[6] = t(6, 2, 0, 5),
		},
	}
end

T.test("plan: spending counts per group and skips free nodes", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	local total, per = P.Spent(tree, { [1] = 5, [3] = 2, [5] = 1, [6] = 4 })
	T.eq(total, 11, "total")
	T.eq(per[1], 7, "group 1")
	T.eq(per[2], 4, "group 2")
end)

T.test("plan: tier gate needs 5 points per row in the same group", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	local ranks = { [1] = 4, [6] = 5 }
	local ok, why, need = P.CanIncrease(tree, ranks, 3)
	T.eq(ok, false, "tier 2 closed at 4 points")
	T.eq(why, "tier")
	T.eq(need, 5)
	ranks[1] = 5
	T.eq(P.CanIncrease(tree, ranks, 3), true, "tier 2 open at 5")
end)

T.test("plan: prerequisite must be maxed", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	local ranks = { [1] = 5, [2] = 5, [3] = 4 }
	local ok, why, detail = P.CanIncrease(tree, ranks, 4)
	T.eq(ok, false)
	T.eq(why, "prereq")
	T.eq(detail, 3)
	ranks[3] = 5
	T.eq(P.CanIncrease(tree, ranks, 4), true)
end)

T.test("plan: 51-point cap and max ranks", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	tree.maxPoints = 6
	local ranks = { [1] = 5, [6] = 1 }
	local ok, why = P.CanIncrease(tree, ranks, 6)
	T.eq(ok, false)
	T.eq(why, "points")
	T.eq(select(2, P.CanIncrease(tree, ranks, 1)), "maxed")
end)

T.test("plan: removing a rank can't strand a deeper talent", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	local ranks = { [1] = 5, [3] = 1 }
	local ok, why, other = P.CanDecrease(tree, ranks, 1)
	T.eq(ok, false, "row 2 needs all 5 points above")
	T.eq(why, "tier")
	T.eq(other, 3)
	ranks[2] = 1
	T.eq(P.CanDecrease(tree, ranks, 1), true, "another row-1 point covers it")
end)

T.test("plan: removing a prerequisite blocked while dependent is learned", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	local ranks = { [1] = 5, [2] = 5, [3] = 5, [4] = 1 }
	local ok, why, other = P.CanDecrease(tree, ranks, 3)
	T.eq(ok, false)
	T.eq(why, "prereq")
	T.eq(other, 4)
end)

T.test("plan: increase/decrease mutate and clean up zero ranks", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	local ranks = {}
	T.eq(P.Increase(tree, ranks, 1), true)
	T.eq(ranks[1], 1)
	T.eq(P.Decrease(tree, ranks, 1), true)
	T.eq(ranks[1], nil)
	T.eq(P.Decrease(tree, ranks, 1), false)
	T.eq(P.Increase(tree, ranks, 5), false, "free node can't be bought")
end)

T.test("plan: free nodes are granted once their tier is reached", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	T.eq(P.IsGranted(tree, { [1] = 5, [2] = 5, [3] = 4 }, 5), false, "14 points")
	T.eq(P.IsGranted(tree, { [1] = 5, [2] = 5, [3] = 5 }, 5), true, "15 points")
	T.eq(P.IsLocked(tree, {}, 3), true)
	T.eq(P.IsLocked(tree, {}, 1), false)
end)

T.test("plan: diff, clean and validate", function()
	local P = T.loadModel().Plan
	local tree = makeTree()
	T.eq(P.Diff(tree, { [1] = 5, [6] = 2 }, { [1] = 3, [2] = 1 }), 5)
	local cleaned = P.Clean(tree, { [1] = 9, [99] = 2, [5] = 1, [6] = 0 })
	T.eq(cleaned[1], 5, "clamped")
	T.eq(cleaned[99], nil, "unknown node dropped")
	T.eq(cleaned[5], nil, "free node dropped")
	T.eq(cleaned[6], nil, "zero dropped")
	T.eq(P.Validate(tree, { [1] = 5, [3] = 5, [4] = 3 }), true)
	local ok, id, why = P.Validate(tree, { [1] = 4, [3] = 1 })
	T.eq(ok, false)
	T.eq(id, 3)
	T.eq(why, "tier")
end)

T.test("plan: ordered by group, row, col", function()
	local P = T.loadModel().Plan
	local list = P.Ordered(makeTree())
	T.eq(list[1].id, 1)
	T.eq(list[#list].id, 6)
end)
