local addonName, ns = ...

-- Options panel in Blizzard's Settings (Esc > Options > AddOns > Build Atlas).

local L = ns.L

local function register()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
	local category = Settings.RegisterVerticalLayoutCategory("Build Atlas")
	local db = ns.db.settings

	local function checkbox(key, label, tooltip, default, onChange)
		local setting = Settings.RegisterAddOnSetting(category, "BuildAtlas_" .. key, key, db, Settings.VarType.Boolean, L[label], default)
		Settings.CreateCheckbox(category, setting, L[tooltip])
		if onChange then
			Settings.SetOnValueChangedCallback("BuildAtlas_" .. key, onChange)
		end
	end

	checkbox("minimapIcon", "Minimap button", "Show the Build Atlas button on the minimap.", true, function() ns.Launcher.UpdateShown() end)
	checkbox("spellTooltips", "Talent info in spell tooltips", "Add which of your talents change a spell to its tooltip (action bars, spellbook).", true)
	checkbox("toasts", "Notices", "Show notices such as \"fight report ready\".", true)
	checkbox("fightToasts", "Fight report notice after combat", "Show a notice with DPS and the talent share after each fight.", true)
	checkbox("levelReminder", "Level-up talent reminder", "After a level-up, say which talent your leveling plan takes next (never learns it for you).", true)

	if Settings.CreateSlider and Settings.CreateSliderOptions then
		local setting = Settings.RegisterAddOnSetting(category, "BuildAtlas_scale", "scale", db, Settings.VarType.Number, L["Window size"], 0.8)
		local options = Settings.CreateSliderOptions(0.5, 1.4, 0.05)
		if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
		end
		Settings.CreateSlider(category, setting, options, L["Size of the Build Atlas window."])
		Settings.SetOnValueChangedCallback("BuildAtlas_scale", function(_, _, value) ns.Window.SetScale(value) end)
	end

	Settings.RegisterAddOnCategory(category)
	ns.SettingsCategory = category
end

ns:RegisterMessage("BA_LOGIN", function()
	local ok, err = pcall(register)
	if not ok then geterrorhandler()(err) end
end)
