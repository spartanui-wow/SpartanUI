local SUI, L = SUI, SUI.L
---@type SUI.Module.TeleportAssist
local module = SUI:GetModule('TeleportAssist')
----------------------------------------------------------------------------------------------------

-- Only for Retail (Classic has no M+ UI)
if not SUI.IsRetail then
	return
end

local createdButtons = {}
local challengeModeLookup = nil -- Built lazily: challengeModeMapID -> spellID
local initialized = false
local pendingRebuild = false

-- ==================== DYNAMIC NAME MATCHING ====================

---Normalize a dungeon name for fuzzy matching
---@param name string
---@return string
local function NormalizeName(name)
	local n = name:lower()
	n = n:gsub('^the ', '')
	n = n:gsub(',.*$', '') -- Strip subtitle after comma ("Ara-Kara, City of Echoes" -> "Ara-Kara")
	n = n:gsub('%s+', ' ')
	n = n:trim()
	return n
end

---Build the challengeModeMapID -> spellID lookup from TELEPORT_DATA dynamically
---@return table<number, number>
local function BuildChallengeModeMap()
	local lookup = {}
	local mapIDs = C_ChallengeMode.GetMapTable()
	if not mapIDs then
		return lookup
	end

	local playerFaction = UnitFactionGroup('player')

	-- Build a searchable index of our TELEPORT_DATA dungeon entries
	---@type table<string, SUI.TeleportAssist.TeleportEntry[]>
	local nameIndex = {}
	for _, entry in ipairs(module.TELEPORT_DATA) do
		-- Only consider non-class, non-portal spell teleports (dungeon/raid teleports)
		if entry.type == 'spell' and not entry.class and not entry.isPortal then
			local normalized = NormalizeName(entry.name)
			if not nameIndex[normalized] then
				nameIndex[normalized] = {}
			end
			table.insert(nameIndex[normalized], entry)
		end
	end

	for _, challengeMapID in ipairs(mapIDs) do
		local name = C_ChallengeMode.GetMapUIInfo(challengeMapID)
		if name then
			local normalizedChallenge = NormalizeName(name)

			-- Try exact match first
			local candidates = nameIndex[normalizedChallenge]

			-- Try containment match if no exact match
			if not candidates then
				for indexName, entries in pairs(nameIndex) do
					if indexName:find(normalizedChallenge, 1, true) or normalizedChallenge:find(indexName, 1, true) then
						candidates = entries
						break
					end
				end
			end

			if candidates then
				-- Pick the correct faction variant if applicable
				local bestEntry = nil
				for _, entry in ipairs(candidates) do
					if not entry.faction or entry.faction == playerFaction then
						bestEntry = entry
						break
					end
				end
				-- Fallback to first candidate if no faction match
				bestEntry = bestEntry or candidates[1]

				if bestEntry then
					lookup[challengeMapID] = bestEntry.id
				end
			else
				if module.logger then
					module.logger.debug('ChallengesIntegration: No teleport match for "' .. name .. '" (mapID ' .. challengeMapID .. ')')
				end
			end
		end
	end

	if module.logger then
		local count = 0
		for _ in pairs(lookup) do
			count = count + 1
		end
		module.logger.debug('ChallengesIntegration: Mapped ' .. count .. ' of ' .. #mapIDs .. ' challenge mode dungeons to teleport spells')
	end

	return lookup
end

---Get or build the challenge mode lookup
---@return table<number, number>
local function GetChallengeModeMap()
	if not challengeModeLookup then
		challengeModeLookup = BuildChallengeModeMap()
	end
	return challengeModeLookup
end

-- ==================== TOOLTIP ENHANCEMENT ====================

---Update the GameTooltip with teleport availability info
---@param parent Frame The original dungeon icon frame
---@param spellID number The teleport spell ID
---@param initialize boolean Whether this is the initial OnEnter call
local function UpdateGameTooltip(parent, spellID, initialize)
	if not initialize and not GameTooltip:IsOwned(parent) then
		return
	end

	-- Call the parent's OnEnter to show Blizzard's default tooltip
	local onEnter = parent:GetScript('OnEnter')
	if onEnter then
		onEnter(parent)
	end

	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local spellName = spellInfo and spellInfo.name

	GameTooltip:AddLine(' ')
	GameTooltip:AddLine(spellName or L['Dungeon Teleport'], 1, 1, 1)

	if InCombatLockdown() then
		GameTooltip:Show()
		return
	end

	if C_SpellBook.IsSpellInSpellBook(spellID) then
		local cd = C_Spell.GetSpellCooldown(spellID)
		if cd and type(cd.duration) == 'number' and type(cd.startTime) == 'number' then
			if not issecretvalue(cd.duration) and not issecretvalue(cd.startTime) then
				if cd.duration == 0 then
					GameTooltip:AddLine(L['Ready'], 0, 1, 0)
				else
					local remaining = math.ceil(cd.startTime + cd.duration - GetTime())
					GameTooltip:AddLine(SecondsToTime(remaining), 1, 0, 0)
				end
			end
		end
		GameTooltip:AddLine(' ')
		GameTooltip:AddLine(L['Click to teleport'], 0.5, 0.5, 0.5)
	else
		GameTooltip:AddLine(L['Teleport not yet learned'], 1, 0, 0)
		GameTooltip:AddLine(L['Complete this dungeon on Mythic+ to learn'], 0.5, 0.5, 0.5)
	end

	GameTooltip:Show()
end

-- ==================== OVERLAY BUTTON CREATION ====================

---Create or update an overlay button on a dungeon icon
---@param parent Frame The ChallengesDungeonIconMixin frame
---@param spellID number The teleport spell ID
local function CreateDungeonButton(parent, spellID)
	if not spellID or not parent then
		return
	end

	local btn = createdButtons[parent]
	if not btn then
		btn = CreateFrame('Button', nil, parent, 'InsecureActionButtonTemplate')
		btn:SetAllPoints(parent)
		btn:RegisterForClicks('AnyDown', 'AnyUp')

		-- Dungeon atlas icon indicator (bottom-left corner)
		btn.DungeonIcon = btn:CreateTexture(nil, 'OVERLAY')
		btn.DungeonIcon:SetAtlas('Dungeon', true)
		btn.DungeonIcon:SetPoint('BOTTOMLEFT', btn, 'BOTTOMLEFT', -5, -5)
		btn.DungeonIcon:SetSize(24, 24)

		-- Hover overlay
		local hoverOverlay = btn:CreateTexture(nil, 'HIGHLIGHT')
		hoverOverlay:SetAllPoints(btn)
		hoverOverlay:SetColorTexture(0, 0, 0, 0.4)

		createdButtons[parent] = btn
	end

	-- Update spell attribute
	btn:SetAttribute('type', 'spell')
	btn:SetAttribute('spell', spellID)
	btn.spellID = spellID

	-- Visual feedback: desaturate dungeon icon if spell not known
	local isKnown = C_SpellBook.IsSpellInSpellBook(spellID)
	btn.DungeonIcon:SetDesaturated(not isKnown)
	btn.DungeonIcon:SetAlpha(isKnown and 1.0 or 0.5)

	-- Tooltip handlers
	btn:SetScript('OnEnter', function()
		UpdateGameTooltip(parent, spellID, true)
	end)

	btn:SetScript('OnLeave', function()
		if GameTooltip:IsOwned(parent) then
			GameTooltip:Hide()
		end
	end)
end

-- ==================== BUTTON MANAGEMENT ====================

---Create overlay buttons on all dungeon icons in the ChallengesFrame
local function CreateDungeonButtons()
	if InCombatLockdown() then
		pendingRebuild = true
		return
	end
	if not ChallengesFrame or not ChallengesFrame.DungeonIcons then
		return
	end
	if not module.CurrentSettings.showChallengesButtons then
		-- Hide all existing buttons
		for _, btn in pairs(createdButtons) do
			btn:Hide()
		end
		return
	end

	local lookup = GetChallengeModeMap()

	for _, icon in pairs(ChallengesFrame.DungeonIcons) do
		local challengeMapID = icon.mapID
		local spellID = lookup[challengeMapID]

		if spellID then
			CreateDungeonButton(icon, spellID)
			local btn = createdButtons[icon]
			if btn then
				btn:Show()
			end
		end
	end
end

-- ==================== INITIALIZATION ====================

---Initialize hooks on Blizzard's ChallengesFrame
---@return boolean success
local function Initialize()
	if not C_AddOns.IsAddOnLoaded('Blizzard_ChallengesUI') then
		return false
	end
	if not ChallengesFrame then
		return false
	end

	-- Hook ChallengesFrame:Update() to re-create buttons when dungeon icons refresh
	if type(ChallengesFrame.Update) == 'function' then
		hooksecurefunc(ChallengesFrame, 'Update', function()
			CreateDungeonButtons()
		end)

		-- Create buttons immediately if frame is already shown
		CreateDungeonButtons()
	end

	initialized = true
	if module.logger then
		module.logger.info('Challenges UI integration initialized')
	end
	return true
end

-- ==================== EVENT HANDLING ====================

local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('ADDON_LOADED')
eventFrame:RegisterEvent('PLAYER_LOGIN')
eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
eventFrame:RegisterEvent('SPELLS_CHANGED')

eventFrame:SetScript('OnEvent', function(self, event, addonName)
	if event == 'ADDON_LOADED' and addonName == 'Blizzard_ChallengesUI' then
		if Initialize() then
			self:UnregisterEvent('ADDON_LOADED')
		end
	elseif event == 'PLAYER_LOGIN' then
		-- Try in case ChallengesUI was already loaded
		if Initialize() then
			self:UnregisterEvent('ADDON_LOADED')
		end
	elseif event == 'PLAYER_REGEN_ENABLED' then
		-- Retry button creation that was blocked by combat
		if initialized and pendingRebuild then
			pendingRebuild = false
			CreateDungeonButtons()
		end
	elseif event == 'SPELLS_CHANGED' then
		-- Rebuild lookup and refresh buttons when spells change (e.g., learned new dungeon teleport)
		challengeModeLookup = nil
		if initialized and not InCombatLockdown() then
			CreateDungeonButtons()
		else
			pendingRebuild = true
		end
	end
end)

-- ==================== MODULE API ====================

---Initialize the Challenges UI integration (called from TeleportAPI.lua OnEnable)
function module:InitializeChallengesIntegration()
	-- The event frame handles initialization automatically when Blizzard_ChallengesUI loads
	if module.logger then
		module.logger.debug('Challenges integration event listener registered')
	end
end
