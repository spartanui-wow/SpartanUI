local unpack, SUI, L, print, UF = unpack, SUI, SUI.L, SUI.print, SUI.UF
if SUI.IsRetail then
	return
end
local module = SUI:NewModule('Nameplates') ---@class SUI.Nameplates | SUI.Module
module.description = 'Basic nameplate module'
local Images = {
	Alliance = {
		bg = {
			Texture = 'Interface\\addons\\SpartanUI\\Images\\war\\UnitFrames',
			Coords = { 0, 0.458984375, 0.74609375, 1 }, --left, right, top, bottom
		},
		flair = {
			Texture = 'Interface\\addons\\SpartanUI\\Images\\war\\UnitFrames',
			Coords = { 0.03125, 0.427734375, 0, 0.421875 },
		},
	},
	Horde = {
		bg = {
			Texture = 'Interface\\addons\\SpartanUI\\Images\\war\\UnitFrames',
			Coords = { 0.572265625, 0.96875, 0.74609375, 1 }, --left, right, top, bottom
		},
		flair = {
			Texture = 'Interface\\addons\\SpartanUI\\Images\\war\\UnitFrames',
			Coords = { 0.541015625, 1, 0, 0.421875 },
		},
	},
}
local BarTexture = 'Interface\\AddOns\\SpartanUI\\images\\statusbars\\Smoothv2'
local NameplateList = {}
local ElementList = {
	'Auras',
	'ClassIcon',
	'Health',
	'Power',
	'Castbar',
	'RareElite',
	'RaidTargetIndicator',
	'QuestMob',
	'PvPIndicator',
	'ThreatIndicator',
	'PvPRoleIndicator',
	'Name',
	'Runes',
	'ClassPower',
	'TargetIndicator',
}
---@type table<SUI.UF.Elements.list, SUI.UF.Elements.Settings>
local ElementDefaults = {
	Runes = {
		enabled = true,
		texture = 'SpartanUI Default',
	},
	ClassPower = {
		enabled = true,
		width = 16,
		height = 6,
		texture = 'SpartanUI Default',
		position = {
			anchor = 'TOPLEFT',
			relativeTo = 'Frame',
			relativePoint = 'BOTTOMLEFT',
			x = 0,
			y = -2,
		},
	},
	QuestMob = {
		enabled = true,
		size = 16,
		position = {
			anchor = 'RIGHT',
			relativePoint = 'LEFT',
			x = 0,
			y = 0,
		},
	},
}

---@type table<SUI.UF.Elements.list, SUI.UF.Elements.Settings>
local CurrentSettings = {}

---@param frame any
---@param obj SUI.UF.Elements.list
local function BuildElement(frame, obj)
	--Ensure we have settings
	if not CurrentSettings[obj] then
		CurrentSettings[obj] = SUI:CopyData(SUI.UF.Elements:GetConfig(obj), {})
	end

	--Build it
	UF.Elements:Build(frame, obj, CurrentSettings[obj])
end

local UpdateElementState = function(frame)
	local elements = module.DB.elements

	frame.PvPIndicator.Override(frame, nil, frame.unit)

	-- Disable or enable elements that should not be enabled
	for _, item in ipairs(ElementList) do
		if frame[item] and elements[item].enabled then
			frame:EnableElement(item)
		else
			frame:DisableElement(item)
		end
	end
	-- Position Updates
	if InCombatLockdown() then
		return
	end

	for _, elementName in ipairs(ElementList) do
		local element = frame[elementName]
		local data = elements[elementName]

		-- Only process if element exists on this frame
		if element then
			-- Setup the Alpha scape and position
			element:SetAlpha(data.alpha)
			element:SetScale(data.scale)

			if UF.Elements:GetConfig(elementName).config.NoBulkUpdate then
				return
			end
			if UF.Elements:GetConfig(elementName).config.type == 'Indicator' and element.SetDrawLayer then
				element:SetDrawLayer('BORDER', 7)
			end

			-- Positioning
			element:ClearAllPoints()
			if data.points then
				if type(data.points) == 'string' then
					element:SetAllPoints(frame[data.points])
				elseif data.points and type(data.points) == 'table' then
					for _, key in pairs(data.points) do
						if key.relativeTo == 'Frame' then
							element:SetPoint(key.anchor, frame, key.anchor, key.x, key.y)
						else
							element:SetPoint(key.anchor, frame[key.relativeTo], key.anchor, key.x, key.y)
						end
					end
				else
					element:SetAllPoints(frame)
				end
			elseif data.position.anchor then
				if data.position.relativeTo == 'Frame' then
					element:SetPoint(data.position.anchor, frame, data.position.relativePoint or data.position.anchor, data.position.x, data.position.y)
				else
					element:SetPoint(data.position.anchor, frame[data.position.relativeTo], data.position.relativePoint or data.position.anchor, data.position.x, data.position.y)
				end
			end

			--Size it if we have a size change function for the element
			if element and data.enabled then
				element:ClearAllPoints()
				element:SetPoint(data.position.anchor, frame, data.position.relativePoint, data.position.x, data.position.y)

				--Size it if we have a size change function for the element
				if element.SizeChange then
					element:SizeChange()
				elseif data.size then
					element:SetSize(data.size, data.size)
				else
					element:SetSize(data.width or frame:GetWidth(), data.height or frame:GetHeight())
				end
			end

			-- Call the elements update function
			if frame[elementName] and data.enabled and frame[elementName].ForceUpdate then
				frame[elementName].ForceUpdate(element)
			end
		end
	end

	-- Power
	frame.Power:ClearAllPoints()
	if elements.Health.enabled then
		frame.Power:SetPoint('TOPLEFT', frame.Health, 'BOTTOMLEFT', 0, 0)
		frame.Power:SetPoint('TOPRIGHT', frame.Health, 'BOTTOMRIGHT', 0, 0)
	else
		frame.Power:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
		frame.Power:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
	end
	-- Castbar
	frame.Castbar:ClearAllPoints()
	if elements.Power.enabled then
		frame.Castbar:SetPoint('TOPLEFT', frame.Power, 'BOTTOMLEFT', 0, 0)
		frame.Castbar:SetPoint('TOPRIGHT', frame.Power, 'BOTTOMRIGHT', 0, 0)
	elseif elements.Health.enabled then
		frame.Castbar:SetPoint('TOPLEFT', frame.Health, 'BOTTOMLEFT', 0, 0)
		frame.Castbar:SetPoint('TOPRIGHT', frame.Health, 'BOTTOMRIGHT', 0, 0)
	else
		frame.Castbar:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
		frame.Castbar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
	end
