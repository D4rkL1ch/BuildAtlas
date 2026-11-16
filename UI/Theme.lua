local addonName, ns = ...

-- Look shared by every window (values from design/Main.dc.html) and small
-- widget helpers. Frames are created in Lua; none use secure templates.

local UI = {}
ns.UI = UI

UI.colors = {
	bgDeep     = "0B0D11",
	window     = "14161B",
	panel      = "181B22",
	panelDark  = "111318",
	bar        = "101217",
	rail       = "0F1115",
	border     = "2C313D",
	borderHi   = "3A4050",
	control    = "232733",
	controlHi  = "2C3140",
	text       = "E7E4DA",
	muted      = "B6BAC4",
	faint      = "9DA3B0",
	gold       = "E0B54A",
	goldLight  = "F3E3B5",
	goldBg     = "2A2416",
	goldEdge   = "7A6327",
	teal       = "4FC3B5",
	tealBg     = "13231F",
	tealEdge   = "2B5A52",
	tealText   = "BFE9E2",
	orange     = "F0A070",
	blue       = "6AA8FF",
	green      = "8FD3A0",
	greenNode  = "5BB974",
	greenBg    = "1F2A24",
	greenBadge = "16241B",
	greenEdge  = "2E5A3B",
	statText   = "B9C7F0",
	statEdge   = "4E5A7A",
	white      = "FFFFFF",
}

-- Game fonts: Morpheus for the Cinzel-like titles, Friz Quadrata (the
-- standard UI font, crisp at small sizes) for everything else.
UI.fonts = {
	title = "Fonts\\MORPHEUS.TTF",
	heading = "Fonts\\FRIZQT__.TTF",
	body = "Fonts\\FRIZQT__.TTF",
}

-- Sizes in the code are the design's CSS pixels; the game renders them much
-- smaller inside a scaled window, so every size goes through this factor.
UI.FONT_SCALE = 1.25

-- Sets font, scaled size and a drop shadow like Blizzard's UI text.
function UI.SetFont(fs, font, size)
	fs:SetFont(UI.fonts[font or "body"], math.floor((size or 13) * UI.FONT_SCALE + 0.5), "")
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetShadowOffset(1, -1)
end

local WHITE = "Interface\\Buttons\\WHITE8X8"

function UI.RGB(hex)
	local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	return r / 255, g / 255, b / 255
end

function UI.Hex(key)
	return UI.colors[key] or key
end

-- "|cffRRGGBBtext|r" for a color key or hex.
function UI.Colorize(text, key)
	return "|cff" .. UI.Hex(key) .. text .. "|r"
end

-- Flat background + 1px (or `edge`) border.
function UI.SetBackdrop(frame, bg, border, edge)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edge or 1 })
	if bg then
		frame:SetBackdropColor(UI.RGB(UI.Hex(bg)))
	else
		frame:SetBackdropColor(0, 0, 0, 0)
	end
	if border then
		frame:SetBackdropBorderColor(UI.RGB(UI.Hex(border)))
	else
		frame:SetBackdropBorderColor(0, 0, 0, 0)
	end
end

function UI.Panel(parent, bg, border, edge)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.SetBackdrop(f, bg, border, edge)
	return f
end

function UI.Text(parent, size, color, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	UI.SetFont(fs, font, size)
	fs:SetTextColor(UI.RGB(UI.Hex(color or "text")))
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

function UI.SetTextColor(fs, color)
	fs:SetTextColor(UI.RGB(UI.Hex(color)))
end

-- Section label: small uppercase muted text.
function UI.Label(parent, text, color)
	local fs = UI.Text(parent, 11, color or "muted", "heading")
	fs:SetText(text:upper())
	return fs
end

-- Plain tooltip on hover. `lines` may be a function returning lines.
function UI.AttachTooltip(frame, title, lines)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		local list = type(lines) == "function" and lines() or lines
		for _, line in ipairs(list or {}) do
			GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true)
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Buttons -------------------------------------------------------------------
-- kind: "default", "primary" (gold), "seg" (segmented toggle), "mini" (+/−),
-- "row" (full-width list row), "chip" (rounded tag).

