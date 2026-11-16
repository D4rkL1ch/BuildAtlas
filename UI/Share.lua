local addonName, ns = ...

-- Import / export pane (design/Share.dc.html).
-- Export: Build Atlas string, Blizzard loadout string, Wowhead link, SimC
-- profile. Addons can't write to the clipboard: the box selects its text and
-- the player presses Ctrl+C.
-- Import: paste anything; the format and class are detected, and the plan
-- loads into the scratch slot (or as build B for Compare).
-- Send: addon message to party, guild or a player; never inside instances.

local UI, L = ns.UI, ns.L
local Codecs = ns.Codecs

local Share = {}
ns.Share = Share

local PREFIX = "BuildAtlas"
local W = 1104 - 64

local FORMATS = {
	{ key = "atlas", label = "Build Atlas string", hint = "Compact string with the game build stamp. Imports in any copy of Build Atlas." },
	{ key = "blizzard", label = "Game loadout string", hint = "The game's own talent string. Also what other talent tools import." },
	{ key = "wowhead", label = "Wowhead link", hint = "Opens in Wowhead's talent calculator (Blizzard string format)." },
	{ key = "simc", label = "SimC profile", hint = "Minimal profile for simc-forever with your talents. Add gear in SimC." },
}

local pane
local state = { format = "atlas", detected = nil, compareTarget = nil }

local function specToClass()
	local map = {}
	for _, c in ipairs(ns.Classes) do map[c.specID] = c.classID end
	return map
end
Share.SpecToClass = specToClass

local function loadoutVersion()
	return C_Traits and ns.Secrets.Read(2, C_Traits.GetLoadoutSerializationVersion) or 2
end

local function treeHash(tree)
	-- Optional; zero-filled skips the game's tree check on import.
	local hash = C_Traits and ns.Secrets.Read(nil, C_Traits.GetTreeHash, tree.treeID)
	if type(hash) == "table" and #hash == 16 then return hash end
end

function Share.Export(current, format)
	local tree, ranks = current.tree, current.ranks
	local version = loadoutVersion()
	if format == "atlas" then
		return Codecs.ExportBuildAtlas(tree, ranks, ns:GetClientBuild(), version, treeHash(tree))
	elseif format == "blizzard" then
		return Codecs.PlanToLoadout(tree, ranks, version, treeHash(tree))
	elseif format == "wowhead" then
		return Codecs.ExportWowhead(tree, ranks, version)
	elseif format == "simc" then
		local c = ns.ClassByID[current.classID]
		local isPlayer = tree.isPlayerClass
		return Codecs.ExportSimC(tree, ranks, {
			classToken = c and c.token, version = version,
			name = isPlayer and UnitName("player") or "BuildAtlas",
			level = isPlayer and UnitLevel("player") or 60,
			race = isPlayer and select(2, UnitRace("player")) or nil,
		})
	end
end

-- Decodes pasted text into { classID, ranks, kind, build, warning } or nil, message.
function Share.Import(text)
	local detected, why = Codecs.Detect(text, specToClass())
	if not detected then
		local messages = {
			empty = "Paste a string or link first.",
			site = "Links from that site aren't supported yet. Paste the game's loadout string or a Build Atlas string.",
			short = "That string is too short to be a talent build.",
			spec = "That string is for a talent tree this client doesn't have.",
			unknown = "Not a talent string Build Atlas recognises.",
		}
		return nil, L[messages[why] or messages.unknown]
	end
	local tree, reason = ns.Talents.ReadTree(detected.classID)
	if not tree then
		return nil, reason == "combat" and L["Other classes can only be loaded out of combat."] or L["Couldn't read that class's talent tree."]
	end
	local ranks, err = Codecs.LoadoutToPlan(tree, detected.loadout)
	if not ranks then return nil, L["The string doesn't match this class's tree."] .. " (" .. tostring(err) .. ")" end
	local result = { classID = detected.classID, ranks = ranks, kind = detected.kind, build = detected.build }
	local client = ns:GetClientBuild()
	if detected.version and detected.version ~= loadoutVersion() then
		result.warning = (L["Saved with string version %d; this game uses %d."]):format(detected.version, loadoutVersion())
	elseif detected.build and detected.build ~= client then
		result.warning = (L["Saved on game build %s; you're on %s. Trees may have changed."]):format(detected.build, client)
	end
	local ok, badNode = ns.Plan.Validate(tree, ranks)
	if not ok then
		result.warning = (result.warning and result.warning .. " " or "") ..
			(L["Not valid on the current tree (%s)."]):format(badNode and tree.talents[badNode] and tree.talents[badNode].name or L["too many points"])
	end
	return result
