local UF, L = SUI.UF, SUI.L

---@param frame table
---@param DB table
local function Build(frame, DB)
	local power = CreateFrame('StatusBar', nil, frame)
	SUI.BlizzAPI.SetFrameStrataSafe(power, DB.FrameStrata, frame)
	power:SetFrameLevel(DB.FrameLevel or 2)
	power:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	power:SetHeight(DB.height)

	if DB.orientation == 'VERTICAL' then
		power:SetOrientation('VERTICAL')
	end

	local bg = power:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(power)
	bg:SetTexture(UF:FindStatusBarTexture(DB.texture))
	bg:SetVertexColor(unpack(DB.bg.color))
	power.bg = bg

	local pos = DB.position or {}
	local relFrame = frame[pos.relativeTo] or frame.Health or frame
	local relPoint = pos.relativePoint or 'BOTTOM'
	local posY = pos.y
	if posY == nil then
		posY = -1
	end
	power:SetPoint('TOPLEFT', relFrame, relPoint .. 'LEFT', 0, posY)
	power:SetPoint('TOPRIGHT', relFrame, relPoint .. 'RIGHT', 0, posY)

	power.TextElements = {}
	for i, key in pairs(DB.text) do
		local NewString = power:CreateFontString(nil, 'OVERLAY')
		SUI.Font:Format(NewString, key.size, 'UnitFrames')
		NewString:SetJustifyH(key.SetJustifyH)
		NewString:SetJustifyV(key.SetJustifyV)
		NewString:SetPoint(key.position.anchor, power, key.position.anchor, key.position.x, key.position.y)
		frame:Tag(NewString, key.text or '')

		power.TextElements[i] = NewString
		if not key.enabled then
			power.TextElements[i]:Hide()
		end
	end

	local costPrediction = CreateFrame('StatusBar', nil, power)
	costPrediction:SetReverseFill(true)
	costPrediction:SetPoint('TOP')
	costPrediction:SetPoint('BOTTOM')
	costPrediction:SetPoint('RIGHT', power:GetStatusBarTexture())
	costPrediction:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	costPrediction:SetStatusBarColor(0, 0, 0, 0.5)
	costPrediction:Hide()
	power.CostPrediction = costPrediction

	-- Classic ships the standalone PowerPrediction element, which reads its
	-- bars from a table on the frame rather than off the Power element.
	if not SUI.IsRetail then
		frame.PowerPrediction = {
			mainBar = costPrediction,
		}
	end

	frame.Power = power
	frame.Power.colorPower = true
	frame.Power.frequentUpdates = true

	-- PostUpdate callback for auto-hide and visibility logic
	local canAccess = SUI.BlizzAPI.canaccessvalue
	frame.Power.PostUpdate = function(element, unit, cur, min, max)
		local powerDB = element.DB
		if not powerDB then
			return
		end

		local shouldHide = false

		-- Auto-hide: hide when power is 0 or unit has no power type
		if powerDB.autoHide then
			if cur and canAccess(cur) and max and canAccess(max) then
				if cur == 0 and max == 0 then
					shouldHide = true
				end
			end
		end

		-- Healer-only: only show on healer frames in group units
		if powerDB.onlyShowForHealer and not shouldHide then
			if unit then
				local role = UnitGroupRolesAssigned(unit)
				if role and canAccess(role) and role ~= 'HEALER' then
					shouldHide = true
				end
			end
		end

		-- Hide out of combat
		if powerDB.hideOutOfCombat and not shouldHide then
			if not UnitAffectingCombat(unit or 'player') then
				shouldHide = true
			end
		end

		if shouldHide then
			element:Hide()
		else
			element:Show()
		end
	end
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.Power
	local DB = settings or element.DB
	if element.CostPrediction then
		element.CostPrediction:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
		if not DB.PowerPrediction then
			element.CostPrediction:Hide()
			element.CostPrediction:SetValue(0)
		end
	end

	-- Handle custom coloring
	if DB.customColors and DB.customColors.useCustom then
		-- Disable automatic coloring when using custom colors
		element.colorPower = false
		-- Set custom color
		element:SetStatusBarColor(unpack(DB.customColors.barColor))
	else
		-- Enable automatic coloring
		element.colorPower = true
	end

	-- Set reverse fill direction
	element:SetReverseFill(DB.reverseFill or false)

	-- Set smooth animation (Retail hardware smoothing)
	if SUI.IsRetail and DB.smoothAnimation then
		element.smoothing = Enum.StatusBarInterpolation.Linear
	else
		element.smoothing = nil -- Disable hardware smoothing if turned off or on Classic
	end

	-- Basic Bar updates
	element:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	element.bg:SetTexture(UF:FindStatusBarTexture(DB.texture))

	-- Set background color (class color or custom color)
	if DB.bg.useClassColor then
		local color = (_G.CUSTOM_CLASS_COLORS and _G.CUSTOM_CLASS_COLORS[select(2, UnitClass('player'))]) or _G.RAID_CLASS_COLORS[select(2, UnitClass('player'))]
		local alpha = DB.bg.classColorAlpha or 0.2
		if color then
			element.bg:SetVertexColor(color.r, color.g, color.b, alpha)
		else
			element.bg:SetVertexColor(1, 1, 1, alpha)
		end
	else
		element.bg:SetVertexColor(unpack(DB.bg.color or { 1, 1, 1, 0.2 }))
	end

	for i, key in pairs(DB.text) do
		if element.TextElements[i] then
			local TextElement = element.TextElements[i]
			TextElement:SetJustifyH(key.SetJustifyH)
			TextElement:SetJustifyV(key.SetJustifyV)
			TextElement:ClearAllPoints()
			TextElement:SetPoint(key.position.anchor, element, key.position.anchor, key.position.x, key.position.y)
			frame:Tag(TextElement, key.text)

			if key.enabled then
				TextElement:Show()
			else
				TextElement:Hide()
			end
		end
	end

	element:ClearAllPoints()
	element:SetSize(DB.width or frame:GetWidth(), DB.height or 20)

	if DB.orientation == 'VERTICAL' then
		element:SetOrientation('VERTICAL')
	else
		element:SetOrientation('HORIZONTAL')
	end

	local pos = DB.position or {}
	local relFrame = frame[pos.relativeTo] or frame.Health or frame
	local relPoint = pos.relativePoint or 'BOTTOM'
	local posY = pos.y
	if posY == nil then
		posY = -1
	end
	element:SetPoint('TOPLEFT', relFrame, relPoint .. 'LEFT', 0, posY)
	element:SetPoint('TOPRIGHT', relFrame, relPoint .. 'RIGHT', 0, posY)