local STYLES = {
	default = { bg = "control", hover = "controlHi", border = "borderHi", text = "text", size = 13 },
	primary = { bg = "gold", hover = "F0C65C", border = "gold", text = "16130A", size = 13 },
	seg     = { bg = "171A21", hover = "1E222B", border = "borderHi", text = "muted", size = 12,
		onBg = "goldBg", onBorder = "goldEdge", onText = "goldLight" },
	mini    = { bg = "control", hover = "controlHi", border = "borderHi", text = "text", size = 16 },
	row     = { bg = "171A21", hover = "171A21", border = "border", hoverBorder = "teal", text = "text", size = 12 },
	chip    = { bg = "1B1E26", hover = "1B1E26", border = "borderHi", hoverBorder = "teal", text = "D6D3C9", size = 12 },
	stat    = { bg = "1B1E26", hover = "1B1E26", border = "statEdge", text = "statText", size = 12 },
}

local ButtonMixin = {}

function ButtonMixin:ApplyLook()
	local s = self.style
	local on = self.isOn and s.onBg
	local bg = on and s.onBg or (self.hovered and self:IsEnabled() and s.hover or s.bg)
	local border = on and s.onBorder or (self.hovered and self:IsEnabled() and s.hoverBorder or s.border)
	UI.SetBackdrop(self, bg, border)
	local textColor = on and s.onText or s.text
	UI.SetTextColor(self.Label, textColor)
	self.Label:SetAlpha(self:IsEnabled() and 1 or 0.45)
end

function ButtonMixin:SetOn(on)
	self.isOn = on and true or false
	self:ApplyLook()
end

function ButtonMixin:SetLabel(text)
	self.Label:SetText(text)
end

-- Width to fit the label plus padding.
function ButtonMixin:FitWidth(pad)
	self:SetWidth(self.Label:GetStringWidth() + (pad or 28))
end

function ButtonMixin:SetEnabledState(enabled)
	self:SetEnabled(enabled)
	self:ApplyLook()
end

function UI.Button(parent, text, kind, width, height)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b.style = STYLES[kind or "default"]
	for k, fn in pairs(ButtonMixin) do b[k] = fn end
	b.Label = UI.Text(b, b.style.size, b.style.text, "body", kind == "row" and "LEFT" or "CENTER")
	if kind == "row" then
		b.Label:SetPoint("LEFT", 10, 0)
		b.Right = UI.Text(b, 12, "muted", "body", "RIGHT")
		b.Right:SetPoint("RIGHT", -10, 0)
		b.Label:SetPoint("RIGHT", b.Right, "LEFT", -8, 0)
	else
		b.Label:SetPoint("CENTER")
	end
	b:SetLabel(text or "")
	b:SetSize(width or (kind == "mini" and 28 or 100), height or (kind == "seg" and 28 or kind == "mini" and 28 or kind == "chip" and 24 or 32))
	if not width and kind ~= "mini" then b:FitWidth() end
	b:SetScript("OnEnter", function(self) self.hovered = true self:ApplyLook() end)
	b:SetScript("OnLeave", function(self) self.hovered = false self:ApplyLook() end)
	b:ApplyLook()
	return b
end

-- A pool of widgets made by `create(parent)`. Acquire() returns a shown one;
-- ReleaseAll() hides them all for reuse.
function UI.Pool(parent, create)
	local pool = { used = 0, items = {} }
	function pool:Acquire()
		self.used = self.used + 1
		local item = self.items[self.used]
		if not item then
			item = create(parent)
			self.items[self.used] = item
		end
		item:ClearAllPoints()
		item:Show()
		return item
	end
	function pool:ReleaseAll()
		for i = 1, #self.items do self.items[i]:Hide() end
		self.used = 0
	end
	return pool
end
