local addonName, ns = ...

-- Talent planner + inspector (design/Main.dc.html). Layout and ranks come
-- from the live tree; synergy rows come from the bundled class data once the
-- data pipeline (M1) ships it. Planning never touches the real talents:
-- applying a plan is a separate, explicit step (M3).

local UI, L = ns.UI, ns.L
local Plan, Talents, SynergyGraph = ns.Plan, ns.Talents, ns.SynergyGraph
local Read = ns.Secrets.Read

local Planner = {}
ns.Planner = Planner

-- Geometry (content area is 1104x744 below the title bar, right of the rail).
local CONTENT_W, CONTENT_H = 1104, 744
local INSPECT_W, FOOTER_H, STRIP_H = 320, 60, 30
local PAD_X, PAD_TOP, TREE_GAP = 18, 16, 14
local TREES_W = CONTENT_W - INSPECT_W - PAD_X * 2
local TREES_H = CONTENT_H - FOOTER_H - PAD_TOP - 12 - STRIP_H - 12
local INNER_W = INSPECT_W - 32

local SLOT_KEYS = { "scratch", "spec1", "spec2" }

local state = {
	classID = nil,
	slot = "scratch",
	selected = nil,   -- nodeID
	spell = nil,      -- spell view when set
}

local pane, tree, graph, ranks, specRanks, readError

-- Helpers ---------------------------------------------------------------------

local function className(classID)
	local name = GetClassInfo and Read(nil, GetClassInfo, classID)
	if not name then
		local c = ns.ClassByID[classID]
		name = c and c.token or tostring(classID)
	end
	return name
end

local function spellName(spell)
	local classData = ns.ClassData and ns.ClassData[state.classID]
	local info = classData and classData.spells and classData.spells[spell]
	if info and info.name then return info.name end
	if type(spell) == "number" then
		return Read(nil, C_Spell.GetSpellName, spell) or ("Spell " .. spell)
	end
	return tostring(spell)
end
Planner.SpellName = spellName

local function rankOf(id)
	return ranks and ranks[id] or 0
end

local function groupName(index)
	local g = tree and tree.groups[index]
	return g and g.name or "?"
end

-- Name of the tree with most points, e.g. "Arms", for slot labels.
local function leaningTree(r)
	if not r then return nil end
	local total, perGroup = Plan.Spent(tree, r)
	if total == 0 then return L["empty"] end
	local best = 1
	for i = 2, #perGroup do
		if perGroup[i] > perGroup[best] then best = i end
	end
	return groupName(best)
end

local function planStore(classID)
	local plans = ns.charDB.plans
	plans[classID] = plans[classID] or {}
	return plans[classID]
end

local function specGroupOfSlot(slot)
	if slot == "spec1" then return 1 elseif slot == "spec2" then return 2 end
end

-- The plan for the current class and slot, created from the live spec the
-- first time (or after a tree change).
local function loadPlan()
	local store = planStore(state.classID)
	local p = store[state.slot]
	if not p or p.treeID ~= tree.treeID then
		local group = specGroupOfSlot(state.slot)
		local start = group and specRanks[group] or (tree.isPlayerClass and specRanks[Talents.GetActiveSpecGroup()]) or {}
		p = { treeID = tree.treeID, ranks = Plan.Clean(tree, start) }
		store[state.slot] = p
	else
		p.ranks = Plan.Clean(tree, p.ranks)
	end
	return p.ranks
end

local function canEdit()
	if InCombatLockdown() then
		ns:Print(L["Plans are read-only in combat."])
		return false
	end
	return true
end

-- Requirement lines for tooltips and the inspector.
local function requirementText(id)
	local ok, why, detail = Plan.CanIncrease(tree, ranks, id)
	if ok then return nil end
	if why == "tier" then
		return (L["Needs %d points in %s"]):format(detail, groupName(tree.talents[id].group))
	elseif why == "prereq" then
		local p = tree.talents[detail]
		return (L["Needs %s at %d/%d"]):format(p.name, p.maxRanks, p.maxRanks)
	elseif why == "points" then
		return L["No points left"]
	elseif why == "maxed" then
		return L["Maxed"]
	elseif why == "free" then
		return (L["Granted at %d points in %s"]):format(tree.talents[id].tierPoints, groupName(tree.talents[id].group))
	end
end

local function removalBlockText(id)
	local ok, why, other = Plan.CanDecrease(tree, ranks, id)
	if ok or why == "empty" or why == "free" then return nil end
	local o = tree.talents[other]
	if why == "prereq" then
		return (L["%s depends on it"]):format(o.name)
	end
	return (L["%s would lose its tier requirement"]):format(o.name)
