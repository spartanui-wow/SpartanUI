local SUI, L = SUI, SUI.L
---@type SUI.Module.TeleportAssist
local module = SUI:GetModule('TeleportAssist')
----------------------------------------------------------------------------------------------------

-- SpellBook integration only applies to Classic clients (Retail uses WorldMapIntegration)
if SUI.IsRetail then
	return
end

local sidePanel = nil
local mopPanel = nil
local mopTabButton = nil
local buttonPool = {}
local initialized = false

-- Items per page: 12 total (2 columns x 6 rows), matching the native spell layout
local ITEMS_PER_PAGE = 12
local ITEMS_PER_COL = 6

-- MOP SpellBook content frames to hide when our tab is active
local SPELLBOOK_CONTENT_FRAMES = {
	'SpellBookSpellIconsFrame',
	'SpellBookProfessionFrame',
	'SpellBookCoreAbilitiesFrame',
	'SpellBookWhatHasChanged',
	'SpellBookPageNavigationFrame',
}

-- Page state
local currentPage = 1
local totalPages = 1
local allEntries = {}

----------------------------------------------------------------------------------------------------
-- Classic: side panel anchored to the right of SpellBookFrame
----------------------------------------------------------------------------------------------------

---Create the side panel frame anchored to the right of SpellBookFrame
function module:CreateSpellBookSidePanel()
	if sidePanel then
		return
	end

	sidePanel = CreateFrame('Frame', 'SUI_SpellBookTeleportPanel', SpellBookFrame, 'BackdropTemplate')
	sidePanel:SetSize(200, SpellBookFrame:GetHeight())
	sidePanel:SetPoint('TOPLEFT', SpellBookFrame, 'TOPRIGHT', -2, 0)
	sidePanel:SetPoint('BOTTOMLEFT', SpellBookFrame, 'BOTTOMRIGHT', -2, 0)
	sidePanel:SetFrameStrata(SpellBookFrame:GetFrameStrata())
	sidePanel:SetFrameLevel(SpellBookFrame:GetFrameLevel() + 1)

	sidePanel:SetBackdrop({
		bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
		edgeFile = 'Interface\\DialogFrame\\UI-DialogBox-Border',
		tile = true,
		tileSize = 32,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	sidePanel:SetBackdropColor(0, 0, 0, 0.9)

	-- Title
	sidePanel.Title = sidePanel:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	sidePanel.Title:SetPoint('TOP', sidePanel, 'TOP', 0, -12)
	sidePanel.Title:SetText('|cffffffffSpartan|cffe21f1fUI|r ' .. L['Teleports'])
	sidePanel.Title:SetTextColor(1, 0.82, 0)

	-- Divider line under title
	sidePanel.Divider = sidePanel:CreateTexture(nil, 'ARTWORK')
	sidePanel.Divider:SetTexture('Interface\\Common\\UI-Divider01-steep')
	sidePanel.Divider:SetSize(180, 16)
	sidePanel.Divider:SetPoint('TOP', sidePanel.Title, 'BOTTOM', 0, -2)

	-- Scroll frame
	sidePanel.ScrollFrame = CreateFrame('ScrollFrame', 'SUI_SpellBookTeleportScrollFrame', sidePanel, 'UIPanelScrollFrameTemplate')
	sidePanel.ScrollFrame:SetPoint('TOPLEFT', sidePanel, 'TOPLEFT', 8, -38)
	sidePanel.ScrollFrame:SetPoint('BOTTOMRIGHT', sidePanel, 'BOTTOMRIGHT', -28, 8)

	-- Scroll child
	sidePanel.Content = CreateFrame('Frame', nil, sidePanel.ScrollFrame)
	sidePanel.Content:SetWidth(sidePanel.ScrollFrame:GetWidth())
	sidePanel.Content:SetHeight(1)
	sidePanel.ScrollFrame:SetScrollChild(sidePanel.Content)

	sidePanel:Hide()
end

----------------------------------------------------------------------------------------------------
-- MOP: paged two-column layout that looks native inside the SpellBook
----------------------------------------------------------------------------------------------------

-- Layout constants matching the native SpellBook button grid exactly:
-- SpellBookFrame is 550x525
-- SpellButton1 TOPLEFT is at x=100, y=-72 from frame TOPLEFT
-- Column 2 is 225px to the right of column 1
-- Rows are spaced 29px apart (top-to-top of each 37px icon)
-- Each entry: 37px icon + 6px gap + text up to right edge of column (~182px total)
local GRID = {
	col1X = 100, -- x from SpellBookFrame TOPLEFT
	col2X = 325, -- 100 + 225
	startY = -72, -- y from SpellBookFrame TOPLEFT
	rowStep = 70, -- pixels between row tops
	iconSize = 37, -- click-target width/height
	entryWidth = 37, -- click-target width (icon only; text labels extend beyond this)
}

---Create the MOP tab button and native-style paged panel
function module:CreateMOPSpellBookTab()
	-- Transparent overlay frame — no backdrop. SpellBookPage1/2 textures are children of
	-- SpellBookFrame and remain visible beneath us, giving us the native book paper look.
	mopPanel = CreateFrame('Frame', 'SUI_SpellBookTeleportMOPPanel', SpellBookFrame)
	mopPanel:SetAllPoints(SpellBookFrame)
	mopPanel:SetFrameStrata(SpellBookFrame:GetFrameStrata())
	mopPanel:SetFrameLevel(SpellBookFrame:GetFrameLevel() + 5)
	mopPanel:Hide()

	-- The native SpellBookPage1/2 textures are children of SpellBookFrame and will keep
	-- showing through — we just hide the Blizzard content frames above them.
	-- Add a title in the book-header area (matches SpellBookFrame:SetTitle position).
	mopPanel.Title = mopPanel:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	mopPanel.Title:SetPoint('TOP', mopPanel, 'TOP', 20, -47)
	mopPanel.Title:SetText(L['Teleports'])
	mopPanel.Title:SetTextColor(0.25, 0.12, 0)

	-- Page number text — mirrors SpellBookPageText position exactly
	-- SpellBookPageText: BOTTOMRIGHT x=-110, y=38 from SpellBookFrame, right-aligned, 102px wide
	mopPanel.PageText = mopPanel:CreateFontString(nil, 'OVERLAY', 'GameFontBlack')
	mopPanel.PageText:SetSize(102, 0)
	mopPanel.PageText:SetJustifyH('RIGHT')
	mopPanel.PageText:SetPoint('BOTTOMRIGHT', mopPanel, 'BOTTOMRIGHT', -110, 38)
	mopPanel.PageText:SetTextColor(0.25, 0.12, 0)

	-- Prev page button — mirrors SpellBookPrevPageButton position exactly
	-- BOTTOMRIGHT x=-66, y=26 from SpellBookFrame
	mopPanel.PrevButton = CreateFrame('Button', 'SUI_SpellBookTeleportPrevPage', mopPanel)
	mopPanel.PrevButton:SetSize(32, 32)
	mopPanel.PrevButton:SetPoint('BOTTOMRIGHT', mopPanel, 'BOTTOMRIGHT', -66, 26)
	mopPanel.PrevButton:SetNormalTexture('Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up')
	mopPanel.PrevButton:SetPushedTexture('Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down')
	mopPanel.PrevButton:SetDisabledTexture('Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled')
	mopPanel.PrevButton:SetHighlightTexture('Interface\\Buttons\\UI-Common-MouseHilight', 'ADD')
	mopPanel.PrevButton:SetScript('OnClick', function()
		if currentPage > 1 then
			currentPage = currentPage - 1
			module:RenderMOPPage()
		end
	end)

	-- Next page button — mirrors SpellBookNextPageButton position exactly
	-- BOTTOMRIGHT x=-31, y=26 from SpellBookFrame
	mopPanel.NextButton = CreateFrame('Button', 'SUI_SpellBookTeleportNextPage', mopPanel)
	mopPanel.NextButton:SetSize(32, 32)
	mopPanel.NextButton:SetPoint('BOTTOMRIGHT', mopPanel, 'BOTTOMRIGHT', -31, 26)
	mopPanel.NextButton:SetNormalTexture('Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up')
	mopPanel.NextButton:SetPushedTexture('Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down')
	mopPanel.NextButton:SetDisabledTexture('Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled')
	mopPanel.NextButton:SetHighlightTexture('Interface\\Buttons\\UI-Common-MouseHilight', 'ADD')
	mopPanel.NextButton:SetScript('OnClick', function()
		if currentPage < totalPages then
			currentPage = currentPage + 1
			module:RenderMOPPage()
		end
	end)

	-- Pre-create 12 entry slots (2 columns x 6 rows) matching native spell button positions
	for i = 1, ITEMS_PER_PAGE do
		local col = (i <= ITEMS_PER_COL) and 1 or 2
		local row = (i <= ITEMS_PER_COL) and i or (i - ITEMS_PER_COL)

		local xPos = (col == 1) and GRID.col1X or GRID.col2X
		local yPos = GRID.startY - ((row - 1) * GRID.rowStep)

		local slot = CreateFrame('Button', 'SUI_MOPTPSlot_' .. i, mopPanel, 'SecureActionButtonTemplate')
		slot:SetSize(GRID.entryWidth, GRID.iconSize)
		slot:SetPoint('TOPLEFT', mopPanel, 'TOPLEFT', xPos, yPos)

		-- Icon
		slot.Icon = slot:CreateTexture(nil, 'BORDER')
		slot.Icon:SetSize(GRID.iconSize, GRID.iconSize)
		slot.Icon:SetPoint('LEFT', slot, 'LEFT', 0, 0)

		-- Slot frame overlay (golden border ring from Spellbook-Parts)
		slot.SlotFrame = slot:CreateTexture(nil, 'OVERLAY')
		slot.SlotFrame:SetTexture('Interface\\Spellbook\\Spellbook-Parts')
		slot.SlotFrame:SetSize(70, 65)
		slot.SlotFrame:SetTexCoord(0.00390625, 0.27734375, 0.44140625, 0.69531250)
		slot.SlotFrame:SetPoint('CENTER', slot.Icon, 'CENTER', 1.5, 0)

		-- Highlight
		slot.HighlightTex = slot:CreateTexture(nil, 'HIGHLIGHT')
		slot.HighlightTex:SetTexture('Interface\\Buttons\\ButtonHilight-Square')
		slot.HighlightTex:SetBlendMode('ADD')
		slot.HighlightTex:SetSize(GRID.iconSize, GRID.iconSize)
		slot.HighlightTex:SetPoint('LEFT', slot, 'LEFT', 0, 0)

		-- Cooldown
		slot.Cooldown = CreateFrame('Cooldown', nil, slot, 'CooldownFrameTemplate')
		slot.Cooldown:SetSize(GRID.iconSize, GRID.iconSize)
		slot.Cooldown:SetPoint('LEFT', slot, 'LEFT', 0, 0)

		-- Favorite star
		slot.FavoriteStar = slot:CreateTexture(nil, 'OVERLAY')
		slot.FavoriteStar:SetAtlas('PetJournal-FavoritesIcon', true)
		slot.FavoriteStar:SetSize(12, 12)
		slot.FavoriteStar:SetPoint('TOPLEFT', slot.Icon, 'TOPLEFT', -2, 2)
		slot.FavoriteStar:Hide()

		-- Spell name
		slot.SpellName = slot:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
		slot.SpellName:SetSize(145, 0)
		slot.SpellName:SetPoint('LEFT', slot.Icon, 'RIGHT', 8, 4)
		slot.SpellName:SetJustifyH('LEFT')
		slot.SpellName:SetMaxLines(1)
		slot.SpellName:SetWordWrap(false)

		-- Sub text (expansion name) — matches SubSpellName font string in SpellButtonTemplate
		slot.SubName = slot:CreateFontString(nil, 'OVERLAY', 'SubSpellFont')
		slot.SubName:SetSize(145, 0)
		slot.SubName:SetPoint('TOPLEFT', slot.SpellName, 'BOTTOMLEFT', 0, -1)
		slot.SubName:SetJustifyH('LEFT')
		slot.SubName:SetMaxLines(1)
		slot.SubName:SetWordWrap(false)
		slot.SubName:SetTextColor(0.5, 0.5, 0.5)

		slot:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
		slot:SetAttribute('useOnKeyDown', false)
		slot:RegisterForDrag('LeftButton')
		slot:SetScript('OnDragStart', function(self)
			module:PickupEntry(self.entry)
		end)

		slot:SetScript('PreClick', function(self, mouseButton)
			if mouseButton == 'RightButton' then
				self:SetAttribute('type', nil)
			end
		end)

		slot:SetScript('PostClick', function(self, mouseButton)
			local entry = self.entry
			if not entry or mouseButton ~= 'RightButton' then
				return
			end
			module:ToggleFavorite(entry)
			if entry.available then
				if entry.type == 'spell' then
					self:SetAttribute('type', 'spell')
				elseif entry.type == 'toy' then
					self:SetAttribute('type', 'toy')
				elseif entry.type == 'item' then
					self:SetAttribute('type', 'item')
				end
			end
			module:RenderMOPPage()
		end)

		slot:SetScript('OnEnter', function(self)
			local entry = self.entry
			if not entry then
				return
			end
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			if entry.type == 'spell' then
				GameTooltip:SetSpellByID(entry.spellId or entry.id)
				GameTooltip:AddLine('|cFFCA3C3CID:|r ' .. (entry.spellId or entry.id))
			elseif entry.type == 'toy' then
				GameTooltip:SetToyByItemID(entry.id)
				GameTooltip:AddLine('|cFFCA3C3CID:|r ' .. entry.id)
			elseif entry.type == 'item' then
				GameTooltip:SetItemByID(entry.id)
				GameTooltip:AddLine('|cFFCA3C3CID:|r ' .. entry.id)
			else
				GameTooltip:AddLine(entry.name, 1, 1, 1)
			end
			GameTooltip:AddLine(' ')
			GameTooltip:AddLine(L['Right-click to toggle favorite'], 0.5, 0.5, 0.5)
			if not entry.available then
				GameTooltip:AddLine(L['Not available'], 1, 0.2, 0.2)
			end
			GameTooltip:Show()
		end)

		slot:SetScript('OnLeave', function()
			GameTooltip:Hide()
		end)

		slot:Hide()
		buttonPool[i] = slot
	end

	-- Create the tab button using the same template as Blizzard's tab buttons
	mopTabButton = CreateFrame('Button', 'SUI_SpellBookTeleportTabButton', SpellBookFrame, 'CharacterFrameTabButtonTemplate')
	mopTabButton:SetText(L['Teleports'])
	mopTabButton:Hide()

	mopTabButton:SetScript('OnClick', function()
		module:ShowMOPTab()
	end)

	-- Hook Blizzard tab buttons to hide our panel when clicked
	for i = 1, 5 do
		local blizzTab = _G['SpellBookFrameTabButton' .. i]
		if blizzTab then
			blizzTab:HookScript('OnClick', function()
				module:HideMOPTab()
			end)
		end
	end

	-- Hook ToggleSpellBook so keyboard bindings (B, K, etc.) also dismiss our panel.
	-- Without this, pressing a keybinding calls ToggleSpellBook directly, bypassing the
	-- tab button hooks above, leaving our panel visible while Blizzard shows its content.
	hooksecurefunc('ToggleSpellBook', function()
		module:HideMOPTab()
	end)

	SpellBookFrame:HookScript('OnShow', function()
		module:RepositionMOPTab()
	end)

	SpellBookFrame:HookScript('OnHide', function()
		module:HideMOPTab()
	end)

	-- Rebuild and re-render when the spellbook changes (catches spells not yet loaded at login)
	SpellBookFrame:HookScript('OnEvent', function(_, event)
		if event == 'SPELLS_CHANGED' and mopPanel and mopPanel:IsShown() then
			module:BuildAvailableTeleports()
			module:RenderMOPPage()
		end
	end)
end

---Position our tab button to the right of the last visible Blizzard tab
function module:RepositionMOPTab()
	if not mopTabButton then
		return
	end

	local lastTab = SpellBookFrameTabButton1
	for i = 2, 5 do
		local tab = _G['SpellBookFrameTabButton' .. i]
		if tab and tab:IsShown() then
			lastTab = tab
		end
	end

	mopTabButton:ClearAllPoints()
	mopTabButton:SetPoint('LEFT', lastTab, 'RIGHT', -15, 0)
	-- Always deselect and hide our panel when the SpellBook opens fresh
	PanelTemplates_DeselectTab(mopTabButton)
	if mopPanel then
		mopPanel:Hide()
	end
	mopTabButton:Show()
end

---Collect all entries into a flat list with favorites first (if enabled)
local function BuildEntryList()
	allEntries = {}

	if module.CurrentSettings.showFavoritesFirst then
		local favorites = module:GetFavorites()
		for _, entry in ipairs(favorites) do
			table.insert(allEntries, entry)
		end
	end

	for _, expansion in ipairs(module.EXPANSION_ORDER) do
		local entries = module.teleportsByCategory[expansion]
		if entries then
			for _, entry in ipairs(entries) do
				local shouldShow = entry.available or not module.CurrentSettings.hideUnavailable
				if shouldShow then
					local alreadyAdded = module.CurrentSettings.showFavoritesFirst and module:IsFavorite(entry)
					if not alreadyAdded then
						table.insert(allEntries, entry)
					end
				end
			end
		end
	end

	totalPages = math.max(1, math.ceil(#allEntries / ITEMS_PER_PAGE))
	if currentPage > totalPages then
		currentPage = totalPages
	end
end

---Render the current page of teleport entries into the 12 button slots
function module:RenderMOPPage()
	if not mopPanel then
		return
	end

	BuildEntryList()

	local pageStart = (currentPage - 1) * ITEMS_PER_PAGE + 1

	for i = 1, ITEMS_PER_PAGE do
		local slot = buttonPool[i]
		if not slot then
			break
		end

		local entryIndex = pageStart + i - 1
		local entry = allEntries[entryIndex]

		if entry then
			slot.entry = entry

			-- Icon
			local iconTexture = entry.icon
			if not iconTexture then
				if entry.type == 'spell' then
					iconTexture = C_Spell.GetSpellTexture(entry.spellId or entry.id)
				elseif entry.type == 'toy' then
					local _, _, toyIcon = C_ToyBox.GetToyInfo(entry.id)
					iconTexture = toyIcon
				elseif entry.type == 'item' then
					iconTexture = C_Item.GetItemIconByID(entry.id)
				end
			end

			if type(iconTexture) == 'string' then
				slot.Icon:SetAtlas(iconTexture)
			else
				slot.Icon:SetTexture(iconTexture or 134400)
			end
			slot.Icon:SetDesaturated(not entry.available)

			-- Names
			local labelText = module:GetDisplayLabel(entry)
			slot.SpellName:SetText(labelText or '')
			if entry.available then
				slot.SpellName:SetTextColor(1.0, 1.0, 1.0)
			else
				slot.SpellName:SetTextColor(0.5, 0.5, 0.5)
			end

			local expansionName = module.EXPANSION_NAMES and module.EXPANSION_NAMES[entry.expansion] or ''
			slot.SubName:SetText(expansionName or '')

			-- Favorite star
			if module:IsFavorite(entry) then
				slot.FavoriteStar:Show()
			else
				slot.FavoriteStar:Hide()
			end

			-- Secure attributes
			if not InCombatLockdown() then
				if entry.available then
					if entry.type == 'spell' then
						slot:SetAttribute('type', 'spell')
						slot:SetAttribute('spell', entry.spellId or entry.id)
					elseif entry.type == 'toy' then
						slot:SetAttribute('type', 'toy')
						slot:SetAttribute('toy', entry.id)
					elseif entry.type == 'item' then
						slot:SetAttribute('type', 'item')
						slot:SetAttribute('item', 'item:' .. entry.id)
					else
						slot:SetAttribute('type', nil)
					end
				else
					slot:SetAttribute('type', nil)
				end
			end

			slot:Show()
		else
			slot.entry = nil
			slot:Hide()
		end
	end

	-- Page text: "Page X" style matching SpellBookPageText
	mopPanel.PageText:SetFormattedText(PAGE_NUMBER, currentPage)

	-- Prev/Next button states
	if currentPage <= 1 then
		mopPanel.PrevButton:Disable()
	else
		mopPanel.PrevButton:Enable()
	end

	if currentPage >= totalPages then
		mopPanel.NextButton:Disable()
	else
		mopPanel.NextButton:Enable()
	end
end

-- Saved bookType so we can restore it when our tab is dismissed
local savedBookType = nil

---Show the TeleportAssist tab inside the SpellBook
function module:ShowMOPTab()
	if not mopPanel then
		return
	end

	-- Hide Blizzard's content frames (page textures remain visible underneath)
	for _, frameName in ipairs(SPELLBOOK_CONTENT_FRAMES) do
		local f = _G[frameName]
		if f then
			f:Hide()
		end
	end

	-- Deselect all Blizzard tabs visually
	for i = 1, 5 do
		local tab = _G['SpellBookFrameTabButton' .. i]
		if tab then
			PanelTemplates_DeselectTab(tab)
		end
	end

	PanelTemplates_SelectTab(mopTabButton)

	-- Clear bookType so ToggleSpellBook never matches and closes the window while our tab is active
	savedBookType = SpellBookFrame.bookType
	SpellBookFrame.bookType = nil

	currentPage = 1
	mopPanel:Show()
	module:RenderMOPPage()
end

---Hide the TeleportAssist tab
function module:HideMOPTab()
	if not (mopPanel and mopPanel:IsShown()) then
		return
	end
	mopPanel:Hide()
	if mopTabButton then
		PanelTemplates_DeselectTab(mopTabButton)
	end
	-- Restore bookType so ToggleSpellBook works correctly again
	if savedBookType ~= nil then
		SpellBookFrame.bookType = savedBookType
		savedBookType = nil
	end
end

----------------------------------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------------------------------

---Initialize the SpellBook tab for Classic/MOP clients
function module:InitSpellBookTab()
	if initialized then
		return
	end

	if not SpellBookFrame then
		if module.logger then
			module.logger.warning('SpellBookFrame not available')
		end
		return
	end

	if SUI.IsMOP then
		module:CreateMOPSpellBookTab()
	else
		module:CreateSpellBookSidePanel()

		SpellBookFrame:HookScript('OnShow', function()
			if sidePanel then
				sidePanel:Show()
				module:UpdateSidePanel(sidePanel)
			end
		end)

		SpellBookFrame:HookScript('OnHide', function()
			if sidePanel then
				sidePanel:Hide()
			end
		end)
	end

	initialized = true

	if module.logger then
		if SUI.IsMOP then
			module.logger.info('SpellBook tab initialized for MOP client')
		else
			module.logger.info('SpellBook side panel initialized for Classic client')
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Classic side panel content (unchanged)
----------------------------------------------------------------------------------------------------

local sidePanelButtonPool = {}
local sidePanelHeaderPool = {}

---Get or create a teleport button for the Classic side panel
---@param index number
---@return Button
local function GetSidePanelButton(index)
	if sidePanelButtonPool[index] then
		return sidePanelButtonPool[index]
	end

	local buttonHeight = 28
	local iconSize = 22

	local button = CreateFrame('Button', 'SUI_SpellBookTPBtn_' .. index, sidePanel.Content, 'SecureActionButtonTemplate')
	button:SetSize(sidePanel.ScrollFrame:GetWidth(), buttonHeight)

	button.Background = button:CreateTexture(nil, 'BACKGROUND')
	button.Background:SetAllPoints()
	button.Background:SetColorTexture(0.1, 0.1, 0.1, 0.5)

	button.Highlight = button:CreateTexture(nil, 'HIGHLIGHT')
	button.Highlight:SetAllPoints()
	button.Highlight:SetColorTexture(1, 1, 1, 0.15)
	button.Highlight:SetBlendMode('ADD')

	button.Icon = button:CreateTexture(nil, 'ARTWORK')
	button.Icon:SetSize(iconSize, iconSize)
	button.Icon:SetPoint('LEFT', button, 'LEFT', 4, 0)

	button.Label = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	button.Label:SetPoint('LEFT', button.Icon, 'RIGHT', 6, 0)
	button.Label:SetPoint('RIGHT', button, 'RIGHT', -4, 0)
	button.Label:SetJustifyH('LEFT')
	button.Label:SetWordWrap(false)

	button.Cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
	button.Cooldown:SetAllPoints(button.Icon)

	button.FavoriteStar = button:CreateTexture(nil, 'OVERLAY')
	button.FavoriteStar:SetAtlas('PetJournal-FavoritesIcon', true)
	button.FavoriteStar:SetSize(12, 12)
	button.FavoriteStar:SetPoint('TOPLEFT', button.Icon, 'TOPLEFT', -2, 2)
	button.FavoriteStar:Hide()

	button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	button:SetAttribute('useOnKeyDown', false)
	button:RegisterForDrag('LeftButton')
	button:SetScript('OnDragStart', function(self)
		module:PickupEntry(self.entry)
	end)

	button:SetScript('PreClick', function(self, mouseButton)
		if mouseButton == 'RightButton' then
			self:SetAttribute('type', nil)
		end
	end)

	button:SetScript('PostClick', function(self, mouseButton)
		local entry = self.entry
		if not entry or mouseButton ~= 'RightButton' then
			return
		end
		module:ToggleFavorite(entry)
		if entry.available then
			if entry.type == 'spell' then
				self:SetAttribute('type', 'spell')
			elseif entry.type == 'toy' then
				self:SetAttribute('type', 'toy')
			elseif entry.type == 'item' then
				self:SetAttribute('type', 'item')
			end
		end
		module:UpdateSidePanel(sidePanel)
	end)

	button:SetScript('OnEnter', function(self)
		local entry = self.entry
		if not entry then
			return
		end
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		if entry.type == 'spell' then
			GameTooltip:SetSpellByID(entry.spellId or entry.id)
		elseif entry.type == 'toy' then
			GameTooltip:SetToyByItemID(entry.id)
		elseif entry.type == 'item' then
			GameTooltip:SetItemByID(entry.id)
		else
			GameTooltip:AddLine(entry.name, 1, 1, 1)
		end
		GameTooltip:AddLine(' ')
		GameTooltip:AddLine(L['Right-click to toggle favorite'], 0.5, 0.5, 0.5)
		if not entry.available then
			GameTooltip:AddLine(L['Not available'], 1, 0.2, 0.2)
		end
		GameTooltip:Show()
	end)

	button:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	sidePanelButtonPool[index] = button
	return button
end

---Get or create a category header for the Classic side panel
---@param index number
---@return FontString
local function GetSidePanelHeader(index)
	if sidePanelHeaderPool[index] then
		return sidePanelHeaderPool[index]
	end

	local header = sidePanel.Content:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	header:SetTextColor(1, 0.82, 0)
	header:SetJustifyH('LEFT')
	sidePanelHeaderPool[index] = header
	return header
end

---Update the Classic side panel content
---@param panel Frame
function module:UpdateSidePanel(panel)
	if not panel then
		return
	end

	panel.Content:SetWidth(panel.ScrollFrame:GetWidth())

	for _, button in pairs(sidePanelButtonPool) do
		button:Hide()
	end
	for _, header in pairs(sidePanelHeaderPool) do
		header:Hide()
	end

	local buttonIndex = 1
	local headerIndex = 1
	local yOffset = 4
	local buttonHeight = 28
	local spacing = 2

	if module.CurrentSettings.showFavoritesFirst then
		local favorites = module:GetFavorites()
		if #favorites > 0 then
			local header = GetSidePanelHeader(headerIndex)
			header:ClearAllPoints()
			header:SetPoint('TOPLEFT', panel.Content, 'TOPLEFT', 4, -yOffset)
			header:SetText(L['Favorites'])
			header:Show()
			headerIndex = headerIndex + 1
			yOffset = yOffset + 18

			for _, entry in ipairs(favorites) do
				local button = GetSidePanelButton(buttonIndex)
				button:SetSize(panel.ScrollFrame:GetWidth(), buttonHeight)
				button:ClearAllPoints()
				button:SetPoint('TOPLEFT', panel.Content, 'TOPLEFT', 0, -yOffset)
				module:SetupSidePanelButton(button, entry)
				buttonIndex = buttonIndex + 1
				yOffset = yOffset + buttonHeight + spacing
			end

			yOffset = yOffset + 6
		end
	end

	for _, expansion in ipairs(module.EXPANSION_ORDER) do
		local entries = module.teleportsByCategory[expansion]
		if entries and #entries > 0 then
			local visibleEntries = {}
			for _, entry in ipairs(entries) do
				local shouldShow = entry.available or not module.CurrentSettings.hideUnavailable
				if shouldShow and module.CurrentSettings.showFavoritesFirst and module:IsFavorite(entry) then
					shouldShow = false
				end
				if shouldShow then
					table.insert(visibleEntries, entry)
				end
			end

			if #visibleEntries > 0 then
				local header = GetSidePanelHeader(headerIndex)
				header:ClearAllPoints()
				header:SetPoint('TOPLEFT', panel.Content, 'TOPLEFT', 4, -yOffset)
				header:SetText(module.EXPANSION_NAMES[expansion] or expansion)
				header:Show()
				headerIndex = headerIndex + 1
				yOffset = yOffset + 18

				for _, entry in ipairs(visibleEntries) do
					local button = GetSidePanelButton(buttonIndex)
					button:SetSize(panel.ScrollFrame:GetWidth(), buttonHeight)
					button:ClearAllPoints()
					button:SetPoint('TOPLEFT', panel.Content, 'TOPLEFT', 0, -yOffset)
					module:SetupSidePanelButton(button, entry)
					buttonIndex = buttonIndex + 1
					yOffset = yOffset + buttonHeight + spacing
				end

				yOffset = yOffset + 6
			end
		end
	end

	panel.Content:SetHeight(math.max(yOffset + 20, panel.ScrollFrame:GetHeight()))
end

---Set up a Classic side panel button for a teleport entry
---@param button Button
---@param entry table
function module:SetupSidePanelButton(button, entry)
	button.entry = entry

	local iconTexture = entry.icon
	if not iconTexture then
		if entry.type == 'spell' then
			iconTexture = C_Spell.GetSpellTexture(entry.spellId or entry.id)
		elseif entry.type == 'toy' then
			local _, _, toyIcon = C_ToyBox.GetToyInfo(entry.id)
			iconTexture = toyIcon
		elseif entry.type == 'item' then
			iconTexture = C_Item.GetItemIconByID(entry.id)
		end
	end

	if type(iconTexture) == 'string' then
		button.Icon:SetAtlas(iconTexture)
	else
		button.Icon:SetTexture(iconTexture or 134400)
	end
	button.Icon:SetDesaturated(not entry.available)

	local labelText = module:GetDisplayLabel(entry)
	if labelText then
		button.Label:SetText(labelText)
		button.Label:Show()
		if entry.available then
			button.Label:SetTextColor(1.0, 0.82, 0.0)
		else
			button.Label:SetTextColor(0.5, 0.5, 0.5)
		end
	else
		button.Label:SetText('')
		button.Label:Hide()
	end

	if module:IsFavorite(entry) then
		button.FavoriteStar:Show()
	else
		button.FavoriteStar:Hide()
	end

	if not InCombatLockdown() then
		if entry.available then
			if entry.type == 'spell' then
				button:SetAttribute('type', 'spell')
				button:SetAttribute('spell', entry.spellId or entry.id)
			elseif entry.type == 'toy' then
				button:SetAttribute('type', 'toy')
				button:SetAttribute('toy', entry.id)
			elseif entry.type == 'item' then
				button:SetAttribute('type', 'item')
				button:SetAttribute('item', 'item:' .. entry.id)
			else
				button:SetAttribute('type', nil)
			end
		else
			button:SetAttribute('type', nil)
		end
	end

	button:Show()
end
