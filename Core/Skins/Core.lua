---@class SUI
local SUI = SUI
---@class SUI.Module.Handler.Skins : SUI.Module
local module = SUI:NewModule('Handler.Skins')

---@class SkinDB
local DBDefaults = {
	Blizzard = {
		GameMenu = {
			Scale = 0.8,
		},
	},
	components = {
		['**'] = {
			enabled = true,
			colors = {
				primary = 'CLASS',
				secondary = 'CLASS',
				background = 'dark',
			},
		},
	},
}
---@type AceConfig.OptionsTable
local OptTable

local DB = nil ---@type SkinDB

local BlizzardRegionList = {
	'Left',
	'Middle',
	'Right',
	'Mid',
	'LeftDisabled',
	'MiddleDisabled',
	'RightDisabled',
	'TopLeft',
	'TopRight',
	'BottomLeft',
	'BottomRight',
	'TopMiddle',
	'MiddleLeft',
	'MiddleRight',
	'BottomMiddle',
	'MiddleMiddle',
	'TabSpacer',
	'TabSpacer1',
	'TabSpacer2',
	'_RightSeparator',
	'_LeftSeparator',
	'Cover',
	'Border',
	'Background',
	'TopTex',
	'TopLeftTex',
	'TopRightTex',
	'LeftTex',
	'BottomTex',
	'BottomLeftTex',
	'BottomRightTex',
	'RightTex',
	'MiddleTex',
	'Center',
}

local Settings = {
	BackdropColor = { 0.05, 0.05, 0.05, 0.85 },
	BackdropColorDark = { 0, 0, 0, 0.95 },
	BackdropColorLight = { 0.17, 0.17, 0.17, 0.9 },
	BaseBorderColor = { 1, 1, 1, 0.3 },
	ObjBorderColor = { 1, 1, 1, 0.5 },
	factionColor = {
		Alliance = { 0, 0.6, 1, 0.5 },
		Horde = { 1, 0.2, 0.2, 0.5 },
	},
	TxBlank = 'Interface\\Addons\\SpartanUI\\images\\blank',
	bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background',
	edgeFile = 'Interface\\BUTTONS\\WHITE8X8',
}
---@class AppearanceMode
local AppearanceMode = {
	Default = 'Default',
	Dark = 'Dark',
	Light = 'Light',
	NoBackdrop = 'NoBackdrop',
}

local function GetBaseBorderColor()
	return Settings.BaseBorderColor or Settings.factionColor[UnitFactionGroup('player')]
end

local function GetClassColor(class)
	local color = (_G.CUSTOM_CLASS_COLORS and _G.CUSTOM_CLASS_COLORS[class]) or _G.RAID_CLASS_COLORS[class]
	if type(color) ~= 'table' then
		return
	end

	if not color.colorStr then
		color.colorStr = module.colors.RGBToHex(color.r, color.g, color.b, 'ff')
	elseif strlen(color.colorStr) == 6 then
		color.colorStr = 'ff' .. color.colorStr
	end

	return color
end

module.colors = {}
function module.colors:GetSecondaryColor(comp)
	-- Ensure component exists in DB, return default if not
	if not DB or not DB.components or not DB.components[comp] then
		-- Return class color with reduced alpha as fallback
		local result = module.colors.GetColorTable(GetClassColor(select(2, UnitClass('player'))))
		result[4] = 0.3
		return result
	end

	local color = DB.components[comp].colors.secondary
	if color == 'CLASS' then
		local result = module.colors.GetColorTable(GetClassColor(select(2, UnitClass('player'))))
		result[4] = 0.3
		return result
	elseif color == 'FACTION' then
		return Settings.factionColor[UnitFactionGroup('player')]
	else
		local result = module.colors.GetColorTable(GetClassColor(color))
		result[4] = 0.3
		return result
	end
end

function module.colors:GetPrimaryColor(comp)
	-- Ensure component exists in DB, return default if not
	if not DB or not DB.components or not DB.components[comp] then
		-- Return class color as fallback
		return module.colors.GetColorTable(GetClassColor(select(2, UnitClass('player'))))
	end

	local color = DB.components[comp].colors.primary
	if color == 'CLASS' then
		return module.colors.GetColorTable(GetClassColor(select(2, UnitClass('player'))))
	elseif color == 'FACTION' then
		return Settings.factionColor[UnitFactionGroup('player')]
	else
		return module.colors.GetColorTable(GetClassColor(color))
	end
