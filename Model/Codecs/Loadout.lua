local addonName, ns = ...

-- Blizzard's talent loadout string (Blizzard_ClassTalentImportExport.lua,
-- serialization version 2 on Forever). Pure Lua, no WoW globals.
--
-- Bits are packed least-significant first into 6-bit characters of the
-- alphabet A-Z a-z 0-9 + / (not standard base64 byte order).
--   header:  version (8), specID (16), tree hash (16 x 8)
--   per node, in C_Traits.GetTreeNodes order (ascending nodeID):
--     selected (1) [ purchased (1) [ partial (1) [ranks (6)] choice (1) [index (2)] ] ]

local Codecs = ns.Codecs or {}
ns.Codecs = Codecs

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHAR_VALUE = {}
for i = 1, #ALPHABET do CHAR_VALUE[ALPHABET:sub(i, i)] = i - 1 end

-- Writer ---------------------------------------------------------------------

local Writer = {}
Writer.__index = Writer

local function newWriter()
	return setmetatable({ chars = {}, current = 0, used = 0 }, Writer)
end

function Writer:Add(bits, value)
	assert(value >= 0 and value < 2 ^ bits, "value does not fit")
	for _ = 1, bits do
		local bit = value % 2
		value = (value - bit) / 2
		self.current = self.current + bit * 2 ^ self.used
		self.used = self.used + 1
		if self.used == 6 then
			self.chars[#self.chars + 1] = ALPHABET:sub(self.current + 1, self.current + 1)
			self.current, self.used = 0, 0
		end
	end
end

function Writer:String()
	local out = table.concat(self.chars)
	if self.used > 0 then out = out .. ALPHABET:sub(self.current + 1, self.current + 1) end
	return out
end

-- Reader ---------------------------------------------------------------------

local Reader = {}
Reader.__index = Reader

local function newReader(text)
	local values = {}
	for i = 1, #text do
		local v = CHAR_VALUE[text:sub(i, i)]
		if v == nil then return nil end
		values[i] = v
	end
	return setmetatable({ values = values, index = 1, bit = 0 }, Reader)
end

function Reader:Bits()
	return #self.values * 6
end

-- Nil when the stream runs out.
function Reader:Get(bits)
	local value = 0
	for i = 0, bits - 1 do
		local v = self.values[self.index]
		if v == nil then return nil end
		local bit = math.floor(v / 2 ^ self.bit) % 2
		value = value + bit * 2 ^ i
		self.bit = self.bit + 1
		if self.bit == 6 then
			self.index, self.bit = self.index + 1, 0
		end
	end
	return value
end

-- Raw encode/decode ---------------------------------------------------------------

-- loadout = { version, specID, hash = {16 bytes} or nil, nodes = { {
--   selected, purchased, ranks, maxRanks, choiceIndex (1-based or nil) }, ... } }
function Codecs.EncodeLoadout(loadout)
	local w = newWriter()
	w:Add(8, loadout.version)
	w:Add(16, loadout.specID)
	for i = 1, 16 do w:Add(8, loadout.hash and loadout.hash[i] or 0) end
	for _, n in ipairs(loadout.nodes) do
		w:Add(1, n.selected and 1 or 0)
		if n.selected then
			w:Add(1, n.purchased and 1 or 0)
			if n.purchased then
				local partial = n.ranks ~= n.maxRanks
				w:Add(1, partial and 1 or 0)
				if partial then w:Add(6, n.ranks) end
				w:Add(1, n.choiceIndex and 1 or 0)
				if n.choiceIndex then w:Add(2, n.choiceIndex - 1) end
			end
		end
	end
	return w:String()
end

-- Returns the loadout with nodes = { { selected, purchased, ranks (nil =
-- max), choiceIndex }, ... } for `nodeCount` nodes, or nil and a reason.
function Codecs.DecodeLoadout(text, nodeCount)
	text = (text or ""):gsub("%s", "")
	local r = newReader(text)
	if not r then return nil, "chars" end
	if r:Bits() < 8 + 16 + 128 then return nil, "short" end
	local loadout = { version = r:Get(8), specID = r:Get(16), hash = {}, nodes = {} }
	for i = 1, 16 do loadout.hash[i] = r:Get(8) end
	for i = 1, nodeCount do
		local selected = r:Get(1)
		if selected == nil then return nil, "truncated" end
		local n = { selected = selected == 1 }
		if n.selected then
			n.purchased = r:Get(1) == 1
			if n.purchased then
				if r:Get(1) == 1 then n.ranks = r:Get(6) end
				if r:Get(1) == 1 then n.choiceIndex = (r:Get(2) or 0) + 1 end
			end
		end
		loadout.nodes[i] = n
	end
	return loadout
end

-- Plans <-> loadout strings ------------------------------------------------------

-- `tree` needs nodeOrder (every node ID of the tree, ascending, as
-- C_Traits.GetTreeNodes returns them), talents, specID. Free nodes are
-- written as granted once their tier is reached.
function Codecs.PlanToLoadout(tree, ranks, version, hash)
	local _, perGroup = ns.Plan.Spent(tree, ranks)
	local nodes = {}
	for i, nodeID in ipairs(tree.nodeOrder) do
		local t = tree.talents[nodeID]
		local r = ranks[nodeID] or 0
		if t and t.free then
			nodes[i] = { selected = ns.Plan.IsGranted(tree, ranks, nodeID, perGroup), purchased = false }
		elseif t and r > 0 then
			nodes[i] = { selected = true, purchased = true, ranks = r, maxRanks = t.maxRanks }
		else
			nodes[i] = { selected = false }
		end
	end
	return Codecs.EncodeLoadout({ version = version or 2, specID = tree.specID, hash = hash, nodes = nodes })
end

-- Returns ranks, loadout or nil and a reason ("chars", "short", "truncated",
-- "class": string is for another class's tree).
function Codecs.LoadoutToPlan(tree, text)
	local loadout, why = Codecs.DecodeLoadout(text, #tree.nodeOrder)
	if not loadout then return nil, why end
	if tree.specID and loadout.specID ~= tree.specID then return nil, "class", loadout end
	local ranks = {}
	for i, nodeID in ipairs(tree.nodeOrder) do
		local n = loadout.nodes[i]
		local t = tree.talents[nodeID]
		if n and n.purchased and t and not t.free then
			ranks[nodeID] = math.min(n.ranks or t.maxRanks, t.maxRanks)
		end
	end
	return ranks, loadout
end

-- Spec ID in a loadout string, to pick the class before decoding.
function Codecs.LoadoutSpecID(text)
	local r = newReader((text or ""):gsub("%s", ""))
	if not r or r:Bits() < 24 then return nil end
	local version = r:Get(8)
	return r:Get(16), version
end