end

---@param frameName string
---@param OptionSet AceConfig.OptionsTable
local function Options(frameName, OptionSet)
	OptionSet.args.general = {
		name = '',
		type = 'group',
		inline = true,
		args = {
			orientation = {
				name = L['Bar orientation'],
				desc = L['Set the power bar to fill horizontally or vertically'],
				type = 'select',
				order = 0.5,
				values = {
					HORIZONTAL = L['Horizontal'],
					VERTICAL = L['Vertical'],
				},
			},
			reverseFill = {
				name = L['Reverse fill direction'],
				desc = L['Make the power bar fill right-to-left instead of left-to-right'],
				type = 'toggle',
				order = 1,
			},
			smoothAnimation = {
				name = L['Smooth bar animation'],
				desc = L['Animate power changes smoothly instead of instantly. Uses hardware acceleration on Retail, addon smoothing on Classic.'],
				type = 'toggle',
				order = 2,
			},
		},
	}

	OptionSet.args.visibility = {
		name = L['Visibility'],
		type = 'group',
		inline = true,
		order = 5,
		args = {
			autoHide = {
				name = L['Auto-hide when empty'],
				desc = L['Hide the power bar when the unit has no power (0/0)'],
				type = 'toggle',
				order = 1,
			},
			onlyShowForHealer = {
				name = L['Only show for healers'],
				desc = L['Only show the power bar on healer frames in groups'],
				type = 'toggle',
				order = 2,
			},
			hideOutOfCombat = {
				name = L['Hide outside combat'],
				desc = L['Hide the power bar when the unit is not in combat'],
				type = 'toggle',
				order = 3,
			},
		},
	}

	if frameName == 'player' then
		if SUI.IsRetail then
			OptionSet.args.PowerPrediction = {
				name = L['Enable power prediction'],
				desc = L['Used to represent cost of spells on top of the Power bar'],
				type = 'toggle',
				width = 'double',
				order = 10,
			}
		end
	end
	UF.Options:AddDynamicText(frameName, OptionSet, 'Power')
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	height = 10,
	width = false,
	FrameStrata = 'BACKGROUND',
	orientation = 'HORIZONTAL',
	reverseFill = false,
	smoothAnimation = false,
	autoHide = false,
	onlyShowForHealer = false,
	hideOutOfCombat = false,
	bg = {
		enabled = true,
		color = { 1, 1, 1, 0.2 },
		useClassColor = false,
		classColorAlpha = 0.2,
	},
	customColors = {
		useCustom = false,
		barColor = { 0, 0, 1, 1 },
	},
	text = {
		['1'] = {
			enabled = false,
			text = '[SUIPower(hideDead)][ / $>SUIPower(max,hideDead,hideZero)]',
			size = 10,
			SetJustifyH = 'CENTER',
			SetJustifyV = 'MIDDLE',
			position = {
				anchor = 'CENTER',
				x = 0,
				y = 0,
			},
		},
		['2'] = {
			enabled = false,
			text = '[perpp]%',
			size = 10,
			SetJustifyH = 'CENTER',
			SetJustifyV = 'MIDDLE',
			position = {
				anchor = 'CENTER',
				x = 0,
				y = 0,
			},
		},
	},
	position = {
		anchor = 'TOP',
		relativeTo = 'Health',
		relativePoint = 'BOTTOM',
		x = 0,
		y = -1,
	},
	config = {
		type = 'StatusBar',
	},
}

UF.Elements:Register('Power', Build, Update, Options, Settings)