end

-- Sending -------------------------------------------------------------------------

function Share.CanSend()
	if IsInInstance() then return false, L["Not available inside instances"] end
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, L["Not available"] end
	return true
end

function Share.Send(chatType, target)
	local ok, why = Share.CanSend()
	if not ok then ns:Print(why) return false end
	local current = ns.Planner.Current()
	if not current then return false end
	local text = Share.Export(current, "atlas")
	local sent = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, chatType, target)
	if sent then ns:Print((L["Build sent to %s."]):format(target or L[chatType:lower()])) end
	return sent
end

ns:RegisterMessage("BA_LOGIN", function()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	end
end)

ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
	if prefix ~= PREFIX or ns.Secrets.IsSecret(text) or ns.Secrets.IsSecret(sender) then return end
	if type(text) ~= "string" or not text:find("^BA1:") then return end
	if sender == UnitName("player") or (sender and sender:match("^([^%-]+)") == UnitName("player")) then return end
	local detected = Codecs.Detect(text, specToClass())
	if not detected then return end
	ns.db.received = ns.db.received or {}
	table.insert(ns.db.received, 1, { from = sender, text = text, time = time() })
	while #ns.db.received > 10 do table.remove(ns.db.received) end
	local name = ns.Planner.ClassName(detected.classID)
	ns.Toasts.Show("info", (L["%s shared a build"]):format(sender), name, {
		text = L["Open"],
		run = function()
			ns.Window.Show("share")
			Share.SetImportText(text)
		end,
	})
end)

-- UI ------------------------------------------------------------------------------

function Share.SetImportText(text)
	if not pane then return end
	pane.input:SetValue(text)
	Share.UpdateDetected()
end

function Share.UpdateDetected()
	local text = pane.input:GetValue()
	if not text or text == "" then
		pane.detected:SetText(L["Paste a Build Atlas string, the game's loadout string, a Wowhead link or a SimC profile."])
		UI.SetTextColor(pane.detected, "faint")
		pane.loadScratch:SetEnabledState(false)
		pane.loadB:SetEnabledState(false)
		state.detected = nil
		return
	end
	local result, err = Share.Import(text)
	state.detected = result
	if not result then
		pane.detected:SetText(err)
		UI.SetTextColor(pane.detected, "orange")
	else
		local total, perGroup = ns.Plan.Spent(ns.Talents.ReadTree(result.classID), result.ranks)
		local split = table.concat(perGroup, "/")
		local kinds = { buildatlas = "Build Atlas", blizzard = L["game string"], wowhead = "Wowhead", simc = "SimC" }
		local line = (L["Detected: %s · %s · %s (%d points)"]):format(kinds[result.kind] or result.kind, ns.Planner.ClassName(result.classID), split, total)
		if result.warning then
			line = line .. " · " .. UI.Colorize(result.warning, "orange")
		else
			line = line .. " · " .. L["tree version matches"]
		end
		pane.detected:SetText(line)
		UI.SetTextColor(pane.detected, "green")
	end
	pane.loadScratch:SetEnabledState(result ~= nil)
	pane.loadB:SetEnabledState(result ~= nil)
end

local function refreshExport()
	local current = ns.Planner.Current()
	for _, tab in ipairs(pane.tabs) do tab:SetOn(tab.key == state.format) end
	local fmt
	for _, f in ipairs(FORMATS) do
		if f.key == state.format then fmt = f end
	end
	pane.hint:SetText(L[fmt.hint])
	if not current then
		pane.title:SetText(L["Export"])
		pane.output:SetValue(L["No plan loaded yet. Open the talent planner first."])
		return
	end
	pane.title:SetText(L["EXPORT · "] .. current.label)
	local ok, text = pcall(Share.Export, current, state.format)
	pane.output:SetValue(ok and text or (L["Couldn't export: "] .. tostring(text)))
end

local function refreshSend()
	local ok, why = Share.CanSend()
	for _, b in ipairs(pane.sendButtons) do b:SetEnabledState(ok) end
	pane.sendNote:SetText(ok and "" or why)
end

