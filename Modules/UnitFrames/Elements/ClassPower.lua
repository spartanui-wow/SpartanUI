local UF, L = SUI.UF, SUI.L

---@param frame table
---@param DB table
local function Build(frame, DB)
	if frame.unitOnCreate ~= 'player' then
		return
	end
	frame.CPAnchor = frame:CreateFontString(nil, 'BORDER')
	frame.CPAnchor:SetPoint('TOPLEFT', frame.Name, 'BOTTOMLEFT', 40, -5)
	local ClassPower = {}
	for index = 1, 10 do
		local Bar = CreateFrame('StatusBar', nil, frame)
		Bar:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))

		-- Create background texture
		local bg = Bar:CreateTexture(nil, 'BACKGROUND')
		bg:SetAllPoints(Bar)
		bg:SetTexture(UF:FindStatusBarTexture(DB.texture))
		bg:SetAlpha(0.3) -- Darken the background
		Bar.bg = bg

		-- Position and size.
		if index == 1 then
			Bar:SetPoint('LEFT', frame.CPAnchor, 'RIGHT', (index - 1) * Bar:GetWidth(), -1)
		else
			Bar:SetPoint('LEFT', ClassPower[index - 1], 'RIGHT', 3, 0)
		end
		ClassPower[index] = Bar
	end

	-- Add PostUpdate callback to handle percentage-fill resources
	ClassPower.PostUpdate = function(element, cur, max, hasMaxChanged, powerType)
		if not element.DB then
			return
		end

		-- Check if this is a percentage-fill resource (max = 1 bar)
		local isPercentageFill = max == 1

		-- Debug: show actual soul fragment count
		local actualFragments = 'N/A'
		if isPercentageFill and powerType == 'SOUL_FRAGMENTS' then
			local metamorphosis = C_UnitAuras.GetPlayerAuraBySpellID(1217607) -- SPELL_VOID_METAMORPHOSIS
			local spell = metamorphosis and 1227702 or 1225789 -- SPELL_SILENCE_THE_WHISPERS or SPELL_DARK_HEART
			local auraInfo = C_UnitAuras.GetPlayerAuraBySpellID(spell)
			if auraInfo then
				actualFragments = string.format('%d/%d', auraInfo.applications, metamorphosis and GetCollapsingStarCost() or C_Spell.GetSpellMaxCumulativeAuraApplications(1225789))
			end
		end

		if isPercentageFill then
			-- For percentage-fill resources (like soul fragments), make the bar full frame width
			local DB = element.DB
			local frame = element.__owner

			if frame then
				element[1]:ClearAllPoints()

				-- Span full frame width, positioned relative to configured element
				local relativeFrame = frame[DB.position.relativeTo] or frame

				-- Anchor left side to left edge of frame, right side to right edge of frame
				-- Vertically position below the relative element
				element[1]:SetPoint('LEFT', frame, 'LEFT', 0, 0)
				element[1]:SetPoint('RIGHT', frame, 'RIGHT', 0, 0)
				element[1]:SetPoint('TOP', relativeFrame, 'BOTTOM', 0, DB.position.y or -5)
				element[1]:SetHeight(DB.height)

				-- Update background to match
				if element[1].bg then
					element[1].bg:SetAllPoints(element[1])
				end
			end
		else
			-- Normal discrete bars - restore standard positioning
			local DB = element.DB
			local frame = element.__owner
			if frame then
				element[1]:ClearAllPoints()
				if DB.position.relativeTo == 'Frame' then
					element[1]:SetPoint(DB.position.anchor, frame, DB.position.relativePoint or DB.position.anchor, DB.position.x, DB.position.y)
				else
					element[1]:SetPoint(DB.position.anchor, frame[DB.position.relativeTo], DB.position.relativePoint or DB.position.anchor, DB.position.x, DB.position.y)
				end
				element[1]:SetSize(DB.width, DB.height)

				-- Update background to match
				if element[1].bg then
					element[1].bg:SetAllPoints(element[1])
				end
			end
		end
	end

	-- Register with oUF
	frame.ClassPower = ClassPower
end