end

-- Actions --------------------------------------------------------------------

function Planner.Select(id)
	state.selected, state.spell = id, nil
	Planner.Render()
end

function Planner.FocusSpell(spell)
	state.spell = spell
	Planner.Render()
end

function Planner.Change(id, delta)
	if not tree or not canEdit() then return end
	local changed
	if delta > 0 then
		changed = Plan.Increase(tree, ranks, id)
	else
		changed = Plan.Decrease(tree, ranks, id)
	end
	state.selected = id
	if not changed then
		local msg = delta > 0 and requirementText(id) or removalBlockText(id)
		if msg and UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.6, 0.4) end
	end
	Planner.Render()
end

function Planner.SetClass(classID)
	state.classID = classID
	state.selected, state.spell = nil, nil
	if classID ~= Talents.PlayerClassID() then state.slot = "scratch" end
	Planner.Refresh()
end

function Planner.SetSlot(slot)
	state.slot = slot
	state.spell = nil
	Planner.Refresh()
end

function Planner.ResetPlan()
	if not tree or not canEdit() then return end
	wipe(ranks)
	Planner.Render()
end

-- Replace the plan with the slot's spec (or the active spec for scratch).
function Planner.LoadFromSpec()
	if not tree or not canEdit() or not tree.isPlayerClass then return end
	local group = specGroupOfSlot(state.slot) or Talents.GetActiveSpecGroup()
	local source = specRanks[group]
	if not source then return end
	wipe(ranks)
	for id, r in pairs(Plan.Clean(tree, source)) do ranks[id] = r end
	Planner.Render()
end

-- Node buttons -------------------------------------------------------------

local function nodeTooltip(self)
	local t = tree and tree.talents[self.nodeID]
	if not t then return end
	local r = rankOf(t.id)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(t.name, 1, 1, 1)
	GameTooltip:AddLine(t.free and L["Granted automatically"] or ((L["Rank %d/%d"]):format(r, t.maxRanks)), 0.88, 0.71, 0.29)
	local desc = Talents.Describe(t, r)
	if desc then GameTooltip:AddLine(desc, 0.9, 0.9, 0.9, true) end
	if r > 0 and r < t.maxRanks then
		local nextDesc = Talents.Describe(t, r + 1)
		if nextDesc then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L["Next rank:"], 0.56, 0.83, 0.63)
			GameTooltip:AddLine(nextDesc, 0.56, 0.83, 0.63, true)
		end
	end
	local req = r < t.maxRanks and requirementText(t.id)
	if req and req ~= L["Maxed"] then GameTooltip:AddLine(req, 0.94, 0.63, 0.44, true) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Click: inspect · Shift-click: add rank · Right-click: remove rank"], 0.55, 0.57, 0.63, true)
	GameTooltip:Show()
end

