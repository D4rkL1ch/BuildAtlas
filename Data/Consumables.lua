local addonName, ns = ...

-- Consumables checklist per role. Item IDs checked against the Forever
-- 1.60.1.70938 item table (names shown in game come from the client).
ns.Consumables = {
	Physical = {
		{ 13510, "Flask of the Titans", "Raid: big health pool for the whole fight." },
		{ 13452, "Elixir of the Mongoose", "Agility and crit: crits feed your proc talents." },
		{ 9206, "Elixir of Greater Strength", "Strength for Attack Power." },
		{ 12451, "Juju Power", "More Strength; does not stack with Elixir of Greater Strength." },
		{ 12460, "Juju Might", "Attack Power." },
		{ 12820, "Winterfall Firewater", "Attack Power; does not stack with Juju Might." },
		{ 13442, "Mighty Rage Potion", "Warriors: burst Rage and Strength." },
		{ 18262, "Elemental Sharpening Stone", "Weapon crit for one hour." },
		{ 12404, "Dense Sharpening Stone", "Weapon damage if you have no Elemental stones." },
		{ 20452, "Smoked Desert Dumplings", "Strength food." },
		{ 13446, "Major Healing Potion", "Emergency healing." },
	},
	Agility = {
		{ 13510, "Flask of the Titans", "Raid: big health pool for the whole fight." },
		{ 13452, "Elixir of the Mongoose", "Agility and crit." },
		{ 9187, "Elixir of Greater Agility", "Agility if you have no Mongoose." },
		{ 12460, "Juju Might", "Attack Power." },
		{ 18262, "Elemental Sharpening Stone", "Melee weapon crit." },
		{ 13928, "Grilled Squid", "Agility food." },
		{ 13446, "Major Healing Potion", "Emergency healing." },
	},
	Caster = {
		{ 13512, "Flask of Supreme Power", "Raid: spell damage for the whole fight." },
		{ 13454, "Greater Arcane Elixir", "Spell damage." },
		{ 9264, "Elixir of Shadow Power", "Shadow damage (warlocks, shadow priests)." },
		{ 17708, "Elixir of Frost Power", "Frost damage (frost mages)." },
		{ 20749, "Brilliant Wizard Oil", "Spell damage and crit on your weapon." },
		{ 13931, "Nightfin Soup", "Mana regeneration food." },
		{ 13444, "Major Mana Potion", "Mana for long fights." },
		{ 20007, "Mageblood Elixir", "Mana regeneration." },
	},
	Healer = {
		{ 13511, "Flask of Distilled Wisdom", "Raid: a bigger mana pool for the whole fight." },
		{ 20007, "Mageblood Elixir", "Mana regeneration." },
		{ 20748, "Brilliant Mana Oil", "Mana regeneration and healing on your weapon." },
		{ 13931, "Nightfin Soup", "Mana regeneration food." },
		{ 13444, "Major Mana Potion", "Mana for long fights." },
		{ 13813, "Blessed Sunfruit Juice", "Spirit food." },
	},
	Tank = {
		{ 13510, "Flask of the Titans", "Raid: big health pool for the whole fight." },
		{ 13445, "Elixir of Greater Defense", "Armor." },
		{ 9088, "Gift of Arthas", "Shadow resistance and extra damage taken by attackers." },
		{ 20004, "Major Troll's Blood Elixir", "Health regeneration." },
		{ 13455, "Greater Stoneshield Potion", "Big armor boost for hard pulls." },
		{ 21151, "Rumsey Rum Black Label", "Stamina." },
		{ 13446, "Major Healing Potion", "Emergency healing." },
		{ 5634, "Free Action Potion", "Immunity to stuns and roots for a short time." },
	},
}

-- Equipment slots worth an enchant: slot ID -> name.
ns.EnchantSlots = {
	{ 1, "Head" }, { 3, "Shoulder" }, { 5, "Chest" }, { 7, "Legs" }, { 8, "Feet" }, { 9, "Wrist" },
	{ 10, "Hands" }, { 15, "Back" }, { 16, "Main hand" },
}
