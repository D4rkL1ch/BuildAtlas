local addonName, ns = ...

-- Stat weights and item scores. Pure: no WoW globals.
-- Stat names are our own ("Strength", "Crit", ...); item stats from
-- C_Item.GetItemStats (ITEM_MOD_* keys) and Pawn / SimC names map onto them.

local StatWeights = {}
ns.StatWeights = StatWeights

StatWeights.STATS = {
	"Strength", "Agility", "Stamina", "Intellect", "Spirit", "Attack power", "Spell power", "Healing power",
	"Crit", "Hit", "Haste", "Weapon DPS", "Armor", "Defense", "Dodge", "Parry", "Block", "Block value",
}

-- Rough starting points per role, per point of stat (crit/hit per 1%).
local BASE = {
	Physical = { Strength = 1.0, Agility = 0.8, Stamina = 0.1, ["Attack power"] = 0.45, Crit = 10, Hit = 9, Haste = 7, ["Weapon DPS"] = 3 },
	Agility = { Strength = 0.5, Agility = 1.0, Stamina = 0.1, ["Attack power"] = 0.5, Crit = 10, Hit = 9, Haste = 7, ["Weapon DPS"] = 3 },
	Caster = { Intellect = 0.4, Spirit = 0.1, Stamina = 0.05, ["Spell power"] = 1.0, Crit = 8, Hit = 9, Haste = 7 },
	Healer = { Intellect = 0.5, Spirit = 0.4, Stamina = 0.05, ["Healing power"] = 1.0, ["Spell power"] = 0.3, Crit = 5, Haste = 6 },
	Tank = { Stamina = 1.0, Strength = 0.5, Agility = 0.6, Armor = 0.06, Defense = 1.2, Dodge = 10, Parry = 9, Block = 6, ["Block value"] = 0.5, Hit = 4 },
}
StatWeights.ROLES = { "Physical", "Agility", "Caster", "Healer", "Tank" }

-- Talent stat chips that map onto weight names.
local LEAN_MAP = {
	Crit = "Crit", ["Spell crit"] = "Crit", Hit = "Hit", ["Spell hit"] = "Hit", Haste = "Haste", ["Attack speed"] = "Haste",
	Strength = "Strength", Agility = "Agility", Stamina = "Stamina", Intellect = "Intellect", Spirit = "Spirit",
	["Attack power"] = "Attack power", ["Spell power"] = "Spell power", ["Healing power"] = "Healing power",
	["Weapon damage"] = "Weapon DPS", Armor = "Armor", Defense = "Defense", Dodge = "Dodge", Parry = "Parry",
	Block = "Block", ["Block value"] = "Block value",
}

-- Role from the plan's stat lean (Compare.Lean list) and class token.
function StatWeights.GuessRole(lean, classToken)
	local score = {}
	for _, s in ipairs(lean or {}) do score[s.stat] = (score[s.stat] or 0) + s.a end
	local tank = (score.Block or 0) + (score.Defense or 0) + (score.Parry or 0) + (score.Dodge or 0) + (score.Armor or 0)
	local heal = score["Healing power"] or 0
	local spell = (score["Spell power"] or 0) + (score["Spell crit"] or 0) + (score["Spell hit"] or 0)
	local phys = (score["Weapon damage"] or 0) + (score.Crit or 0) + (score["Attack power"] or 0) + (score.Hit or 0)
	if tank >= 3 and tank >= phys then return "Tank" end
	if heal >= 2 and heal >= spell then return "Healer" end
	if spell > phys then return "Caster" end
	if classToken == "ROGUE" or classToken == "HUNTER" then return "Agility" end
	if classToken == "MAGE" or classToken == "WARLOCK" or classToken == "PRIEST" then return "Caster" end
	return "Physical"
end

-- Own estimate: role base, nudged up by stats the talents lean on (max +50%).
function StatWeights.Estimate(role, lean)
	local w = {}
	for k, v in pairs(BASE[role] or BASE.Physical) do w[k] = v end
	for _, s in ipairs(lean or {}) do
		local name = LEAN_MAP[s.stat]
		if name and w[name] then w[name] = w[name] * (1 + math.min(0.5, 0.1 * s.a)) end
	end
	return w
end

