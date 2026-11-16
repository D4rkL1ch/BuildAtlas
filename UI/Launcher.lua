local addonName, ns = ...

-- Ways to open the window. The LibDBIcon minimap button and toasts from
-- design/Launcher.dc.html come later; for now the addon compartment (the
-- addons button by the minimap) and /batlas.

local L = ns.L

ns:RegisterMessage("BA_LOGIN", function()
	if ns.db.settings.showAddonCompartment and AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon({
			text = "Build Atlas",
			icon = "Interface\\Icons\\INV_Misc_Book_11",
			notCheckable = true,
			func = function() ns.Window.Toggle("planner") end,
			funcOnEnter = function(button)
				GameTooltip:SetOwner(button, "ANCHOR_LEFT")
				GameTooltip:SetText("Build Atlas", 1, 1, 1)
				GameTooltip:AddLine(L["Click to open the talent planner."], 0.85, 0.85, 0.85)
				GameTooltip:Show()
			end,
			funcOnLeave = function() GameTooltip:Hide() end,
		})
	end
end)
