---@class SUI
local SUI = SUI
local L = SUI.L
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- On clients with Edit Mode, some visible frames are placed by the game rather than by
-- SpartanUI. Move mode outlines them so players know where they are and how to move them,
-- without SpartanUI touching them (opening Edit Mode from addon code can taint it).

---@class SUI.MoveIt.BlizzardFrames
local BlizzardFrames = {}
MoveIt.BlizzardFrames = BlizzardFrames

local CANDIDATES = {
	{ frame = 'ChatFrame1', label = 'Chat window' },
	{ frame = 'ObjectiveTrackerFrame', label = 'Quest tracker' },
	{ frame = 'BuffFrame', label = 'Buffs' },
	{ frame = 'DebuffFrame', label = 'Debuffs' },
	{ frame = 'PlayerCastingBarFrame', label = 'Cast bar' },
	{ frame = 'GameTooltipDefaultContainer', label = 'Tooltip' },
	{ frame = 'BagsBar', label = 'Bags' },
	{ frame = 'MicroMenuContainer', label = 'Game menu buttons' },
	{ frame = 'LootFrame', label = 'Loot window' },
}

local HOW_TO = "This is placed by the game's Edit Mode. To move it, close frame moving, press Escape and choose Edit Mode."

local boxes = {}

---@return boolean
function BlizzardFrames:IsSupported()
	return C_EditMode ~= nil
end

---@param index number
---@return Button
local function GetBox(index)
	local box = boxes[index]
	if box then
		return box
	end
	box = CreateFrame('Button', nil, UIParent)
	box:SetFrameStrata('DIALOG')
	box:SetFrameLevel(2)
	box.border = Style:CreateBorder(box)
	box.border:SetColor(1, 1, 1, 0.3)
	box.label = Style:CreateText(box, 10, Style.color.muted)
	box.label:SetPoint('TOPLEFT', 4, -4)
	box.label:SetPoint('RIGHT', box, 'RIGHT', -4, 0)
	box.label:SetJustifyH('LEFT')
	box.label:SetWordWrap(false)
	box.sub = Style:CreateText(box, 9, Style.color.faint)
	box.sub:SetPoint('TOPLEFT', box.label, 'BOTTOMLEFT', 0, -1)
	box.sub:SetText(L['Moved in Edit Mode'])
	box:SetScript('OnEnter', function(self)
		self.border:SetColor(1, 1, 1, 0.7)
		GameTooltip:SetOwner(self, 'ANCHOR_CURSOR')
		GameTooltip:SetText(self.label:GetText() or '', 1, 1, 1)
		GameTooltip:AddLine(L[HOW_TO], nil, nil, nil, true)
		GameTooltip:Show()
	end)
	box:SetScript('OnLeave', function(self)
		self.border:SetColor(1, 1, 1, 0.3)
		GameTooltip:Hide()
	end)
	box:SetScript('OnClick', function()
		if MoveIt.ControlToolbar then
			MoveIt.ControlToolbar:SetHint(L[HOW_TO])
		end
	end)
	boxes[index] = box
	return box
end

---Outline game-placed frames that are on screen
function BlizzardFrames:Show()
	self:Hide()
	if not self:IsSupported() then
		return
	end
	local used = 0
	for _, candidate in ipairs(CANDIDATES) do
		local frame = _G[candidate.frame]
		local width = frame and frame.GetWidth and frame:GetWidth()
		if frame and frame:IsVisible() and width and width > 1 and not frame.mover then
			used = used + 1
			local box = GetBox(used)
			box:ClearAllPoints()
			box:SetAllPoints(frame)
			box.label:SetText(L[candidate.label])
			box:Show()
		end
	end
end

function BlizzardFrames:Hide()
	for _, box in ipairs(boxes) do
		box:Hide()
	end
end
