local UF, L = SUI.UF, SUI.L

-- On WoW Forever combo points stay on the target they were built on. UnitPower keeps reporting
-- the old target's points after a target switch, so read the current target's instead.
local _, playerClass = UnitClass('player')
local TARGET_BOUND_COMBO_POINTS = SUI.IsForever and GetComboPoints and (playerClass == 'ROGUE' or playerClass == 'DRUID')

---@param element table
---@param max number
local function ShowTargetComboPoints(element, max)
	local unit = UnitHasVehicleUI('player') and 'vehicle' or 'player'
	local points = GetComboPoints(unit, 'target')
	if not points or not max or not SUI.BlizzAPI.canaccessvalue(points) or not SUI.BlizzAPI.canaccessvalue(max) then
		return
	end
	for i = 1, max do
		if element[i] then
			element[i]:SetValue(i <= points and 1 or 0)
		end
	end
end

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

	ClassPower.PostUpdate = function(element, cur, max, hasCurChanged, hasMaxChanged, powerType)
		if not element.DB then
			return
		end

		if TARGET_BOUND_COMBO_POINTS and powerType == 'COMBO_POINTS' then
			ShowTargetComboPoints(element, max)
		end

		local isPercentageFill = max == 1

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

	if TARGET_BOUND_COMBO_POINTS then
		local watcher = CreateFrame('Frame')
		watcher:RegisterEvent('PLAYER_TARGET_CHANGED')
		watcher:RegisterEvent('COMBO_TARGET_CHANGED')
		watcher:SetScript('OnEvent', function()
			if ClassPower.ForceUpdate and frame:IsElementEnabled('ClassPower') then
				ClassPower:ForceUpdate()
			end
		end)
	end

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