end

local PlayerPowerIcons = function(frame, attachPoint)
	--Runes
	if select(2, UnitClass('player')) == 'DEATHKNIGHT' then
		BuildElement(frame, 'Runes')

		DeathKnightResourceOverlayFrame:HookScript('OnShow', function()
			DeathKnightResourceOverlayFrame:Hide()
		end)
	else
		BuildElement(frame, 'ClassPower')
	end
end

local NamePlateFactory = function(frame, unit)
	---#TODO: Cleanup the nameplate factory
	if unit:match('nameplate') then
		local blizzPlate = frame:GetParent().UnitFrame
		if blizzPlate then
			frame.blizzPlate = blizzPlate
			frame.widget = blizzPlate.WidgetContainer
		end

		frame.unitGUID = UnitGUID(unit)
		frame.unitOnCreate = 'Nameplate'
		-- Safely extract NPC ID, handling secret values
		if frame.unitGUID then
			local success, result = pcall(function()
				return select(6, strsplit('-', frame.unitGUID))
			end)
			frame.npcID = success and result or nil
		else
			frame.npcID = nil
		end

		local elementsDB = module.DB.elements
		local height = 0
		if elementsDB.Health.enabled then
			height = height + elementsDB.Health.height
		end
		if elementsDB.Power.enabled then
			height = height + elementsDB.Power.height
		end
		if elementsDB.Castbar.enabled then
			height = height + elementsDB.Castbar.height
		end

		frame:SetSize(module.DB.width, height)
		frame:SetPoint('CENTER', 0, 0)

		frame.raised = CreateFrame('Frame', nil, frame)
		local level = frame:GetFrameLevel() + 100
		frame.raised:SetFrameLevel(level)
		frame.raised.__owner = frame

		frame.bg = {}
		frame.bg.artwork = {}
		frame.bg.solid = frame:CreateTexture(nil, 'BACKGROUND')
		frame.bg.solid:SetAllPoints()
		frame.bg.solid:SetTexture(BarTexture)
		frame.bg.solid:SetVertexColor(0, 0, 0, 0.5)

		frame.bg.artwork.Neutral = frame:CreateTexture(nil, 'BACKGROUND')
		frame.bg.artwork.Neutral:SetAllPoints()
		frame.bg.artwork.Neutral:SetTexture(BarTexture)
		frame.bg.artwork.Neutral:SetVertexColor(0, 0, 0, 0.6)

		frame.bg.artwork.Alliance = frame:CreateTexture(nil, 'BACKGROUND')
		frame.bg.artwork.Alliance:SetAllPoints()
		frame.bg.artwork.Alliance:SetTexture(Images.Alliance.bg.Texture)
		frame.bg.artwork.Alliance:SetTexCoord(unpack(Images.Alliance.bg.Coords))
		frame.bg.artwork.Alliance:SetSize(frame:GetSize())

		frame.bg.artwork.Horde = frame:CreateTexture(nil, 'BACKGROUND')
		frame.bg.artwork.Horde:SetAllPoints()
		frame.bg.artwork.Horde:SetTexture(Images.Horde.bg.Texture)
		frame.bg.artwork.Horde:SetTexCoord(unpack(Images.Horde.bg.Coords))
		frame.bg.artwork.Horde:SetSize(frame:GetSize())

		-- Name
		BuildElement(frame, 'Name')

		-- health bar
		BuildElement(frame, 'ThreatIndicator')
		BuildElement(frame, 'RaidTargetIndicator')
		BuildElement(frame, 'ClassIcon')
		BuildElement(frame, 'QuestMob')
		BuildElement(frame, 'PvPRoleIndicator')

		BuildElement(frame, 'Health')
		BuildElement(frame, 'Power')
		frame.Power:SetWidth(module.DB.width)
		BuildElement(frame, 'Castbar')
		frame.Castbar:SetWidth(module.DB.width)

		BuildElement(frame, 'TargetIndicator')
		BuildElement(frame, 'WidgetXPBar')

		BuildElement(frame, 'PvPIndicator')
		frame.PvPIndicator.Override = function(self, event, unit)
			if unit ~= self.unit then
				return
			end
			local factionColor = {
				['Alliance'] = { 0, 0, 1, 0.3 },
				['Horde'] = { 1, 0, 0, 0.3 },
				['Neutral'] = { 0, 0, 0, 0.5 },
			}
			local settings = module.DB.elements
			self.bg.solid:Hide()
			self.bg.artwork.Neutral:Hide()
			self.bg.artwork.Alliance:Hide()
			self.bg.artwork.Horde:Hide()

			if not settings.Background.enabled then
				return
			end

			local factionGroup = UnitFactionGroup(unit) or 'Neutral'
			if settings.Background.type == 'solid' then
				self.bg.solid:Show()
				if settings.Background.colorMode == 'faction' and factionGroup then
					self.bg.solid:SetVertexColor(unpack(factionColor[factionGroup]))
				elseif settings.Background.colorMode == 'reaction' then
					local colors = SUIUF.colors.reaction[UnitReaction(unit, 'player')]
					if colors then
						if colors[1] == 0.9 and colors[2] == 0.7 then
							self.bg.solid:SetVertexColor(0.5, 0.5, 0.5, 0.5)
						else
							self.bg.solid:SetVertexColor(colors[1], colors[2], colors[3])
						end
					else
						self.bg.solid:SetVertexColor(0, 0, 0)
					end
				else
					self.bg.solid:SetVertexColor(0, 0, 0)
				end
				self.bg.solid:SetAlpha(settings.Background.alpha)
			else
				if factionGroup then
					self.bg.artwork[factionGroup]:Show()
					self.bg.artwork[factionGroup]:SetAlpha(settings.Background.alpha)
				else
					self.bg.artwork.Neutral:Show()
					self.bg.artwork.Neutral:SetAlpha(settings.Background.alpha)
				end
			end
		end

		-- Hots/Dots
		local Auras = CreateFrame('Frame', unit .. 'Auras', frame)
		Auras:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', 0, 2)
		Auras:SetSize(frame:GetWidth(), 16)
		if UnitReaction(unit, 'player') <= 2 then
			if module.DB.onlyShowPlayer and module.DB.showStealableBuffs then
				Auras.showStealableBuffs = module.DB.showStealableBuffs
			else
				Auras.onlyShowPlayer = module.DB.onlyShowPlayer
				Auras.showStealableBuffs = module.DB.showStealableBuffs
			end
		else
			Auras.onlyShowPlayer = module.DB.onlyShowPlayer
		end

		frame.Auras = Auras

		-- Rare Elite indicator
		local RareElite = frame:CreateTexture(nil, 'BACKGROUND', nil, -2)
		RareElite:SetTexture('Interface\\Addons\\SpartanUI\\Images\\status-glow')
		RareElite:SetAlpha(0.6)
		RareElite:SetAllPoints(frame)
		frame.RareElite = RareElite

		-- WidgetXPBar
		if SUI.IsRetail then
			local WidgetXPBar = CreateFrame('StatusBar', frame:GetDebugName() .. 'WidgetXPBar', frame)
			-- WidgetXPBar:SetFrameStrata(frame:GetFrameStrata())
			WidgetXPBar:SetFrameLevel(5)
			WidgetXPBar:SetStatusBarTexture(BarTexture)
			WidgetXPBar:SetSize(frame:GetWidth(), elementsDB.XPBar.height)
			WidgetXPBar:SetPoint('TOP', frame, 'BOTTOM', 0, elementsDB.XPBar.Offset)
			WidgetXPBar:SetStatusBarColor(0, 0.5, 1, 0.7)

			WidgetXPBar.bg = WidgetXPBar:CreateTexture(nil, 'BACKGROUND')
			WidgetXPBar.bg:SetAllPoints()
			WidgetXPBar.bg:SetTexture(BarTexture)
			WidgetXPBar.bg:SetVertexColor(0, 0, 0, 0.5)

			WidgetXPBar.Rank = WidgetXPBar:CreateFontString()
			WidgetXPBar.Rank:SetJustifyH('LEFT')
			WidgetXPBar.Rank:SetJustifyV('MIDDLE')
			WidgetXPBar.Rank:SetAllPoints(WidgetXPBar)
			SUI.Font:Format(WidgetXPBar.Rank, 7, 'Nameplate')

			WidgetXPBar.ProgressText = WidgetXPBar:CreateFontString()
			WidgetXPBar.ProgressText:SetJustifyH('CENTER')
			WidgetXPBar.ProgressText:SetJustifyV('MIDDLE')
			WidgetXPBar.ProgressText:SetAllPoints(WidgetXPBar)
			SUI.Font:Format(WidgetXPBar.ProgressText, 7, 'Nameplate')

			frame.WidgetXPBar = WidgetXPBar
		end

		-- Setup Player Icons
		if module.DB.ShowPlayerPowerIcons then
			local attachPoint = 'Castbar'
			if not elementsDB.Castbar.enabled then
				if elementsDB.Power.enabled then
					attachPoint = 'Power'
				else
					attachPoint = 'Health'
				end
			end

			PlayerPowerIcons(frame, attachPoint)
		end

		-- Setup Scale
		frame:SetScale(module.DB.Scale)
	end
