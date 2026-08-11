-- oUF AuraDesigner Element
-- Scans unit auras and matches against user-defined spell IDs
-- Dispatches to the SUI element for visual display (icon, border, glow)
--
-- RETAIL 12.1+: Uses AuraUtil.ForEachAura with filter strings
-- RETAIL 12.0: Uses C_UnitAuras.GetAuraDataByIndex with secret-value guards
-- CLASSIC: Uses C_UnitAuras.GetAuraDataByIndex with full access + spellName fallback

local _, ns = ...
local oUF = ns.oUF or oUF

if not oUF then
	return
end

local isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local hasForEachAura = AuraUtil and AuraUtil.ForEachAura

-- Resolve canaccessvalue for all code paths
local function CanAccess(value)
	if SUI and SUI.BlizzAPI and SUI.BlizzAPI.canaccessvalue then
		return SUI.BlizzAPI.canaccessvalue(value)
	end
	if canaccessvalue then
		return canaccessvalue(value)
	end
	return true
end

-- Build lookup tables from entries grouped by filter
-- Returns { HELPFUL = { [spellId] = entryKey, ... }, HARMFUL = { ... } }
local function BuildLookups(entries)
	local lookups = {}
	local nameToKey = {}
	for entryKey, entry in pairs(entries) do
		if entry.enabled and entry.spellId and entry.spellId > 0 then
			local filter = entry.filter or 'HELPFUL'
			if not lookups[filter] then
				lookups[filter] = {}
			end
			lookups[filter][entry.spellId] = entryKey
		end
		if entry.enabled and entry.spellName and entry.spellName ~= '' then
			local filter = entry.filter or 'HELPFUL'
			local key = filter .. ':' .. entry.spellName
			nameToKey[key] = entryKey
		end
	end
	return lookups, nameToKey
end

-- ============================================================
-- AURA SCANNING
-- ============================================================

local function ScanAuras_NewAPI(unit, entries, lookups, nameToKey)
	local matches = {}

	for filter, spellLookup in pairs(lookups) do
		pcall(AuraUtil.ForEachAura, unit, filter, nil, function(aura)
			if aura.spellId and CanAccess(aura.spellId) then
				local entryKey = spellLookup[aura.spellId]
				if entryKey then
					local entry = entries[entryKey]
					if entry.onlyMine then
						if aura.sourceUnit and CanAccess(aura.sourceUnit) and aura.sourceUnit == 'player' then
							matches[entryKey] = aura
						end
					else
						matches[entryKey] = aura
					end
				end
			end
		end, true)
	end

	return matches
end

local function ScanAuras_Retail_Legacy(unit, entries, lookups, nameToKey)
	local matches = {}

	for filter, spellLookup in pairs(lookups) do
		for i = 1, 40 do
			local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
			if not aura then
				break
			end
			if aura.spellId and CanAccess(aura.spellId) then
				local entryKey = spellLookup[aura.spellId]
				if entryKey then
					local entry = entries[entryKey]
					if entry.onlyMine then
						if aura.sourceUnit and CanAccess(aura.sourceUnit) and aura.sourceUnit == 'player' then
							matches[entryKey] = aura
						end
					else
						matches[entryKey] = aura
					end
				end
			end
		end
	end

	return matches
end

local function ScanAuras_Classic(unit, entries, lookups, nameToKey)
	local matches = {}

	for filter, spellLookup in pairs(lookups) do
		for i = 1, 40 do
			local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
			if not aura then
				break
			end

			local entryKey = nil

			-- Try spell ID first
			if aura.spellId and CanAccess(aura.spellId) then
				entryKey = spellLookup[aura.spellId]
			end

			-- Fallback: spell name match
			if not entryKey and aura.name and CanAccess(aura.name) then
				local key = filter .. ':' .. aura.name
				entryKey = nameToKey[key]
			end

			if entryKey then
				local entry = entries[entryKey]
				if entry.onlyMine then
					if aura.sourceUnit and CanAccess(aura.sourceUnit) and aura.sourceUnit == 'player' then
						matches[entryKey] = aura
					end
				else
					matches[entryKey] = aura
				end
			end
		end
	end

	return matches
end

local function ScanAuras(unit, entries)
	if not entries or not next(entries) then
		return {}
	end

	local lookups, nameToKey = BuildLookups(entries)
	if not next(lookups) then
		return {}
	end

	if isRetail then
		if hasForEachAura then
			return ScanAuras_NewAPI(unit, entries, lookups, nameToKey)
		else
			return ScanAuras_Retail_Legacy(unit, entries, lookups, nameToKey)
		end
	else
		return ScanAuras_Classic(unit, entries, lookups, nameToKey)
	end
end

-- ============================================================
-- OUF ELEMENT
-- ============================================================

local function Update(self, event, unit)
	if self.unit ~= unit and event ~= 'ForceUpdate' then
		return
	end

	local element = self.AuraDesigner
	if not element then
		return
	end

	local DB = element.DB
	if not DB or not DB.enabled then
		if element.HideAll then
			element:HideAll()
		end
		return
	end

	unit = self.unit
	if not unit or not UnitExists(unit) then
		if element.HideAll then
			element:HideAll()
		end
		return
	end

	local matches = ScanAuras(unit, DB.entries or {})

	for entryKey, entry in pairs(DB.entries or {}) do
		if entry.enabled then
			local auraData = matches[entryKey]
			if auraData and element.ShowVisual then
				element:ShowVisual(entryKey, entry, auraData, unit)
			elseif element.HideVisual then
				element:HideVisual(entryKey, entry)
			end
		end
	end
end

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self)
	local element = self.AuraDesigner
	if element then
		element.__owner = self
		element.ForceUpdate = ForceUpdate
		self:RegisterEvent('UNIT_AURA', Update)
		return true
	end
end

local function Disable(self)
	local element = self.AuraDesigner
	if element then
		self:UnregisterEvent('UNIT_AURA', Update)
		if element.HideAll then
			element:HideAll()
		end
	end
end

oUF:AddElement('AuraDesigner', Update, Enable, Disable)
