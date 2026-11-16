local addonName, ns = ...

-- Apply a plan to the character (design/Apply.dc.html). Only adds points
-- through the game's own trait system: C_Traits.PurchaseRank per rank, then
-- C_Traits.CommitConfig. Any failure rolls the staged points back. Never
-- refunds, never runs in combat, never touches the game's talent window.

local UI, L = ns.UI, ns.L
local Talents = ns.Talents

local ApplyDialog = {}
ns.ApplyDialog = ApplyDialog

local W = 460
local COMMIT_TIMEOUT = 15

local dialog
local job -- { configID, treeID, steps, total, startedAt, state }

-- Analysis (pure enough to test) ---------------------------------------------------

-- What applying `ranks` to the live spec would do. Returns
-- { adds = { {id, name, from, to} }, addPoints, removals = n, blockers = {}, configID, available }.
function ApplyDialog.Analyze(current)
	local result = { adds = {}, addPoints = 0, removals = 0, blockers = {}, notes = {} }
	local tree = current.tree
	if not tree.isPlayerClass then
		table.insert(result.blockers, L["Plans for other classes can't be applied."])
		return result
	end
	local active = Talents.GetActiveSpecGroup()
	local target = current.specGroup or active
	if target ~= active then
		table.insert(result.blockers, (L["Spec %d isn't active. Switch to it in the game's talent window first."]):format(target))
	end
	local configID = Talents.GetSpecConfigID(active)
	result.configID = configID
	if not configID then
		table.insert(result.blockers, L["Talent data isn't ready yet."])
		return result
	end
	if InCombatLockdown() then
		table.insert(result.blockers, L["You're in combat. Apply unlocks when combat ends."])
	end
	if C_Traits.ConfigHasStagedChanges and ns.Secrets.Read(false, C_Traits.ConfigHasStagedChanges, configID) then
		table.insert(result.blockers, L["The game's talent window has unsaved changes. Save or undo them there first."])
	end
	local live = Talents.ReadRanks(tree, configID) or {}
	local removed = 0
	for id, t in pairs(tree.talents) do
		local want, have = current.ranks[id] or 0, live[id] or 0
		if want > have then
			table.insert(result.adds, { id = id, name = t.name, from = have, to = want, tier = t.tierPoints })
			result.addPoints = result.addPoints + (want - have)
		elseif want < have then
			removed = removed + (have - want)
		end
	end
	if removed > 0 then
		result.removals = removed
		table.insert(result.blockers, (L["This plan removes %d points. Reset talents at a class trainer (costs gold), then apply again."]):format(removed))
	end
	table.sort(result.adds, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		return a.id < b.id
	end)
	local currency = ns.Secrets.Read(nil, C_Traits.GetTreeCurrencyInfo, configID, tree.treeID, false)
	result.available = currency and currency[1] and currency[1].quantity
	if result.available and result.addPoints > result.available then
		table.insert(result.notes, (L["Only %d points available at your level: the first %d in tier order are learned."]):format(result.available, result.available))
	end
	if result.addPoints == 0 and #result.blockers == 0 then
		table.insert(result.blockers, L["Nothing to learn: your spec already has every point of this plan."])
	end
	return result
end

-- Running -------------------------------------------------------------------------

local function finish(state, message)
	if job then job.state, job.message = state, message end
	ApplyDialog.Render()
end

local function rollback(configID)
	if configID then pcall(C_Traits.RollbackConfig, configID) end
end

function ApplyDialog.Run(analysis)
	if InCombatLockdown() then return finish("failed", L["You're in combat."]) end
	local configID = analysis.configID
	local budget = analysis.available or analysis.addPoints
	local learned = 0
	job = { configID = configID, state = "saving", startedAt = GetTime(), learned = 0 }
	for _, add in ipairs(analysis.adds) do
		for _ = add.from + 1, add.to do
			if learned >= budget then break end
			local ok, purchased = pcall(C_Traits.PurchaseRank, configID, add.id)
			if not ok or not purchased then
				rollback(configID)
				return finish("failed", (L["The game refused a rank of %s. Staged points were dropped."]):format(add.name))
			end
			learned = learned + 1
		end
	end
	job.learned = learned
	if learned == 0 then return finish("failed", L["No points could be learned."]) end
	local ok, committed = pcall(C_Traits.CommitConfig, configID)
	if not ok or not committed then
		rollback(configID)
		return finish("failed", L["The game didn't accept the save. Staged points were dropped."])
	end
	ApplyDialog.Render()
	ns.Util.After(COMMIT_TIMEOUT, function()
		if job and job.state == "saving" then
			rollback(configID)
			finish("failed", L["Saving took too long (cast interrupted?). Staged points were dropped."])
		end
	end)