local function createNode(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetPoint("TOPLEFT", 2, -2)
	b.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.Ring = CreateFrame("Frame", nil, b, "BackdropTemplate")
	b.Ring:SetPoint("TOPLEFT", -4, 4)
	b.Ring:SetPoint("BOTTOMRIGHT", 4, -4)
	b.Badge = UI.Panel(b, "0E1014", "borderHi")
	b.Badge:SetSize(34, 17)
	b.Badge:SetPoint("BOTTOMRIGHT", 12, -9)
	b.Badge:SetFrameLevel(b:GetFrameLevel() + 3)
	b.Badge.Text = UI.Text(b.Badge, 10, "text", "body", "CENTER")
	b.Badge.Text:SetPoint("CENTER", 0, 0)
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			Planner.Change(self.nodeID, -1)
		elseif IsShiftKeyDown() then
			Planner.Change(self.nodeID, 1)
		else
			Planner.Select(self.nodeID)
		end
	end)
	b:SetScript("OnEnter", nodeTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function styleNode(b, t, perGroup, related)
	local r = rankOf(t.id)
	local locked = Plan.IsLocked(tree, ranks, t.id, perGroup)
	local granted = Plan.IsGranted(tree, ranks, t.id, perGroup)
	b.Icon:SetTexture(t.icon or 134400)
	local bg, border = "1B1E26", "borderHi"
	if granted or (r > 0 and r >= t.maxRanks) then
		bg, border = "goldBg", "gold"
	elseif r > 0 then
		bg, border = "greenBg", "greenNode"
	end
	UI.SetBackdrop(b, bg, border, 2)
	b.Icon:SetDesaturated(r == 0 and not granted)
	b.Icon:SetAlpha((r == 0 and not granted) and 0.65 or 1)
	b:SetAlpha(locked and 0.4 or 1)
	b.Badge.Text:SetText(t.free and L["auto"] or (r .. "/" .. t.maxRanks))
	if state.spell == nil and t.id == state.selected then
		UI.SetBackdrop(b.Ring, nil, "white", 2)
		b.Ring:Show()
	elseif related[t.id] then
		UI.SetBackdrop(b.Ring, nil, "teal", 2)
		b.Ring:Show()
	else
		b.Ring:Hide()
	end
end

-- Tree panels ------------------------------------------------------------------

local function createTreePanel(parent)
	local p = UI.Panel(parent, "panel", "border")
	p.Name = UI.Text(p, 15, "goldLight", "heading")
	p.Name:SetPoint("TOPLEFT", 14, -12)
	p.Points = UI.Text(p, 13, "gold", "body", "RIGHT")
	p.Points:SetPoint("TOPRIGHT", -14, -13)
	p.nodes = UI.Pool(p, createNode)
	p.lines = {}
	return p
end

local function renderTrees(perGroup, related)
	local n = #tree.groups
	local width = (TREES_W - TREE_GAP * (n - 1)) / n
	pane.treePanels:ReleaseAll()
	for gi = 1, n do
		local p = pane.treePanels:Acquire()
		p:SetSize(width, TREES_H)
		p:SetPoint("TOPLEFT", pane.trees, "TOPLEFT", (gi - 1) * (width + TREE_GAP), 0)
		p.Name:SetText(groupName(gi))
		p.Points:SetText((perGroup[gi] or 0) .. " " .. L["pts"])
		p.nodes:ReleaseAll()
		for _, line in ipairs(p.lines) do line:Hide() end

		local cols, rows = tree.cols, math.max(tree.rows, 1)
		local pitchX = math.min(60, (width - 24) / cols)
		local pitchY = math.min(62, (TREES_H - 52) / rows)
		local size = math.floor(math.min(42, pitchX - 14, pitchY - 14))
		local x0 = (width - (cols - 1) * pitchX - size) / 2
		local byID = {}
		for _, t in ipairs(pane.ordered) do
			if t.group == gi then
				local b = p.nodes:Acquire()
				b.nodeID = t.id
				b:SetSize(size, size)
				b:SetPoint("TOPLEFT", p, "TOPLEFT", x0 + t.col * pitchX, -(44 + t.row * pitchY))
				styleNode(b, t, perGroup, related)
				byID[t.id] = b
			end
		end
		-- Prerequisite arrows, drawn under the nodes.
		local li = 0
		for _, t in ipairs(pane.ordered) do
			if t.group == gi then
				for _, pid in ipairs(t.prereqs) do
					local from, to = byID[pid], byID[t.id]
					if from and to then
						li = li + 1
						local line = p.lines[li]
						if not line then
							line = p:CreateLine(nil, "ARTWORK")
							line:SetThickness(2)
							p.lines[li] = line
						end
						line:SetStartPoint("CENTER", from)
						line:SetEndPoint("CENTER", to)
						local met = rankOf(pid) >= tree.talents[pid].maxRanks
						line:SetColorTexture(UI.RGB(met and UI.colors.gold or UI.colors.borderHi))
						line:Show()
					end
				end
			end
		end
	end
end

-- "Spells this build modifies" strip.
local function renderStrip()
	pane.chips:ReleaseAll()
	if not graph.hasData then
		pane.stripNote:SetText(L["Synergy data for this class isn't bundled yet."])
		pane.stripNote:Show()
		return
	end
	pane.stripNote:Hide()
	local x = pane.stripLabel:GetStringWidth() + 12
	for _, s in ipairs(graph:BuildSpells(ranks)) do
		local chip = pane.chips:Acquire()
		chip:SetLabel(spellName(s.spell) .. "  " .. UI.Colorize("×" .. s.count, "teal"))
		chip:FitWidth(20)
		if x + chip:GetWidth() > TREES_W then
			chip:Hide()
			break
		end
		chip:SetPoint("LEFT", pane.strip, "LEFT", x, 0)
		chip.spell = s.spell
		x = x + chip:GetWidth() + 8
	end
end

-- Inspector ------------------------------------------------------------------

local layoutY

local function place(widget, height, gap)
	widget:SetPoint("TOPLEFT", pane.inspect, "TOPLEFT", 0, -layoutY)
	layoutY = layoutY + height + (gap or 12)
end

local function addText(text, size, color, font, gap)
	local fs = pane.texts:Acquire()
	UI.SetFont(fs, font, size)
	UI.SetTextColor(fs, color or "text")
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:SetWidth(INNER_W)
	fs:SetText(text)
	place(fs, fs:GetStringHeight(), gap)
	return fs
end

local function addLabel(text, color)
	return addText(text:upper(), 11, color or "muted", "heading", 6)
end

-- Text in a bordered box (rank descriptions, notes).
local function addBox(lines, bg, border)
	local box = pane.boxes:Acquire()
	UI.SetBackdrop(box, bg or "panel", border or "border")
	box:SetWidth(INNER_W)
	local h = 10
	box.used = box.used or {}
	for _, fs in ipairs(box.used) do fs:Hide() end
	for i, line in ipairs(lines) do
		local fs = box.used[i]
		if not fs then
			fs = box:CreateFontString(nil, "OVERLAY")
			box.used[i] = fs
		end
		UI.SetFont(fs, "body", 13)
		UI.SetTextColor(fs, line.color or "text")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		fs:SetWidth(INNER_W - 24)
		fs:SetText(line.text)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -h)
		fs:Show()
		h = h + fs:GetStringHeight() + 6
	end
	box:SetHeight(h + 4)
	place(box, h + 4)
	return box
