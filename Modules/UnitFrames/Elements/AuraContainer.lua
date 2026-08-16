---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

-- Shared implementation for the three aura containers: Buffs, Debuffs and a
-- custom one.
--
-- Each is its own AuraContainer with its own anchor, growth direction, icon
-- size and filters, which is what lets buffs sit above the frame growing up
-- while debuffs sit below growing down. A single container cannot do that: the
-- growth direction and the flow layout belong to the container, not to the
-- groups inside it.
--
-- Groups within one container are filter variants of the same aura type - the
-- ones you cast and the ones everyone else cast - drawn at the same size and
-- flowing together on purpose.

local Container = {}
UF.AuraContainer = Container

---Translate one container's settings into the options AddGroup expects.
---@param element table
---@param DB table
---@param variant string 'player' or 'others'
---@return table
local function BuildGroupSettings(element, DB, variant)
	local function number(value, fallback)
		return type(value) == 'number' and value or fallback
	end

	local size = number(DB.size, 24)

	return {
		maxFrameCount = number(DB.number, 10),
		size = size,
		sortMethod = UF.Auras:GetSortMethod(DB.sortMethod),
		sortDirection = UF.Auras:GetSortDirection(DB.sortDirection),
		candidateFilters = UF.Auras:BuildCandidateFilters(DB),

		showCount = DB.showCount ~= false,
		showDuration = DB.showDuration ~= false,
		showBuffBorder = DB.showBuffBorder,
		showDebuffBorder = DB.showDebuffBorder,
		showBuffIndicator = DB.showBuffIndicator,
		showDebuffIndicator = DB.showDebuffIndicator,
		showStealableBorder = DB.showStealableBorder,
		dispelBorderStyle = DB.dispelBorderStyle,
		disableCooldown = DB.showCooldown == false,
		disableMouse = DB.clickThrough,
		cancelButton = DB.cancelButton,

		durationColors = UF.Auras:GetDurationColorCurve(DB.expiring),
		durationText = DB.durationText,
		stackText = DB.stackText,

		layout = {
			elementSpacing = number(DB.spacing, 2),
			lineSpacing = number(DB.lineSpacing, number(DB.spacing, 2)),
			groupSpacing = number(DB.groupSpacing, 4),
		},

		CreateButton = function(auraElement, options, button)
			UF.Auras:CreateAuraButton(auraElement, options, button)
			button.auraVariant = variant
			UF.Auras:StyleButton(button, DB, element)
		end,
	}
end

---Build a container and attach its filter variants.
---@param frame table
---@param elementName string
---@param DB table
---@param baseFilter string 'HELPFUL' or 'HARMFUL'
---@return table|nil
function Container:Build(frame, elementName, DB, baseFilter)
	if not UF.Auras:HasNativeContainers() then
		return
	end

	-- Containers cannot be removed once created, so a second build would leave
	-- the first drawing its own copy of every aura.
	if frame[elementName] then
		self:Update(frame, elementName, DB, baseFilter)
		return frame[elementName]
	end

	-- A pixel of padding on the side the rows grow towards. Without it the
	-- first row sits flush against the container edge and clips.
	local growDown = (DB.growthy or 'UP') == 'DOWN'

	local element = frame:CreateAuras({
		initialAnchor = DB.position and DB.position.anchor or 'TOPLEFT',
		growthX = DB.growthx or 'RIGHT',
		growthY = DB.growthy or 'UP',
		layoutLimit = UF.Auras:GetLayoutLimit(DB, frame),
		paddingTop = growDown and 1 or 0,
		paddingBottom = growDown and 0 or 1,
	})

	element.DB = DB
	element.baseFilter = baseFilter
	element.elementName = elementName
	element.groupKeys = {}
	frame[elementName] = element

	UF.Auras:PositionContainer(element, frame, DB)
	UF.Auras:AttachVariants(element, DB, baseFilter, BuildGroupSettings)

	-- A disabled container still has live groups, and a group matches auras
	-- whether or not the container is shown, so its filters are pointed at
	-- nothing until it is turned on. Without this a disabled container draws
	-- the same auras as an enabled one over the top of it.
	UF.Auras:ApplyContainerFilters(element, DB, baseFilter)
	UF.Auras:ScheduleContainerStateSync(frame)

	return element
end

---@param frame table
---@param elementName string
---@param settings? table
---@param baseFilter? string
function Container:Update(frame, elementName, settings, baseFilter)
	local element = frame[elementName]
	if not element then
		return
	end

	local DB = settings or element.DB
	element.DB = DB
	element.baseFilter = baseFilter or element.baseFilter

	if not DB.enabled then
		element:SetEnabled(false)
		return
	end

	UF.Auras:PositionContainer(element, frame, DB)

	if UF.Auras:VariantsNeedRepoint(element, DB) then
		UF.Auras:RepointVariants(frame, element, DB)
		return
	end

	element:SetEnabled(true)
	element:ForceUpdate()
end

---Settings shared by all three containers. Each element adds its own defaults.
---@param displayName string
---@param overrides table
---@return SUI.UF.Elements.Settings
function Container:Settings(displayName, overrides)
	local settings = {
		enabled = true,
		config = {
			type = 'Auras',
			DisplayName = displayName,
			-- The container owns its own anchoring and sizing; the generic
			-- element pipeline would fight the flow layout.
			NoBulkUpdate = true,
		},
		position = {
			anchor = 'TOPLEFT',
			relativeTo = 'Frame',
			x = 0,
			y = 0,
		},
		growthx = 'RIGHT',
		growthy = 'UP',
		number = 16,
		size = 24,
		spacing = 2,
		perRow = 8,
		-- Auras others cast are shown alongside your own by default.
		showOthers = true,
	}

	for key, value in pairs(overrides) do
		settings[key] = value
	end

	return settings
end