end

ns:RegisterEvent("TRAIT_CONFIG_UPDATED", function(_, configID)
	if job and job.state == "saving" and configID == job.configID then
		finish("success", (L["%d points learned."]):format(job.learned))
		ns.Talents.Invalidate(ns.Talents.PlayerClassID())
	end
end)

ns:RegisterEvent("CONFIG_COMMIT_FAILED", function(_, configID)
	if job and job.state == "saving" and configID == job.configID then
		rollback(configID)
		finish("failed", L["The cast was interrupted. Staged points were dropped."])
	end
end)

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if dialog and dialog:IsShown() and (not job or job.state ~= "saving") then ApplyDialog.Render() end
end)

-- UI ------------------------------------------------------------------------------

local function create()
	dialog = UI.Panel(UIParent, "window", "4A5163")
	dialog:SetSize(W, 300)
	dialog:SetPoint("CENTER", 0, 60)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	dialog.Title = UI.Text(dialog, 18, "white", "title")
	dialog.Title:SetPoint("TOPLEFT", 20, -18)
	dialog.Body = UI.Text(dialog, 12, "muted")
	dialog.Body:SetPoint("TOPLEFT", 20, -48)
	dialog.Body:SetWidth(W - 40)
	dialog.Body:SetWordWrap(true)
	dialog.lines = UI.Pool(dialog, function(p)
		local row = CreateFrame("Frame", nil, p)
		row:SetSize(W - 40, 20)
		row.Left = UI.Text(row, 12, "text")
		row.Left:SetPoint("LEFT")
		row.Right = UI.Text(row, 12, "gold", "body", "RIGHT")
		row.Right:SetPoint("RIGHT")
		return row
	end)
	dialog.Primary = UI.Button(dialog, "", "primary")
	dialog.Primary:SetPoint("BOTTOMRIGHT", -20, 16)
	dialog.Secondary = UI.Button(dialog, L["Cancel"], "default")
	dialog.Secondary:SetPoint("RIGHT", dialog.Primary, "LEFT", -10, 0)
	dialog.Secondary:SetScript("OnClick", function() ApplyDialog.Close() end)
	dialog.Bar = UI.Panel(dialog, "0E1014", "borderHi")
	dialog.Bar:SetSize(W - 40, 10)
	dialog.Bar.Fill = dialog.Bar:CreateTexture(nil, "ARTWORK")
	dialog.Bar.Fill:SetPoint("TOPLEFT", 1, -1)
	dialog.Bar.Fill:SetHeight(8)
	dialog.Bar.Fill:SetColorTexture(UI.RGB(UI.colors.gold))
	dialog:SetScript("OnUpdate", function()
		if job and job.state == "saving" then
			local p = math.min(1, (GetTime() - job.startedAt) / 1.5)
			dialog.Bar.Fill:SetWidth(math.max(1, (W - 42) * p))
		end
	end)
end

local function layoutLines(y, rows)
	dialog.lines:ReleaseAll()
	for _, r in ipairs(rows) do
		local row = dialog.lines:Acquire()
		row:SetPoint("TOPLEFT", 20, y)
		row.Left:SetText(r[1])
		row.Right:SetText(r[2] or "")
		UI.SetTextColor(row.Left, r.color or "text")
		UI.SetTextColor(row.Right, r.rightColor or "gold")
		y = y - 22
	end
	return y
end

