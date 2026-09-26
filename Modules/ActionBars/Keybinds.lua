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

function module:SetupKeybinds()
	GetController()

	self:RegisterEvent('UPDATE_BINDINGS', function()
		module:RunOutOfCombat('keybinds', module.UpdateKeybinds, module)
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
		end)
		LibKeyBound.RegisterCallback(self, 'LIBKEYBOUND_DISABLED', function()
			module.keyBoundMode = false
			module.gridShown = false
			for _, bar in pairs(module.bars) do
				bar:UpdateFade()
			end
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
