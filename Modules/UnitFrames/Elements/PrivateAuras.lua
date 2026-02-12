local UF, L = SUI.UF, SUI.L

-- ============================================================
-- PRIVATE AURAS ELEMENT
-- Displays private auras (Blizzard-controlled raid mechanics)
--
-- Notes:
-- - Only works on player, party, and raid units (API restriction)
-- - Visual appearance controlled by Blizzard (cannot customize icons/textures)
-- - SUI provides positioning, sizing, and layout configuration
-- - Available in Retail and all Classic versions
-- ============================================================

---@param frame table
---@param DB table
local function Build(frame, DB)
	local PrivateAuras = CreateFrame('Frame', nil, frame)
	PrivateAuras:SetSize(DB.width or 180, DB.height or 30)

	-- Configure oUF PrivateAuras element options
	PrivateAuras.size = DB.size or 30
	PrivateAuras.spacing = DB.spacing or 0
	PrivateAuras.num = DB.num or 6
	PrivateAuras.disableCooldown = DB.disableCooldown or false
	PrivateAuras.disableCooldownText = DB.disableCooldownText or false
	PrivateAuras.initialAnchor = DB.initialAnchor or 'LEFT'
	PrivateAuras.growthX = DB.growthX or 'RIGHT'
	PrivateAuras.growthY = DB.growthY or 'UP'

	-- Set position
	if DB.position then
		PrivateAuras:ClearAllPoints()
		local relativeTo = DB.position.relativeTo and frame[DB.position.relativeTo] or frame
		PrivateAuras:SetPoint(DB.position.anchor or 'BOTTOM', relativeTo, DB.position.relativePoint or 'TOP', DB.position.x or 0, DB.position.y or 5)
	else
		-- Default: above the frame
		PrivateAuras:SetPoint('BOTTOM', frame, 'TOP', 0, 5)
	end

	frame.PrivateAuras = PrivateAuras
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.PrivateAuras
	if not element then
		return
	end

	local DB = settings or element.DB

	-- Update oUF element configuration
	element.size = DB.size or 30
	element.spacing = DB.spacing or 0
	element.num = DB.num or 6
	element.disableCooldown = DB.disableCooldown or false
	element.disableCooldownText = DB.disableCooldownText or false
	element.initialAnchor = DB.initialAnchor or 'LEFT'
	element.growthX = DB.growthX or 'RIGHT'
	element.growthY = DB.growthY or 'UP'

	-- Update size
	element:SetSize(DB.width or 180, DB.height or 30)

	-- Update position
	element:ClearAllPoints()
	if DB.position then
		local relativeTo = DB.position.relativeTo and frame[DB.position.relativeTo] or frame
		element:SetPoint(DB.position.anchor or 'BOTTOM', relativeTo, DB.position.relativePoint or 'TOP', DB.position.x or 0, DB.position.y or 5)
	else
		element:SetPoint('BOTTOM', frame, 'TOP', 0, 5)
	end

	-- Force oUF to update the private auras
	if frame:IsElementEnabled('PrivateAuras') then
		frame:DisableElement('PrivateAuras')
		frame:EnableElement('PrivateAuras')
	end
end

---@param frameName string
---@param OptionSet AceConfig.OptionsTable
local function Options(frameName, OptionSet)
	OptionSet.args.general = {
		name = L['General'],
		type = 'group',
		inline = true,
		order = 1,
		args = {
			size = {
				name = L['Icon size'],
				desc = L['Size of each private aura icon'],
				type = 'range',
				min = 16,
				max = 60,
				step = 1,
				order = 1,
			},
			num = {
				name = L['Number to show'],
				desc = L['Maximum number of private auras to display (typically 6)'],
				type = 'range',
				min = 1,
				max = 10,
				step = 1,
				order = 2,
			},
			spacing = {
				name = L['Spacing'],
				desc = L['Space between each private aura icon'],
				type = 'range',
				min = 0,
				max = 10,
				step = 1,
				order = 3,
			},
		},
	}

	OptionSet.args.display = {
		name = L['Display Options'],
		type = 'group',
		inline = true,
		order = 2,
		args = {
			disableCooldown = {
				name = L['Hide cooldown spiral'],
				desc = L['Hide the cooldown spiral on private aura icons'],
				type = 'toggle',
				order = 1,
			},
			disableCooldownText = {
				name = L['Hide cooldown text'],
				desc = L['Hide the countdown numbers on private aura icons'],
				type = 'toggle',
				order = 2,
			},
		},
	}

	OptionSet.args.growth = {
		name = L['Growth Direction'],
		type = 'group',
		inline = true,
		order = 3,
		args = {
			growthX = {
				name = L['Horizontal growth'],
				desc = L['Direction icons grow horizontally'],
				type = 'select',
				order = 1,
				values = {
					['RIGHT'] = L['Right'],
					['LEFT'] = L['Left'],
				},
			},
			growthY = {
				name = L['Vertical growth'],
				desc = L['Direction icons grow vertically'],
				type = 'select',
				order = 2,
				values = {
					['UP'] = L['Up'],
					['DOWN'] = L['Down'],
				},
			},
			initialAnchor = {
				name = L['Initial anchor'],
				desc = L['Starting anchor point for private aura layout'],
				type = 'select',
				order = 3,
				values = {
					['LEFT'] = L['Left'],
					['RIGHT'] = L['Right'],
					['TOP'] = L['Top'],
					['BOTTOM'] = L['Bottom'],
					['CENTER'] = L['Center'],
					['TOPLEFT'] = L['Top Left'],
					['TOPRIGHT'] = L['Top Right'],
					['BOTTOMLEFT'] = L['Bottom Left'],
					['BOTTOMRIGHT'] = L['Bottom Right'],
				},
			},
		},
	}

	OptionSet.args.info = {
		name = L['About Private Auras'],
		type = 'group',
		inline = true,
		order = 100,
		args = {
			description = {
				name = L['Private auras are special Blizzard-controlled auras used for raid mechanics. Their appearance cannot be customized by addons - only positioning and sizing can be configured.'],
				type = 'description',
				order = 1,
				fontSize = 'medium',
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	size = 30,
	spacing = 0,
	num = 6,
	width = 180,
	height = 30,
	disableCooldown = false,
	disableCooldownText = false,
	initialAnchor = 'LEFT',
	growthX = 'RIGHT',
	growthY = 'UP',
	position = {
		anchor = 'BOTTOM',
		relativeTo = 'Frame',
		relativePoint = 'TOP',
		x = 0,
		y = 5,
	},
	config = {
		type = 'Indicator',
	},
}

UF.Elements:Register('PrivateAuras', Build, Update, Options, Settings)
