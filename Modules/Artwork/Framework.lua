---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Artwork : SUI.Module
local module = SUI:NewModule('Artwork')
module.ActiveStyle = {}
module.BarBG = {}
module.DisplayName = 'Artwork'
module.description = 'CORE: Provides the graphical looks of SUI'
module.Core = true
local styleArt
local petbattle = CreateFrame('FRAME')
-------------------------------------------------

local ArtworkDefaults = {
	Style = 'War',
	FirstLoad = true,
	VehicleUI = true,
	barBG = {
		['**'] = {
			enabled = true,
			alpha = 1,
		},
		['1'] = {},
		['2'] = {},
		['3'] = {},
		['4'] = {},
		['5'] = {},
		['6'] = {},
		['7'] = {},
		['8'] = {},
		['9'] = {},
		['10'] = {},
		Stance = {},
		MenuBar = {},
	},
	Viewport = {
		enabled = false,
		offset = { top = 0, bottom = 0, left = 0, right = 0 },
	},
	SlidingTrays = {
		['**'] = {
			collapsed = false,
		},
	},
	Trays = {
		['**'] = {
			left = {
				enabled = true,
				size = { width = 410, height = 45 },
				collapseDirection = 'up',
				customFrames = '',
				color = { r = 1, g = 1, b = 1, a = 1 },
			},
			right = {
				enabled = true,
				size = { width = 410, height = 45 },
				collapseDirection = 'up',
				customFrames = '',
				color = { r = 1, g = 1, b = 1, a = 1 },
			},
		},
	},
	Offset = {
		Top = 0,
		TopAuto = true,
		Bottom = 0,
		BottomAuto = true,
		Horizontal = {
			Bottom = 0,
			Top = 0,
		},
	},
	BlizzMoverStates = {
		['**'] = {
			enabled = true,
		},
	},
}