end

local NameplateCallback = function(self, event, unit)
	if not self or not unit or event == 'NAME_PLATE_UNIT_REMOVED' then
		return
	end

	-- Verify this is an oUF frame before calling oUF methods
	-- This prevents errors when other nameplate addons (Plater, KuiNameplates, etc.) are active
	if not self.UpdateAllElements or not self.EnableElement or not self.DisableElement then
		return
	end

	-- UnitNameplateShowsWidgetsOnly is Retail-only
	self.ShowWidgetOnly = SUI.IsRetail and UnitNameplateShowsWidgetsOnly(unit) or false

	local elementDB = module.DB.elements
	if event == 'NAME_PLATE_UNIT_ADDED' then
		local blizzPlate = self:GetParent().UnitFrame
		if blizzPlate then
			self.blizzPlate = blizzPlate
			self.widget = blizzPlate.WidgetContainer
		end
		self.unitGUID = UnitGUID(unit)
		-- Safely extract NPC ID, handling secret values
		if self.unitGUID then
			local success, result = pcall(function()
				return select(6, strsplit('-', self.unitGUID))
			end)
			self.npcID = success and result or nil
		else
			self.npcID = nil
		end

		NameplateList[self:GetName()] = true

		self:UpdateAllElements('ForceUpdate')

		if self.ShowWidgetOnly then
			self.widgetContainer = self.blizzPlate.WidgetContainer
			if self.widgetContainer then
				if not UnitInPartyIsAI(unit) and not UnitPlayerControlled(unit) then
					for _, element in ipairs(ElementList) do
						if self:IsElementEnabled(element) then
							self:DisableElement(element)
							if self[element] then
								self[element]:Hide()
							end
						end
					end
				end

				self.widgetContainer:SetParent(self)
				self.widgetContainer:ClearAllPoints()
				self.widgetContainer:SetPoint('TOP', self, 'BOTTOM')

				local function skinWidgets()
					local widgetCount = 0
					for _, widget in pairs(self.widgetContainer.widgetFrames) do
						if widget then
							SUI.Skins.SkinWidgets(widget)
							widgetCount = widgetCount + 1
						end
					end

					if widgetCount == 0 then
						-- If no widgets were found, try again after a short delay
						C_Timer.After(0.1, skinWidgets)
					end
				end
				skinWidgets()
			end
			if not UnitInPartyIsAI(unit) and not UnitPlayerControlled(unit) then
				return
			end
		end
	elseif event == 'NAME_PLATE_UNIT_REMOVED' then
		NameplateList[self:GetName()] = false
	end

	for _, item in ipairs(ElementList) do
		if self[item] and elementDB[item].enabled then
			self:EnableElement(item)
		else
			self:DisableElement(item)
		end
	end

	for element, _ in pairs(self.elementList) do
		if self[element] and elementDB[element] then
			self[element].DB = elementDB[element]
			UF.Elements:Update(self, element, elementDB[element])
		end
	end

	-- Update elements
	UpdateElementState(self)

	-- Update Player Icons
	if UnitIsUnit(unit, 'player') and event == 'NAME_PLATE_UNIT_ADDED' then
		if self.Runes then
			self:EnableElement('Runes')
			self.Runes:ForceUpdate()
		elseif self.ClassPower then
			self:EnableElement('ClassPower')
			self.ClassPower:ForceUpdate()
		end
	else
		if self.Runes then
			self:DisableElement('Runes')
		elseif self.ClassPower then
			self:DisableElement('ClassPower')
		end
	end

	-- Set the Scale of the nameplate
	self:SetScale(module.DB.Scale)
