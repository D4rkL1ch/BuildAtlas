---@diagnostic disable: undefined-global
-- Offline tests with stubbed WoW APIs. Not shipped.
-- Run: tools\tests\run.ps1   (uses the LuaLS binary as the Lua interpreter)
--
-- The interpreter is newer than WoW's Lua 5.1, so this catches logic errors,
-- not 5.1 syntax issues; LuaLS diagnostics (runtime 5.1) cover those.

local repoRoot = assert(arg and arg[1], "usage: run.lua <repoRoot>")
local testDir = repoRoot .. "/tools/tests/"
local stubs = dofile(testDir .. "wowstubs.lua")

local T = { stubs = stubs }
local failures, passed = 0, 0

function T.test(name, fn)
	stubs.reset()
	local ok, err = pcall(fn)
	if ok and #stubs.errors > 0 then
		ok, err = false, "handler error: " .. tostring(stubs.errors[1])
	end
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		io.write("FAIL ", name, "\n  ", tostring(err), "\n")
	end
end

function T.eq(actual, expected, msg)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(msg or "value", tostring(expected), tostring(actual)), 2)
	end
end

function T.ok(value, msg)
	if not value then error((msg or "expected truthy") .. ", got " .. tostring(value), 2) end
end

function T.contains(haystack, needle, msg)
	if not tostring(haystack):find(needle, 1, true) then
		error(("%s: '%s' not found in:\n%s"):format(msg or "text", needle, tostring(haystack)), 2)
	end
end

-- Load every file listed in the TOC, in order, sharing one namespace table.
function T.loadAddon()
	local ns = {}
	for line in io.lines(repoRoot .. "/BuildAtlas.toc") do
		local file = line:match("^%s*([^#%s][^\r\n]-)%s*$")
		if file then
			local chunk = assert(loadfile(repoRoot .. "/" .. file:gsub("\\", "/")))
			chunk("BuildAtlas", ns)
		end
	end
	return ns
end

-- Load only the pure model files (no events, no frames).
function T.loadModel()
	local ns = { POINTS_PER_TIER = 5, MAX_TALENT_POINTS = 51 }
	for _, file in ipairs({ "Model/Plan.lua", "Model/SynergyGraph.lua" }) do
		assert(loadfile(repoRoot .. "/" .. file))("BuildAtlas", ns)
	end
	return ns
end

function T.boot(savedVars, charVars)
	_G.BuildAtlasDB, _G.BuildAtlasCharDB = savedVars, charVars
	local ns = T.loadAddon()
	stubs.fire("ADDON_LOADED", "SomeOtherAddon")
	stubs.fire("ADDON_LOADED", "BuildAtlas")
	stubs.fire("PLAYER_LOGIN")
	return ns
end

for _, file in ipairs({ "test_plan.lua", "test_synergy.lua", "test_talents.lua", "test_probe.lua", "test_ui.lua", "test_data.lua", "test_m2.lua" }) do
	assert(loadfile(testDir .. file))(T)
end

io.write(("%d passed, %d failed\n"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
