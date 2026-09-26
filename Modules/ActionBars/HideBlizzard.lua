---@type SUI
local SUI = SUI
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local IS_MAINLINE = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- Every frame name below is looked up at runtime and skipped when missing, so the same
-- list covers Retail and every Classic client.
local hider = CreateFrame('Frame', 'SUI_ActionBarHider')
hider:Hide()
module.hider = hider

---Clear a key on a Blizzard table until the game treats it as secure again.
---EditMode writes flags such as isShownExternal from insecure code paths; wiping them this
---way keeps later Blizzard reads of the table from being blamed on SpartanUI.
---@param tbl table
---@param key string
local function PurgeKey(tbl, key)
	tbl[key] = nil
	local c = 42
	repeat
		if tbl[c] == nil then
			tbl[c] = nil
		end
		c = c + 1
	until issecurevariable(tbl, key)
end

---@param frame Frame|nil
---@param clearEvents boolean
local function HideBarFrame(frame, clearEvents)
	if not frame then
		return
	end
	if clearEvents then
		frame:UnregisterAllEvents()
	end
	if frame.system then
		PurgeKey(frame, 'isShownExternal')
	end
	-- EditMode replaces Hide on its frames; calling that version taints
	if frame.HideBase then
		frame:HideBase()
	else
		frame:Hide()
	end
	frame:SetParent(hider)
end

---@param button Button|nil
local function HideActionButton(button)
	if not button then
		return
	end
	button:Hide()
	button:UnregisterAllEvents()
	button:SetAttribute('statehidden', true)
	-- On Classic clients cutting this link makes the client fire extra events and stall
	if IS_MAINLINE then
		button.bar = nil
	end
end

---True when the player wants Blizzard's own vehicle bar instead of SpartanUI paging bar 1.
---@return boolean
function module:UseBlizzardVehicleUI()
	return OverrideActionBar ~= nil and SUI:GetArtworkSetting('VehicleUI') == true
end

function module:HideBlizzard()
	if self.blizzardHidden then
		return
	end
	self.blizzardHidden = true

	HideBarFrame(MainMenuBar, false)
	HideBarFrame(MainActionBar, false)
	HideBarFrame(MultiBarBottomLeft, true)
	HideBarFrame(MultiBarBottomRight, true)
	HideBarFrame(MultiBarLeft, true)
	HideBarFrame(MultiBarRight, true)
	HideBarFrame(MultiBar5, true)
	HideBarFrame(MultiBar6, true)
	HideBarFrame(MultiBar7, true)

	for i = 1, 12 do
		HideActionButton(_G['ActionButton' .. i])
		HideActionButton(_G['MultiBarBottomLeftButton' .. i])
		HideActionButton(_G['MultiBarBottomRightButton' .. i])
		HideActionButton(_G['MultiBarRightButton' .. i])
		HideActionButton(_G['MultiBarLeftButton' .. i])
		HideActionButton(_G['MultiBar5Button' .. i])
		HideActionButton(_G['MultiBar6Button' .. i])
		HideActionButton(_G['MultiBar7Button' .. i])
	end

	HideBarFrame(MicroButtonAndBagsBar, false)
	-- Pet and stance bars keep their events: SpartanUI reuses their buttons and relies on
	-- Blizzard's own code to keep those buttons up to date
	HideBarFrame(StanceBar or StanceBarFrame, false)
	HideBarFrame(PetActionBar or PetActionBarFrame, false)
	-- Blizzard's possess bar stays: it only appears while mind-controlling and carries the
	-- button that ends it
	-- With SpartanUI's bag or menu bar turned off, Blizzard's stays as it is
	if self:UsesOwnBagBar() then
		HideBarFrame(BagsBar, true)
	end
	-- The micro menu is only moved, never hidden: Blizzard never shows it again, and the
	-- vehicle bar and pet battle UI borrow it
	if self.CurrentSettings.micro.enabled and MicroMenu then
		MicroMenu:SetParent(hider)
	end
	-- SpartanUI draws its own experience and reputation bars; keep Blizzard's if those are off
	if SUI:IsModuleEnabled('Artwork') and SUI:IsModuleEnabled('Artwork.StatusBars') then
		HideBarFrame(StatusTrackingBarManager, false)
	end

	-- The totem bar keeps its events so shaman totem buttons keep working where it exists
	if MultiCastActionBarFrame and select(2, UnitClass('player')) ~= 'SHAMAN' then
		HideBarFrame(MultiCastActionBarFrame, false)
	end

	-- These events drive the old main bar's visibility; it has to stay hidden
	if MainMenuBar then
		MainMenuBar:UnregisterEvent('PLAYER_REGEN_ENABLED')
		MainMenuBar:UnregisterEvent('PLAYER_REGEN_DISABLED')
		MainMenuBar:UnregisterEvent('ACTIONBAR_SHOWGRID')
		MainMenuBar:UnregisterEvent('ACTIONBAR_HIDEGRID')
	end

	-- The vehicle exit button is a child of the main bar that was just hidden
	if MainMenuBarVehicleLeaveButton and MainMenuBarVehicleLeaveButton:GetParent() ~= UIParent then
		MainMenuBarVehicleLeaveButton:SetParent(UIParent)
	end

	self:UpdateBlizzardVehicle()

	if C_AddOns.IsAddOnLoaded('Blizzard_NewPlayerExperience') then
		self:DisableActionBarTutorials()
	else
		if NPE_LoadUI ~= nil then
			hooksecurefunc('NPE_LoadUI', function()
				module:DisableActionBarTutorials()
			end)
		end
		local watcher = CreateFrame('Frame')
		watcher:RegisterEvent('ADDON_LOADED')
		watcher:SetScript('OnEvent', function(frame, _, addon)
			if addon == 'Blizzard_NewPlayerExperience' then
				frame:UnregisterAllEvents()
				module:DisableActionBarTutorials()
			end
		end)
	end
end

---New player tutorials look for Blizzard's own buttons and error when they are gone.
function module:DisableActionBarTutorials()
	-- Current Retail runs its tutorials through TutorialManager
	if TutorialManager and TutorialManager.ShutdownTutorial and Class_AddSpellToActionBarService then
		pcall(TutorialManager.ShutdownTutorial, TutorialManager, Class_AddSpellToActionBarService.name)
	end
	if not (Tutorials and Tutorials.AddSpellToActionBar) then
		return
	end
	Tutorials.AddSpellToActionBar:Disable()
	Tutorials.AddClassSpellToActionBar:Disable()
	Tutorials.Intro_CombatTactics:Disable()
	Tutorials.AutoPushSpellWatcher:Complete()
end

---Show or hide Blizzard's vehicle bar to match the Artwork "Use Blizzard Vehicle UI" setting.
function module:UpdateBlizzardVehicle()
	if not OverrideActionBar then
		return
	end
	if InCombatLockdown() then
		self:RunOutOfCombat('blizzvehicle', self.UpdateBlizzardVehicle, self)
		return
	end
	if self:UseBlizzardVehicleUI() then
		OverrideActionBar:SetParent(UIParent)
		if ActionBarController_GetCurrentActionBarState and LE_ACTIONBAR_STATE_OVERRIDE and ActionBarController_GetCurrentActionBarState() ~= LE_ACTIONBAR_STATE_OVERRIDE then
			OverrideActionBar:Hide()
		end
	else
		OverrideActionBar:SetParent(hider)
	end
end