---@param frame table
local function Update(frame)
	local element = frame.ClassPower
	local DB = element.DB

	if DB.position.relativeTo == 'Frame' then
		element[1]:SetPoint(DB.position.anchor, frame, DB.position.relativePoint or DB.position.anchor, DB.position.x, DB.position.y)
	else
		element[1]:SetPoint(DB.position.anchor, frame[DB.position.relativeTo], DB.position.relativePoint or DB.position.anchor, DB.position.x, DB.position.y)
	end

	-- Check if this is a percentage-fill resource (like soul fragments)
	-- oUF sets element.__max to track the maximum number of bars to show
	local isPercentageFill = element.__max and element.__max == 1
	local barWidth = DB.width
	local spacing = DB.spacing or 3

	-- For percentage-fill resources, make the single bar wider
	-- Calculate width as if showing 5 bars (width * 5 + spacing * 4)
	if isPercentageFill then
		barWidth = (DB.width * 5) + (spacing * 4)
		if SUI.logger then
			SUI.logger.debug(string.format('ClassPower: Percentage fill mode - __max=%s, width=%d->%d', tostring(element.__max), DB.width, barWidth))
		end
	end

	for i = 1, #element do
		-- Set size based on whether it's the primary bar in percentage mode
		if i == 1 and isPercentageFill then
			element[i]:SetSize(barWidth, DB.height)
		else
			element[i]:SetSize(DB.width, DB.height)
		end
		element[i]:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.ClassPower
	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.ClassPower[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.ClassPower[option] = val
		UF.Unit[unitName]:ElementUpdate('ClassPower')
	end

	OptionSet.args.texture = {
		type = 'select',
		dialogControl = 'LSM30_Statusbar',
		order = 2,
		width = 'double',
		name = L['Bar Texture'],
		desc = L['Select the texture used for the class power bars'],
		values = AceGUIWidgetLSMlists.statusbar,
		get = function()
			return ElementSettings.texture
		end,
		set = function(_, val)
			OptUpdate('texture', val)
		end,
	}

	OptionSet.args.display.args.height = {
		type = 'range',
		order = 1,
		name = L['Height'],
		desc = L['Set the height of the class power bars'],
		min = 1,
		max = 100,
		step = 1,
		get = function()
			return ElementSettings.height
		end,
		set = function(_, val)
			OptUpdate('height', val)
		end,
	}

	OptionSet.args.display.args.width = {
		type = 'range',
		order = 2,
		name = L['Width'],
		desc = L['Set the width of individual class power bars'],
		min = 1,
		max = 100,
		step = 1,
		get = function()
			return ElementSettings.width
		end,
		set = function(_, val)
			OptUpdate('width', val)
		end,
	}

	OptionSet.args.display.args.spacing = {
		type = 'range',
		order = 3,
		name = L['Spacing'],
		desc = L['Set the spacing between class power bars'],
		min = 0,
		max = 20,
		step = 1,
		get = function()
			return ElementSettings.spacing
		end,
		set = function(_, val)
			OptUpdate('spacing', val)
		end,
	}

	OptionSet.args.colors = {
		type = 'group',
		order = 4,
		name = L['Colors'],
		inline = true,
		args = {
			useClassColors = {
				type = 'toggle',
				order = 1,
				name = L['Use Class Colors'],
				desc = L['Use class-specific colors for power bars'],
				get = function()
					return ElementSettings.useClassColors
				end,
				set = function(_, val)
					OptUpdate('useClassColors', val)
				end,
			},
			customColor = {
				type = 'color',
				order = 2,
				name = L['Custom Color'],
				desc = L['Set a custom color for power bars'],
				disabled = function()
					return ElementSettings.useClassColors
				end,
				get = function()
					return unpack(ElementSettings.customColor or { 1, 1, 1 })
				end,
				set = function(_, r, g, b)
					OptUpdate('customColor', { r, g, b })
				end,
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	width = 16,
	height = 5,
	spacing = 3,
	position = {
		anchor = 'TOPLEFT',
		relativeTo = 'Name',
		relativePoint = 'BOTTOMLEFT',
		y = -5,
	},
	config = {
		NoBulkUpdate = true,
		type = 'Indicator',
		DisplayName = 'Class Power',
		Description = 'Controls the display of Combo Points, Arcane Charges, Chi Orbs, Holy Power, Soul Shards, and Soul Fragments',
	},
}

UF.Elements:Register('ClassPower', Build, Update, Options, Settings)