end

function module.colors.SetColorTable(t, data)
	if not data.r or not data.g or not data.b then
		error('SetColorTable: Could not unpack color values.')
	end

	if t and (type(t) == 'table') then
		t[1], t[2], t[3], t[4] = module.colors.UpdateColorTable(data)
	else
		t = module.colors.GetColorTable(data)
	end

	return t
end

function module.colors.UpdateColorTable(data)
	if not data.r or not data.g or not data.b then
		error('UpdateColorTable: Could not unpack color values.')
	end

	if data.r > 1 or data.r < 0 then
		data.r = 1
	end
	if data.g > 1 or data.g < 0 then
		data.g = 1
	end
	if data.b > 1 or data.b < 0 then
		data.b = 1
	end
	if data.a and (data.a > 1 or data.a < 0) then
		data.a = 1
	end

	if data.a then
		return data.r, data.g, data.b, data.a
	else
		return data.r, data.g, data.b
	end
end

function module.colors.GetColorTable(data)
	if not data.r or not data.g or not data.b then
		error('GetColorTable: Could not unpack color values.')
	end

	if data.r > 1 or data.r < 0 then
		data.r = 1
	end
	if data.g > 1 or data.g < 0 then
		data.g = 1
	end
	if data.b > 1 or data.b < 0 then
		data.b = 1
	end
	if data.a and (data.a > 1 or data.a < 0) then
		data.a = 1
	end

	if data.a then
		return { data.r, data.g, data.b, data.a }
	else
		return { data.r, data.g, data.b }
	end
end

function module.colors.RGBToHex(r, g, b, header)
	r = r <= 1 and r >= 0 and r or 1
	g = g <= 1 and g >= 0 and g or 1
	b = b <= 1 and b >= 0 and b or 1
	return format('%02x%02x%02x', header or '|cff', r * 255, g * 255, b * 255)
end

function module.colors.HexToRGB(hex)
	local a, r, g, b = strmatch(hex, '^|?c?(%x%x)(%x%x)(%x%x)(%x?%x?)|?r?$')
	if not a then
		return 0, 0, 0, 0
	end
	if b == '' then
		r, g, b, a = a, r, g, 'ff'
	end

	return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), tonumber(a, 16)
end

local value = GetClassColor(select(2, UnitClass('player')))
Settings.ClassColor = module.colors.SetColorTable(Settings.ClassColor, value)
Settings.MutedClassColor = module.colors.SetColorTable(Settings.MutedClassColor, value)
Settings.MutedClassColor[4] = 0.3

function module:SetClassBorderColor(frame, script)
	if frame.backdrop then
		frame = frame.backdrop
	end
	if frame.SetBackdropBorderColor then
		frame:SetBackdropBorderColor(unpack(script == 'OnEnter' and Settings.ClassColor or Settings.MutedClassColor))
	end
end

local function RemoveBlizzardRegions(frame, name, fadeOut)
	if not name then
		name = frame.GetName and frame:GetName()
	end
	for _, area in pairs(BlizzardRegionList) do
		local object = (name and _G[name .. area]) or frame[area]
		if object then
			if fadeOut then
				object:SetAlpha(0)
			else
				object:Hide()
			end
		end
	end
end

function module.RemoveTextures(frame, option)
	if (not frame.GetNumRegions) or (frame.Panel and not frame.Panel.CanBeRemoved) then
		return
	end
	local region, layer, texture
	for i = 1, frame:GetNumRegions() do
		region = select(i, frame:GetRegions())
		if region and (region:GetObjectType() == 'Texture') then
			layer = region:GetDrawLayer()
			texture = region:GetTexture()

			if option then
				-- elseif texture ~= 'Interface\\DialogFrame\\UI-DialogBox-Background' then
				if type(option) == 'boolean' then
					if region.UnregisterAllEvents then
						region:UnregisterAllEvents()
						region:SetParent(nil)
					else
						region.Show = region.Hide
					end
					region:Hide()
				elseif type(option) == 'string' and ((layer == option) or (texture ~= option)) then
					region:SetTexture('')
				end
			else
				region:SetTexture('')
			end
		end
	end
end

function module.RemoveAllTextures(frame)
	for i = 1, frame:GetNumChildren() do
		local childFrame = select(i, frame:GetChildren())
		if childFrame:GetObjectType() == 'Button' and childFrame:GetText() then
			-- Widget_ButtonStyle(childFrame)
		elseif not childFrame.ignore then
			module.RemoveTextures(childFrame)
		end
	end