local function build(host)
	pane = {}
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints()
	pane.frame = f
	local x, y = 32, -24

	pane.title = UI.Label(f, "Export")
	pane.title:SetPoint("TOPLEFT", x, y)
	y = y - 28
	pane.tabs = {}
	local tx = x
	for _, fmt in ipairs(FORMATS) do
		local tab = UI.Button(f, L[fmt.label], "seg", nil, 30)
		tab.key = fmt.key
		tab:SetPoint("TOPLEFT", tx, y)
		tab:SetScript("OnClick", function()
			state.format = fmt.key
			refreshExport()
		end)
		tx = tx + tab:GetWidth() - 1
		pane.tabs[#pane.tabs + 1] = tab
	end
	y = y - 40
	pane.hint = UI.Text(f, 12, "muted")
	pane.hint:SetPoint("TOPLEFT", x, y)
	y = y - 24
	pane.output = UI.TextArea(f, W, 96, true)
	pane.output:SetPoint("TOPLEFT", x, y)
	y = y - 104
	local select = UI.Button(f, L["Select all"], "default")
	select:SetPoint("TOPLEFT", x, y)
	select:SetScript("OnClick", function() pane.output:SelectAll() end)
	local copyNote = UI.Text(f, 12, "faint")
	copyNote:SetPoint("LEFT", select, "RIGHT", 12, 0)
	copyNote:SetText(L["then Ctrl+C. Addons can't write to the clipboard directly."])
	y = y - 56

	local importLabel = UI.Label(f, "Import")
	importLabel:SetPoint("TOPLEFT", x, y)
	y = y - 24
	pane.input = UI.TextArea(f, W, 96, false)
	pane.input:SetPoint("TOPLEFT", x, y)
	pane.input.Edit:SetScript("OnTextChanged", function(_, userInput)
		if userInput then Share.UpdateDetected() end
	end)
	y = y - 108
	pane.detected = UI.Text(f, 12, "faint")
	pane.detected:SetPoint("TOPLEFT", x, y)
	pane.detected:SetWidth(W - 420)
	pane.detected:SetWordWrap(true)
	pane.loadScratch = UI.Button(f, L["Load into scratch plan"], "primary")
	pane.loadScratch:SetPoint("TOPRIGHT", f, "TOPLEFT", x + W, y + 6)
	pane.loadScratch:SetScript("OnClick", function()
		local d = state.detected
		if d and ns.Planner.LoadInto(d.classID, d.ranks, "scratch") then ns.Window.Show("planner") end
	end)
	pane.loadB = UI.Button(f, L["Load as build B (compare)"], "default")
	pane.loadB:SetPoint("RIGHT", pane.loadScratch, "LEFT", -10, 0)
	pane.loadB:SetScript("OnClick", function()
		local d = state.detected
		if not d then return end
		ns.charDB.imported = { classID = d.classID, ranks = d.ranks, label = L["Imported"] }
		ns.Window.Show("compare")
	end)
	y = y - 64

	local sendLabel = UI.Label(f, "Send in game")
	sendLabel:SetPoint("TOPLEFT", x, y)
	y = y - 28
	pane.sendButtons = {}
	local party = UI.Button(f, L["To party"], "default")
	party:SetPoint("TOPLEFT", x, y)
	party:SetScript("OnClick", function() Share.Send(IsInRaid() and "RAID" or "PARTY") end)
	local guild = UI.Button(f, L["To guild"], "default")
	guild:SetPoint("LEFT", party, "RIGHT", 8, 0)
	guild:SetScript("OnClick", function() Share.Send("GUILD") end)
	local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	nameBox:SetSize(160, 28)
	nameBox:SetAutoFocus(false)
	nameBox:SetPoint("LEFT", guild, "RIGHT", 18, 0)
	local whisper = UI.Button(f, L["To player"], "default")
	whisper:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
	whisper:SetScript("OnClick", function()
		local name = strtrim(nameBox:GetText() or "")
		if name ~= "" then Share.Send("WHISPER", name) end
	end)
	pane.sendButtons = { party, guild, whisper }
	pane.sendNote = UI.Text(f, 12, "orange")
	pane.sendNote:SetPoint("LEFT", whisper, "RIGHT", 14, 0)

	pane.Refresh = function()
		refreshExport()
		refreshSend()
		Share.UpdateDetected()
	end
	return pane
end

ns.Window.RegisterPane("share", build)
ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
	if pane and pane.frame:IsShown() then refreshSend() end
end)
