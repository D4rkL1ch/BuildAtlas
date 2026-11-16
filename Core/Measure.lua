local addonName, ns = ...

-- Fight capture from the game's damage meter, after combat only (combat
-- values are secret to addons). Each fight stores the player's per-spell
-- damage, the talents of the active spec and a gear fingerprint.
-- Benchmark runs are fights captured while a run is armed.

local L = ns.L
local Secrets = ns.Secrets

local Measure = {}
ns.Measure = Measure

local MAX_FIGHTS = 30
local MAX_RUNS = 60
local CAPTURE_DELAY = 1.5

-- "1:12" for 72 seconds.
function Measure.Clock(seconds)
	seconds = math.floor((seconds or 0) + 0.5)
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- Gear fingerprint: the equipped item IDs (slots 1-19), so benchmark runs
-- with different gear can be left out of averages.
function Measure.GearKey()
	local ids = {}
	for slot = 1, 19 do
		ids[slot] = tostring(Secrets.Read(0, GetInventoryItemID, "player", slot) or 0)
	end
	return table.concat(ids, ".")
end

-- Talent ranks of the active spec keyed by talent spellID (what the data
-- and attribution use), plus a label like "Spec 1 · Arms 31/20/0".
function Measure.TalentSnapshot()
	local classID = ns.Talents.PlayerClassID()
	local tree = ns.Talents.ReadTree(classID)
	if not tree then return {}, "?" end
	local group = ns.Talents.GetActiveSpecGroup()
	local ranks = ns.Talents.ReadRanks(tree, ns.Talents.GetSpecConfigID(group)) or {}
	local bySpell = {}
	for id, r in pairs(ranks) do
		local t = tree.talents[id]
		if t and t.spellID then bySpell[t.spellID] = r end
	end
	local _, perGroup = ns.Plan.Spent(tree, ranks)
	local best = 1
	for i = 2, #perGroup do
		if perGroup[i] > perGroup[best] then best = i end
	end
	local label = ("%s %d · %s %s"):format(L["Spec"], group, tree.groups[best] and tree.groups[best].name or "?", table.concat(perGroup, "/"))
	return bySpell, label, ranks
end

-- Reads one damage meter session for the player. Nil when unavailable or
-- anything is secret.
function Measure.ReadSession(sessionID)
	if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromID) then return nil end
	local damageDone = Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
	local guid = UnitGUID("player")
	local source = Secrets.Read(nil, C_DamageMeter.GetCombatSessionSourceFromID, sessionID, damageDone, guid)
	if not source or type(source.combatSpells) ~= "table" then return nil end
	local spells, total = {}, 0
	for _, sp in ipairs(source.combatSpells) do
		local id, amount = sp.spellID, sp.totalAmount
		if Secrets.IsSecret(id) or Secrets.IsSecret(amount) then return nil end
		if type(id) == "number" and type(amount) == "number" and amount > 0 then
			spells[id] = (spells[id] or 0) + amount
			total = total + amount
		end
	end
	return spells, total
end

local function latestSession()
	local sessions = Secrets.Read(nil, C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions)
	if type(sessions) ~= "table" then return nil end
	local latest
	for _, s in ipairs(sessions) do
		if type(s.sessionID) == "number" and (not latest or s.sessionID > latest.sessionID) then latest = s end
	end
	return latest
end

-- Captures the newest finished session once. Returns the stored fight or nil.
function Measure.Capture()
	if InCombatLockdown() then return nil end
	local session = latestSession()
	if not session or session.sessionID == ns.charDB.lastSessionID then return nil end
	local spells, total = Measure.ReadSession(session.sessionID)
	if not spells or total <= 0 then return nil end
	ns.charDB.lastSessionID = session.sessionID
	local talents, label, ranks = Measure.TalentSnapshot()
	local duration = session.durationSeconds
	if Secrets.IsSecret(duration) or type(duration) ~= "number" or duration <= 0 then duration = nil end
	local name = session.name
	if Secrets.IsSecret(name) or type(name) ~= "string" or name == "" then name = L["Fight"] end
	local fight = {
		id = session.sessionID, name = name, duration = duration or 1, total = total,
		dps = total / (duration or 1), spells = spells, time = time(),
		classID = ns.Talents.PlayerClassID(), talents = talents, ranks = ranks, build = label,
		gear = Measure.GearKey(),
	}
	local fights = ns.charDB.fights
	table.insert(fights, 1, fight)
	while #fights > MAX_FIGHTS do table.remove(fights) end
	ns:SendMessage("BA_FIGHT", fight)
	return fight
end

function Measure.Estimate(fight)
	local classData = ns.ClassData and ns.ClassData[fight.classID]
	if not classData then return { rows = {}, total = fight.total, fromTalents = 0, share = 0 } end
	return ns.Attribution.Estimate(fight, classData, fight.talents or {})
end

-- Benchmark ---------------------------------------------------------------------

-- Arm a run: length in seconds, tag = build label. It starts when combat
-- starts and is recorded when combat ends.
function Measure.Arm(length, tag)
	ns.charDB.armed = { length = length, tag = tag, armedAt = time() }
	ns:SendMessage("BA_BENCH_CHANGED")
end

function Measure.Disarm()
	ns.charDB.armed = nil
	ns:SendMessage("BA_BENCH_CHANGED")
end

function Measure.Runs()
	ns.db.bench = ns.db.bench or {}
	return ns.db.bench
end

function Measure.DeleteRun(index)
	table.remove(Measure.Runs(), index)
	ns:SendMessage("BA_BENCH_CHANGED")
end

local function recordRun(fight)
	local armed = ns.charDB.armed
	if not armed or not armed.started then return end
	local run = {
		tag = armed.tag, length = armed.length, duration = fight.duration, dps = fight.dps,
		gear = fight.gear, time = fight.time, classID = fight.classID, fight = fight.id,
	}
	local runs = Measure.Runs()
	table.insert(runs, 1, run)
	while #runs > MAX_RUNS do table.remove(runs) end
	ns.charDB.armed = nil
	ns:SendMessage("BA_BENCH_CHANGED")
	local off = math.abs(fight.duration - armed.length) / armed.length
	local note = off > 0.2 and (L[" (ran %d sec instead of %d)"]):format(math.floor(fight.duration + 0.5), armed.length) or ""
	ns.Toasts.Show("info", L["Benchmark run recorded"], ("%s · %.0f DPS%s"):format(run.tag, run.dps, note), {
		text = L["Open benchmark"], run = function() ns.Window.Show("bench") end,
	})
end

-- Events ---------------------------------------------------------------------------

ns:RegisterMessage("BA_LOADED", function()
	ns.charDB.fights = ns.charDB.fights or {}
	if ns.charDB.armed then ns.charDB.armed.started = nil end
end)

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	local armed = ns.charDB and ns.charDB.armed
	if armed and not armed.started then armed.started = time() end
end)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	ns.Util.After(CAPTURE_DELAY, function()
		local fight = Measure.Capture()
		if not fight then return end
		if ns.charDB.armed and ns.charDB.armed.started then
			recordRun(fight)
		elseif ns.db.settings.fightToasts ~= false and fight.duration >= 5 then
			local est = Measure.Estimate(fight)
			ns.Toasts.Show("info", L["Fight report ready"],
				("%s · %s · %.0f DPS · %d%% %s"):format(fight.name, Measure.Clock(fight.duration), fight.dps,
					math.floor(est.share * 100 + 0.5), L["from talents (est.)"]),
				{ text = L["Open report"], run = function() ns.Window.Show("report") end })
		end
	end)
end)
