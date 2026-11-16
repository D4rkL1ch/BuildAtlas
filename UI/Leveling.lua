local addonName, ns = ...

-- Leveling path (design/Leveling.dc.html): one tile per talent point from
-- level 10 to 60 for a chosen plan or preset; the optional level-up reminder
-- says which talent comes next. Build Atlas never learns talents by itself
-- on level-up.

local UI, L = ns.UI, ns.L
local Presets, Talents = ns.Presets, ns.Talents

local Leveling = {}
ns.Leveling = Leveling

local TILE, GAP, PER_ROW = 58, 6, 10
local pane
local state = { selected = nil }

-- Sources: plan slots and presets of the player's class.
function Leveling.Sources()
	local classID = Talents.PlayerClassID()
	local tree = Talents.ReadTree(classID)
	if not tree then return {}, nil end
	local list = {}
	local plans = ns.charDB.plans[classID] or {}
	for _, slot in ipairs({ "scratch", "spec1", "spec2" }) do
		local p = plans[slot]
		if p and next(p.ranks) then
			local label = slot == "scratch" and L["Scratch plan"] or (L["Spec %d plan"]):format(slot == "spec1" and 1 or 2)
			list[#list + 1] = { key = slot, label = label, steps = function() return Presets.PathFromPlan(tree, p.ranks) end }
		end
	end
	for i, preset in ipairs(Presets.ForClass(classID)) do
		if preset.valid then
			list[#list + 1] = { key = "preset" .. i, label = L["Preset · "] .. preset.name, steps = function() return Presets.PathFromOrder(tree, preset.order) end }
		end
	end
	return list, tree
end

function Leveling.Steps()
	local list, tree = Leveling.Sources()
	local key = ns.charDB.levelingSource
	local chosen
	for _, s in ipairs(list) do
		if s.key == key then chosen = s end
	end
	chosen = chosen or list[1]
	if not chosen then return nil, tree end
	ns.charDB.levelingSource = chosen.key
	return chosen.steps(), tree, chosen
end

local function learnedPoints(tree)
	local live = Talents.ReadRanks(tree, Talents.GetSpecConfigID(Talents.GetActiveSpecGroup())) or {}
	local n = 0
	for _, r in pairs(live) do n = n + r end
	return n
end

function Leveling.Render()
	pane.tiles:ReleaseAll()
	local steps, tree, chosen = Leveling.Steps()
	pane.dd:Refresh()
	pane.remind:SetChecked(ns.db.settings.levelReminder ~= false)
	local level = UnitLevel("player")
	if not steps or not tree or not chosen then
		pane.title:SetText(L["LEVELING PATH"])
		pane.detailName:SetText(L["Make a plan in the planner or pick a preset first."])
		return
	end
	pane.title:SetText((L["LEVELING PATH · %s · you are level %d"]):format(chosen.label, level))
	local learned = learnedPoints(tree)
	if not state.selected then
		state.selected = math.max(1, math.min(#steps, level - Presets.FIRST_TALENT_LEVEL + 1))
	end
	for i, step in ipairs(steps) do
		local t = tree.talents[step.id]
		local b = pane.tiles:Acquire()
		local row, col = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
		b:SetPoint("TOPLEFT", pane.grid, "TOPLEFT", col * (TILE + GAP), -row * (TILE + GAP))
		b.Level:SetText(tostring(step.level))
		b.Icon:SetTexture(t and t.icon or 134400)
		local done = i <= learned
		local current = step.level == level
		local milestone = t and t.row >= 6
		local border = done and "greenNode" or (milestone and "gold" or "borderHi")
		UI.SetBackdrop(b, current and "goldBg" or "1B1E26", i == state.selected and "white" or border, 2)
		b.Icon:SetDesaturated(not done)
		b:SetScript("OnClick", function() state.selected = i Leveling.Render() end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText((L["Level %d"]):format(step.level), 1, 1, 1)
			GameTooltip:AddLine(("%s %d/%d"):format(t and t.name or "?", step.rank, t and t.maxRanks or 0), 0.88, 0.71, 0.29)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	local step = steps[state.selected]
	local t = step and tree.talents[step.id]
	if step and t then
		pane.detailLevel:SetText((L["LEVEL %d"]):format(step.level))
		pane.detailName:SetText(("%s %d/%d"):format(t.name, step.rank, t.maxRanks))
		local data = Talents.Data(t)
		local why = data and data.note or Talents.Describe(t, step.rank) or ""
		pane.detailWhy:SetText(why)
		local split = Presets.SplitAt(tree, steps, state.selected)
		pane.detailSplit:SetText((L["Points by then: %s"]):format(table.concat(split, " / ")))
	end

	-- Dual spec card
	local groups = Talents.GetNumSpecGroups()
	if groups >= 2 then
		pane.dual:SetText(L["Dual spec is active: plan Spec 2 in the planner's Spec 2 slot."])
	else
		local gold = math.floor((GetMoney and GetMoney() or 0) / 10000)
		pane.dual:SetText((L["Dual spec unlocks at level 40 for 50g (you have %dg). Two specs mean no trainer reset trips: resets cost 1g the first time and more each time after."]):format(gold))
	end
end

local function build(host)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f

	pane.title = UI.Label(f, "Leveling path")
	pane.title:SetPoint("TOPLEFT", 24, -20)
	local srcLabel = UI.Text(f, 12, "muted")
	srcLabel:SetText(L["Plan"])
	srcLabel:SetPoint("TOPLEFT", 24, -52)
	pane.dd = UI.Dropdown(f, 320, function() return (Leveling.Sources()) end, function() return ns.charDB.levelingSource end, function(k)
		ns.charDB.levelingSource = k
		state.selected = nil
		Leveling.Render()
	end)
	pane.dd:SetPoint("TOPLEFT", 70, -46)
	pane.remind = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	pane.remind:SetPoint("TOPLEFT", 420, -42)
	pane.remind:SetScript("OnClick", function(self)
		ns.db.settings.levelReminder = self:GetChecked() and true or false
	end)
	local remindLabel = UI.Text(f, 12, "text")
	remindLabel:SetPoint("LEFT", pane.remind, "RIGHT", 4, 0)
	remindLabel:SetText(L["Remind me on level-up"])

	pane.grid = CreateFrame("Frame", nil, f)
	pane.grid:SetPoint("TOPLEFT", 24, -92)
	pane.grid:SetSize(PER_ROW * (TILE + GAP), 6 * (TILE + GAP))
	pane.tiles = UI.Pool(pane.grid, function(p)
		local b = CreateFrame("Button", nil, p, "BackdropTemplate")
		b:SetSize(TILE, TILE)
		b.Icon = b:CreateTexture(nil, "ARTWORK")
		b.Icon:SetSize(30, 30)
		b.Icon:SetPoint("TOP", 0, -6)
		b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.Level = UI.Text(b, 11, "text", "body", "CENTER")
		b.Level:SetPoint("BOTTOM", 0, 4)
		return b
	end)
	local legend = UI.Text(f, 11, "faint")
	legend:SetPoint("TOPLEFT", pane.grid, "BOTTOMLEFT", 0, -8)
	legend:SetText(L["Green border: learned · gold fill: your level · gold border: top-of-tree talent · white: selected"])

	local d = UI.Panel(f, "panelDark", "border")
	d:SetPoint("TOPLEFT", 700, -92)
	d:SetSize(370, 520)
	pane.detailLevel = UI.Text(d, 11, "muted", "heading")
	pane.detailLevel:SetPoint("TOPLEFT", 16, -16)
	pane.detailName = UI.Text(d, 18, "white", "title")
	pane.detailName:SetPoint("TOPLEFT", 16, -34)
	pane.detailName:SetWidth(338)
	pane.detailName:SetWordWrap(true)
	pane.detailWhy = UI.Text(d, 12, "tealText")
	pane.detailWhy:SetPoint("TOPLEFT", 16, -70)
	pane.detailWhy:SetWidth(338)
	pane.detailWhy:SetWordWrap(true)
	pane.detailSplit = UI.Text(d, 12, "gold")
	pane.detailSplit:SetPoint("TOPLEFT", 16, -200)
	local dualLabel = UI.Label(d, "Dual spec")
	dualLabel:SetPoint("TOPLEFT", 16, -250)
	pane.dual = UI.Text(d, 12, "muted")
	pane.dual:SetPoint("TOPLEFT", 16, -272)
	pane.dual:SetWidth(338)
	pane.dual:SetWordWrap(true)
	local plan2 = UI.Button(d, L["Plan Spec 2"], "default")
	plan2:SetPoint("BOTTOMLEFT", 16, 16)
	plan2:SetScript("OnClick", function()
		ns.Window.Show("planner")
		ns.Planner.SetSlot("spec2")
	end)
	local pick = UI.Button(d, L["Pick a preset"], "default")
	pick:SetPoint("LEFT", plan2, "RIGHT", 10, 0)
	pick:SetScript("OnClick", function() ns.Window.Show("presets") end)

	pane.Refresh = Leveling.Render
	return pane
end

ns.Window.RegisterPane("leveling", build)

-- Level-up reminder: says the next talent; never learns it.
ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
	if ns.db.settings.levelReminder == false or ns.Secrets.IsSecret(level) or type(level) ~= "number" then return end
	if level < Presets.FIRST_TALENT_LEVEL then return end
	ns.Util.After(2, function()
		if InCombatLockdown() then return end
		local steps, tree = Leveling.Steps()
		local step = steps and steps[level - Presets.FIRST_TALENT_LEVEL + 1]
		local t = step and tree and tree.talents[step.id]
		if step and t then
			ns.Toasts.Show("info", (L["Level %d: next talent"]):format(level), ("%s %d/%d"):format(t.name, step.rank, t.maxRanks), {
				text = L["Open leveling path"], run = function() ns.Window.Show("leveling") end,
			})
		end
	end)
end)
