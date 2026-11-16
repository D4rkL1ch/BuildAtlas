local addonName, ns = ...

-- Forever classes. specID is the single class-wide "spec" Forever uses for
-- the trait tree (from Blizzard's Camelot talent UI, SpecializationVisuals).
-- Tree IDs are read live via C_ClassTalents.GetTraitTreeForSpec(specID).
ns.Classes = {
	{ classID = 1,  token = "WARRIOR", specID = 1491 },
	{ classID = 2,  token = "PALADIN", specID = 1486 },
	{ classID = 3,  token = "HUNTER",  specID = 1485 },
	{ classID = 4,  token = "ROGUE",   specID = 1488 },
	{ classID = 5,  token = "PRIEST",  specID = 1487 },
	{ classID = 7,  token = "SHAMAN",  specID = 1489 },
	{ classID = 8,  token = "MAGE",    specID = 1482 },
	{ classID = 9,  token = "WARLOCK", specID = 1490 },
	{ classID = 11, token = "DRUID",   specID = 1484 },
}

ns.ClassByID = {}
for _, c in ipairs(ns.Classes) do ns.ClassByID[c.classID] = c end

-- Talent points available at max level.
ns.MAX_TALENT_POINTS = 51
-- Points per tier when the live data has no gate condition.
ns.POINTS_PER_TIER = 5