end

---@param frame FrameExpanded
---@param appearanceMode? AppearanceMode
function module.SetTemplate(frame, appearanceMode)
	frame.appearanceMode = appearanceMode or 'Default'

	if not frame.SetBackdrop then
		_G.Mixin(frame, _G.BackdropTemplateMixin)
		frame:HookScript('OnSizeChanged', frame.OnBackdropSizeChanged)
	end

	local edgeSize = 1
	if frame.appearanceMode == AppearanceMode.NoBackdrop then
		frame:SetBackdrop(nil)
	elseif frame.appearanceMode == AppearanceMode.NoBorder then
		frame:SetBackdrop({
			bgFile = Settings.edgeFile,
		})
	else
		frame:SetBackdrop({
			bgFile = Settings.edgeFile,
			edgeFile = Settings.edgeFile,
			edgeSize = edgeSize,
		})
	end

	if frame.appearanceMode == AppearanceMode.Dark then
		frame:SetBackdropColor(unpack(Settings.BackdropColorDark))
	elseif frame.appearanceMode == AppearanceMode.Light then
		frame:SetBackdropColor(unpack(Settings.BackdropColorLight))
	else
		frame:SetBackdropColor(unpack(Settings.BackdropColor))
	end

	if frame.appearanceMode ~= AppearanceMode.NoBorder then
		frame:SetBackdropBorderColor(unpack(Settings.MutedClassColor))
	end
end

module.Objects = {}

---@param widget any|AceGUITabGroupTab
---@param mode? AppearanceMode
function module.Objects.Tab(widget, mode, NormalTex, regionsToFade)
	hooksecurefunc(widget, 'SetPoint', function(self, left, parent, right, x, y)
		if y == -7 then
			self:ClearAllPoints()
			self:SetPoint(left, parent, right, 0, -4)
		elseif x == -10 then
			self:ClearAllPoints()
			self:SetPoint(left, parent, right, 0, 0)
		end
	end)

	widget.Left:SetTexture('Interface\\AddOns\\SpartanUI\\images\\UI-Tab')
	widget.Left:SetTexCoord(0.1, 0.15, 0, 1)
	widget.Left:SetVertexColor(1, 1, 1, 0.2)

	widget.Middle:SetTexture('Interface\\AddOns\\SpartanUI\\images\\UI-Tab')
	widget.Middle:SetTexCoord(0.15, 0.85, 0, 1)
	widget.Middle:SetVertexColor(1, 1, 1, 0.2)

	widget.Right:SetTexture('Interface\\AddOns\\SpartanUI\\images\\UI-Tab')
	widget.Right:SetTexCoord(0.85, 1, 0, 1)
	widget.Right:SetVertexColor(1, 1, 1, 0.2)

	local color = module.colors:GetSecondaryColor('Ace3')

	widget.LeftDisabled:SetTexture('Interface\\AddOns\\SpartanUI\\images\\UI-Tab')
	widget.LeftDisabled:SetTexCoord(0.1, 0.15, 0, 1)
	widget.LeftDisabled:SetVertexColor(unpack(color))

	widget.MiddleDisabled:SetTexture('Interface\\AddOns\\SpartanUI\\images\\UI-Tab')
	widget.MiddleDisabled:SetTexCoord(0.15, 0.85, 0, 1)
	widget.MiddleDisabled:SetVertexColor(unpack(color))

	widget.RightDisabled:SetTexture('Interface\\AddOns\\SpartanUI\\images\\UI-Tab')
	widget.RightDisabled:SetTexCoord(0.85, 1, 0, 1)
	widget.RightDisabled:SetVertexColor(unpack(color))

	widget.LeftDisabled:ClearAllPoints()
	widget.LeftDisabled:SetPoint('TOPLEFT')

	if widget.text then
		widget:SetNormalFontObject(GameFontHighlightSmall)
	end
end

function module.Objects.CheckBox(button, mode, NormalTex, regionsToFade)
	-- local check = button.check
	-- local checkbg = button.checkbg
	-- local highlight = button.highlight
	-- highlight:SetVertexColor(unpack(Settings.ClassColor))
	-- checkbg:SetVertexColor(unpack(Settings.ClassColor))
	-- check:SetVertexColor(unpack(Settings.MutedClassColor))
end

