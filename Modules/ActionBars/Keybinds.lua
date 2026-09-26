---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local LibKeyBound = LibStub('LibKeyBound-1.0', true)

-- Keys bound to Blizzard's own action commands (ACTIONBUTTON1, MULTIACTIONBAR1BUTTON1 ...)
-- are redirected to SpartanUI's buttons with override bindings. The redirects live on a
-- secure frame so they can be dropped and restored in combat: in pet battles, and in
-- vehicles when Blizzard's vehicle bar is in use, the keys must reach Blizzard's UI.

local controller

local APPLY_SNIPPET = [[
	self:ClearBindings()
	local mode = self:GetAttribute('mode')
	if self:GetAttribute('suspended') or mode == 'clear' then
		return
	end
	-- An override bar showing a vehicle page counts as a vehicle
	if mode == 'override' then
		local overrideBar = self:GetFrameRef('overrideBar')
		if overrideBar and (overrideBar:GetAttribute('actionpage') or 0) > 10 then
			mode = 'vehicle'
		end
	end
	local count = self:GetAttribute('bindCount') or 0
	for i = 1, count do
		local key = self:GetAttribute('bindKey' .. i)
		local target = self:GetAttribute('bindTarget' .. i)
		if key and target then
			self:SetBindingClick(false, key, target, 'Keybind')
		end
	end
	-- Blizzard's vehicle bar is on screen: the first six action keys drive it
	if mode == 'vehicle' then
		for i = 1, 6 do
			local command = 'ACTIONBUTTON' .. i
			for k = 1, select('#', GetBindingKey(command)) do
				local key = select(k, GetBindingKey(command))
				self:SetBindingClick(true, key, 'OverrideActionBarButton' .. i)
			end
		end
	end
]]

local function GetController()
	if controller then
		return controller
	end
	controller = CreateFrame('Frame', 'SUI_ActionBarBindings', UIParent, 'SecureHandlerStateTemplate')
	controller:SetAttribute('ApplyBindings', APPLY_SNIPPET)
	controller:SetAttribute(
		'_onstate-bindmode',
		[[
		self:SetAttribute('mode', newstate)
		self:RunAttribute('ApplyBindings')
	]]
	)
	if OverrideActionBar then
		controller:SetFrameRef('overrideBar', OverrideActionBar)
	end
	return controller
end

---Conditions under which SpartanUI's key redirects step aside.
---@return string
function module:GetBindingDriver()
	local driver = ''
	if SUI.IsRetail or SUI.IsMOP or SUI.IsCata then
		driver = '[petbattle] clear; '
	end
	if self:UseBlizzardVehicleUI() then
		driver = driver .. '[overridebar] override; [vehicleui] vehicle; '
	end
	return driver .. 'bind'
end

---Keys bound to Bartender4's own buttons do nothing once Bartender4 is gone. Move them to
---the matching SpartanUI buttons: bars on Blizzard pages go to Blizzard's binding names,
---so the keys still work if the player switches back to Bartender4.
---Bartender4 binding commands and the SpartanUI command each one moves to.
---@return table<string, string>
function module:GetBartender4BindingMap()
	local map = {}
	for _, id in ipairs(self.ACTION_BAR_IDS) do
		for i = 1, 12 do
			local command = self:GetActionButtonBinding(id, i)
			local abs = (id - 1) * 12 + i
			map[('CLICK BT4Button%d:Keybind'):format(abs)] = command
			map[('CLICK BT4Button%d:LeftButton'):format(abs)] = command
		end
	end
	for i = 1, 10 do
		map[('CLICK BT4PetButton%d:LeftButton'):format(i)] = ('BONUSACTIONBUTTON%d'):format(i)
		map[('CLICK BT4StanceButton%d:LeftButton'):format(i)] = ('SHAPESHIFTBUTTON%d'):format(i)
	end
	return map
end

---How many keys are still bound to Bartender4's buttons.
---@return number
function module:CountBartender4Bindings()
	local count = 0
	for command in pairs(self:GetBartender4BindingMap()) do
		count = count + select('#', GetBindingKey(command))
	end
	return count
end

function module:MigrateBartender4Bindings()
	if _G.Bartender4 or InCombatLockdown() then
		return
	end
	local moved = self:MigrateBindings(self:GetBartender4BindingMap())
	if moved > 0 then
		SUI:Print((L['Moved %d key bindings from Bartender4 to SpartanUI action bars.']):format(moved))
	end
