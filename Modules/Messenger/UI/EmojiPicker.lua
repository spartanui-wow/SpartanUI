local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local W = M.Widgets
local L = M.L

-- Emoji grid that opens above a composer and types the picked code into it.

---@class Messenger.EmojiPicker
local EP = {}
M.UI.EmojiPicker = EP

local CELL = 28
local PER_ROW = 8
local PAD = 8

local picker

local function Build()
	local E = M.Emoji
	local rows = math.ceil(#E.list / PER_ROW)
	picker = CreateFrame('Frame', 'MessengerEmojiPicker', UIParent)
	picker:SetSize(PER_ROW * CELL + PAD * 2, rows * CELL + PAD * 2 + 20)
	picker:SetFrameStrata('FULLSCREEN_DIALOG')
	picker:SetClampedToScreen(true)
	picker:EnableMouse(true)
	T.Fill(picker, T.color.popup)
	T.Border(picker, T.color.edgeStrong)
	picker:Hide()
	tinsert(UISpecialFrames, 'MessengerEmojiPicker')

	picker.hint = T.Text(picker, 'meta', T.color.faint)
	picker.hint:SetPoint('BOTTOMLEFT', PAD, 7)
	picker.hint:SetText(L['Pick one, or type it: :) :fire: <3'])

	for i, entry in ipairs(E.list) do
		local btn = CreateFrame('Button', nil, picker)
		btn:SetSize(CELL, CELL)
		local col = (i - 1) % PER_ROW
		local row = math.floor((i - 1) / PER_ROW)
		btn:SetPoint('TOPLEFT', PAD + col * CELL, -PAD - row * CELL)
		btn.hl = T.Fill(btn, T.color.hover)
		btn.hl:Hide()
		btn.icon = btn:CreateTexture(nil, 'ARTWORK')
		btn.icon:SetSize(CELL - 8, CELL - 8)
		btn.icon:SetPoint('CENTER')
		btn.icon:SetTexture(E:Path(entry.file))
		btn:SetScript('OnEnter', function(self)
			self.hl:Show()
			picker.hint:SetText(entry.code)
			T.SetColor(picker.hint, T.color.text)
		end)
		btn:SetScript('OnLeave', function(self)
			self.hl:Hide()
			picker.hint:SetText(L['Pick one, or type it: :) :fire: <3'])
			T.SetColor(picker.hint, T.color.faint)
		end)
		btn:SetScript('OnClick', function()
			local edit = picker.edit
			if edit and edit:IsEnabled() then
				local text = edit:GetText() or ''
				local insert = entry.code
				if text ~= '' and not text:find('%s$') then
					insert = ' ' .. insert
				end
				edit:Insert(insert .. ' ')
				edit:SetFocus()
			end
			if not IsShiftKeyDown() then
				picker:Hide()
			end
		end)
	end

	picker:SetScript('OnEvent', function(self)
		if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
			self:Hide()
		end
	end)
	picker:SetScript('OnShow', function(self)
		pcall(self.RegisterEvent, self, 'GLOBAL_MOUSE_DOWN')
	end)
	picker:SetScript('OnHide', function(self)
		pcall(self.UnregisterEvent, self, 'GLOBAL_MOUSE_DOWN')
	end)
end

---Opens the picker above a button for the given edit box, or closes it when already open there.
---@param owner Frame
---@param edit EditBox
function EP:Toggle(owner, edit)
	if not picker then
		Build()
	end
	if picker:IsShown() and picker.owner == owner then
		picker:Hide()
		return
	end
	W.CloseMenu()
	picker.owner = owner
	picker.edit = edit
	picker:ClearAllPoints()
	picker:SetPoint('BOTTOMRIGHT', owner, 'TOPRIGHT', 0, 4)
	picker:Show()
end