function module.Objects.Button(button, mode, NormalTex, regionsToFade)
	if button.isSkinned then
		return
	end

	if button.SetNormalTexture and not NormalTex then
		button:SetNormalTexture('')
	end
	if button.SetHighlightTexture then
		button:SetHighlightTexture(Settings.bgFile)
	end
	if button.SetPushedTexture then
		button:SetPushedTexture(Settings.bgFile)
	end
	if button.SetDisabledTexture then
		button:SetDisabledTexture(Settings.bgFile)
	end

	if mode == 'NoBackdrop' then
		module.RemoveAllTextures(button)
	end

	RemoveBlizzardRegions(button, nil, regionsToFade)

	if button.Text then
		SUI.Font:Format(button.Text, 12, 'Blizzard')
	end

	local function SetModifiedBackdrop(self)
		if self:IsEnabled() then
			module:SetClassBorderColor(self, 'OnEnter')
		end
	end

	local function SetOriginalBackdrop(self)
		if self:IsEnabled() then
			module:SetClassBorderColor(self, 'OnLeave')
		end
	end

	local function SetDisabledBackdrop(self)
		if self:IsMouseOver() then
			module:SetClassBorderColor(self, 'OnDisable')
		end
	end

	module.SetTemplate(button, mode)

	button:HookScript('OnEnter', SetModifiedBackdrop)
	button:HookScript('OnLeave', SetOriginalBackdrop)
	button:HookScript('OnDisable', SetDisabledBackdrop)

	if button.Text then
		button.Text:SetTextColor(1, 1, 1)
	end

	button.isSkinned = true
end

function module.Objects.StatusBar(statusBarFrame)
	local bar = statusBarFrame.Bar
	if not bar or bar.backdrop then
		return
	end

	-- Create a background frame
	local bgFrame = CreateFrame('Frame', nil, bar)
	bgFrame:SetFrameLevel(bar:GetFrameLevel() - 1) -- Set background frame level lower than the bar
	bgFrame:SetAllPoints(bar)

	-- Create a border frame
	local borderFrame = CreateFrame('Frame', nil, bar)
	borderFrame:SetFrameLevel(bar:GetFrameLevel() + 1) -- Set border frame level higher than the bar
	borderFrame:SetAllPoints(bar)

	-- Set up the background frame
	module.SetTemplate(bgFrame, 'NoBackdrop')
	bgFrame:SetBackdrop({
		bgFile = Settings.edgeFile,
	})
	bgFrame:SetBackdropColor(unpack(Settings.BackdropColor))

	-- Set up the border frame
	module.SetTemplate(borderFrame, 'NoBorder')
	borderFrame:SetBackdrop({
		edgeFile = Settings.edgeFile,
		edgeSize = 1,
	})
	borderFrame:SetBackdropBorderColor(unpack(Settings.MutedClassColor))

	-- Hide default textures
	if bar.BGLeft then
		bar.BGLeft:SetAlpha(0)
	end
	if bar.BGRight then
		bar.BGRight:SetAlpha(0)
	end
	if bar.BGCenter then
		bar.BGCenter:SetAlpha(0)
	end
	if bar.BorderLeft then
		bar.BorderLeft:SetAlpha(0)
	end
	if bar.BorderRight then
		bar.BorderRight:SetAlpha(0)
	end
	if bar.BorderCenter then
		bar.BorderCenter:SetAlpha(0)
	end

	-- Store references
	bar.bgFrame = bgFrame
	bar.borderFrame = borderFrame
end

---Skins a object
---@param ObjType string
---@param object FrameExpanded
---@param mode? AppearanceMode
---@param component? string
function module.SkinObj(ObjType, object, mode, component)
	if not object or (component and DB.components[component] and not DB.components[component].enabled) or object.isSkinned then
		return
	end
	if ObjType and module.Objects[ObjType] then
		module.Objects[ObjType](object, mode)
		return
	end

	if not object.SetBackdrop then
		Mixin(object, BackdropTemplateMixin)
	end

	object:SetBackdrop({
		bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background',
		edgeFile = 'Interface\\BUTTONS\\WHITE8X8',
		edgeSize = 1,
		TileSize = 20,
	})
	if mode and mode == AppearanceMode.Dark then
		object:SetBackdropColor(unpack(Settings.BackdropColorDark))
	elseif mode and mode == AppearanceMode.Light then
		object:SetBackdropColor(unpack(Settings.BackdropColorLight))
	else
		object:SetBackdropColor(unpack(Settings.BackdropColor))
	end

	object:SetBackdropBorderColor(unpack(GetBaseBorderColor()))
	object.isSkinned = true