end

function module:SetupKeybinds()
	GetController()

	-- Key bindings are not loaded yet when the bars are built at login, so the Bartender4
	-- move waits for the first binding update and for entering the world
	self:RegisterEvent('UPDATE_BINDINGS', function()
		module:RunOutOfCombat('bt4bindings', module.MigrateBartender4Bindings, module)
		module:RunOutOfCombat('keybinds', module.UpdateKeybinds, module)
	end)
	local migrateWatcher = CreateFrame('Frame')
	migrateWatcher:RegisterEvent('PLAYER_ENTERING_WORLD')
	migrateWatcher:SetScript('OnEvent', function()
		module:RunOutOfCombat('bt4bindings', module.MigrateBartender4Bindings, module)
	end)

	-- The housing editor uses the number keys for its own tools
	if EventRegistry and C_HouseEditor then
		EventRegistry:RegisterCallback('HouseEditor.StateUpdated', function(_, active)
			module:RunOutOfCombat('keybind-suspend', module.SetKeybindsSuspended, module, active and true or false)
		end, self)
	end

	if LibKeyBound then
		LibKeyBound.RegisterCallback(self, 'LIBKEYBOUND_ENABLED', function()
			module.keyBoundMode = true
			module.gridShown = true
			for _, bar in pairs(module.bars) do
				bar:UpdateFade()
			end
			module:UpdateGlobalFade()
		end)
		LibKeyBound.RegisterCallback(self, 'LIBKEYBOUND_DISABLED', function()
			module.keyBoundMode = false
			module.gridShown = false
			for _, bar in pairs(module.bars) do
				bar:UpdateFade()
			end
			module:UpdateGlobalFade()
		end)
	end
end

---@param suspended boolean
function module:SetKeybindsSuspended(suspended)
	local frame = GetController()
	frame:SetAttribute('suspended', suspended or nil)
	frame:Execute([[ self:RunAttribute('ApplyBindings') ]])
end

---Rebuild the key redirect table and re-apply it.
function module:UpdateKeybinds()
	if not self.active then
		return
	end
	if InCombatLockdown() then
		self:RunOutOfCombat('keybinds', self.UpdateKeybinds, self)
		return
	end
	local frame = GetController()

	local count = 0
	for id, bar in self:IterateActionBars() do
		local db = bar and bar:GetDB()
		if db and db.enabled and self.BLIZZARD_BINDINGS[id] then
			for i, button in ipairs(bar.buttons) do
				local command = self:GetActionButtonBinding(id, i)
				if not command:find('^CLICK ') then
					for _, key in ipairs({ GetBindingKey(command) }) do
						count = count + 1
						frame:SetAttribute('bindKey' .. count, key)
						frame:SetAttribute('bindTarget' .. count, button:GetName())
					end
				end
			end
		end
	end
	-- Drop stale entries left over from a longer previous list
	local old = frame:GetAttribute('bindCount') or 0
	for i = count + 1, old do
		frame:SetAttribute('bindKey' .. i, nil)
		frame:SetAttribute('bindTarget' .. i, nil)
	end
	frame:SetAttribute('bindCount', count)

	UnregisterStateDriver(frame, 'bindmode')
	RegisterStateDriver(frame, 'bindmode', self:GetBindingDriver())
	frame:Execute([[ self:RunAttribute('ApplyBindings') ]])
end

---Toggle hover-to-bind mode.
function module:ToggleKeybindMode()
	if InCombatLockdown() then
		SUI:Print(ERR_NOT_IN_COMBAT)
		return
	end
	if LibKeyBound then
		LibKeyBound:Toggle()
	elseif QuickKeybindFrame then
		QuickKeybindFrame:Show()
	end
end

-- Readable names for the bars without a Blizzard binding, shown in the key bindings screen
for _, barID in ipairs({ 2, 7, 8, 9, 10 }) do
	_G['BINDING_HEADER_SUIBAR' .. barID] = ('SpartanUI %s %d'):format(L['Bar'], barID)
	for i = 1, 12 do
		_G[('BINDING_NAME_CLICK SUI_ActionBar%dButton%d:Keybind'):format(barID, i)] = ('%s %d %s %d'):format(L['Bar'], barID, L['Button'], i)
	end
end
