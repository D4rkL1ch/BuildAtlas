local addonName, ns = ...

local Util = {}
ns.Util = Util

function Util.Round(x)
	return math.floor(x + 0.5)
end

function Util.CopyShallow(t)
	local out = {}
	if t then
		for k, v in pairs(t) do out[k] = v end
	end
	return out
end

-- Runs fn after `seconds`, or right away when C_Timer is missing.
function Util.After(seconds, fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(seconds, fn)
	else
		fn()
	end
end