---Get the active artwork style name
---@return string
function SUI:GetActiveStyle()
	if module.CurrentSettings then
		return module.CurrentSettings.Style
	end
	-- Fallback before module init (shouldn't happen, but safety)
	return (SUI.DB and SUI.DB.Artwork and SUI.DB.Artwork.Style) or 'War'
end

---Set the active artwork style
---@param style string
function SUI:SetActiveStyle(style)
	if module.CurrentSettings and style ~= module.CurrentSettings.Style then
		module:SetActiveStyle(style)
	end
end

---Get an Artwork module setting (for external modules)
---@param key string Dot-notation path like 'VehicleUI' or 'Viewport.enabled'
---@return any
function SUI:GetArtworkSetting(key)
	return SUI.DBM:Get(module, key)
end

-- Looks offered in setup, newest first; the rest follow in the order players pick them most
-- Popular first, then new, then the rest
local SETUP_LOOKS = { 'War', 'Classic', 'Atlas', 'Boughs', 'Meridian', 'ModernFlat', 'HealerGrid', 'ClassicDark', 'Midnight', 'Fel', 'Digital', 'Arcane', 'Minimal', 'Tribal', 'Transparent' }
local SETUP_TAGS = { Atlas = 'New', Boughs = 'New', Meridian = 'New', ModernFlat = 'New', HealerGrid = 'New', ClassicDark = 'New', War = 'Popular', Classic = 'Popular' }

---Setup cards for every look, built from the theme registry
---@return table[]
local function BuildLookCards()
	local cards = {}
	for _, name in ipairs(SETUP_LOOKS) do
		local entry = SUI.ThemeRegistry:Get(name)
		if entry then
			local card = {
				value = name,
				title = entry.displayName or name,
				caption = entry.description,
				tag = SETUP_TAGS[name] and L[SETUP_TAGS[name]] or nil,
				tagStyle = SETUP_TAGS[name] and SETUP_TAGS[name]:lower() or nil,
				-- War shows the player's own faction
				art = { texture = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_' .. ((name == 'War' and UnitFactionGroup('player') == 'Alliance') and 'War_Alliance' or name) },
				accent = entry.accent,
			}
			local variants = SUI.ThemeRegistry:GetVariants(name)
			if variants then
				card.variants = {}
				for _, variant in ipairs(variants) do
					card.variants[#card.variants + 1] = { value = variant.id, text = variant.label }
				end
			end
			cards[#cards + 1] = card
		end
	end
	return cards
end

---Switch to a look: its artwork and its unit frames, as the theme buttons in the options do. A
---variant can set either itself (applyStyle, applyUF); whatever it leaves out comes from the theme.
---Fel's Engulfed and Calmed only change its minimap, so Fel itself is switched to first.
---@param value string Theme name
---@param variant? string Variant id
local function ApplyLook(value, variant)
	local variants = SUI.ThemeRegistry:GetVariants(value)
	if not variants then
		SUI:SetActiveStyle(value)
		if SUI.UF then
			SUI.UF:SetActiveStyle(value)
		end
		return
	end
	variant = variant or SUI.ThemeRegistry:GetActiveVariant(value) or value
	local appliesStyle, appliesUF = false, false
	for _, entry in ipairs(variants) do
		if entry.id == variant then
			appliesStyle = entry.applyStyle ~= nil
			appliesUF = entry.applyUF ~= nil
		end
	end
	if not appliesStyle and SUI:GetActiveStyle() ~= value then
		SUI:SetActiveStyle(value)
	end
	if not appliesUF and SUI.UF then
		SUI.UF:SetActiveStyle(value)
	end
	SUI.ThemeRegistry:ApplyVariant(value, variant)
end

---The look shown as in use: a sub-theme counts as its family
---@return string
local function ActiveLook()
	local style = module.CurrentSettings.Style
	local entry = SUI.ThemeRegistry:Get(style)
	return (entry and entry.variantGroup) or style
end

---Look cards with each look's current variant, for the settings window
---@return table[]
function module:GetLookCards()
	local cards = BuildLookCards()
	for _, card in ipairs(cards) do
		if card.variants then
			card.variant = SUI.ThemeRegistry:GetActiveVariant(card.value)
		end
	end
	return cards
end

---@param value string
---@param variant? string
function module:ApplyLook(value, variant)
	ApplyLook(value, variant)
end

---@return string
function module:GetActiveLook()
	return ActiveLook()
end

local function RegisterSetupWizardPages()
	local reg = SUI.Setup and SUI.Setup.registration
	if not reg or reg:GetStep('theme') then
		return
	end

	reg:AddStep({
		id = 'theme',
		kind = 'look',
		name = L['Look'],
		title = L['Pick a look'],
		text = L['This sets the art, frames, action bars and minimap together. You can change any part later.'],
		order = 20,
		scope = 'profile',
		-- A copied or shared profile brings its own look
		hidden = function()
			return not SUI.Setup:IsStartingFresh()
		end,
		onLeave = function(ctx)
			if ctx and ctx.closing then
				return
			end
			SUI.Setup:EnsureWelcomeDone()
		end,
		cards = BuildLookCards(),
		get = ActiveLook,
		set = function(value)
			ApplyLook(value)
		end,
		getVariant = function(value)
			return SUI.ThemeRegistry:GetActiveVariant(value)
		end,
		setVariant = function(value, variant)
			ApplyLook(value, variant)
		end,
	})

	-- Size and letters on one page. Look-only extras and the vehicle switch live in the look's settings.
	reg:AddStep({
		id = 'artwork-options',
		kind = 'custom',
		name = L['Make it yours'],
		title = L['Make it yours'],
		text = L['How big things are and how the letters look. Both can change later in /sui.'],
		order = 21,
		scope = 'profile',
		cache = false,
		summary = function()
			local Font = SUI:GetModule('Handler.Font') ---@type SUI.Font
			return ('%d%% size, %s'):format(math.floor((SUI.DB.scale or 0.92) * 100 + 0.5), Font:GetFace('Global') or '')
		end,
		hidden = function()
			return not SUI.Setup:IsStartingFresh()
		end,
		build = function(contentFrame)
			local UI = LibAT.UI
			local Font = SUI:GetModule('Handler.Font') ---@type SUI.Font
			local width = contentFrame:GetWidth()
			local _, sizeHeight = UI.BuildWidgets(contentFrame, {
				sizeHeader = { type = 'header', name = L['Size'], order = 1 },
				scale = {
					type = 'slider',
					name = L['Size of everything SpartanUI draws'],
					desc = L['Makes everything SpartanUI draws bigger or smaller. 92 is the default.'],
					min = 50,
					max = 100,
					step = 1,
					order = 2,
					get = function()
						return math.floor((SUI.DB.scale or 0.92) * 100 + 0.5)
					end,
					set = function(_, val)
						SUI.DB.scale = val / 100
						module:UpdateScale()
					end,
				},
				transparency = {
					type = 'slider',
					name = L['How much of the art you can see'],
					desc = L['100 is fully solid. Lower lets the game show through the art.'],
					min = 0,
					max = 100,
					step = 1,
					order = 3,
					get = function()
						return math.floor((SUI.DB.alpha or 1) * 100)
					end,
					set = function(_, val)
						SUI.DB.alpha = val / 100
						module:UpdateAlpha()
					end,
				},
				lettersHeader = { type = 'header', name = L['Letters'], order = 10 },
			}, width - 20)

			local LSM = SUI.Lib.LSM
			local sample = contentFrame:CreateFontString(nil, 'OVERLAY')
			local function ShowSample()
				local path = LSM:Fetch('font', Font:GetFace('Global')) or STANDARD_TEXT_FONT
				sample:SetFont(path, 15, 'OUTLINE')
				local health = UnitHealthMax('player') or 0
				sample:SetText(('%s   %s / %s   %s'):format(UnitName('player') or '', BreakUpLargeNumbers(health), BreakUpLargeNumbers(health), L['The quick brown fox jumps over the lazy dog']))
			end

			local tiles = {}
			local function PaintTiles()
				local current = Font:GetFace('Global')
				for name, button in pairs(tiles) do
					button.style = name == current and 'primary' or 'secondary'
					if button.ApplyKit then
						button:ApplyKit()
					end
				end
			end
			local function Pick(name)
				Font:SetFace('Global', name)
				Font:Refresh()
				ShowSample()
				PaintTiles()
			end

			local tileWidth = math.floor((width - 20 - 3 * 8) / 4)
			local top = sizeHeight + 4
			for k, name in ipairs({ 'Roboto Condensed Bold', 'Roboto Bold', 'Roboto Medium', 'NotoSans Bold', 'Cognosis', 'Myriad', 'Arial Narrow', 'Friz Quadrata TT' }) do
				local button = UI.CreateButton(contentFrame, tileWidth, 26, name)
				local text = button:GetFontString()
				local path = LSM:Fetch('font', name, true)
				if text and path then
					text:SetFont(path, 13, '')
				end
				button:SetScript('OnClick', function()
					Pick(name)
				end)
				local column = (k - 1) % 4
				local row = math.floor((k - 1) / 4)
				button:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', column * (tileWidth + 8), -(top + row * 34))
				tiles[name] = button
			end
			top = top + 2 * 34 + 6

			-- Every installed font, each name drawn in its own letters
			local more = UI.CreateDropdown(contentFrame, L['More fonts'], 260, 24)
			more:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -top)
			if more.SetupMenu then
				more:SetupMenu(function(_, root)
					local names = {}
					for name in pairs(LSM:HashTable('font')) do
						names[#names + 1] = name
					end
					table.sort(names)
					for _, name in ipairs(names) do
						local entry = root:CreateRadio(name, function()
							return Font:GetFace('Global') == name
						end, function()
							Pick(name)
						end)
						local path = LSM:Fetch('font', name, true)
						if entry.AddInitializer and path then
							entry:AddInitializer(function(button)
								local text = button.fontString or button.Text
								if text and text.SetFont then
									text:SetFont(path, 13, '')
								end
							end)
						end
					end
				end)
			end
			top = top + 24 + 14

			sample:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -top)
			sample:SetPoint('RIGHT', contentFrame, 'RIGHT', -10, 0)
			sample:SetJustifyH('LEFT')
			sample:SetWordWrap(true)
			ShowSample()
			PaintTiles()
			top = top + 40

			contentFrame.totalHeight = top
			contentFrame:SetHeight(top)
		end,
	})
end

local function StyleUpdate()
	if InCombatLockdown() then
		return
	end

	module:UpdateScale()
	module:UpdateAlpha()
	module:updateOffset()
	module:updateHorizontalOffset()
	module:updateViewport()
	module:UpdateBarBG()
end

local function GetStyleModule(styleName)
	local entry = SUI.ThemeRegistry:Get(styleName)
	local modName = 'Style.' .. (entry and entry.variantGroup or styleName)
	return SUI:GetModule(modName, true), modName
end

function module:SetActiveStyle(style)
	if style and style ~= module.CurrentSettings.Style then
		local OldStyle, oldModName = GetStyleModule(module.CurrentSettings.Style)
		local NewStyle, newModName = GetStyleModule(style)

		-- Update the DB
		module.DB.Style = style
		SUI.DBM:RefreshSettings(module)

		-- Ensure new theme data is loaded before updating subsystems
		SUI.ThemeRegistry:GetData(style)

		-- Only cycle Disable/Enable if the Ace3 module actually changes.
		-- Sub-themes like ArcaneRed share their parent's module (Style.Arcane).
		if oldModName ~= newModName then
			if OldStyle then
				OldStyle:Disable()
			end
			if NewStyle then
				NewStyle:Enable()
			end
		end

		--Update bars
		SUI.Handlers.BarSystem.Refresh()

		--Update minimap
		local minimapModule = SUI:GetModule('Minimap') ---@type SUI.Module.Minimap
		if minimapModule then
			minimapModule:SetActiveStyle(style)
		end

		--Update statusbar
		local StatusBars = SUI:GetModule('Artwork.StatusBars') ---@type SUI.Module.Artwork.StatusBars
		if StatusBars then
			StatusBars:SetActiveStyle(style)
		end

		--Update UnitFrames
		if SUI.UF and SUI.UF.Style then
			SUI.UF.Style:Change(style)
		end
	end

	-- Build ActiveStyle from ThemeRegistry data + barBG from Artwork DB
	local themeData = SUI.ThemeRegistry:GetData(module.CurrentSettings.Style) or {}
	module.ActiveStyle = {
		Artwork = {
			barBG = module.CurrentSettings.barBG,
		},
	}
	-- Merge in theme data fields for anything else that might read them
	for k, v in pairs(themeData) do
		if k ~= 'Artwork' then
			module.ActiveStyle[k] = v
		end
	end
	styleArt = _G['SUI_Art_' .. module.CurrentSettings.Style]

	--Send Custom change event
	SUI.Event:SendEvent('ARTWORK_STYLE_CHANGED')

	-- Update core elements based on new style
	StyleUpdate()
end

function module:UpdateScale()
	-- Set overall UI scale
	SpartanUI:SetScale(SUI.DB.scale)

	-- Call style scale update if defined.
	local styleModule = (GetStyleModule(module.CurrentSettings.Style))
	if styleModule and styleModule.UpdateScale then
		styleModule:UpdateScale()
	end
	if SUI:IsModuleEnabled('UnitFrames') then
		SUI.UF:ScaleFrames(SUI.DB.scale)
	end

	-- Call Minimap scale update
	local minimap = SUI:GetModule('Minimap', true) ---@type SUI.Module.Minimap
	if minimap and minimap.Settings and minimap.Settings.scaleWithArt then
		minimap:UpdateScale()
	end

	-- Update Bar scales
	SUI.Handlers.BarSystem:Refresh()
end

function module:UpdateAlpha()
	if styleArt then
		styleArt:SetAlpha(SUI.DB.alpha)
	end
	-- Call module scale update if defined.
	local styleModule = (GetStyleModule(module.CurrentSettings.Style))
	if styleModule and styleModule.UpdateAlpha then
		styleModule:UpdateAlpha()
	end
end

function module:updateOffset()
	if InCombatLockdown() then
		return
	end

	SUI.Log('updateOffset called - TopAuto: ' .. tostring(module.CurrentSettings.Offset.TopAuto) .. ', BottomAuto: ' .. tostring(module.CurrentSettings.Offset.BottomAuto), 'Artwork', 'debug')

	local Top, Bottom = 0, 0
	local Tfubar, TChocolateBar, Ttitan, TLibsDataBar = 0, 0, 0, 0
	local Bfubar, BChocolateBar, Btitan, BLibsDataBar = 0, 0, 0, 0
	local SUITopOffset, SUIBottomOffset = 0, 0

	if module.CurrentSettings.Offset.TopAuto or module.CurrentSettings.Offset.BottomAuto then
		-- FuBar Offset
		for i = 1, 4 do
			local bar = _G['FuBarFrame' .. i]
			if bar and bar:IsVisible() then
				local point = bar:GetPoint(1)
				if point:find('TOP.*') then
					Tfubar = Tfubar + bar:GetHeight()
				end
				if point == 'BOTTOMLEFT' then
					Bfubar = Bfubar + bar:GetHeight()
				end
			end
		end

		-- Chocolate Bar Offset
		for i = 1, 100 do
			local bar = _G['ChocolateBar' .. i]
			if bar and bar:IsVisible() then
				local point = bar:GetPoint(1)
				if point:find('TOP.*') then
					TChocolateBar = TChocolateBar + bar:GetHeight()
				end
				if point == 'RIGHT' then
					BChocolateBar = BChocolateBar + bar:GetHeight()
				end
			end
		end

		-- Titan Bar
		local TitanBars = { ['Bar2'] = 'top', ['Bar'] = 'top', ['AuxBar2'] = 'bottom', ['AuxBar'] = 'bottom' }
		for k, v in pairs(TitanBars) do
			local bar = _G['Titan_Bar__Display_' .. k]
			if bar and bar:IsVisible() then
				if v == 'top' then
					Ttitan = Ttitan + ((TitanPanelGetVar('Scale') or 1) * bar:GetHeight())
				else
					Btitan = Btitan + ((TitanPanelGetVar('Scale') or 1) * bar:GetHeight())
				end
			end
		end

		-- LibsDataBar Detection
		if LibsDataBar and LibsDataBar.API then
			local ldbOffsets = LibsDataBar.API:GetBarOffsets()
			if ldbOffsets then
				TLibsDataBar = ldbOffsets.top or 0
				BLibsDataBar = ldbOffsets.bottom or 0
				SUI.Log('LibsDataBar offsets detected - top: ' .. TLibsDataBar .. ', bottom: ' .. BLibsDataBar, 'Artwork', 'debug')
			end
		else
			SUI.Log('LibsDataBar.API not available', 'Artwork', 'debug')
		end

		-- Blizz Legion Order Hall
		if OrderHallCommandBar and OrderHallCommandBar:IsVisible() then
			Top = Top + OrderHallCommandBar:GetHeight()
		end

		-- Calculate SUI's own offset (excluding LibsDataBar - we'll add that separately)
		SUITopOffset = max(Top + Tfubar + Ttitan + TChocolateBar, 0)
		SUIBottomOffset = max(Bottom + Bfubar + Btitan + BChocolateBar, 0)

		-- Update runtime settings if set to auto (total offset including LibsDataBar)
		-- Runtime only - recomputed each login from actual bar positions. Manual offsets persist in DB.
		if module.CurrentSettings.Offset.TopAuto then
			module.CurrentSettings.Offset.Top = max(SUITopOffset + TLibsDataBar, 0)
		end
		if module.CurrentSettings.Offset.BottomAuto then
			module.CurrentSettings.Offset.Bottom = max(SUIBottomOffset + BLibsDataBar, 0)
		end
	end

	-- Call module update if defined.
	local styleModule = (GetStyleModule(module.CurrentSettings.Style))
	if styleModule and styleModule.updateOffset then
		styleModule:updateOffset(module.CurrentSettings.Offset.Top, module.CurrentSettings.Offset.Bottom)
	end

	SpartanUI:ClearAllPoints()
	SpartanUI:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', 0, (module.CurrentSettings.Offset.Top * -1))
	if module.CurrentSettings.Offset.BottomAuto and _G['TitanPanelBottomAnchor'] then
		SpartanUI:SetPoint('BOTTOMLEFT', _G['TitanPanelBottomAnchor'], 'BOTTOMLEFT', 0, 0)
	else
		SpartanUI:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 0, module.CurrentSettings.Offset.Bottom)
	end

	-- LibsDataBar integration is ONE-WAY:
	-- SUI reads LibsDataBar's bar offsets (done above) and adjusts artwork accordingly
	-- LibsDataBar does NOT need to know about SUI - it positions itself based on config only
end

function module:updateHorizontalOffset()
	SUI_BottomAnchor:ClearAllPoints()
	SUI_BottomAnchor:SetPoint('BOTTOM', SpartanUI, 'BOTTOM', module.CurrentSettings.Offset.Horizontal.Bottom, 0)

	SUI_TopAnchor:ClearAllPoints()
	SUI_TopAnchor:SetPoint('TOP', SpartanUI, 'TOP', module.CurrentSettings.Offset.Horizontal.Top, 0)

	-- Call module scale update if defined.
	local styleModule = (GetStyleModule(module.CurrentSettings.Style))
	if styleModule and styleModule.updateXOffset then
		styleModule:updateXOffset()
	end
end

function module:updateViewport()
	-- Defensive check: ensure Viewport exists in settings (might be missing after profile swap)
	if not module.CurrentSettings or not module.CurrentSettings.Viewport then
		return
	end

	if not InCombatLockdown() and module.CurrentSettings.Viewport.enabled then
		WorldFrame:ClearAllPoints()
		WorldFrame:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', module.CurrentSettings.Viewport.offset.left, (module.CurrentSettings.Viewport.offset.top * -1))
		WorldFrame:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', (module.CurrentSettings.Viewport.offset.right * -1), module.CurrentSettings.Viewport.offset.bottom)
	end
end

function module:OnInitialize()
	if SUI:IsModuleDisabled('Artwork') then
		return
	end

	SUI.DBM:SetupModule(self, ArtworkDefaults, nil, { autoCalculateDepth = true })

	-- One-time migration from old root SUI.DB.Artwork location
	if SUI.DB.Artwork then
		local oldData = SUI.DB.Artwork
		for k, v in pairs(oldData) do
			if type(v) == 'table' then
				-- Deep compare for nested tables (Offset, Viewport, barBG, etc.)
				if ArtworkDefaults[k] and type(ArtworkDefaults[k]) == 'table' then
					local function migrateTable(src, defaults, dest)
						for sk, sv in pairs(src) do
							if sk == '**' then
								-- Skip wildcards
							elseif type(sv) == 'table' and type(defaults[sk]) == 'table' then
								dest[sk] = dest[sk] or {}
								migrateTable(sv, defaults[sk], dest[sk])
							elseif sv ~= defaults[sk] then
								dest[sk] = sv
							end
						end
					end
					self.DB[k] = self.DB[k] or {}
					migrateTable(v, ArtworkDefaults[k], self.DB[k])
					-- Clean up empty tables
					if not next(self.DB[k]) then
						self.DB[k] = nil
					end
				end
			elseif v ~= ArtworkDefaults[k] then
				self.DB[k] = v
			end
		end
		SUI.DB.Artwork = nil
		SUI.DBM:RefreshSettings(self)
	end

	SUI.DBM:RegisterSequentialProfileRefresh(module)

	-- Setup options
	module:SetupOptions()

	-- Initalize style
	module:SetActiveStyle()

	-- Register theme textures with LibSharedMedia
	module:RegisterThemeTextures()

	-- Loop over the BlizzMovers and execute them
	module.BlizzMovers()
end

local function VehicleUI()
	if module.CurrentSettings.VehicleUI then
		local minimapModule = SUI:GetModule('Minimap', true)
		local artFrame = _G['SUI_Art_' .. module.CurrentSettings.Style]

		petbattle:HookScript('OnHide', function()
			if InCombatLockdown() then
				return
			end
			if artFrame then
				artFrame:Hide()
			end
			if SUI:IsModuleEnabled('Minimap') and (minimapModule.DB.AutoDetectAllowUse or minimapModule.DB.ManualAllowUse) then
				Minimap:Hide()
			end
		end)
		petbattle:HookScript('OnShow', function()
			if InCombatLockdown() then
				return
			end
			if artFrame then
				artFrame:Show()
			end
			if SUI:IsModuleEnabled('Minimap') and (minimapModule.DB.AutoDetectAllowUse or minimapModule.DB.ManualAllowUse) then
				Minimap:Show()
			end
		end)
		RegisterStateDriver(SpartanUI, 'visibility', '[petbattle][overridebar][vehicleui] hide; show')
	end
end

function module:ReloadDB()
	if module.CurrentSettings and module.CurrentSettings.Viewport then
		module:updateViewport()
	end
end

function module:SetActiveStyleForced(newStyle, oldStyle)
	local OldStyleMod, oldModName = GetStyleModule(oldStyle)
	local NewStyleMod, newModName = GetStyleModule(newStyle)

	-- Ensure new theme data is loaded
	SUI.ThemeRegistry:GetData(newStyle)

	-- Cycle Disable/Enable if the Ace3 module actually changes
	if oldModName ~= newModName then
		if OldStyleMod then
			OldStyleMod:Disable()
		end
		if NewStyleMod then
			NewStyleMod:Enable()
		end
	end

	self:ForceStyleRefresh(newStyle)
end

function module:ForceStyleRefresh(style)
	-- Ensure theme data is loaded
	SUI.ThemeRegistry:GetData(style)

	-- Refresh bars
	SUI.Handlers.BarSystem.Refresh()

	-- Refresh minimap
	local minimapModule = SUI:GetModule('Minimap') ---@type SUI.Module.Minimap
	if minimapModule and minimapModule.SetActiveStyle then
		minimapModule:SetActiveStyle(style)
	end

	-- Refresh statusbars
	local StatusBars = SUI:GetModule('Artwork.StatusBars') ---@type SUI.Module.Artwork.StatusBars
	if StatusBars and StatusBars.SetActiveStyle then
		StatusBars:SetActiveStyle(style)
	end

	-- Refresh UnitFrames
	if SUI.UF and SUI.UF.Style then
		SUI.UF.Style:Change(style)
	end

	-- Rebuild ActiveStyle table
	local themeData = SUI.ThemeRegistry:GetData(module.CurrentSettings.Style) or {}
	module.ActiveStyle = {
		Artwork = { barBG = module.CurrentSettings.barBG },
	}
	for k, v in pairs(themeData) do
		if k ~= 'Artwork' then
			module.ActiveStyle[k] = v
		end
	end
	styleArt = _G['SUI_Art_' .. module.CurrentSettings.Style]

	SUI.Event:SendEvent('ARTWORK_STYLE_CHANGED')
	StyleUpdate()
end

function module:OnEnable()
	if SUI:IsModuleDisabled('Artwork') then
		return
	end

	-- Eagerly load the active theme's data so BridgeToSubsystems populates
	-- all subsystem registries (Minimap, StatusBars, BarSystem, UF.Style)
	-- before they run their own OnEnable
	SUI.ThemeRegistry:GetData(module.CurrentSettings.Style)

	if SUI.Handlers.BarSystem then
		SUI.Handlers.BarSystem.Refresh()
	end

	RegisterSetupWizardPages()
	VehicleUI()
	StyleUpdate()
	module:RegisterEvent('ADDON_LOADED', StyleUpdate)
	module:RegisterEvent('PLAYER_ENTERING_WORLD', StyleUpdate)

	-- Lib's DataBar loads first (OptionalDeps), so its API is ready here when it is installed
	if LibsDataBar and LibsDataBar.API then
		LibsDataBar.API:RegisterCallback('SpartanUI', function(event)
			if event == 'refresh' or event == 'resize' or event == 'move' or event == 'show' or event == 'hide' or event == 'host' or event == 'remove' then
				module:updateOffset()
			end
		end)
	end
end

function module:UpdateBarBG()
	if not module.BarBG[module.CurrentSettings.Style] then
		return
	end
	local usersettings = module.ActiveStyle.Artwork.barBG
	for i, bgFrame in pairs(module.BarBG[module.CurrentSettings.Style]) do
		if usersettings[i] then
			if usersettings[i].enabled then
				bgFrame:Show()
				bgFrame.BG:Show()

				-- Keep background in normal position - borders will extend outside
				-- Reset background to default positioning first
				bgFrame.BG:ClearAllPoints()
				if bgFrame.skinSettings.point then
					bgFrame.BG:SetPoint(bgFrame.skinSettings.point)
				else
					bgFrame.BG:SetAllPoints(bgFrame)
				end

				-- Handle different background types
				local bgType = usersettings[i].bgType or 'texture'
				if bgType == 'color' then
					-- Solid color background
					local color
					if usersettings[i].classColorBG then
						-- Use class color for background
						local _, class = UnitClass('player')
						local classColor = RAID_CLASS_COLORS[class]
						if classColor then
							color = { classColor.r, classColor.g, classColor.b, 1 }
						else
							color = usersettings[i].backgroundColor or { 0, 0, 0, 1 }
						end
					else
						color = usersettings[i].backgroundColor or { 0, 0, 0, 1 }
					end
					bgFrame.BG:SetColorTexture(color[1], color[2], color[3], color[4] * usersettings[i].alpha)
				elseif bgType == 'custom' then
					-- Custom texture from LibSharedMedia
					local LSM = LibStub('LibSharedMedia-3.0')
					local texture = usersettings[i].customTexture or 'Blizzard'
					bgFrame.BG:SetTexture(LSM:Fetch('statusbar', texture))
					bgFrame.BG:SetAlpha((bgFrame.skinSettings.alpha or 1) * usersettings[i].alpha)

					-- Apply texture color/tint
					local useSkinColors = usersettings[i].useSkinColors ~= false -- Default to true
					if usersettings[i].classColorBG then
						-- Use class color for background texture
						local _, class = UnitClass('player')
						local classColor = RAID_CLASS_COLORS[class]
						if classColor then
							bgFrame.BG:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
						else
							local skinColor = bgFrame.skinSettings.color or { 1, 1, 1, 1 }
							bgFrame.BG:SetVertexColor(skinColor[1], skinColor[2], skinColor[3], skinColor[4])
						end
					elseif not useSkinColors and usersettings[i].textureColor then
						-- Use custom user color
						local textureColor = usersettings[i].textureColor
						bgFrame.BG:SetVertexColor(textureColor[1], textureColor[2], textureColor[3], textureColor[4])
					else
						-- Use default/skin colors (for custom textures, default to white)
						local skinColor = bgFrame.skinSettings.color or { 1, 1, 1, 1 }
						bgFrame.BG:SetVertexColor(skinColor[1], skinColor[2], skinColor[3], skinColor[4])
					end
				else
					-- Default theme texture
					bgFrame.BG:SetTexture(bgFrame.skinSettings.TexturePath)
					bgFrame.BG:SetTexCoord(unpack(bgFrame.skinSettings.TexCoord or { 0, 1, 0, 1 }))
					bgFrame.BG:SetAlpha((bgFrame.skinSettings.alpha or 1) * usersettings[i].alpha)

					-- Apply texture color/tint or use skin defaults
					local useSkinColors = usersettings[i].useSkinColors ~= false -- Default to true
					if usersettings[i].classColorBG then
						-- Use class color for background texture
						local _, class = UnitClass('player')
						local classColor = RAID_CLASS_COLORS[class]
						if classColor then
							bgFrame.BG:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
						else
							local skinColor = bgFrame.skinSettings.color or { 1, 1, 1, 1 }
							bgFrame.BG:SetVertexColor(skinColor[1], skinColor[2], skinColor[3], skinColor[4])
						end
					elseif not useSkinColors and usersettings[i].textureColor then
						-- Use custom user color
						local textureColor = usersettings[i].textureColor
						bgFrame.BG:SetVertexColor(textureColor[1], textureColor[2], textureColor[3], textureColor[4])
					else
						-- Use skin-defined colors or default
						local skinColor = bgFrame.skinSettings.color or { 1, 1, 1, 1 }
						bgFrame.BG:SetVertexColor(skinColor[1], skinColor[2], skinColor[3], skinColor[4])
					end
				end

				-- Handle borders with individual side support
				if usersettings[i].borderEnabled then
					-- Initialize border container if not exists
					if not bgFrame.Borders then
						bgFrame.Borders = {}
					end

					local borderSize = usersettings[i].borderSize or 1
					local borderColors = usersettings[i].borderColors or {}
					local borderSides = usersettings[i].borderSides or { top = true, bottom = true, left = true, right = true }

					-- Create/update individual border sides
					local sides = { 'top', 'bottom', 'left', 'right' }
					for _, side in ipairs(sides) do
						if borderSides[side] then
							-- Create border side if it doesn't exist
							if not bgFrame.Borders[side] then
								bgFrame.Borders[side] = CreateFrame('Frame', nil, bgFrame:GetParent())
								bgFrame.Borders[side]:SetFrameLevel(bgFrame:GetFrameLevel() + 1) -- Above background
								bgFrame.Borders[side].texture = bgFrame.Borders[side]:CreateTexture(nil, 'ARTWORK')
								bgFrame.Borders[side].texture:SetTexture('Interface\\Buttons\\WHITE8X8')
							end

							-- Get individual border color for this side
							local sideColor = borderColors[side] or { 1, 1, 1, 1 }

							-- Use class color if enabled for this specific side
							local classColorBorders = usersettings[i].classColorBorders or {}
							if classColorBorders[side] then
								local _, class = UnitClass('player')
								local classColor = RAID_CLASS_COLORS[class]
								if classColor then
									sideColor = { classColor.r, classColor.g, classColor.b, sideColor[4] or 1 }
								end
							end

							-- Position border sides outside the background frame
							-- Horizontal borders (top/bottom) extend to cover vertical border areas for proper corners
							local border = bgFrame.Borders[side]
							border:ClearAllPoints()

							if side == 'top' then
								-- Extend left/right to cover vertical border areas
								local leftExtend = (borderSides.left and borderSize) or 0
								local rightExtend = (borderSides.right and borderSize) or 0
								border:SetPoint('BOTTOMLEFT', bgFrame, 'TOPLEFT', -leftExtend, 0)
								border:SetPoint('BOTTOMRIGHT', bgFrame, 'TOPRIGHT', rightExtend, 0)
								border:SetHeight(borderSize)
							elseif side == 'bottom' then
								-- Extend left/right to cover vertical border areas
								local leftExtend = (borderSides.left and borderSize) or 0
								local rightExtend = (borderSides.right and borderSize) or 0
								border:SetPoint('TOPLEFT', bgFrame, 'BOTTOMLEFT', -leftExtend, 0)
								border:SetPoint('TOPRIGHT', bgFrame, 'BOTTOMRIGHT', rightExtend, 0)
								border:SetHeight(borderSize)
							elseif side == 'left' then
								-- Don't extend vertically - horizontal borders will cover corners
								border:SetPoint('TOPRIGHT', bgFrame, 'TOPLEFT', 0, 0)
								border:SetPoint('BOTTOMRIGHT', bgFrame, 'BOTTOMLEFT', 0, 0)
								border:SetWidth(borderSize)
							elseif side == 'right' then
								-- Don't extend vertically - horizontal borders will cover corners
								border:SetPoint('TOPLEFT', bgFrame, 'TOPRIGHT', 0, 0)
								border:SetPoint('BOTTOMLEFT', bgFrame, 'BOTTOMRIGHT', 0, 0)
								border:SetWidth(borderSize)
							end

							border.texture:SetAllPoints(border)
							border.texture:SetColorTexture(sideColor[1], sideColor[2], sideColor[3], sideColor[4])
							border:Show()
						elseif bgFrame.Borders[side] then
							-- Hide unused border sides
							bgFrame.Borders[side]:Hide()
						end
					end
				elseif bgFrame.Borders then
					-- Hide all border sides and reset background positioning
					for _, side in ipairs({ 'top', 'bottom', 'left', 'right' }) do
						if bgFrame.Borders[side] then
							bgFrame.Borders[side]:Hide()
						end
					end
					-- Reset background to default positioning when borders are disabled
					bgFrame.BG:ClearAllPoints()
					if bgFrame.skinSettings.point then
						bgFrame.BG:SetPoint(bgFrame.skinSettings.point)
					else
						bgFrame.BG:SetAllPoints(bgFrame)
					end
				end
			else
				bgFrame:Hide()
				bgFrame.BG:Hide()
				if bgFrame.Border then
					bgFrame.Border:Hide()
				end
				if bgFrame.Borders then
					for _, side in ipairs({ 'top', 'bottom', 'left', 'right' }) do
						if bgFrame.Borders[side] then
							bgFrame.Borders[side]:Hide()
						end
					end
				end
				-- Reset background positioning when disabled
				bgFrame.BG:ClearAllPoints()
				if bgFrame.skinSettings.point then
					bgFrame.BG:SetPoint(bgFrame.skinSettings.point)
				else
					bgFrame.BG:SetAllPoints(bgFrame)
				end
			end
		end
	end
end

function module:CreateBarBG(skinSettings, number, parent)
	local frame = CreateFrame('Frame', skinSettings.name .. '_Bar' .. number, (parent or UIParent))
	frame.skinSettings = skinSettings
	frame:SetFrameStrata('BACKGROUND')
	frame:SetSize((skinSettings.width or 400), (skinSettings.height or 32))
	frame.BG = frame:CreateTexture(skinSettings.name .. '_Bar' .. number .. 'BG', 'BACKGROUND')
	frame.BG:SetTexture(skinSettings.TexturePath)
	frame.BG:SetTexCoord(unpack(skinSettings.TexCoord or { 0, 1, 0, 1 }))
	frame.BG:SetAlpha(skinSettings.alpha or 1)
	if skinSettings.point then
		frame.BG:SetPoint(skinSettings.point)
	else
		frame.BG:SetAllPoints(frame)
	end

	if not module.BarBG[skinSettings.name] then
		module.BarBG[skinSettings.name] = {}
	end
	module.BarBG[skinSettings.name][tostring(number)] = frame

	module:UpdateBarBG()

	return frame
end

---Register theme textures with LibSharedMedia for use in custom backgrounds
function module:RegisterThemeTextures()
	local LSM = SUI.Lib.LSM
	if not LSM then
		return
	end

	-- -- Define theme texture mappings
	-- local themeTextures = {
	-- 	War = {
	-- 		{ name = 'SUI War - StatusBar Alliance', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\StatusBar-Alliance.blp' },
	-- 		{ name = 'SUI War - StatusBar Horde', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\StatusBar-Horde.blp' },
	-- 		{ name = 'SUI War - StatusBar Neutral', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\StatusBar-Neutral.blp' },
	-- 		{ name = 'SUI War - Bar Background', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\Barbg.blp' },
	-- 		{ name = 'SUI War - Bar Background Alliance', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\Barbg-Alliance.blp' },
	-- 		{ name = 'SUI War - Bar Background Horde', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\Barbg-Horde.blp' },
	-- 	},
	-- 	Fel = {
	-- 		{ name = 'SUI Fel - StatusBar', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\StatusBar.png' },
	-- 		{ name = 'SUI Fel - Status Fill', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Status_bar_Fill.blp' },
	-- 	},
	-- 	Tribal = {
	-- 		{ name = 'SUI Tribal - StatusBar', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\images\\Statusbar.blp' },
	-- 		{ name = 'SUI Tribal - Bar Background', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\images\\Barbg.tga' },
	-- 	},
	-- 	Digital = {
	-- 		{ name = 'SUI Digital - Bar Background', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Digital\\Images\\BarBG.blp' },
	-- 	},
	-- 	Classic = {
	-- 		{ name = 'SUI Classic - Bar Backdrop 0', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Classic\\Images\\bar-backdrop0.blp' },
	-- 		{ name = 'SUI Classic - Bar Backdrop 1', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Classic\\Images\\bar-backdrop1.blp' },
	-- 		{ name = 'SUI Classic - Bar Backdrop 3', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Classic\\Images\\bar-backdrop3.blp' },
	-- 	},
	-- 	Minimal = {
	-- 		{ name = 'SUI Minimal - Bar Backdrop 1', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Minimal\\Images\\bar-backdrop1.blp' },
	-- 		{ name = 'SUI Minimal - Bar Backdrop 3', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Minimal\\Images\\bar-backdrop3.blp' },
	-- 	},
	-- 	Transparent = {
	-- 		{ name = 'SUI Transparent - Bar Backdrop 0', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Transparent\\Images\\bar-backdrop0.blp' },
	-- 		{ name = 'SUI Transparent - Bar Backdrop 1', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Transparent\\Images\\bar-backdrop1.blp' },
	-- 		{ name = 'SUI Transparent - Bar Backdrop 3', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Transparent\\Images\\bar-backdrop3.blp' },
	-- 	},
	-- 	Arcane = {
	-- 		{ name = 'SUI Arcane - StatusBar', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\StatusBar.tga' },
	-- 	},
	-- }

	-- -- Register all textures with LibSharedMedia
	-- for themeName, textures in pairs(themeTextures) do
	-- 	for _, texture in pairs(textures) do
	-- 		LSM:Register('statusbar', texture.name, texture.file)
	-- 	end
	-- end
end

SUI.Artwork = module
