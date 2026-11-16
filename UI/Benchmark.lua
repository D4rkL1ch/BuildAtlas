local addonName, ns = ...

-- Dummy benchmark (design/Benchmark.dc.html). Arm a run of a set length and
-- tag it with a build; it starts with combat and is recorded from the
-- damage meter when combat ends. No live numbers during the run.

local UI, L = ns.UI, ns.L
local Measure, Attribution = ns.Measure, ns.Attribution

local Bench = {}
ns.Benchmark = Bench

local LENGTHS = { { 60, "1 min" }, { 120, "2 min" }, { 180, "3 min" }, { 300, "5 min" } }
local pane
local state = { length = 120, tag = nil }

-- Tag choices: the live active spec plus the planner's plans for this class.
function Bench.Tags()
	local _, live = Measure.TalentSnapshot()
	local list = { { key = live, label = live .. L[" (live)"] } }
	local classID = ns.Talents.PlayerClassID()
	local plans = ns.charDB.plans[classID] or {}
	local tree = ns.Talents.ReadTree(classID)
	if tree then
		for _, slot in ipairs({ "scratch", "spec1", "spec2" }) do
			local p = plans[slot]
			if p and next(p.ranks) then
				local _, perGroup = ns.Plan.Spent(tree, p.ranks)
				local label = (slot == "scratch" and L["Scratch plan"] or (L["Spec %d plan"]):format(slot == "spec1" and 1 or 2)) .. " · " .. table.concat(perGroup, "/")
				list[#list + 1] = { key = label, label = label }
			end
		end
	end
	return list
end

function Bench.Render()
	local armed = ns.charDB.armed
	for _, b in ipairs(pane.lengths) do b:SetOn(b.length == state.length) end
	local tags = Bench.Tags()
	if not state.tag then state.tag = tags[1] and tags[1].key end
	pane.tagDD:Refresh()
	if armed then
		pane.arm:SetLabel(L["Disarm"])
		pane.status:SetText(armed.started and L["Run in progress. Results after combat."] or
			(L["Armed: %s · %s. Starts on your first hit; stop at the time."]):format(armed.tag, Measure.Clock(armed.length)))
		UI.SetTextColor(pane.status, "teal")
	else
		pane.arm:SetLabel(L["Arm: starts on first hit"])
		pane.status:SetText("")
	end
	pane.arm:FitWidth()
	pane.arm:SetEnabledState(not InCombatLockdown())

	-- Results for this class and current gear
	local classID = ns.Talents.PlayerClassID()
	local gear = Measure.GearKey()
	local runs = {}
	for _, r in ipairs(Measure.Runs()) do
		if r.classID == classID then runs[#runs + 1] = r end
	end
	local groups, overlap = Attribution.BenchSummary(runs, gear)
	pane.results.rows:ReleaseAll()
	local y = 0
	local maxAvg = groups[1] and groups[1].max or 1
	for i, g in ipairs(groups) do
		local r = pane.results.rows:Acquire()
		r:SetPoint("TOPLEFT", pane.results.Content, "TOPLEFT", 0, -y)
		r.Left:SetText(g.tag)
		r.Right:SetText(("%.0f DPS avg"):format(g.avg))
		r.Sub:SetText((L["%d runs · range %.0f–%.0f"]):format(g.n, g.min, g.max))
		r.Bar:SetWidth(math.max(2, 420 * g.avg / maxAvg))
		r.Bar:SetColorTexture(UI.RGB(UI.colors[i == 1 and "blue" or "gold"]))
		y = y + 58
	end
	pane.results:SetContentHeight(y)
	if #groups >= 2 then
		local diff = (groups[1].avg - groups[2].avg) / groups[2].avg * 100
		local text = (L["%s is about %.1f%% ahead."]):format(groups[1].tag, diff)
		if overlap then
			text = text .. " " .. L["The ranges overlap, so do a few more runs to be sure."]
		elseif groups[1].n < 3 or groups[2].n < 3 then
			text = text .. " " .. L["Fewer than 3 runs on one build: treat as a first impression."]
		end
		pane.verdict:SetText(text)
	elseif #groups == 1 then
		pane.verdict:SetText(L["Record runs on a second build to compare."])
	else
		pane.verdict:SetText(L["No runs with your current gear yet."])
	end

	-- History
	pane.history.rows:ReleaseAll()
	y = 0
	local excluded = 0
	for i, r in ipairs(Measure.Runs()) do
		if r.classID == classID then
			local row = pane.history.rows:Acquire()
			row:SetPoint("TOPLEFT", pane.history.Content, "TOPLEFT", 0, -y)
			local otherGear = r.gear ~= gear
			if otherGear then excluded = excluded + 1 end
			row.Num:SetText(tostring(i))
			row.Tag:SetText(r.tag .. (otherGear and UI.Colorize(L[" · other gear"], "orange") or ""))
			row.Len:SetText(Measure.Clock(r.duration))
			row.Dps:SetText(("%.0f"):format(r.dps))
			row.Delete:SetScript("OnClick", function()
				Measure.DeleteRun(i)
			end)
			y = y + 26
		end
	end
	pane.history:SetContentHeight(y)
	pane.excluded:SetText(excluded > 0 and (L["%d runs had different gear and are left out of the averages."]):format(excluded) or "")
end

local function build(host)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f

	local newLabel = UI.Label(f, "New run")
	newLabel:SetPoint("TOPLEFT", 32, -22)
	local lenLabel = UI.Text(f, 12, "muted")
	lenLabel:SetText(L["Length"])
	lenLabel:SetPoint("TOPLEFT", 32, -52)
	pane.lengths = {}
	local x = 100
	for _, l in ipairs(LENGTHS) do
		local b = UI.Button(f, L[l[2]], "seg", 64, 28)
		b.length = l[1]
		b:SetPoint("TOPLEFT", x, -46)
		b:SetScript("OnClick", function() state.length = l[1] Bench.Render() end)
		x = x + 63
		pane.lengths[#pane.lengths + 1] = b
	end
	local tagLabel = UI.Text(f, 12, "muted")
	tagLabel:SetText(L["Tag run as"])
	tagLabel:SetPoint("TOPLEFT", 400, -52)
	pane.tagDD = UI.Dropdown(f, 280, Bench.Tags, function() return state.tag end, function(k) state.tag = k Bench.Render() end)
	pane.tagDD:SetPoint("TOPLEFT", 480, -46)
	pane.arm = UI.Button(f, L["Arm: starts on first hit"], "primary")
	pane.arm:SetPoint("TOPLEFT", 790, -44)
	pane.arm:SetScript("OnClick", function()
		if ns.charDB.armed then
			Measure.Disarm()
		else
			Measure.Arm(state.length, state.tag or "?")
		end
		Bench.Render()
	end)
	pane.status = UI.Text(f, 12, "teal")
	pane.status:SetPoint("TOPLEFT", 32, -86)

	local resLabel = UI.Label(f, "Result · same gear")
	resLabel:SetPoint("TOPLEFT", 32, -118)
	pane.results = UI.ScrollList(f, 500, 300)
	pane.results:SetPoint("TOPLEFT", 32, -140)
	pane.results.rows = UI.Pool(pane.results.Content, function(p)
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(450, 54)
		r.Left = UI.Text(r, 13, "text")
		r.Left:SetPoint("TOPLEFT")
		r.Right = UI.Text(r, 13, "gold", "body", "RIGHT")
		r.Right:SetPoint("TOPRIGHT")
		r.Bar = r:CreateTexture(nil, "ARTWORK")
		r.Bar:SetHeight(8)
		r.Bar:SetPoint("TOPLEFT", 0, -22)
		r.Sub = UI.Text(r, 11, "muted")
		r.Sub:SetPoint("TOPLEFT", 0, -36)
		return r
	end)
	pane.verdict = UI.Text(f, 13, "text")
	pane.verdict:SetPoint("TOPLEFT", pane.results, "BOTTOMLEFT", 0, -12)
	pane.verdict:SetWidth(500)
	pane.verdict:SetWordWrap(true)
	local footnote = UI.Text(f, 11, "faint")
	footnote:SetPoint("TOPLEFT", pane.verdict, "BOTTOMLEFT", 0, -16)
	footnote:SetWidth(500)
	footnote:SetWordWrap(true)
	footnote:SetText(L["Numbers come from the game's damage meter after each run ends. Nothing shows live during the run: Forever hides combat values from addons. You end the run yourself by stopping at the time."])

	local histLabel = UI.Label(f, "Run history")
	histLabel:SetPoint("TOPLEFT", 560, -118)
	pane.history = UI.ScrollList(f, 510, 480)
	pane.history:SetPoint("TOPLEFT", 560, -140)
	pane.history.rows = UI.Pool(pane.history.Content, function(p)
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(470, 24)
		r.Num = UI.Text(r, 11, "faint")
		r.Num:SetPoint("LEFT")
		r.Tag = UI.Text(r, 12, "text")
		r.Tag:SetPoint("LEFT", 28, 0)
		r.Tag:SetWidth(270)
		r.Len = UI.Text(r, 12, "muted", "body", "RIGHT")
		r.Len:SetPoint("LEFT", 300, 0)
		r.Len:SetWidth(50)
		r.Dps = UI.Text(r, 12, "gold", "body", "RIGHT")
		r.Dps:SetPoint("LEFT", 356, 0)
		r.Dps:SetWidth(60)
		r.Delete = UI.Button(r, "×", "mini", 22, 22)
		r.Delete:SetPoint("RIGHT")
		return r
	end)
	pane.excluded = UI.Text(f, 11, "orange")
	pane.excluded:SetPoint("TOPLEFT", pane.history, "BOTTOMLEFT", 0, -8)

	pane.Refresh = Bench.Render
	return pane
end

ns.Window.RegisterPane("bench", build)
ns:RegisterMessage("BA_BENCH_CHANGED", function()
	if pane and pane.frame:IsShown() then Bench.Render() end
end)
