-- Stand-ins for globals Blizzard's own Lua and XML define (FrameXML), plus XML templates.
--
-- MODELS[name] builds the value of one global. The mock installs it only when the flavor's data
-- file lists the name under `fxml`, which api_matrix.py --generate fills from the branch's
-- source. TEMPLATES[name] runs on a frame created with that template, again only when the
-- branch defines it. To model something new: add an entry with the exact signature
-- "\tName = function(M)" or "\tName = function(M, frame)" (the generator matches it), then run
-- "python Tests/Nameplates/api_matrix.py --generate".

local MODELS = {}
local TEMPLATES = {}

local function copy(t, seen)
	if type(t) ~= 'table' then
		return t
	end
	seen = seen or {}
	if seen[t] then
		return seen[t]
	end
	local out = {}
	seen[t] = out
	for k, v in pairs(t) do
		out[copy(k, seen)] = copy(v, seen)
	end
	return out
end

local function Mixin(object, ...)
	for i = 1, select('#', ...) do
		local mixin = select(i, ...)
		for k, v in pairs(mixin) do
			object[k] = v
		end
	end
	return object
end

local function NewColor(M, r, g, b, a)
	local color = Mixin({}, M.ColorMixin)
	color:SetRGBA(r, g, b, a)
	return color
end

