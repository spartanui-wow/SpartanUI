local _, ns = ...
local M = ns.Messenger

---@class Messenger.UI
local UI = M.UI

function UI:Enable()
	self.Toast:Enable()
	self.Launcher:Enable()
	self.Fade:Enable()
	self.PopOut:Restore()
	M:Fire('UNREAD_CHANGED')
	C_Timer.After(6, function()
		if M.enabled then
			self.Toast:ShowIntro()
		end
	end)
end

function UI:Disable()
	self.Deck:Hide()
	self.PopOut:CloseAll()
	self.Toast:HideAll()
	self.Fade:Disable()
	self.Launcher:Update()
end

---The composer that currently has keyboard focus, if any.
---@return EditBox|nil
function UI:FocusedComposer()
	return M.Composer.Focused()
end
