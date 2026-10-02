---@class SUI
local SUI = SUI

-- The game's color picker in the window kit: no crest (it is a small dialog) and its title in a
-- framed plaque on the top edge, where the game draws its own header.
-- The skin is a separate frame kept just under the picker, so it never touches the picker's own
-- fields or the order its parts draw in.

local skin

---Hide the art the game draws for the picker's frame and title (all clients)
---@param picker Frame
local function HideBlizzardArt(picker)
	if picker.Border then
		picker.Border:SetAlpha(0)
	end
	if picker.Header then
		picker.Header:SetAlpha(0)
	end
	-- Classic clients: a backdrop on the picker itself, a header texture and an unnamed title
	if picker.ClearBackdrop then
		picker:ClearBackdrop()
	end
	if _G.ColorPickerFrameHeader then
		_G.ColorPickerFrameHeader:SetAlpha(0)
	end
	for _, region in ipairs({ picker:GetRegions() }) do
		if region:GetObjectType() == 'FontString' and region:GetText() == _G.COLOR_PICKER then
			region:SetAlpha(0)
		end
	end
end

---Background just under the picker, frame and title plaque just over its parts
local function KeepUnder(picker)
	local level = picker:GetFrameLevel()
	if skin.pickerLevel == level and skin:GetFrameStrata() == picker:GetFrameStrata() then
		return
	end
	skin.pickerLevel = level
	skin:SetFrameStrata(picker:GetFrameStrata())
	skin:SetFrameLevel(math.max(0, level - 2))
	skin.VisualRoot:SetFrameLevel(math.max(0, level - 1))
	skin.FrameArt:SetFrameLevel(level + 40)
	skin.TitleFrame:SetFrameLevel(level + 45)
end

local function OnEnable()
	local picker = ColorPickerFrame
	local Kit = LibAT and LibAT.UI and LibAT.UI.Kit
	if skin or not picker or not Kit or not Kit.DressShell then
		return
	end
	if SUI:IsAddonEnabled('Skinner') or SUI:IsAddonEnabled('ConsolePort') then
		return
	end

	skin = CreateFrame('Frame', 'SUI_ColorPickerSkin', UIParent)
	skin:SetAllPoints(picker)
	skin:Hide()
	Kit:DressShell(skin, { title = _G.COLOR_PICKER or 'Color Picker', crest = false, titleFrame = true, titleBar = false, close = false })
	HideBlizzardArt(picker)

	-- The picker rises when clicked; the skin follows it so nothing slips in between
	skin:SetScript('OnUpdate', function()
		KeepUnder(picker)
	end)
	picker:HookScript('OnShow', function(self)
		KeepUnder(self)
		skin:Show()
	end)
	picker:HookScript('OnHide', function()
		skin:Hide()
	end)
	if picker:IsShown() then
		KeepUnder(picker)
		skin:Show()
	end
end

SUI.Skins:Register('ColorPicker', OnEnable)