end

function module:UpdateNameplates()
	for k, v in pairs(NameplateList) do
		if v then
			UpdateElementState(_G[k])
		end
	end
end

function module:OnInitialize()
	---#TODO: convert to new element settings process
	---@class SUI.NamePlates.Settings
	local defaults = {
		ShowTarget = true,
		onlyShowPlayer = true,
		showStealableBuffs = false,
		Scale = 1,
		width = 128,
		elements = {
			['**'] = {
				enabled = false,
				Scale = 1,
				points = false,
				alpha = 1,
				scale = 1,
				FrameLevel = nil,
				FrameStrata = nil,
				bg = {
					enabled = false,
					color = false,
				},
				text = {
					['**'] = {
						enabled = false,
						text = '',
						size = 10,
						SetJustifyH = 'CENTER',
						SetJustifyV = 'MIDDLE',
						position = {
							anchor = 'CENTER',
							x = 0,
							y = 0,
						},
					},
					['1'] = {
						enabled = false,
						position = {},
					},
					['2'] = {
						enabled = false,
						position = {},
					},
				},
				position = {
					anchor = 'CENTER',
					x = 0,
					y = 0,
				},
			},
			Auras = {},
			Background = {
				type = 'solid',
				colorMode = 'reaction',
				alpha = 0.35,
			},
			Dispel = {},
			RareElite = {},
			Name = {
				enabled = true,
				textSize = 7,
				SetJustifyH = 'LEFT',
				SetJustifyV = 'MIDDLE',
				text = '[SUI_ColorClass][name]',
				position = {
					anchor = 'LEFT',
					relativeTo = 'Health',
					relativePoint = 'LEFT',
					x = 3,
					y = 0,
				},
			},
			Health = {
				enabled = true,
				height = 8,
				offset = 0,
				texture = 'SpartanUI Default',
				colorReaction = true,
				colorSmooth = true,
				colorClass = true,
				colorTapping = true,
				colorDisconnected = true,
				bg = {
					enabled = true,
					color = { 1, 1, 1, 0.3 },
				},
				text = {
					['1'] = {
						enabled = true,
						size = 5,
						text = '[SUIHealth(percentage)]',
						position = {
							anchor = 'RIGHT',
							x = -2,
							y = 0,
						},
					},
				},
			},
			Power = {
				enabled = false,
				height = 3,
				offset = 1,
				texture = 'SpartanUI Default',
				bg = {
					enabled = true,
					color = { 1, 1, 1, 0.2 },
				},
				text = {
					['1'] = {
						enabled = false,
						text = '[power:current-formatted] / [power:max-formatted]',
					},
					['2'] = {
						enabled = false,
						text = '[perpp]%',
					},
				},
			},
			PvPIndicator = {
				size = 10,
			},
			ThreatIndicator = {},
			Castbar = {
				enabled = true,
				width = false,
				height = 5,
				offset = -6,
				interruptable = true,
				FlashOnInterruptible = true,
				latency = false,
				InterruptSpeed = 0.1,
				texture = 'SpartanUI Default',
				bg = {
					enabled = true,
					color = { 1, 1, 1, 0.2 },
				},
				Icon = {
					enabled = false,
					size = 12,
					position = {
						anchor = 'LEFT',
						x = 0,
						y = 0,
					},
				},
				text = {
					['1'] = {
						enabled = true,
						text = '[Spell name]',
						position = {
							anchor = 'CENTER',
							x = 0,
							y = 0,
						},
					},
					['2'] = {
						enabled = true,
						text = '[Spell timer]',
						size = 8,
						position = {
							anchor = 'RIGHT',
							x = 0,
							y = 0,
						},
					},
				},
			},
			ClassIcon = {
				enabled = false,
				size = 20,
				VisibleOn = 'PlayerControlled',
				position = {
					anchor = 'TOP',
					x = 0,
					y = 40,
				},
			},
			RaidTargetIndicator = {
				enabled = true,
				size = 15,
				position = {
					anchor = 'BOTTOMRIGHT',
					x = 0,
					y = 0,
				},
			},
			QuestMob = {
				enabled = true,
				size = 16,
				position = {
					anchor = 'RIGHT',
					relativePoint = 'LEFT',
					x = 0,
					y = 0,
				},
			},
			XPBar = {
				height = 5,
				Offset = -10,
			},
			PvPRoleIndicator = {
				enabled = true,
				size = 20,
				position = {
					anchor = 'BOTTOM',
					relativeTo = 'Name',
					relativePoint = 'TOP',
					x = 0,
					y = 7,
				},
				['**'] = {
					display = true,
				},
				friendly = {
					display = true,
					alertonDamage = false,
					damageThreshold = 10000,
				},
				enemy = {},
			},
			Runes = {
				enabled = true,
				texture = 'SpartanUI Default',
			},
			ClassPower = {
				enabled = true,
				width = 16,
				height = 6,
				texture = 'SpartanUI Default',
				position = {
					anchor = 'TOPLEFT',
					relativeTo = 'Frame',
					relativePoint = 'BOTTOMLEFT',
					x = 0,
					y = -2,
				},
			},
			TargetIndicator = {
				enabled = true,
				ShowTarget = true,
				mode = 'texture',
				texture = {
					textureKey = 'DoubleArrow',
					placement = 'sides',
					scale = 1.0,
					color = { 1, 1, 1, 1 },
					alpha = 1.0,
				},
				border = {
					size = 2,
					color = { 1, 1, 0, 1 },
					sides = { top = true, bottom = true, left = true, right = true },
					displayLevel = 5,
				},
			},
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('Nameplates', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.NamePlates.Settings

	-- Register for sequential profile refresh with UpdateAllNameplates
	SUI.DBM:RegisterSequentialProfileRefresh(module, 'UpdateAllNameplates')

	-- Migrate old settings
	if SUI.DB.Nameplates then
		print('Nameplate DB Migration')
		module.DB = SUI:MergeData(module.DB, SUI.DB.Nameplates, true)
		SUI.DB.Nameplates = nil
	end

	SUIUF:RegisterStyle('Spartan_NamePlates', NamePlateFactory)
end

function module:OnDisable()
	SUI.opt.args.Modules.args.Nameplates.enabled = false
end

function module:OnEnable()
	module:BuildOptions()
	if SUI:IsModuleDisabled('Nameplates') then
		return
	end

	-- Check if other nameplate addons are active and skip initialization
	local otherNameplateAddons = { 'Plater', 'KuiNameplates', 'ThreatPlates', 'TidyPlates', 'NeatPlates' }
	for _, addonName in ipairs(otherNameplateAddons) do
		if C_AddOns.IsAddOnLoaded(addonName) then
			if SUI.logger then
				SUI.logger.info('Nameplate addon "' .. addonName .. '" detected - SpartanUI Nameplates disabled')
			end
			return
		end
	end

	--Make sure we start fresh before spawning nameplates
	CurrentSettings = {}
	for _, v in ipairs(ElementList) do
		--Import base options
		CurrentSettings[v] = SUI:CopyData(ElementDefaults[v], SUI.UF.Elements:GetConfig(v))
		--Import User settings from elements table
		SUI:CopyData(CurrentSettings[v], module.DB.elements[v] or {})
	end

	if not oUF_NamePlateDriver then
		SUIUF:SetActiveStyle('Spartan_NamePlates')
		SUIUF:SpawnNamePlates(nil, NameplateCallback)

		-- oUF is not hiding the mana bar. So we need to hide it.
		if ClassNameplateManaBarFrame then
			ClassNameplateManaBarFrame:HookScript('OnShow', function()
				ClassNameplateManaBarFrame:Hide()
			end)
		end
	end
end

---Update all active nameplates with new profile settings
function module:UpdateAllNameplates()
	-- Update CurrentSettings cache with new profile data
	for objName, defaults in pairs(ElementDefaults) do
		CurrentSettings[objName] = SUI:CopyData(SUI.UF.Elements:GetConfig(objName), {})
	end

	-- Update all existing nameplates
	for _, nameplate in pairs(NameplateList) do
		if nameplate and nameplate.unitFrame then
			UpdateElementState(nameplate.unitFrame)
		end
	end

	if module.logger then
		module.logger.info('Updated all nameplates for new profile')
	end
end

function module:BuildOptions()
	local Options = UF.Options
	local function toInt(val)
		if val then
			return 1
		end
		return 0
	end
	local function toBool(val)
		if tonumber(val) == 1 then
			return true
		else
			return false
		end
	end

	---@type AceConfig.OptionsTable
	local OptSet = Options:CreateFrameOptionSet(L['Nameplates'], function(info)
		return module.DB[info[#info]]
	end, function(info, val)
		module.DB[info[#info]] = val
		module:UpdateNameplates()
	end)
	OptSet.disabled = function()
		return SUI:IsModuleDisabled(module)
	end
	OptSet.args.General.args.Display = {
		name = L.Display,
		type = 'group',
		order = 1,
		args = {
			width = {
				name = L['Frame width'],
				type = 'input',
				order = 1,
			},
			Scale = {
				name = L['Scale'],
				type = 'range',
				width = 'full',
				min = 0.01,
				max = 3,
				step = 0.01,
				order = 2,
			},
		},
	}
	OptSet.args.General.args.Blizzard = {
		name = L['Blizzard display options'],
		type = 'group',
		args = {
			nameplateShowAll = {
				name = UNIT_NAMEPLATES_AUTOMODE,
				desc = OPTION_TOOLTIP_UNIT_NAMEPLATES_AUTOMODE,
				type = 'toggle',
				width = 'double',
				get = function(info)
					return toBool(GetCVar('nameplateShowAll'))
				end,
				set = function(info, val)
					SetCVar('nameplateShowAll', toInt(val))
				end,
			},
			nameplateShowSelf = {
				name = DISPLAY_PERSONAL_RESOURCE,
				desc = OPTION_TOOLTIP_UNIT_NAMEPLATES_AUTOMODE,
				type = 'toggle',
				width = 'double',
				get = function(info)
					return toBool(GetCVar('nameplateShowSelf'))
				end,
				set = function(info, val)
					SetCVar('nameplateShowSelf', toInt(val))
				end,
			},
			nameplateMotion = {
				name = UNIT_NAMEPLATES_TYPES,
				desc = function(info)
					if GetCVar('nameplateMotion') == '1' then
						return UNIT_NAMEPLATES_TYPE_TOOLTIP_2
					else
						return UNIT_NAMEPLATES_TYPE_TOOLTIP_1
					end
				end,
				type = 'select',
				values = { ['1'] = UNIT_NAMEPLATES_TYPE_2, ['0'] = UNIT_NAMEPLATES_TYPE_1 },
				get = function(info)
					return GetCVar('nameplateMotion')
				end,
				set = function(info, val)
					SetCVar('nameplateMotion', tonumber(val))
				end,
			},
		},
	}

	for _, elementName in ipairs(ElementList) do
		local config = UF.Elements:GetConfig(elementName).config

		--TODO: Right now these are the same, but in the future they will not be
		local ElementSettings = module.DB.elements[elementName]
		local UserSetting = module.DB.elements[elementName]

		---@type AceConfig.OptionsTable
		local ElementOptSet = {
			name = config.DisplayName and L[config.DisplayName] or elementName,
			desc = config.Description or '',
			type = 'group',
			order = 1,
			get = function(info)
				return ElementSettings[info[#info]] or false
			end,
			set = function(info, val)
				--Update memory
				ElementSettings[info[#info]] = val
				--Update the DB
				UserSetting[info[#info]] = val
				-- TODO: Update the frame
			end,
			args = {},
		}

		local PositionGet = function(info)
			return ElementSettings.position[info[#info]]
		end
		local PositionSet = function(info, val)
			if val == elementName then
				SUI:Print(L['Cannot set position to self'])
				return
			end
			--Update memory
			ElementSettings.position[info[#info]] = val
			--Update the DB
			UserSetting.position[info[#info]] = val
			-- TODO: Update the frame
		end

		if config.type == 'General' then
		elseif config.type == 'StatusBar' then
			-- TODO
			-- Options:StatusBarDefaults(frameName, ElementOptSet, elementName)
		elseif config.type == 'Indicator' then
			Options:IndicatorAddDisplay(ElementOptSet)
			Options:AddPositioning(ElementList, ElementOptSet, PositionGet, PositionSet)
		elseif config.type == 'Text' then
			--TODO
		elseif config.type == 'Auras' then
			--TODO
		end

		-- Helper function to override get/set functions recursively
		local function OverrideGetSet(optTable, path)
			for key, option in pairs(optTable) do
				if option.args then
					-- Recursively handle nested groups
					OverrideGetSet(option.args, path)
				elseif option.get or option.set then
					-- Override get function
					if option.get then
						option.get = function(info)
							local setting = ElementSettings
							for _, pathKey in ipairs(path) do
								setting = setting[pathKey]
							end
							local value = setting[info[#info]]
							if option.type == 'color' and value then
								return unpack(value, 1, 4)
							else
								return value
							end
						end
					end

					-- Override set function
					if option.set then
						option.set = function(info, val, ...)
							local setting = ElementSettings
							local userSetting = UserSetting
							for _, pathKey in ipairs(path) do
								setting = setting[pathKey]
								userSetting = userSetting[pathKey]
							end

							if option.type == 'color' then
								setting[info[#info]] = { val, ... }
								userSetting[info[#info]] = { val, ... }
							else
								setting[info[#info]] = val
								userSetting[info[#info]] = val
							end
							module:UpdateNameplates()
						end
					end
				end
			end
		end

		--Add element-specific options using shared system where available
		if elementName == 'Name' then
			-- Add nameplate-specific text format option
			ElementOptSet.args.text = {
				name = L['Text'] or 'Text',
				type = 'input',
				width = 'full',
				multiline = true,
				order = 10,
				desc = 'Text format for nameplate names. Use [difficulty][level] [SUI_ColorClass][name] or custom format.',
				get = function()
					return ElementSettings.text or '[SUI_ColorClass][name]'
				end,
				set = function(_, val)
					ElementSettings.text = val
					UserSetting.text = val
					module:UpdateNameplates()
				end,
			}

			-- Add positioning controls for Name element
			ElementOptSet.args.position = {
				name = L['Position'] or 'Position',
				type = 'group',
				inline = true,
				order = 20,
				args = {
					anchor = {
						name = L['Anchor Point'] or 'Anchor Point',
						type = 'select',
						order = 1,
						values = {
							TOPLEFT = L['Top Left'] or 'Top Left',
							TOP = L['Top'] or 'Top',
							TOPRIGHT = L['Top Right'] or 'Top Right',
							LEFT = L['Left'] or 'Left',
							CENTER = L['Center'] or 'Center',
							RIGHT = L['Right'] or 'Right',
							BOTTOMLEFT = L['Bottom Left'] or 'Bottom Left',
							BOTTOM = L['Bottom'] or 'Bottom',
							BOTTOMRIGHT = L['Bottom Right'] or 'Bottom Right',
						},
						get = function()
							return ElementSettings.position and ElementSettings.position.anchor or 'BOTTOM'
						end,
						set = function(_, val)
							ElementSettings.position = ElementSettings.position or {}
							ElementSettings.position.anchor = val
							UserSetting.position = UserSetting.position or {}
							UserSetting.position.anchor = val
							module:UpdateNameplates()
						end,
					},
					relativePoint = {
						name = L['Relative Point'] or 'Relative Point',
						type = 'select',
						order = 2,
						values = {
							TOPLEFT = L['Top Left'] or 'Top Left',
							TOP = L['Top'] or 'Top',
							TOPRIGHT = L['Top Right'] or 'Top Right',
							LEFT = L['Left'] or 'Left',
							CENTER = L['Center'] or 'Center',
							RIGHT = L['Right'] or 'Right',
							BOTTOMLEFT = L['Bottom Left'] or 'Bottom Left',
							BOTTOM = L['Bottom'] or 'Bottom',
							BOTTOMRIGHT = L['Bottom Right'] or 'Bottom Right',
						},
						get = function()
							return ElementSettings.position and ElementSettings.position.relativePoint or 'TOP'
						end,
						set = function(_, val)
							ElementSettings.position = ElementSettings.position or {}
							ElementSettings.position.relativePoint = val
							UserSetting.position = UserSetting.position or {}
							UserSetting.position.relativePoint = val
							module:UpdateNameplates()
						end,
					},
					x = {
						name = L['X Offset'] or 'X Offset',
						type = 'range',
						order = 3,
						min = -100,
						max = 100,
						step = 1,
						get = function()
							return ElementSettings.position and ElementSettings.position.x or 0
						end,
						set = function(_, val)
							ElementSettings.position = ElementSettings.position or {}
							ElementSettings.position.x = val
							UserSetting.position = UserSetting.position or {}
							UserSetting.position.x = val
							module:UpdateNameplates()
						end,
					},
					y = {
						name = L['Y Offset'] or 'Y Offset',
						type = 'range',
						order = 4,
						min = -100,
						max = 100,
						step = 1,
						get = function()
							return ElementSettings.position and ElementSettings.position.y or 0
						end,
						set = function(_, val)
							ElementSettings.position = ElementSettings.position or {}
							ElementSettings.position.y = val
							UserSetting.position = UserSetting.position or {}
							UserSetting.position.y = val
							module:UpdateNameplates()
						end,
					},
				},
			}

			-- Add text justification controls
			ElementOptSet.args.justify = {
				name = L['Text Alignment'] or 'Text Alignment',
				type = 'group',
				inline = true,
				order = 30,
				args = {
					SetJustifyH = {
						name = L['Horizontal'] or 'Horizontal',
						type = 'select',
						order = 1,
						values = {
							LEFT = L['Left'] or 'Left',
							CENTER = L['Center'] or 'Center',
							RIGHT = L['Right'] or 'Right',
						},
						get = function()
							return ElementSettings.SetJustifyH or 'CENTER'
						end,
						set = function(_, val)
							ElementSettings.SetJustifyH = val
							UserSetting.SetJustifyH = val
							module:UpdateNameplates()
						end,
					},
					SetJustifyV = {
						name = L['Vertical'] or 'Vertical',
						type = 'select',
						order = 2,
						values = {
							TOP = L['Top'] or 'Top',
							MIDDLE = L['Middle'] or 'Middle',
							BOTTOM = L['Bottom'] or 'Bottom',
						},
						get = function()
							return ElementSettings.SetJustifyV or 'MIDDLE'
						end,
						set = function(_, val)
							ElementSettings.SetJustifyV = val
							UserSetting.SetJustifyV = val
							module:UpdateNameplates()
						end,
					},
				},
			}

			-- Add text size control
			ElementOptSet.args.textSize = {
				name = L['Text Size'] or 'Text Size',
				type = 'range',
				order = 40,
				min = 6,
				max = 20,
				step = 1,
				get = function()
					return ElementSettings.textSize or 8
				end,
				set = function(_, val)
					ElementSettings.textSize = val
					UserSetting.textSize = val
					module:UpdateNameplates()
				end,
			}
		elseif elementName == 'Health' or elementName == 'Power' or elementName == 'Castbar' then
			-- Use the existing StatusBarDefaults to get all the standard options
			Options:StatusBarDefaults('player', ElementOptSet, elementName)
			-- Override the main options to work with nameplate settings structure
			OverrideGetSet(ElementOptSet.args, {})
			-- Note: Skip AddDynamicText as it requires UF.CurrentSettings structure
			-- Note: Other elements use shared building but require UF.CurrentSettings structure for options
		end

		-- Add element-specific options that aren't covered by shared system
		if elementName == 'Castbar' then
			ElementOptSet.args.FlashOnInterruptible = {
				name = L['Flash on interruptible cast'] or 'Flash on interruptible cast',
				type = 'toggle',
				width = 'double',
				order = 10,
				get = function()
					return ElementSettings.FlashOnInterruptible
				end,
				set = function(_, val)
					ElementSettings.FlashOnInterruptible = val
					UserSetting.FlashOnInterruptible = val
					module:UpdateNameplates()
				end,
			}
			ElementOptSet.args.InterruptSpeed = {
				name = L['Interrupt flash speed'] or 'Interrupt flash speed',
				type = 'range',
				width = 'double',
				min = 0.01,
				max = 1,
				step = 0.01,
				order = 11,
				get = function()
					return ElementSettings.InterruptSpeed
				end,
				set = function(_, val)
					ElementSettings.InterruptSpeed = val
					UserSetting.InterruptSpeed = val
					module:UpdateNameplates()
				end,
			}
			ElementOptSet.args.interruptable = {
				name = L['Show interrupt or spell steal'] or 'Show interrupt or spell steal',
				type = 'toggle',
				width = 'double',
				order = 20,
				get = function()
					return ElementSettings.interruptable
				end,
				set = function(_, val)
					ElementSettings.interruptable = val
					UserSetting.interruptable = val
					module:UpdateNameplates()
				end,
			}
			ElementOptSet.args.latency = {
				name = L['Show latency'] or 'Show latency',
				type = 'toggle',
				order = 21,
				get = function()
					return ElementSettings.latency
				end,
				set = function(_, val)
					ElementSettings.latency = val
					UserSetting.latency = val
					module:UpdateNameplates()
				end,
			}
		end

		if not ElementOptSet.args.enabled then
			--Add a disable check to all args
			for k, v in pairs(ElementOptSet.args) do
				v.disabled = function()
					return not ElementSettings.enabled
				end
			end

			ElementOptSet.args.enabled = {
				name = L['Enabled'],
				type = 'toggle',
				order = 1,
			}
		end
		-- Add element option to screen
		OptSet.args[config.type].args[elementName] = ElementOptSet
	end

	SUI.opt.args.Modules.args.Nameplates = OptSet
end