end

local function GetWidgetVisualizationTypeKey(value)
	for k, v in pairs(Enum.UIWidgetVisualizationType) do
		if v == value then
			return k
		end
	end
	return nil -- Return nil if no matching key is found
end

--Skins a frame and all its children
---@param widget Frame
function module.SkinWidgets(widget)
	if not widget or not widget.widgetType or widget.SUISkinned then
		return
	end
	---@diagnostic disable-next-line: undefined-field
	local widgetFunc = module.Objects[GetWidgetVisualizationTypeKey(widget.widgetType)]
	if widgetFunc then
		widgetFunc(widget)
	end
	widget.SUISkinned = true
end

module.Registry = {}

local function functionAddToOptions(name, settings)
	OptTable.args.enabledState.args[name] = {
		name = name,
		type = 'toggle',
		order = 1,
	}

	local colors = {
		['CLASS'] = 'AUTO - Class Color',
		['CUSTOM'] = 'Custom Color',
		['DRUID'] = '|cffFF7C0ADruid (Orange)',
		['HUNTER'] = '|cffAAD372Hunter (Pistachio)',
		['MAGE'] = '|cff3FC7EBMage (Light Blue)',
		['PALADIN'] = '|cffF48CBAPaladin (Pink)',
		['PRIEST'] = '|cffFFFFFFPriest (White)',
		['ROGUE'] = '|cffFFF468Rogue (Yellow)',
		['SHAMAN'] = '|cff0070DDShaman (Blue)',
		['WARLOCK'] = '|cff8788EEWarlock (Purple)',
		['WARRIOR'] = '|cffC69B6DWarrior (Tan)',
		['DEATHKNIGHT'] = '|cffC41E3ADeath Knight (Red)',
		['MONK'] = '|cff00FF98Monk (Spring Green)',
		['DEMONHUNTER'] = '|cffA330C9Demon Hunter (Dark Magenta)',
		['EVOKER'] = '|cff33937FEvoker (Dark Emerald)',
	}

	local OptionsTab = {
		name = name,
		type = 'group',
		args = {
			colors = {
				name = 'Colors',
				type = 'group',
				inline = true,
				order = 1,
				get = function(info)
					return DB.components[name].colors[info[#info]]
				end,
				set = function(info, val)
					DB.components[name].colors[info[#info]] = val
				end,
				args = {
					primary = {
						name = 'Primary',
						type = 'select',
						order = 1,
						values = colors,
					},
					secondary = {
						name = 'Secondary',
						type = 'select',
						order = 2,
						values = colors,
					},
				},
			},
		},
	}
	if settings.Options then
		settings.Options(OptionsTab)
	end
	OptTable.args[name] = OptionsTab
end
---Register a module to be skinned
---@param Name string
---@param OnEnable? function
---@param OnInitialize? function
---@param Options? function
---@param Settings? table
function module:Register(Name, OnEnable, OnInitialize, Options, Settings)
	module.Registry[Name] = {
		OnEnable = OnEnable,
		OnInitialize = OnInitialize,
		Options = Options,
		Settings = Settings,
	}

	if OptTable and not OptTable.args[Name] then
		functionAddToOptions(Name, module.Registry[Name])
	end
end

local function Options()
	OptTable = {
		name = 'Skins',
		type = 'group',
		childGroups = 'tab',
		args = {
			enabledState = {
				name = 'Elements',
				type = 'group',
				inline = true,
				order = 1,
				get = function(info)
					return DB.components[info[#info]].enabled
				end,
				set = function(info, val)
					DB.components[info[#info]].enabled = val
					SUI:reloadui()
				end,
				args = {},
			},
		},
	}

	for name, settings in pairs(module.Registry) do
		functionAddToOptions(name, settings)
	end

	SUI.Options:AddOptions(OptTable, 'Skins')
end

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('Skins', { profile = DBDefaults })

	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterProfileCallbacks(module)
	DB = module.Database.profile

	for name, Data in pairs(module.Registry) do
		if Data.OnInitalize and DB.components[name] and DB.components[name].enabled then
			Data.OnInitalize()
		end
	end
end

function module:OnEnable()
	Options()

	for name, Data in pairs(module.Registry) do
		if Data.OnEnable and DB.components[name] and DB.components[name].enabled then
			Data.OnEnable()
		end
	end
end

SUI.Skins = module
