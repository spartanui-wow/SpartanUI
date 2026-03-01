---@class FramePositioning
---@field point AnchorPoint
---@field relativePoint AnchorPoint
---@field xOfs integer
---@field yOfs integer
local FramePositioning = {}

---@class SUI.UF.Unit.Settings
---@field anchor? FramePositioning
---@field elements? table<string, SUI.UF.Elements.Settings>
---@field visibility? UFrameVisibility
---@field config? SUI.UF.Unit.Config
local UFrameSettings = {
	enabled = true,
	width = 180,
	scale = 1,
	moved = false,
}

---@class SUI.UF.Unit.Config
---@field displayName? string
---@field useUnitWatch? boolean Visibility managed by oUF RegisterUnitWatch instead of VisibilityCheck
local config = {
	IsGroup = false,
	isChild = false,
	isFriendly = false,
}

---@class UFrameVisibility
local visibility = {
	alphaDelay = 1,
	hideDelay = 3,
	showAlways = false,
	showInCombat = true,
	showWithTarget = false,
	showInRaid = false,
	showInParty = false,
}

---@alias UnitFrameName
---|"player"
---|"target"
---|"targettarget"
---|"boss"
---|"bosstarget"
---|"raid"
---|"party"
---|"partypet"
---|"partytarget"
---|"arena"
---|"pet"
---|"pettarget"

---@class SUI.UF.Unit.Frame : frame, SUI.UF.Elements.Details
---@field unitOnCreate UnitFrameName
---@field DB SUI.UF.Unit.Settings
---@field elementList table<integer, SUI.UF.Elements.list>
---@field UpdateAll function
---@field ElementUpdate function
---@field mover frame
---@field config SUI.UF.Unit.Settings
---@field frames? table<integer, SUI.UF.Unit.Frame>
---@field header? frame
local SUIUnitFrame = {}
