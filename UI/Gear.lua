local addonName, ns = ...

-- Stats & gear (design/Gear.dc.html). Stat weights from a rough own estimate
-- (role + talent lean) or pasted Pawn / SimC weights; "Send to Pawn" when
-- Pawn is loaded (integrate, don't compete). Upgrade check over the bags,
-- consumables and enchant checklist. Everything refreshes out of combat.

local UI, L = ns.UI, ns.L
local SW, Compare = ns.StatWeights, ns.Compare
local Read = ns.Secrets.Read

local Gear = {}
ns.Gear = Gear

local pane

-- Equip location -> slot IDs it can go into.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

local function settings()
	ns.charDB.weights = ns.charDB.weights or { source = "own" }
	return ns.charDB.weights
end

-- Role, weights and a label for the plan in the planner (or the live spec).
function Gear.Weights()
	local current = ns.Planner.Current()
	local s = settings()
	local lean = {}
	local classToken = ns.ClassByID[ns.Talents.PlayerClassID()] and ns.ClassByID[ns.Talents.PlayerClassID()].token
	if current then lean = Compare.Lean(current.tree, current.ranks, nil, current.graph) end
	local role = s.role or SW.GuessRole(lean, classToken)
	if s.source == "pasted" and s.pasted then
		return s.pasted, role, s.name or L["Pasted weights"]
	end
	return SW.Estimate(role, lean), role, L["Own estimate (rough)"]
end

local function itemStats(link)
	if not link then return nil end
	local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
	return Read(nil, fn, link)
end

local function equipLoc(link)
	local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local ok, _, _, subType, loc = pcall(fn, link)
	if ok then return loc, subType end
end

-- Talent-aware remark for an item, from talent names in the plan.
local function talentNote(subType, loc, current)
	if not current then return nil end
	local names = {}
	for id, r in pairs(current.ranks) do
		if r > 0 and current.tree.talents[id] then names[#names + 1] = current.tree.talents[id].name end
	end
	local all = table.concat(names, "|")
	subType = subType or ""
	if all:find("Two-Handed", 1, true) then
		if loc == "INVTYPE_2HWEAPON" then return L["Two-handed: your two-hand talents apply."] end
		if loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then return L["One-handed: loses your Two-Handed Weapon Specialization."] end
	end
	if all:find("Dual Wield", 1, true) and (loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONOFFHAND") then
		return L["Off-hand option for your Dual Wield Specialization."]
	end
	if (all:find("Shield", 1, true) or all:find("Bastion", 1, true)) and loc == "INVTYPE_SHIELD" then
		return L["Shield: your shield talents apply."]
	end
	for _, w in ipairs({ "Axe", "Sword", "Mace", "Dagger", "Polearm", "Fist" }) do
		if subType:find(w, 1, true) and all:find("Weaponmaster", 1, true) then
			return (L["%s: Weaponmaster gives a %s bonus."]):format(subType, w)
		end
	end
end

-- Upgrades in the bags: { {link, score, equipped, pct, note} } best first.
function Gear.Upgrades(weights)
	local out = {}
	if not (C_Container and C_Container.GetContainerNumSlots) then return out end
	local current = ns.Planner.Current()
	local equippedScore = {}
	for slot = 1, 18 do
		equippedScore[slot] = SW.Score(itemStats(Read(nil, GetInventoryItemLink, "player", slot)), weights)
	end
	for bag = 0, 4 do
		for slot = 1, Read(0, C_Container.GetContainerNumSlots, bag) or 0 do
			local link = Read(nil, C_Container.GetContainerItemLink, bag, slot)
			local loc, subType
			if link then loc, subType = equipLoc(link) end
			local slots = loc and SLOTS[loc]
			if slots then
				local score = SW.Score(itemStats(link), weights)
				local base = math.huge
				for _, s in ipairs(slots) do base = math.min(base, equippedScore[s] or 0) end
				if score > 0 then
					local pct = base > 0 and (score - base) / base * 100 or 100
					out[#out + 1] = { link = link, score = score, pct = pct, note = talentNote(subType, loc, current) }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.pct > b.pct end)
	return out
end

-- Counts of the role's consumables (bags + bank) and the alts' counts.
function Gear.Consumables(role)
	local list = ns.Consumables[role] or ns.Consumables.Physical
	local out = {}
	local me = UnitName("player")
	local alts = ns.db.inventory or {}
	for _, c in ipairs(list) do
		local count = Read(0, C_Item and C_Item.GetItemCount, c[1], true) or 0
		local altCount = 0
		for char, items in pairs(alts) do
			if char ~= me then altCount = altCount + (items[c[1]] or 0) end
		end
		local name = Read(nil, C_Item and C_Item.GetItemNameByID, c[1]) or c[2]
		out[#out + 1] = { id = c[1], name = name, why = c[3], count = count, alts = altCount }
	end
	return out
end

-- Remembers this character's consumable counts for the alts column.
function Gear.SnapshotInventory()
	if InCombatLockdown() then return end
	ns.db.inventory = ns.db.inventory or {}
	local counts = {}
	for _, list in pairs(ns.Consumables) do
		for _, c in ipairs(list) do
			local n = Read(0, C_Item and C_Item.GetItemCount, c[1], true) or 0
			if n > 0 then counts[c[1]] = n end
		end
	end
	ns.db.inventory[UnitName("player")] = counts
end

function Gear.MissingEnchants()
	local out = {}
	for _, s in ipairs(ns.EnchantSlots) do
		local link = Read(nil, GetInventoryItemLink, "player", s[1])
		if link then
			local enchant = link:match("item:%d+:(%d*)")
			if not enchant or enchant == "" or enchant == "0" then out[#out + 1] = s[2] end
		end
	end
	return out
end

-- Pawn ----------------------------------------------------------------------------

function Gear.PawnAvailable()
	return type(PawnImportScale) == "function"
end

function Gear.SendToPawn()
	local weights, _, label = Gear.Weights()
	local name = "Build Atlas - " .. (label or "")
	local tag = SW.ToPawn(weights, name)
	if not Gear.PawnAvailable() then return false, tag end
	local ok = pcall(PawnImportScale, tag, true)
	return ok, tag
end

-- UI ------------------------------------------------------------------------------

function Gear.Render()
	if InCombatLockdown() then return end
	local weights, role, label = Gear.Weights()
	local s = settings()
	pane.srcOwn:SetOn(s.source ~= "pasted")
	pane.srcPasted:SetOn(s.source == "pasted")
	pane.srcPasted:SetEnabledState(s.pasted ~= nil)
	pane.roleDD:Refresh()
	pane.sourceNote:SetText(label .. " · " .. L[role])
	pane.pawnStatus:SetText(Gear.PawnAvailable() and L["Pawn found"] or L["Pawn not loaded: copy the scale string instead"])
	UI.SetTextColor(pane.pawnStatus, Gear.PawnAvailable() and "green" or "faint")

	pane.weights.rows:ReleaseAll()
	local y, maxW = 0, 0.01
	for _, stat in ipairs(SW.STATS) do maxW = math.max(maxW, weights[stat] or 0) end
	for _, stat in ipairs(SW.STATS) do
		local v = weights[stat]
		if v and v > 0 then
			local r = pane.weights.rows:Acquire()
			r:SetPoint("TOPLEFT", pane.weights.Content, "TOPLEFT", 0, -y)
			r.Left:SetText(L[stat])
			r.Right:SetText(("%.2f"):format(v))
			r.Bar:SetWidth(math.max(2, 120 * v / maxW))
			y = y + 22
		end
	end
	pane.weights:SetContentHeight(y)

	pane.upgrades.rows:ReleaseAll()
	y = 0
	local ups = Gear.Upgrades(weights)
	for i, u in ipairs(ups) do
		if i > 12 then break end
		local r = pane.upgrades.rows:Acquire()
		r:SetPoint("TOPLEFT", pane.upgrades.Content, "TOPLEFT", 0, -y)
		r.Left:SetText(u.link)
		r.Right:SetText(("%+.1f%%"):format(u.pct))
		UI.SetTextColor(r.Right, u.pct >= 0 and "green" or "orange")
		r.Note:SetText(u.note or "")
		r:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(u.link)
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		y = y + (u.note and 40 or 24)
	end
	if #ups == 0 then
		local r = pane.upgrades.rows:Acquire()
		r:SetPoint("TOPLEFT", pane.upgrades.Content, "TOPLEFT", 0, 0)
		r.Left:SetText(L["No equippable items with these stats in your bags."])
		r.Right:SetText("") r.Note:SetText("")
		y = 24
	end
	pane.upgrades:SetContentHeight(y)

	pane.checks.rows:ReleaseAll()
	y = 0
	for _, c in ipairs(Gear.Consumables(role)) do
		local r = pane.checks.rows:Acquire()
		r:SetPoint("TOPLEFT", pane.checks.Content, "TOPLEFT", 0, -y)
		r.Left:SetText(c.name)
		UI.SetTextColor(r.Left, c.count > 0 and "text" or "orange")
		r.Right:SetText(c.alts > 0 and ("%d · %s %d"):format(c.count, L["alts"], c.alts) or tostring(c.count))
		r.Note:SetText(c.why)
		r:SetScript("OnEnter", nil)
		y = y + 40
	end
	local missing = Gear.MissingEnchants()
	local r = pane.checks.rows:Acquire()
	r:SetPoint("TOPLEFT", pane.checks.Content, "TOPLEFT", 0, -y)
	r.Left:SetText(L["Enchants"])
	UI.SetTextColor(r.Left, #missing == 0 and "green" or "orange")
	r.Right:SetText(#missing == 0 and L["all set"] or (L["%d missing"]):format(#missing))
	r.Note:SetText(#missing > 0 and table.concat(missing, ", ") or "")
	y = y + 40
	pane.checks:SetContentHeight(y)
end

local function textRows(col, height)
	col.rows = UI.Pool(col.Content, function(p)
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(col.Content:GetWidth(), height or 20)
		r:EnableMouse(true)
		r.Left = UI.Text(r, 12, "text")
		r.Left:SetPoint("TOPLEFT")
		r.Left:SetWidth(col.Content:GetWidth() - 90)
		r.Right = UI.Text(r, 12, "gold", "body", "RIGHT")
		r.Right:SetPoint("TOPRIGHT")
		r.Note = UI.Text(r, 11, "muted")
		r.Note:SetPoint("TOPLEFT", 0, -18)
		r.Note:SetWidth(col.Content:GetWidth())
		r.Bar = r:CreateTexture(nil, "ARTWORK")
		r.Bar:SetHeight(6)
		r.Bar:SetPoint("LEFT", 110, 0)
		r.Bar:SetColorTexture(UI.RGB(UI.colors.gold))
		r.Bar:SetWidth(1)
		return r
	end)
end

local function build(host)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f

	local wl = UI.Label(f, "Stat weights")
	wl:SetPoint("TOPLEFT", 24, -20)
	pane.srcOwn = UI.Button(f, L["Own estimate"], "seg", nil, 28)
	pane.srcOwn:SetPoint("TOPLEFT", 24, -42)
	pane.srcOwn:SetScript("OnClick", function() settings().source = "own" Gear.Render() end)
	pane.srcPasted = UI.Button(f, L["Pasted"], "seg", nil, 28)
	pane.srcPasted:SetPoint("LEFT", pane.srcOwn, "RIGHT", -1, 0)
	pane.srcPasted:SetScript("OnClick", function() settings().source = "pasted" Gear.Render() end)
	pane.roleDD = UI.Dropdown(f, 130, function()
		local list = { { key = "auto", label = L["Role: auto"] } }
		for _, r in ipairs(SW.ROLES) do list[#list + 1] = { key = r, label = L["Role: "] .. L[r] } end
		return list
	end, function() return settings().role or "auto" end, function(k)
		settings().role = k ~= "auto" and k or nil
		Gear.Render()
	end)
	pane.roleDD:SetPoint("LEFT", pane.srcPasted, "RIGHT", 10, 0)
	pane.sourceNote = UI.Text(f, 11, "muted")
	pane.sourceNote:SetPoint("TOPLEFT", 24, -78)
	pane.weights = UI.ScrollList(f, 330, 270)
	pane.weights:SetPoint("TOPLEFT", 24, -98)
	textRows(pane.weights)
	local paste = UI.TextArea(f, 330, 70, false)
	paste:SetPoint("TOPLEFT", 24, -378)
	pane.paste = paste
	local usePaste = UI.Button(f, L["Use pasted Pawn / SimC weights"], "default")
	usePaste:SetPoint("TOPLEFT", 24, -454)
	usePaste:SetScript("OnClick", function()
		local w, name = SW.Parse(paste:GetValue())
		if not w then
			ns:Print(L["No stat weights found. Paste a Pawn scale tag or Stat=value pairs."])
			return
		end
		local s = settings()
		s.pasted, s.name, s.source = w, name, "pasted"
		Gear.Render()
	end)
	local send = UI.Button(f, L["Send to Pawn"], "primary")
	send:SetPoint("TOPLEFT", 24, -494)
	send:SetScript("OnClick", function()
		local ok, tag = Gear.SendToPawn()
		if ok then
			ns:Print(L["Scale sent to Pawn."])
		else
			paste:SetValue(tag)
			paste:SelectAll()
			ns:Print(L["Pawn isn't loaded. The scale string is in the box: Ctrl+C and import it in Pawn."])
		end
	end)
	pane.pawnStatus = UI.Text(f, 11, "faint")
	pane.pawnStatus:SetPoint("LEFT", send, "RIGHT", 10, 0)

	local ul = UI.Label(f, "Upgrade check · bags")
	ul:SetPoint("TOPLEFT", 380, -20)
	pane.upgrades = UI.ScrollList(f, 340, 560)
	pane.upgrades:SetPoint("TOPLEFT", 380, -42)
	textRows(pane.upgrades)
	local un = UI.Text(f, 11, "faint")
	un:SetPoint("TOPLEFT", pane.upgrades, "BOTTOMLEFT", 0, -8)
	un:SetWidth(340)
	un:SetWordWrap(true)
	un:SetText(L["Scores use the weights on the left. Refreshed when you leave combat."])

	local cl = UI.Label(f, "Consumables & enchants")
	cl:SetPoint("TOPLEFT", 740, -20)
	pane.checks = UI.ScrollList(f, 340, 560)
	pane.checks:SetPoint("TOPLEFT", 740, -42)
	textRows(pane.checks)
	local cn = UI.Text(f, 11, "faint")
	cn:SetPoint("TOPLEFT", pane.checks, "BOTTOMLEFT", 0, -8)
	cn:SetWidth(340)
	cn:SetWordWrap(true)
	cn:SetText(L["Counts cover your bags and bank; alts are counted from their last login."])

	pane.Refresh = Gear.Render
	return pane
end

ns.Window.RegisterPane("gear", build)

ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
	Gear.SnapshotInventory()
	if pane and pane.frame:IsShown() then Gear.Render() end
end)
ns:RegisterMessage("BA_LOGIN", function() ns.Util.After(5, Gear.SnapshotInventory) end)