-- Names used by Pawn and SimC, lower-cased, to ours.
local ALIASES = {
	strength = "Strength", str = "Strength", agility = "Agility", agi = "Agility", stamina = "Stamina", sta = "Stamina",
	intellect = "Intellect", int = "Intellect", spirit = "Spirit", spi = "Spirit",
	ap = "Attack power", attackpower = "Attack power", rap = "Attack power", feralap = "Attack power",
	spelldamage = "Spell power", spellpower = "Spell power", sp = "Spell power", healing = "Healing power",
	crit = "Crit", critrating = "Crit", meleecrit = "Crit", spellcrit = "Crit",
	hit = "Hit", hitrating = "Hit", meleehit = "Hit", spellhit = "Hit",
	haste = "Haste", hasterating = "Haste",
	dps = "Weapon DPS", meleedps = "Weapon DPS", weapondps = "Weapon DPS", wdps = "Weapon DPS",
	armor = "Armor", defense = "Defense", defenserating = "Defense", dodge = "Dodge", dodgerating = "Dodge",
	parry = "Parry", parryrating = "Parry", block = "Block", blockrating = "Block", blockvalue = "Block value",
}

-- Parses a Pawn scale tag "( Pawn: v1: "Name": Strength=1, ... )" or any
-- "Name=value" list (SimC weights). Returns weights, name or nil.
function StatWeights.Parse(text)
	if not text or text == "" then return nil end
	local name = text:match('Pawn:%s*v%d+:%s*"([^"]+)"')
	local w, n = {}, 0
	for key, value in text:gmatch("([%a_]+)%s*=%s*(%-?[%d%.]+)") do
		local stat = ALIASES[key:lower():gsub("_", "")]
		local v = tonumber(value)
		if stat and v then
			w[stat] = v
			n = n + 1
		end
	end
	if n == 0 then return nil end
	return w, name
end

-- Pawn scale tag for our weights (Pawn's stat names).
local TO_PAWN = {
	Strength = "Strength", Agility = "Agility", Stamina = "Stamina", Intellect = "Intellect", Spirit = "Spirit",
	["Attack power"] = "Ap", ["Spell power"] = "SpellDamage", ["Healing power"] = "Healing", Crit = "CritRating",
	Hit = "HitRating", Haste = "HasteRating", ["Weapon DPS"] = "Dps", Armor = "Armor", Defense = "DefenseRating",
	Dodge = "DodgeRating", Parry = "ParryRating", Block = "BlockRating", ["Block value"] = "BlockValue",
}
function StatWeights.ToPawn(weights, name)
	local parts = {}
	for _, stat in ipairs(StatWeights.STATS) do
		if weights[stat] and TO_PAWN[stat] then
			parts[#parts + 1] = ("%s=%s"):format(TO_PAWN[stat], (("%.3f"):format(weights[stat]):gsub("0+$", ""):gsub("%.$", "")))
		end
	end
	return ('( Pawn: v1: "%s": %s )'):format(name, table.concat(parts, ", "))
end

-- C_Item.GetItemStats keys (ITEM_MOD_STRENGTH_SHORT, ...) to our stats.
local ITEM_KEYS = {
	{ "STRENGTH", "Strength" }, { "AGILITY", "Agility" }, { "STAMINA", "Stamina" }, { "INTELLECT", "Intellect" },
	{ "SPIRIT", "Spirit" }, { "RANGED_ATTACK_POWER", "Attack power" }, { "ATTACK_POWER", "Attack power" },
	{ "HEALING", "Healing power" }, { "SPELL_DAMAGE", "Spell power" }, { "SPELL_POWER", "Spell power" },
	{ "CRIT", "Crit" }, { "HIT", "Hit" }, { "HASTE", "Haste" }, { "DAMAGE_PER_SECOND", "Weapon DPS" },
	{ "RESISTANCE0", "Armor" }, { "ARMOR", "Armor" }, { "DEFENSE", "Defense" }, { "DODGE", "Dodge" },
	{ "PARRY", "Parry" }, { "BLOCK_VALUE", "Block value" }, { "BLOCK", "Block" },
}
function StatWeights.StatOfItemKey(key)
	for _, pair in ipairs(ITEM_KEYS) do
		if key:find(pair[1], 1, true) then return pair[2] end
	end
end

-- Score of an item's stats table (as GetItemStats returns it).
function StatWeights.Score(itemStats, weights)
	local score = 0
	for key, value in pairs(itemStats or {}) do
		local stat = type(key) == "string" and StatWeights.StatOfItemKey(key)
		if stat and weights[stat] and type(value) == "number" then score = score + value * weights[stat] end
	end
	return score
end