function ApplyDialog.Render()
	if not dialog then return end
	local y
	dialog.Bar:Hide()
	dialog.Primary:Show()
	if job and job.state == "saving" then
		dialog.Title:SetText(L["Saving talents…"])
		dialog.Body:SetText(L["Saving talents is a short cast. Stay still and out of combat."])
		dialog.lines:ReleaseAll()
		dialog.Bar:Show()
		dialog.Bar:ClearAllPoints()
		dialog.Bar:SetPoint("TOPLEFT", 20, -90)
		dialog.Primary:Hide()
		dialog.Secondary:SetLabel(L["Close"])
		dialog:SetHeight(170)
		return
	elseif job and job.state == "success" then
		dialog.Title:SetText(L["Spec updated"])
		dialog.Body:SetText(job.message .. " " .. L["Plan and spec now match."])
		UI.SetTextColor(dialog.Body, "green")
		dialog.lines:ReleaseAll()
		dialog.Primary:SetLabel(L["Done"])
		dialog.Primary:FitWidth()
		dialog.Primary:SetEnabledState(true)
		dialog.Primary:SetScript("OnClick", function() ApplyDialog.Close() end)
		dialog.Secondary:Hide()
		dialog:SetHeight(150)
		return
	elseif job and job.state == "failed" then
		dialog.Title:SetText(L["Save failed — nothing changed"])
		dialog.Body:SetText(job.message or "")
		UI.SetTextColor(dialog.Body, "orange")
		dialog.lines:ReleaseAll()
		dialog.Primary:SetLabel(L["Try again"])
		dialog.Primary:FitWidth()
		dialog.Primary:SetEnabledState(true)
		dialog.Primary:SetScript("OnClick", function()
			job = nil
			ApplyDialog.Render()
		end)
		dialog.Secondary:Show()
		dialog.Secondary:SetLabel(L["Close"])
		dialog:SetHeight(160)
		return
	end

	local current = ns.Planner.Current()
	if not current then return ApplyDialog.Close() end
	local analysis = ApplyDialog.Analyze(current)
	local specName = (L["Spec %d"]):format(current.specGroup or Talents.GetActiveSpecGroup())
	dialog.Secondary:Show()
	dialog.Secondary:SetLabel(L["Cancel"])
	UI.SetTextColor(dialog.Body, "muted")
	if #analysis.blockers > 0 then
		dialog.Title:SetText(L["Can't apply right now"])
		dialog.Body:SetText("")
		local rows = {}
		for _, b in ipairs(analysis.blockers) do rows[#rows + 1] = { "• " .. b, color = "orange" } end
		y = layoutLines(-52, rows)
		for _, line in ipairs(dialog.lines.items) do
			if line:IsShown() then
				line.Left:SetWidth(W - 40)
				line.Left:SetWordWrap(true)
			end
		end
		dialog.Primary:SetLabel((L["Learn %d points"]):format(analysis.addPoints))
		dialog.Primary:FitWidth()
		dialog.Primary:SetEnabledState(false)
		dialog.Secondary:SetLabel(L["Close"])
		dialog:SetHeight(-y + 80 + #analysis.blockers * 14)
		return
	end
	dialog.Title:SetText((L["Apply to %s?"]):format(specName))
	dialog.Body:SetText(L["Build Atlas will learn these points through the game's own talent system. It never removes points."])
	local rows = {}
	for i, add in ipairs(analysis.adds) do
		if i > 10 then
			rows[#rows + 1] = { (L["+%d more talents"]):format(#analysis.adds - 10), color = "muted" }
			break
		end
		local t = current.tree.talents[add.id]
		rows[#rows + 1] = { add.name, ("+%d → %d/%d"):format(add.to - add.from, add.to, t.maxRanks) }
	end
	local unspent = analysis.available and math.max(0, analysis.available - analysis.addPoints)
	if unspent then rows[#rows + 1] = { L["Unspent after apply"], tostring(unspent), color = "muted", rightColor = "muted" } end
	for _, note in ipairs(analysis.notes) do rows[#rows + 1] = { note, color = "orange" } end
	y = layoutLines(-84, rows)
	local points = analysis.available and math.min(analysis.available, analysis.addPoints) or analysis.addPoints
	dialog.Primary:SetLabel((L["Learn %d points"]):format(points))
	dialog.Primary:FitWidth()
	dialog.Primary:SetEnabledState(not InCombatLockdown())
	dialog.Primary:SetScript("OnClick", function() ApplyDialog.Run(analysis) end)
	dialog:SetHeight(-y + 70)
end

function ApplyDialog.Open()
	if not dialog then create() end
	if job and job.state ~= "saving" then job = nil end
	dialog:Show()
	ApplyDialog.Render()
end

function ApplyDialog.Close()
	if dialog then dialog:Hide() end
	if job and job.state ~= "saving" then job = nil end
	if ns.Window.IsShown() then ns.Window.Refresh() end
end

function ApplyDialog._Job() return job end
