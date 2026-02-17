---@class ElementProps
---@field DB SUI.UF.Elements.Settings
---@field TextElements table<integer, FontString>
local ElementProps = {}

---@class SUI.UF.Elements.Config
---@field NoBulkUpdate? boolean
---@field NoGenericOptions? boolean
---@field type? ElementType
---@field DisplayName? string
---@field Description? string
local ElementConfig = {}

---@alias ElementType
---|'Indicator'
---|'StatusBar'
---|'Text'
---|'Auras'
---|'General'

---@class SUI.UF.Element.Settings
---@field enabled boolean
---@field scale integer
---@field points boolean|table|string
---@field size integer|boolean
---@field FrameStrata FrameStrata
---@field FrameLevel integer
---@field config? SUI.UF.Elements.Config
---@field position SUI.UF.Elements.Positioning
---@field rules SUI.UF.Auras.Rules
local ElementSettings = {
	enabled = false,
	points = false,
	alpha = 1,
	width = 20,
	height = 20,
	size = false,
	scale = 1,
	FrameStrata = nil,
	FrameLevel = nil,
	bg = {
		enabled = false,
		texture = nil,
		color = false,
	},
}

---@class SUI.UF.Elements.Positioning
---@field anchor AnchorPoint
---@field relativeTo SUI.UF.Elements.list
---@field relativePoint AnchorPoint
local ElementPositioning = {
	anchor = 'CENTER',
	relativeTo = 'Frame',
	relativePoint = nil,
	x = 0,
	y = 0,
}

---@class FramePositioning
local FramePositioning = {}

---@class ElementTextData
---@field SetJustifyH JustifyH
---@field SetJustifyV JustifyV
---@field position SUI.UF.Elements.Positioning
local ElementTextData = {
	enabled = false,
	text = '',
	size = 10,
	SetJustifyH = 'CENTER',
	SetJustifyV = 'MIDDLE',
}

---@alias SUI.UF.Elements.list
---|"AdditionalPower"
---|"AssistantIndicator"
---|"AuraBars"
---|"Auras"
---|"Buffs"
---|"Castbar"
---|"ClassIcon"
---|"ClassPower"
---|"CombatIndicator"
---|"Debuffs"
---|"Dispel"
---|"GroupRoleIndicator"
---|"HappinessIndicator"
---|"Health"
---|"LeaderIndicator"
---|"Name"
---|"PhaseIndicator"
---|"Portrait"
---|"Power"
---|"PvPIndicator"
---|"QuestMob"
---|"RaidTargetIndicator"
---|"RaidRoleIndicator"
---|"Range"
---|"RareElite"
---|"ReadyCheckIndicator"
---|"RestingIndicator"
---|"ResurrectIndicator"
---|"Runes"
---|"SpartanArt"
---|"StatusText"
---|"SUI_RaidGroup"
---|"ThreatIndicator"
---|"Totems"

---@class SUI.UF.Elements.Details
---@field AdditionalPower ElementProps
---@field AssistantIndicator ElementProps
---@field AuraBars ElementProps
---@field Auras ElementProps
---@field Buffs ElementProps
---@field Castbar ElementProps
---@field ClassIcon ElementProps
---@field ClassPower ElementProps
---@field CombatIndicator ElementProps
---@field Debuffs ElementProps
---@field Dispel ElementProps
---@field GroupRoleIndicator ElementProps
---@field HappinessIndicator ElementProps
---@field Health ElementProps
---@field LeaderIndicator ElementProps
---@field Name ElementProps
---@field PhaseIndicator ElementProps
---@field Portrait ElementProps
---@field Power ElementProps
---@field PvPIndicator ElementProps
---@field QuestMob ElementProps
---@field RaidTargetIndicator ElementProps
---@field RaidRoleIndicator ElementProps
---@field Range ElementProps
---@field RareElite ElementProps
---@field ReadyCheckIndicator ElementProps
---@field RestingIndicator ElementProps
---@field ResurrectIndicator ElementProps
---@field Runes ElementProps
---@field SpartanArt ElementProps
---@field StatusText ElementProps
---@field SUI_RaidGroup ElementProps
---@field ThreatIndicator ElementProps
---@field Totems ElementProps
local SUIElements = {}