end

local function addRow(left, right, rightColor, onClick)
	local row = pane.rows:Acquire()
	row:SetWidth(INNER_W)
	row:SetHeight(right and right ~= "" and 34 or 30)
	row:SetLabel(left)
	row.Right:SetText(right or "")
	UI.SetTextColor(row.Right, rightColor or "muted")
	row:SetScript("OnClick", onClick)
	row:ApplyLook()
	place(row, row:GetHeight(), 6)
	return row
end

local function renderSpellView()
	addLabel(L["Spell view"], "teal")
	addText(spellName(state.spell), 20, "white", "title")
	local list = graph:TalentsTouching(state.spell)
	addText((L["%d talents across all trees change this spell. Teal rings mark them."]):format(#list), 13, "muted")
	for _, id in ipairs(list) do
		local t = tree.talents[id]
		addRow(t.name .. "  " .. UI.Colorize(graph:EffectOn(id, state.spell) or "", "muted"),
			rankOf(id) .. "/" .. t.maxRanks, "gold", function() Planner.Select(id) end)
	end
	layoutY = layoutY + 6
	local back = pane.rows:Acquire()
	back:SetWidth(INNER_W)
	back:SetHeight(32)
	back:SetLabel(L["Back to talent"])
	back.Right:SetText("")
	back:SetScript("OnClick", function() Planner.FocusSpell(nil) end)
	place(back, 32)
end

local function renderTalentView()
	local t = tree.talents[state.selected]
	if not t then return end
	local r = rankOf(t.id)
	local tier = math.floor(t.tierPoints / ns.POINTS_PER_TIER) + 1
	addLabel(groupName(t.group) .. " · " .. L["tier"] .. " " .. tier, "muted")
	addText(t.name, 20, "white", "title", 14)

	-- − rank +, then the hint on its own wrapped line
	local rankRow = pane.rankRow
	rankRow:Show()
	place(rankRow, 30, 8)
	rankRow.Rank:SetText(t.free and L["auto"] or (r .. "/" .. t.maxRanks))
	local canAdd = Plan.CanIncrease(tree, ranks, t.id)
	local canRemove = Plan.CanDecrease(tree, ranks, t.id)
	local inCombat = InCombatLockdown()
	rankRow.Plus:SetEnabledState(canAdd and not inCombat)
	rankRow.Minus:SetEnabledState(canRemove and not inCombat)
	local hint = (r >= t.maxRanks and not t.free) and L["Maxed"] or requirementText(t.id) or ""
	if r > 0 and not canRemove then hint = removalBlockText(t.id) or hint end
	if hint ~= "" then
		addText(hint, 12, (r > 0 and not canRemove) and "orange" or "muted", "body", 12)
	else
		layoutY = layoutY + 6
	end

	local lines = {}
	local desc = Talents.Describe(t, r)
	if r == 0 and not t.free then
		lines[#lines + 1] = { text = L["Not learned."] .. " " .. (desc or ""), color = "text" }
	else
		lines[#lines + 1] = { text = desc or L["No description."], color = "text" }
	end
	if r > 0 and r < t.maxRanks then
		local nextDesc = Talents.Describe(t, r + 1)
		if nextDesc then lines[#lines + 1] = { text = L["Next rank: "] .. nextDesc, color = "green" } end
	end
	addBox(lines)

	if #t.prereqs > 0 then
		local names = {}
		for _, pid in ipairs(t.prereqs) do
			local p = tree.talents[pid]
			names[#names + 1] = ("%s %d/%d"):format(p.name, rankOf(pid), p.maxRanks)
		end
		addText(L["Requires: "] .. table.concat(names, ", "), 12, "muted")
	end

	local data = Talents.Data(t)
	if data and data.classic then
		addText(UI.Colorize(L["Vs Classic: "], "faint") .. data.classic, 12, "muted")
	end

	if not graph.hasData then
		addLabel(L["Modifies"])
		addText(L["Which spells this talent changes, what it scales with and its synergies come from bundled game data, which isn't in this build yet. Layout, ranks and descriptions above are read live from the game."], 12, "faint")
		return
	end

	addLabel(L["Modifies"])
	local mods = graph:Mods(t.id)
	if #mods == 0 then
		addText(L["Passive stat talent — no spell is changed."], 12, "faint")
	end
	for _, m in ipairs(mods) do
		addRow(spellName(m.spell), m.fx, "muted", function() Planner.FocusSpell(m.spell) end)
	end

	local stats = graph:Stats(t.id)
	if #stats > 0 then
		addLabel(L["Scales with"])
		local x = 0
		local rowTop = layoutY
		for _, s in ipairs(stats) do
			local chip = pane.statChips:Acquire()
			chip:SetLabel(s)
			chip:FitWidth(20)
			if x + chip:GetWidth() > INNER_W then
				x = 0
				rowTop = rowTop + 30
			end
			chip:SetPoint("TOPLEFT", pane.inspect, "TOPLEFT", x, -rowTop)
			x = x + chip:GetWidth() + 6
		end
		layoutY = rowTop + 24 + 12
	end

	local note = graph:Note(t.id)
	if note then addBox({ { text = note, color = "tealText" } }, "tealBg", "tealEdge") end

	local related = graph:Related(t.id)
	if #related > 0 then
		addLabel(L["Synergizes with (shared spells)"])
		for _, rel in ipairs(related) do
			local o = tree.talents[rel.id]
			local via = {}
			for i, s in ipairs(rel.via) do via[i] = spellName(s) end
			local owned = rankOf(rel.id) > 0
			addRow(o.name .. "\n" .. UI.Colorize(L["via "] .. table.concat(via, ", "), "muted"),
				owned and L["In build"] or L["Not taken"], owned and "green" or "orange",
				function() Planner.Select(rel.id) end)
		end
	end
end

local function renderInspector()
	pane.texts:ReleaseAll()
	pane.boxes:ReleaseAll()
	pane.rows:ReleaseAll()
	pane.statChips:ReleaseAll()
	pane.rankRow:Hide()
	pane.rankRow:ClearAllPoints()
	layoutY = 0
	if state.spell then renderSpellView() else renderTalentView() end
end

-- Footer and title tools --------------------------------------------------------

local function renderFooter(total, perGroup)
	local parts = {}
	for i = 1, #tree.groups do parts[i] = tostring(perGroup[i] or 0) end
	pane.split:SetText(table.concat(parts, " / "))
	pane.total:SetText((L["%d of %d points spent"]):format(total, tree.maxPoints))
	if tree.isPlayerClass then
		local active = Talents.GetActiveSpecGroup()
		local target = specGroupOfSlot(state.slot) or active
		local diff = specRanks[target] and Plan.Diff(tree, ranks, specRanks[target]) or 0
		if diff == 0 then
			pane.diff:SetText((L["Matches Spec %d"]):format(target))
			UI.SetTextColor(pane.diff, "green")
		else
			pane.diff:SetText((L["Differs from Spec %d by %d points"]):format(target, diff))
			UI.SetTextColor(pane.diff, "orange")
		end
		pane.fromSpec:SetLabel((L["Load Spec %d"]):format(target))
		pane.fromSpec:FitWidth()
		pane.fromSpec:SetEnabledState(not InCombatLockdown())
		pane.fromSpec:Show()
		pane.apply:SetLabel((L["Apply to Spec %d"]):format(target))
		pane.apply:FitWidth()
	else
		pane.diff:SetText("")
		pane.fromSpec:Hide()
		pane.apply:SetLabel(L["Apply"])
		pane.apply:FitWidth()
	end
	pane.reset:SetEnabledState(not InCombatLockdown())
	pane.combatNote:SetShown(InCombatLockdown())
end

local function renderTitleTools()
	pane.classButton:SetLabel(className(state.classID) .. (state.classID == Talents.PlayerClassID() and L[" (you)"] or ""))
	if pane.classButton.FitWidth then pane.classButton:FitWidth(36) end
	local isPlayer = tree and tree.isPlayerClass
	local numGroups = Talents.GetNumSpecGroups()
	local active = Talents.GetActiveSpecGroup()
	local x = 0
	for i, key in ipairs(SLOT_KEYS) do
		local seg = pane.slots[i]
		local label
		if key == "scratch" then
			label = L["Scratch plan"]
		else
			local g = i - 1
			label = (L["Spec %d"]):format(g)
			if isPlayer and g <= numGroups then
				label = label .. " · " .. (leaningTree(specRanks[g]) or "?")
				if g == active then label = label .. L[" (active)"] end
			elseif isPlayer then
				label = label .. L[" · locked"]
			end
		end
		seg:SetLabel(label)
		seg:FitWidth(24)
		seg:ClearAllPoints()
		seg:SetPoint("LEFT", pane.slotsAnchor, "LEFT", x, 0)
		x = x + seg:GetWidth() - 1
		local enabled = key == "scratch" or (isPlayer and (i - 1) <= numGroups)
		seg:SetEnabledState(enabled and true or false)
		seg:SetOn(state.slot == key)
	end
end

-- Rendering --------------------------------------------------------------------

function Planner.Render()
	if not pane or not tree then return end
	local total, perGroup = Plan.Spent(tree, ranks)
	local related
	if state.spell then
		related = {}
		for _, id in ipairs(graph:TalentsTouching(state.spell)) do related[id] = true end
	else
		related = state.selected and graph:RelatedSet(state.selected) or {}
	end
	renderTrees(perGroup, related)
	renderStrip()
	renderInspector()
	renderFooter(total, perGroup)
	renderTitleTools()
end

local ERRORS = {
	notree = "Couldn't find the talent tree for this class on this client.",
	noconfig = "Talent data isn't ready yet. It loads a few seconds after login.",
	combat = "Other classes can only be loaded out of combat.",
	noview = "This client can't show other classes' trees yet.",
	empty = "The talent tree came back empty.",
}

function Planner.Refresh()
	if not pane then return end
	state.classID = state.classID or Talents.PlayerClassID()
	local newTree, why = Talents.ReadTree(state.classID)
	if newTree ~= tree then
		tree = newTree
		graph = tree and SynergyGraph.New(tree, ns.ClassData and ns.ClassData[state.classID])
		pane.ordered = tree and Plan.Ordered(tree) or {}
	end
	readError = why
	if not tree then
		pane.body:Hide()
		pane.error:Show()
		pane.error.Text:SetText(L[ERRORS[why] or "Couldn't read the talent tree."])
		renderTitleTools()
		return
	end
	pane.error:Hide()
	pane.body:Show()
	ns.Window.UpdateDataBadge(ns.ClassData and ns.ClassData[state.classID] and ns.ClassData[state.classID].build)

	specRanks = {}
	if tree.isPlayerClass then
		for g = 1, Talents.GetNumSpecGroups() do
			specRanks[g] = Talents.ReadRanks(tree, Talents.GetSpecConfigID(g))
		end
	elseif state.slot ~= "scratch" then
		state.slot = "scratch"
	end
	ranks = loadPlan()
	if not state.selected or not tree.talents[state.selected] then
		state.selected = pane.ordered[1] and pane.ordered[1].id
		for _, t in ipairs(pane.ordered) do
			if (ranks[t.id] or 0) > 0 then state.selected = t.id break end
		end
	end
	Planner.Render()
end

-- Build --------------------------------------------------------------------

local function buildTitleTools(window)
	local tools = CreateFrame("Frame", nil, window.TitleTools)
	tools:SetAllPoints()
	pane.tools = tools

	local classLabel = UI.Text(tools, 12, "muted")
	classLabel:SetText(L["Class"])
	classLabel:SetPoint("LEFT", 0, -4)

	-- Class menu: the modern dropdown when present, else a cycling button.
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, tools, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		dropdown:SetWidth(170)
		dropdown:SetPoint("LEFT", classLabel, "RIGHT", 10, 0)
		dropdown:SetupMenu(function(_, root)
			for _, c in ipairs(ns.Classes) do
				root:CreateRadio(className(c.classID) .. (c.classID == Talents.PlayerClassID() and L[" (you)"] or ""),
					function() return state.classID == c.classID end,
					function() Planner.SetClass(c.classID) end)
			end
		end)
		-- The dropdown shows the checked radio's text itself; just refresh it.
		pane.classButton = { SetLabel = function(_, _) if dropdown.GenerateMenu then dropdown:GenerateMenu() end end }
		pane.classAnchor = dropdown
	else
		local b = UI.Button(tools, "", "default", 170, 28)
		b:SetPoint("LEFT", classLabel, "RIGHT", 10, 0)
		b:SetScript("OnClick", function()
			local idx = 1
			for i, c in ipairs(ns.Classes) do
				if c.classID == state.classID then idx = i end
			end
			Planner.SetClass(ns.Classes[idx % #ns.Classes + 1].classID)
		end)
		pane.classButton = b
		pane.classAnchor = b
	end

	pane.slotsAnchor = CreateFrame("Frame", nil, tools)
	pane.slotsAnchor:SetSize(1, 28)
	pane.slotsAnchor:SetPoint("LEFT", pane.classAnchor, "RIGHT", 14, 0)
	pane.slots = {}
	for i, key in ipairs(SLOT_KEYS) do
		local seg = UI.Button(tools, key, "seg", nil, 28)
		seg:SetScript("OnClick", function() Planner.SetSlot(key) end)
		pane.slots[i] = seg
	end
end

local function buildFooter(f)
	local footer = UI.Panel(f, "bar", nil)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_H)
	local line = footer:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(UI.RGB(UI.colors.border))
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(1)

	pane.split = UI.Text(footer, 15, "text")
	pane.split:SetPoint("LEFT", 16, 0)
	pane.total = UI.Text(footer, 13, "muted")
	pane.total:SetPoint("LEFT", pane.split, "RIGHT", 12, 0)
	pane.diff = UI.Text(footer, 12, "orange")
	pane.diff:SetPoint("LEFT", pane.total, "RIGHT", 12, 0)
	pane.combatNote = UI.Text(footer, 12, "orange")
	pane.combatNote:SetPoint("LEFT", pane.diff, "RIGHT", 12, 0)
	pane.combatNote:SetText(L["Read-only in combat"])

	pane.apply = UI.Button(footer, L["Apply to Spec 1"], "primary")
	pane.apply:SetPoint("RIGHT", -16, 0)
	pane.apply:SetEnabledState(false)
	UI.AttachTooltip(pane.apply, L["Apply"], { L["Learning the planned talents comes in milestone M3. Planning never changes your real talents."] })
	pane.share = UI.Button(footer, L["Share…"], "default")
	pane.share:SetPoint("RIGHT", pane.apply, "LEFT", -10, 0)
	pane.share:SetEnabledState(false)
	UI.AttachTooltip(pane.share, L["Share"], { L["Import and export come in milestone M3."] })
	pane.compare = UI.Button(footer, L["Compare…"], "default")
	pane.compare:SetPoint("RIGHT", pane.share, "LEFT", -10, 0)
	pane.compare:SetEnabledState(false)
	UI.AttachTooltip(pane.compare, L["Compare"], { L["Build comparison comes in milestone M4."] })
	pane.fromSpec = UI.Button(footer, L["Load Spec 1"], "default")
	pane.fromSpec:SetPoint("RIGHT", pane.compare, "LEFT", -10, 0)
	pane.fromSpec:SetScript("OnClick", Planner.LoadFromSpec)
	UI.AttachTooltip(pane.fromSpec, L["Load spec"], { L["Replace this plan with the talents the spec has now."] })
	pane.reset = UI.Button(footer, L["Reset plan"], "default")
	pane.reset:SetPoint("RIGHT", pane.fromSpec, "LEFT", -10, 0)
	pane.reset:SetScript("OnClick", Planner.ResetPlan)
end

local function buildInspector(body)
	local panel = UI.Panel(body, "panelDark", nil)
	panel:SetPoint("TOPRIGHT")
	panel:SetPoint("BOTTOMRIGHT", 0, FOOTER_H)
	panel:SetWidth(INSPECT_W)
	local edge = panel:CreateTexture(nil, "ARTWORK")
	edge:SetColorTexture(UI.RGB(UI.colors.border))
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(1)

	local inspect = CreateFrame("Frame", nil, panel)
	inspect:SetPoint("TOPLEFT", 16, -16)
	inspect:SetPoint("BOTTOMRIGHT", -16, 16)
	pane.inspect = inspect
	pane.texts = UI.Pool(inspect, function(p) return p:CreateFontString(nil, "OVERLAY") end)
	pane.boxes = UI.Pool(inspect, function(p) return UI.Panel(p, "panel", "border") end)
	pane.rows = UI.Pool(inspect, function(p) return UI.Button(p, "", "row", INNER_W, 32) end)
	pane.statChips = UI.Pool(inspect, function(p) return UI.Button(p, "", "stat", nil, 24) end)

	local rankRow = CreateFrame("Frame", nil, inspect)
	rankRow:SetSize(INNER_W, 30)
	rankRow.Minus = UI.Button(rankRow, "−", "mini", 30, 30)
	rankRow.Minus:SetPoint("LEFT")
	rankRow.Minus:SetScript("OnClick", function() Planner.Change(state.selected, -1) end)
	rankRow.Rank = UI.Text(rankRow, 16, "gold", "body", "CENTER")
	rankRow.Rank:SetWidth(60)
	rankRow.Rank:SetPoint("LEFT", rankRow.Minus, "RIGHT", 6, 0)
	rankRow.Plus = UI.Button(rankRow, "+", "mini", 30, 30)
	rankRow.Plus:SetPoint("LEFT", rankRow.Rank, "RIGHT", 6, 0)
	rankRow.Plus:SetScript("OnClick", function() Planner.Change(state.selected, 1) end)
	pane.rankRow = rankRow
end

local function build(host, window)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f

	buildTitleTools(window)
	f:SetScript("OnShow", function() pane.tools:Show() end)
	f:SetScript("OnHide", function() pane.tools:Hide() end)

	local body = CreateFrame("Frame", nil, f)
	body:SetAllPoints()
	pane.body = body

	pane.trees = CreateFrame("Frame", nil, body)
	pane.trees:SetPoint("TOPLEFT", PAD_X, -PAD_TOP)
	pane.trees:SetSize(TREES_W, TREES_H)
	pane.treePanels = UI.Pool(pane.trees, createTreePanel)

	pane.strip = CreateFrame("Frame", nil, body)
	pane.strip:SetSize(TREES_W, STRIP_H)
	pane.strip:SetPoint("TOPLEFT", pane.trees, "BOTTOMLEFT", 0, -12)
	pane.stripLabel = UI.Label(pane.strip, L["Spells this build modifies"])
	pane.stripLabel:SetPoint("LEFT")
	pane.stripNote = UI.Text(pane.strip, 12, "faint")
	pane.stripNote:SetPoint("LEFT", pane.stripLabel, "RIGHT", 12, 0)
	pane.chips = UI.Pool(pane.strip, function(p)
		local chip = UI.Button(p, "", "chip", nil, 24)
		chip:SetScript("OnClick", function(self) Planner.FocusSpell(self.spell) end)
		return chip
	end)

	buildInspector(body)
	buildFooter(body)

	pane.error = CreateFrame("Frame", nil, f)
	pane.error:SetAllPoints()
	pane.error.Text = UI.Text(pane.error, 14, "muted", "body", "CENTER")
	pane.error.Text:SetPoint("CENTER", 0, 20)
	local retry = UI.Button(pane.error, L["Try again"], "default")
	retry:SetPoint("TOP", pane.error.Text, "BOTTOM", 0, -16)
	retry:SetScript("OnClick", function()
		Talents.Invalidate(state.classID)
		Planner.Refresh()
	end)
	pane.error:Hide()

	pane.Refresh = function() Planner.Refresh() end
	return pane
end

ns.Window.RegisterPane("planner", build)

-- Live updates: talents learned, spec switched, tree hotfixed.
local function onTalentsChanged()
	Talents.Invalidate(Talents.PlayerClassID())
	if ns.Window.IsShown() and ns.Window.current == "planner" then Planner.Refresh() end
end

ns:RegisterEvent("TRAIT_CONFIG_UPDATED", onTalentsChanged)
ns:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED", onTalentsChanged)
ns:RegisterEvent("PLAYER_TALENT_UPDATE", onTalentsChanged)
ns:RegisterEvent("TRAIT_TREE_CHANGED", function()
	Talents.Invalidate()
	if ns.Window.IsShown() and ns.Window.current == "planner" then Planner.Refresh() end
end)

-- A description that was still loading arrived: redraw (cheap, no re-read).
local renderQueued = false
ns:RegisterMessage("BA_SPELL_DATA", function()
	if renderQueued or not (ns.Window.IsShown() and ns.Window.current == "planner") then return end
	renderQueued = true
	ns.Util.After(0.1, function()
		renderQueued = false
		Planner.Render()
	end)
end)

-- For tests and debugging.
function Planner._State()
	return state, tree, ranks, readError
end
