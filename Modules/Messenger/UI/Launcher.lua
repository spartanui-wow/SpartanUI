local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local L = M.L

-- Data broker launcher with the unread count, and an optional minimap button.

---@class Messenger.Launcher
local Ln = {}
M.UI.Launcher = Ln

local BROKER_NAME = 'LibsMessenger'

function Ln:Enable()
	if self.object then
		self:Update()
		return
	end
	local LDB = LibStub('LibDataBroker-1.1', true)
	if not LDB then
		return
	end
	local path, left, right, top, bottom = T.IconCoords('bubble')
	self.object = LDB:NewDataObject(BROKER_NAME, {
		type = 'data source',
		label = L['Messenger'],
		text = '0',
		icon = path,
		iconCoords = { left, right, top, bottom },
		OnClick = function(_, button)
			if button == 'RightButton' then
				M:OpenOptions()
			else
				M:Toggle()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(L['Messenger'], 1, 1, 1)
			local unread = M.Store:TotalUnread()
			if unread > 0 then
				tooltip:AddLine(string.format(L['%d unread messages'], unread), T.color.text[1], T.color.text[2], T.color.text[3])
			else
				tooltip:AddLine(L['No unread messages'], T.color.muted[1], T.color.muted[2], T.color.muted[3])
			end
			tooltip:AddLine(' ')
			local key = M:GetToggleKeyText()
			if key then
				tooltip:AddLine(string.format(L['Click or press %s to open. Right-click for settings.'], key), T.color.muted[1], T.color.muted[2], T.color.muted[3])
			else
				tooltip:AddLine(L['Click to open. Right-click for settings.'], T.color.muted[1], T.color.muted[2], T.color.muted[3])
			end
		end,
	})

	local Icon = LibStub('LibDBIcon-1.0', true)
	if Icon then
		Icon:Register(BROKER_NAME, self.object, M.settings.minimap)
		self.icon = Icon
	end

	M:On('UNREAD_CHANGED', function()
		Ln:Update()
	end)
	self:Update()
end

function Ln:Update()
	if self.object then
		local unread = M.enabled and M.Store:TotalUnread() or 0
		self.object.text = tostring(unread)
	end
end

---@param show boolean
function Ln:SetMinimapShown(show)
	M.settings.minimap.hide = not show
	if self.icon then
		if show then
			self.icon:Show(BROKER_NAME)
		else
			self.icon:Hide(BROKER_NAME)
		end
	end
end
