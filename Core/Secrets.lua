local addonName, ns = ...

-- Every combat-time read goes through here. Secret values (Midnight-era
-- "addon disarmament") can be displayed by Blizzard widgets but must not be
-- compared, concatenated, stored or used as table keys by addon code.

local Secrets = {}
ns.Secrets = Secrets

local issecret = issecretvalue

function Secrets.IsSecret(value)
	return issecret ~= nil and issecret(value) or false
end

-- Calls fn(...) and returns its first result, or `fallback` if the call
-- errors or the result is secret. Never throws.
function Secrets.Read(fallback, fn, ...)
	if type(fn) ~= "function" then return fallback end
	local ok, value = pcall(fn, ...)
	if not ok or Secrets.IsSecret(value) then return fallback end
	return value
end

-- Like Read, but returns every result, each one replaced by `fallback` when
-- secret. The first return is whether the call itself succeeded.
function Secrets.ReadAll(fallback, fn, ...)
	if type(fn) ~= "function" then return false end
	local results = { pcall(fn, ...) }
	if not results[1] then return false end
	for i = 2, #results do
		if Secrets.IsSecret(results[i]) then results[i] = fallback end
	end
	return unpack(results)
end

-- A copy of `value` that is safe to keep in SavedVariables: secrets become
-- the string "<secret>", functions and userdata their type name, and tables
-- are copied to `depth` levels.
function Secrets.Sanitize(value, depth)
	if Secrets.IsSecret(value) then return "<secret>" end
	local t = type(value)
	if t == "table" then
		depth = depth or 4
		if depth <= 0 then return "<table>" end
		local out = {}
		for k, v in pairs(value) do
			if not Secrets.IsSecret(k) and (type(k) == "string" or type(k) == "number") then
				out[k] = Secrets.Sanitize(v, depth - 1)
			end
		end
		return out
	elseif t == "function" or t == "userdata" or t == "thread" then
		return "<" .. t .. ">"
	end
	return value
end

function Secrets.InCombat()
	return InCombatLockdown() and true or false
end
