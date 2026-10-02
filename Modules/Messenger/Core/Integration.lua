local _, ns = ...
local M = ns.Messenger
local U = M.Util
local L = M.L

-- Hooks into the rest of the game UI. Every hook here only reads Blizzard state and acts on
-- Messenger's own frames, with one opt-out exception: taking over whispers started in the normal
-- chat box (see TakeOver). That closes the Blizzard edit box from addon code, which can leave its
-- state addon-touched; SendChatMessage is restricted for addon-touched code during chat
-- lockdown, so the player chose this trade knowingly and it can be turned off.

---@class Messenger.Integration
local I = {}
M.Integration = I

----------------------------------------------------------------------------------------------------
-- Shift-click links into the composer
----------------------------------------------------------------------------------------------------

local lastLink, lastLinkTime

local function OnInsertLink(text)
	if not M.enabled or type(text) ~= 'string' then
		return
	end
	local box = M.UI:FocusedComposer()
	if not box then
		return
	end
	-- The same click can reach both the new and the legacy function name
	local now = GetTime()
	if lastLink == text and lastLinkTime == now then
		return
	end
	lastLink, lastLinkTime = text, now
	box:Insert(text)
end

----------------------------------------------------------------------------------------------------
-- "Message in Messenger" on player right-click menus
----------------------------------------------------------------------------------------------------

local MENU_TAGS = {
	'MENU_UNIT_PLAYER',
	'MENU_UNIT_TARGET',
	'MENU_UNIT_FOCUS',
	'MENU_UNIT_PARTY',
	'MENU_UNIT_RAID',
	'MENU_UNIT_RAID_PLAYER',
	'MENU_UNIT_FRIEND',
	'MENU_UNIT_BN_FRIEND',
	'MENU_UNIT_GUILD',
	'MENU_UNIT_CHAT_ROSTER',
	'MENU_UNIT_COMMUNITIES_GUILD_MEMBER',
	'MENU_UNIT_COMMUNITIES_WOW_MEMBER',
	'MENU_UNIT_RECENT_ALLY',
}

---Works out who a player menu is for. Returns a Battle.net entry or a Name-Realm string.
---@param contextData table
---@return table|nil bnEntry, string|nil fullName
local function MenuTarget(contextData)
	if type(contextData) ~= 'table' then
		return nil
	end
	local bnID = U.Num(contextData.bnetIDAccount)
	if bnID then
		return M.Contacts:GetBNetByID(bnID), nil
	end
	local unit = U.Str(contextData.unit)
	if unit then
		local ok, isPlayer = pcall(UnitIsPlayer, unit)
		if not ok or U.IsSecret(isPlayer) or not isPlayer then
			return nil
		end
	end
	local name = U.Str(contextData.name)
	if not name then
		return nil
	end
	local full = U.JoinName(name, contextData.server or contextData.surname)
	if not full or U.SameName(full, U.PlayerFullName()) then
		return nil
	end
	return nil, full
end