MODELS = {
	UIParent = function(M)
		local f = M.NewObject('Frame', 'UIParent')
		M.Set(f, 'w', 1920)
		M.Set(f, 'h', 1080)
		return f
	end,
	WorldFrame = function(M)
		local f = M.NewObject('Frame', 'WorldFrame')
		M.Set(f, 'w', 1920)
		M.Set(f, 'h', 1080)
		return f
	end,
	GameTooltip = function(M)
		local tip = M.NewObject('GameTooltip', 'GameTooltip', _G.UIParent)
		tip:Hide()
		return tip
	end,
	DEFAULT_CHAT_FRAME = function(M)
		local chat = M.NewObject('MessageFrame', 'ChatFrame1', _G.UIParent)
		M.chat = M.chat or {}
		-- AddMessage is a documented MessageFrame method; this records what was written
		M.Override(chat, 'AddMessage', function(_, text)
			M.chat[#M.chat + 1] = tostring(text)
		end)
		return chat
	end,
	NamePlateDriverFrame = function(M)
		local driver = M.NewObject('Frame', 'NamePlateDriverFrame', _G.UIParent)
		M.Set(driver, 'w', 0)
		driver.UpdateNamePlateOptions = function(self)
			M.Log(self, 'UpdateNamePlateOptions')
		end
		driver.SetBaseNamePlateSize = function(self, w, h)
			M.Log(self, 'SetBaseNamePlateSize', w, h)
		end
		driver.GetBaseNamePlateWidth = function()
			return 110
		end
		driver.GetBaseNamePlateHeight = function()
			return 45
		end
		return driver
	end,
	Mixin = function(M)
		return Mixin
	end,
	CreateFromMixins = function(M)
		return function(...)
			return Mixin({}, ...)
		end
	end,
	CreateAndInitFromMixin = function(M)
		return function(mixin, ...)
			local object = Mixin({}, mixin)
			object:Init(...)
			return object
		end
	end,
	CopyTable = function(M)
		return function(t, shallow)
			if shallow then
				local out = {}
				for k, v in pairs(t) do
					out[k] = v
				end
				return out
			end
			return copy(t)
		end
	end,
	tContains = function(M)
		return function(t, value)
			for _, v in pairs(t) do
				if v == value then
					return true
				end
			end
			return false
		end
	end,
	tInvert = function(M)
		return function(t)
			local out = {}
			for k, v in pairs(t) do
				out[v] = k
			end
			return out
		end
	end,
	tIndexOf = function(M)
		return function(t, value)
			for i, v in ipairs(t) do
				if v == value then
					return i
				end
			end
		end
	end,
	tDeleteItem = function(M)
		return function(t, value)
			local removed = 0
			for i = #t, 1, -1 do
				if t[i] == value then
					table.remove(t, i)
					removed = removed + 1
				end
			end
			return removed
		end
	end,
	Round = function(M)
		return function(v)
			if v < 0 then
				return math.ceil(v - 0.5)
			end
			return math.floor(v + 0.5)
		end
	end,
	Clamp = function(M)
		return function(v, lo, hi)
			if v < lo then
				return lo
			elseif v > hi then
				return hi
			end
			return v
		end
	end,
	Saturate = function(M)
		return function(v)
			return math.max(0, math.min(1, v))
		end
	end,
	Lerp = function(M)
		return function(a, b, t)
			return a + (b - a) * t
		end
	end,
	ColorMixin = function(M)
		return M.ColorMixin
	end,
	CreateColor = function(M)
		return function(r, g, b, a)
			return NewColor(M, r, g, b, a)
		end
	end,
	CreateColorFromHexString = function(M)
		return function(hex)
			local a, r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), tonumber(hex:sub(7, 8), 16)
			return NewColor(M, r / 255, g / 255, b / 255, a / 255)
		end
	end,
	-- Stand-in colors; suites should not assert exact class color values
	RAID_CLASS_COLORS = function(M)
		local out = {}
		local list = {
			WARRIOR = { 0.78, 0.61, 0.43 },
			PALADIN = { 0.96, 0.55, 0.73 },
			HUNTER = { 0.67, 0.83, 0.45 },
			ROGUE = { 1, 0.96, 0.41 },
			PRIEST = { 1, 1, 1 },
			SHAMAN = { 0, 0.44, 0.87 },
			MAGE = { 0.25, 0.78, 0.92 },
			WARLOCK = { 0.53, 0.53, 0.93 },
			DRUID = { 1, 0.49, 0.04 },
			DEATHKNIGHT = { 0.77, 0.12, 0.23 },
			MONK = { 0, 1, 0.6 },
		}
		for class, rgb in pairs(list) do
			local c = NewColor(M, rgb[1], rgb[2], rgb[3], 1)
			c.colorStr = c:GenerateHexColor()
			out[class] = c
		end
		return out
	end,
	STANDARD_TEXT_FONT = function(M)
		return 'Fonts\\FRIZQT__.TTF'
	end,
	UNIT_NAME_FONT = function(M)
		return 'Fonts\\FRIZQT__.TTF'
	end,
	DAMAGE_TEXT_FONT = function(M)
		return 'Fonts\\FRIZQT__.TTF'
	end,
	NAMEPLATE_FONT = function(M)
		return 'Fonts\\FRIZQT__.TTF'
	end,
	SystemFont_NamePlate = function(M)
		return M.NewFont('SystemFont_NamePlate', 9)
	end,
	SystemFont_NamePlateFixed = function(M)
		return M.NewFont('SystemFont_NamePlateFixed', 9)
	end,
	SystemFont_LargeNamePlate = function(M)
		return M.NewFont('SystemFont_LargeNamePlate', 12)
	end,
	SystemFont_LargeNamePlateFixed = function(M)
		return M.NewFont('SystemFont_LargeNamePlateFixed', 12)
	end,
	SystemFont_NamePlateCastBar = function(M)
		return M.NewFont('SystemFont_NamePlateCastBar', 9)
	end,
	SystemFont_Outline_Small = function(M)
		return M.NewFont('SystemFont_Outline_Small', 10, 'OUTLINE')
	end,
	SystemFont_Shadow_Small = function(M)
		return M.NewFont('SystemFont_Shadow_Small', 10)
	end,
	GameFontNormal = function(M)
		return M.NewFont('GameFontNormal', 12)
	end,
	GameFontNormalSmall = function(M)
		return M.NewFont('GameFontNormalSmall', 10)
	end,
	GameFontHighlight = function(M)
		return M.NewFont('GameFontHighlight', 12)
	end,
	GameFontHighlightSmall = function(M)
		return M.NewFont('GameFontHighlightSmall', 10)
	end,
	NumberFontNormal = function(M)
		return M.NewFont('NumberFontNormal', 14, 'OUTLINE')
	end,
	NumberFontNormalSmall = function(M)
		return M.NewFont('NumberFontNormalSmall', 12, 'OUTLINE')
	end,
	SetCVar = function(M)
		return function(name, value, eventName)
			return C_CVar.SetCVar(name, value, eventName)
		end
	end,
	GetCVar = function(M)
		return function(name)
			return C_CVar.GetCVar(name)
		end
	end,
	GetCVarBool = function(M)
		return function(name)
			return C_CVar.GetCVarBool(name)
		end
	end,
	GetCVarDefault = function(M)
		return function(name)
			return C_CVar.GetCVarDefault(name)
		end
	end,
	SetCVarBitfield = function(M)
		return function(name, index, value, scriptCVar)
			return C_CVar.SetCVarBitfield(name, index, value, scriptCVar)
		end
	end,
	GetCVarBitfield = function(M)
		return function(name, index)
			return C_CVar.GetCVarBitfield(name, index)
		end
	end,
	SetCVarToDefault = function(M)
		return function(name)
			return C_CVar.SetCVarToDefault(name)
		end
	end,
	BackdropTemplateMixin = function(M)
		return M.BackdropTemplateMixin
	end,
	AuraContainerSortMethod = function(M)
		return M.LiteralTable('AuraContainerSortMethod')
	end,
	AuraContainerSortDirection = function(M)
		return M.LiteralTable('AuraContainerSortDirection')
	end,
	SlashCmdList = function(M)
		return {}
	end,
	hash_SlashCmdList = function(M)
		return {}
	end,
	StaticPopupDialogs = function(M)
		return {}
	end,
	StaticPopup_Show = function(M)
		return function(which, ...)
			M.popups = M.popups or {}
			M.popups[#M.popups + 1] = { which, ... }
		end
	end,
	CreateAtlasMarkup = function(M)
		return function(atlas, w, h)
			return '|A:' .. tostring(atlas) .. ':' .. tostring(h or 0) .. ':' .. tostring(w or 0) .. '|a'
		end
	end,
	CreateTextureMarkup = function(M)
		return function(file)
			return '|T' .. tostring(file) .. '|t'
		end
	end,
}

TEMPLATES = {
	BackdropTemplate = function(M, frame)
		Mixin(frame, M.BackdropTemplateMixin)
	end,
	CustomAuraContainerTemplate = function(M, frame)
		if M.TypeOf(frame) ~= 'AuraContainer' then
			error('CustomAuraContainerTemplate needs frame type AuraContainer', 4)
		end
		M.Set(frame, 'auraTemplate', true)
	end,
	DisableUntrustedLayoutScriptsTemplate = function(M, frame) end,
	PingableUnitFrameTemplate = function(M, frame) end,
	GameTooltipTemplate = function(M, frame) end,
	SecureActionButtonTemplate = function(M, frame)
		M.Set(frame, 'protected', true)
	end,
	SecureHandlerStateTemplate = function(M, frame)
		M.Set(frame, 'protected', true)
	end,
}

return { models = MODELS, templates = TEMPLATES, Mixin = Mixin, copy = copy }