local function AddMenuEntry(_, rootDescription, contextData)
	if not M.enabled then
		return
	end
	local bnEntry, full = MenuTarget(contextData)
	if not bnEntry and not full then
		return
	end
	rootDescription:CreateDivider()
	rootDescription:CreateButton(L['Message in Messenger'], function()
		if bnEntry then
			M:OpenBNet(bnEntry, true)
		else
			M:OpenWhisper(full, true)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Reply key
----------------------------------------------------------------------------------------------------

-- Whispers hidden from the main chat never become the game's "last whisper", so the normal
-- Reply key would answer whoever last reached the main chat. While Messenger holds whispers,
-- the keys bound to Reply are pointed at Messenger's own reply instead. Override bindings are
-- temporary: the player's saved key bindings are never changed.

local bindingOwner = CreateFrame('Frame')
local appliedKeys = ''
local pendingKeys = false

---@return boolean
local function WantReplyKey()
	local route = M.settings and M.settings.routes.WHISPER
	return M.enabled and M.settings.replyKey and M.host and M.host.replyBinding ~= nil and route and route.capture and route.hide or false
end

function I:ApplyReplyKey()
	if InCombatLockdown() then
		pendingKeys = true
		return
	end
	pendingKeys = false
	local keys = {}
	if WantReplyKey() then
		for _, key in ipairs({ GetBindingKey('REPLY') }) do
			keys[#keys + 1] = key
		end
	end
	local signature = table.concat(keys, ',')
	if signature == appliedKeys then
		return
	end
	appliedKeys = signature
	ClearOverrideBindings(bindingOwner)
	for _, key in ipairs(keys) do
		SetOverrideBinding(bindingOwner, false, key, M.host.replyBinding)
	end
end

----------------------------------------------------------------------------------------------------
-- Whispers started in the normal chat box open in Messenger instead
----------------------------------------------------------------------------------------------------

local hookedBoxes = setmetatable({}, { __mode = 'k' })
local takingOver = false

---@return boolean
local function WantTakeOver()
	local route = M.settings and M.settings.routes.WHISPER
	return M.enabled and M.settings.takeOverWhispers and route and route.capture or false
end

---Moves a whisper the player just started in the Blizzard chat box into Messenger.
---@param editBox EditBox
local function TakeOver(editBox)
	if takingOver or not WantTakeOver() or U.IsRestricted() or not editBox:HasFocus() then
		return
	end
	local chatType = editBox:GetAttribute('chatType')
	if chatType ~= 'WHISPER' and chatType ~= 'BN_WHISPER' then
		return
	end
	local target = U.Str(editBox:GetAttribute('tellTarget'))
	if not target then
		return
	end
	local bnEntry
	if chatType == 'BN_WHISPER' then
		bnEntry = M.Contacts:GetBNetByAccountName(target) or M.Contacts:GetBNetByTag(target)
		if not bnEntry then
			return
		end
	end

	-- Let Blizzard finish parsing ("/w Name ") before the box is touched
	C_Timer.After(0, function()
		if takingOver or not editBox:HasFocus() or editBox:GetAttribute('chatType') ~= chatType or U.IsRestricted() then
			return
		end
		takingOver = true
		local draft = editBox:GetText() or ''
		editBox:SetAttribute('tellTarget', nil)
		editBox:SetAttribute('chatType', 'SAY')
		local sticky = editBox:GetAttribute('stickyType')
		if sticky == 'WHISPER' or sticky == 'BN_WHISPER' then
			-- Otherwise the next Enter would reopen a whisper and bounce straight back here
			editBox:SetAttribute('stickyType', 'SAY')
		end
		editBox:SetText('')
		local escape = editBox:GetScript('OnEscapePressed')
		if escape then
			escape(editBox)
			-- The first Escape may only close the name suggestions
			if editBox:HasFocus() then
				escape(editBox)
			end
		else
			editBox:ClearFocus()
		end
		takingOver = false

		if bnEntry then
			M:OpenBNet(bnEntry, true)
		else
			M:OpenWhisper(target, true)
		end
		local box = M.UI:FocusedComposer()
		if box and draft ~= '' then
			box:SetText(draft)
		end
	end)
end

---@param editBox EditBox|nil
local function HookEditBox(editBox)
	if not editBox or hookedBoxes[editBox] then
		return
	end
	hookedBoxes[editBox] = true
	if type(editBox.UpdateHeader) == 'function' then
		hooksecurefunc(editBox, 'UpdateHeader', TakeOver)
	end
end

local function InstallTakeOver()
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		HookEditBox(_G['ChatFrame' .. i .. 'EditBox'])
	end
	-- New chat windows get their edit boxes hooked the first time they open
	if ChatFrameUtil and ChatFrameUtil.ActivateChat then
		hooksecurefunc(ChatFrameUtil, 'ActivateChat', HookEditBox)
	end
	if ChatEdit_ActivateChat then
		hooksecurefunc('ChatEdit_ActivateChat', HookEditBox)
	end
	-- Older clients update the header through a global function instead of a method
	if ChatEdit_UpdateHeader then
		hooksecurefunc('ChatEdit_UpdateHeader', function(editBox)
			if editBox and type(editBox.UpdateHeader) ~= 'function' then
				TakeOver(editBox)
			end
		end)
	end
end

---Binds a key to a command in the player's saved key bindings, replacing any key the command
---had. An empty key just clears it. Key bindings cannot change in combat.
---@param command string
---@param key string|nil
---@return boolean changed
function I:SetKey(command, key)
	if InCombatLockdown() then
		return false
	end
	for _, old in ipairs({ GetBindingKey(command) }) do
		SetBinding(old)
	end
	if key and key ~= '' then
		SetBinding(key, command)
	end
	SaveBindings(GetCurrentBindingSet())
	return true
end

local pendingDefaultKey = false

---Gives the open/close binding its default key (Ctrl+O) once per character, but only when the
---player has not bound it already and the key does nothing else. Never takes a key in use.
function I:ApplyDefaultKey()
	local host = M.host
	if not (host and host.toggleBinding and host.defaultToggleKey) or M.db.char.defaultKeyOffered then
		return
	end
	if InCombatLockdown() then
		pendingDefaultKey = true
		return
	end
	pendingDefaultKey = false
	M.db.char.defaultKeyOffered = true
	if GetBindingKey(host.toggleBinding) then
		return
	end
	local action = GetBindingAction(host.defaultToggleKey)
	if action and action ~= '' then
		return
	end
	self:SetKey(host.toggleBinding, host.defaultToggleKey)
end

----------------------------------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------------------------------

local function SlashHandler(input)
	input = U.Trim(input or '')
	if input == '' then
		M:Toggle()
	elseif strlower(input) == 'options' or strlower(input) == 'settings' then
		M:OpenOptions()
	else
		local entry = input:find('#', 1, true) and M.Contacts:GetBNetByTag(input)
		if entry then
			M:OpenBNet(entry, true)
		else
			M:OpenWhisper(input, true)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Lifecycle (hooks cannot be removed, so everything installs once and checks M.enabled)
----------------------------------------------------------------------------------------------------

function I:Enable()
	M:RegisterEvent('UPDATE_BINDINGS', 'Integration', function()
		I:ApplyReplyKey()
		M:Fire('KEYS_CHANGED')
	end)
	M:RegisterEvent('PLAYER_REGEN_ENABLED', 'Integration', function()
		if pendingKeys then
			I:ApplyReplyKey()
		end
		if pendingDefaultKey then
			I:ApplyDefaultKey()
		end
	end)
	if not self.listening then
		self.listening = true
		M:On('SETTINGS_CHANGED', function()
			I:ApplyReplyKey()
		end)
	end
	I:ApplyReplyKey()
	I:ApplyDefaultKey()

	if self.installed then
		return
	end
	self.installed = true

	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, 'InsertLink', OnInsertLink)
	end
	if ChatEdit_InsertLink then
		hooksecurefunc('ChatEdit_InsertLink', OnInsertLink)
	end

	InstallTakeOver()

	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs(MENU_TAGS) do
			Menu.ModifyMenu(tag, AddMenuEntry)
		end
	end

	SLASH_LIBSMESSENGER1 = '/messenger'
	SLASH_LIBSMESSENGER2 = '/msgr'
	SlashCmdList['LIBSMESSENGER'] = SlashHandler
end

function I:Disable()
	M:UnregisterEvent('UPDATE_BINDINGS', 'Integration')
	M:UnregisterEvent('PLAYER_REGEN_ENABLED', 'Integration')
	I:ApplyReplyKey()
end
