---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

-- Importers read another bar addon's saved settings and translate them into SpartanUI's
-- format. Saved settings are only in memory while that addon is enabled, so each importer
-- reports itself unavailable until the player turns the addon on for a session.

---@class SUI.ActionBars.ImportPosition
---@field point string Point on the bar
---@field anchor Frame|string Frame the bar is placed against
---@field relativePoint string Point on the anchor
---@field x number Offset in UIParent units
---@field y number Offset in UIParent units

---@class SUI.ActionBars.ImportResult
---@field settings table Partial settings in SpartanUI's layout (bars, pet, stance, micro, bags, globals)
---@field positions table<string, SUI.ActionBars.ImportPosition> Keyed by bar key
---@field scales table<string, number> Keyed by bar key
---@field bindings table<string, string> Old binding command -> SpartanUI binding command
---@field notes string[] Things that could not be carried over

---@class SUI.ActionBars.Importer
---@field id string
---@field name string
---@field IsAvailable fun(self): boolean, string|nil
---@field GetProfiles fun(self): string[]
---@field GetCurrentProfile fun(self): string|nil
---@field Build fun(self, profile: string): SUI.ActionBars.ImportResult
---@field DisableSource? fun(self) Stop the source addon drawing bars after import

module.Importers = {} ---@type table<string, SUI.ActionBars.Importer>
module.ImporterOrder = {} ---@type string[]

---@param importer SUI.ActionBars.Importer
function module:RegisterImporter(importer)
	if not self.Importers[importer.id] then
		table.insert(self.ImporterOrder, importer.id)
	end
	self.Importers[importer.id] = importer
end

---@return SUI.ActionBars.ImportResult
function module:NewImportResult()
	return {
		settings = { bars = {} },
		positions = {},
		scales = {},
		bindings = {},
		notes = {},
	}
end

---Look up a key on a table only when it really exists (AceDB tables fill in defaults).
---@param tbl table|nil
---@param key any
---@return any
function module.RawGet(tbl, key)
	if type(tbl) ~= 'table' then
		return nil
	end
	return rawget(tbl, key)
end

---Copy defaults, then lay saved values over them. AceDB drops values equal to their
---default when saving, so every importer needs the source addon's defaults filled back in.
---@param defaults table|nil
---@param saved table|nil
---@return table
function module:MergeWithDefaults(defaults, saved)
	local result = {}
	if type(defaults) == 'table' then
		result = SUI:CopyData(result, defaults)
		-- CopyData leaves wildcard metatables behind; strip them so pairs() sees real data
		setmetatable(result, nil)
	end
	if type(saved) == 'table' then
		result = SUI:MergeData(result, saved, true)
	end
	return result
end

---A LibSharedMedia font name that exists here, or '' for the default font.
---@param name string|nil
---@return string
function module:ResolveFontName(name)
	if type(name) == 'string' and name ~= '' and SUI.Lib.LSM:IsValid('font', name) then
		return name
	end
	return ''
end

---Normalize outline flags to what FontString:SetFont accepts.
---@param flags string|nil
---@return string
function module:ResolveFontFlags(flags)
	if type(flags) ~= 'string' then
		return 'OUTLINE'
	end
	flags = flags:upper():gsub('SHADOW', '')
	if flags == '' or flags == 'NONE' then
		return ''
	end
	if flags == 'MONOCHROMEOUTLINE' then
		return 'MONOCHROME,OUTLINE'
	elseif flags == 'MONOCHROMETHICKOUTLINE' then
		return 'MONOCHROME,THICKOUTLINE'
	end
	return flags
end

---@param color table|nil {r=,g=,b=} or {r,g,b}
---@return table|nil
function module:ResolveColor(color)
	if type(color) ~= 'table' then
		return nil
	end
	local r = color.r or color[1]
	local g = color.g or color[2]
	local b = color.b or color[3]
	if r and g and b then
		return { r, g, b }
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Applying
----------------------------------------------------------------------------------------------------

---Write a table of imported values into one settings section.
---@param path any[]
---@param values table
local function WriteSection(path, values)
	for key, value in pairs(values) do
		-- Recurse into sections; list-style tables (colors) are stored whole
		if type(value) == 'table' and value[1] == nil then
			local sub = {}
			for i = 1, #path do
				sub[i] = path[i]
			end
			sub[#sub + 1] = key
			WriteSection(sub, value)
		else
			module:SetSetting(path, key, value)
		end
	end
end

---How many micro buttons are showing, whether or not SpartanUI's bar is running yet.
---@return number
function module:CountMicroButtons()
	local bar = self.bars.BT4BarMicroMenu
	if bar and #bar.buttons > 0 then
		return #bar.buttons
	end
	local count = 0
	if MicroMenu and MicroMenu.GetChildren then
		for _, child in ipairs({ MicroMenu:GetChildren() }) do
			if child.layoutIndex and child:IsShown() then
				count = count + 1
			end
		end
	end
	return count > 0 and count or 12
end

---How many buttons the bag bar shows with these settings.
---@param db table
---@return number
function module:CountBagButtons(db)
	local count = 1
	if db.showKeyring and self:HasKeyring() then
		count = count + 1
	end
	if db.showReagentBag and _G.CharacterReagentBag0Slot then
		count = count + 1
	end
	if not db.onlyBackpack then
		count = count + 4
	end
	return count
end

---Work out the settings section and button count that decide a bar's size.
---@param key string
---@return table|nil db
---@return number count
local function GetBarSizing(key)
	local current = module.CurrentSettings
	local id = tonumber(key:match('^BT4Bar(%d+)$'))
	if id then
		local db = current.bars[id]
		return db, db and db.buttons or 12
	elseif key == 'BT4BarPetBar' then
		return current.pet, NUM_PET_ACTION_SLOTS or 10
	elseif key == 'BT4BarStanceBar' then
		return current.stance, math.max(GetNumShapeshiftForms() or 0, 1)
	elseif key == 'BT4BarMicroMenu' then
		return current.micro, module:CountMicroButtons()
	elseif key == 'BT4BarBagBar' then
		return current.bags, module:CountBagButtons(current.bags)
	end
	return nil, 0
end

---Convert an imported position into a MoveIt position string at the given scale.
---@param key string
---@param position SUI.ActionBars.ImportPosition
---@param scale number
---@return string|nil
function module:ConvertImportPosition(key, position, scale)
	local db, count = GetBarSizing(key)
	if not db then
		return nil
	end
	local width, height = self:CalculateBarSize(db, count)

	local anchor = position.anchor
	if type(anchor) == 'string' then
		anchor = _G[anchor]
	end
	anchor = anchor or UIParent

	-- Place a stand-in of the bar's on-screen size, then describe where it landed
	-- relative to the nearest screen corner, the same way MoveIt saves a dragged frame.
	local probe = self.importProbe or CreateFrame('Frame', nil, UIParent)
	self.importProbe = probe
	probe:SetScale(1)
	probe:SetSize(width * scale, height * scale)
	probe:ClearAllPoints()
	local ok = pcall(probe.SetPoint, probe, position.point or 'CENTER', anchor, position.relativePoint or position.point or 'CENTER', position.x or 0, position.y or 0)
	if not ok or not probe:GetCenter() then
		return nil
	end

	local MoveIt = SUI:GetModule('MoveIt', true) ---@type MoveIt
	local corner, x, y = 'BOTTOMLEFT', probe:GetLeft(), probe:GetBottom()
	if MoveIt and MoveIt.PositionCalculator then
		corner = MoveIt.PositionCalculator:GetClosestAnchor(probe)
		x, y = MoveIt.PositionCalculator:CalculateAnchorOffset(probe, corner)
	end
	-- The mover is scaled, so its offsets are in scaled units
	return ('%s,UIParent,%s,%d,%d'):format(corner, corner, math.floor(x / scale + 0.5), math.floor(y / scale + 0.5))
end

---Rebind keys from another addon's binding commands to SpartanUI's.
---@param bindings table<string, string>
---@return number moved
function module:MigrateBindings(bindings)
	local moved = 0
	for oldCommand, newCommand in pairs(bindings) do
		for _, key in ipairs({ GetBindingKey(oldCommand) }) do
			if SetBinding(key, newCommand) then
				moved = moved + 1
			end
		end
	end
	if moved > 0 then
		SaveBindings(GetCurrentBindingSet())
	end
	return moved
end

local SIZE_KEYS = { 'buttonSize', 'buttonHeight', 'keepSizeRatio' }

---Drop button sizes so bars kept in the theme's slots also keep the theme's size.
---@param settings table
local function StripSizes(settings)
	local function strip(section)
		if type(section) == 'table' then
			for _, key in ipairs(SIZE_KEYS) do
				section[key] = nil
			end
		end
	end
	for _, bar in pairs(settings.bars or {}) do
		strip(bar)
	end
	for _, section in ipairs({ 'pet', 'stance', 'micro', 'bags' }) do
		strip(settings[section])
	end
end

---@class SUI.ActionBars.ImportOptions
---@field positions boolean Also move bars to where the other addon had them
---@field keybinds boolean Move key bindings for bars without a Blizzard binding
---@field disableSource boolean Stop the other addon drawing bars

---Apply an import and switch to SpartanUI's bars.
---@param importerID string
---@param profile string
---@param options SUI.ActionBars.ImportOptions
---@return boolean success
---@return string|nil message
function module:RunImport(importerID, profile, options)
	if InCombatLockdown() then
		return false, ERR_NOT_IN_COMBAT
	end
	local importer = self.Importers[importerID]
	if not importer then
		return false, L['Unknown import source']
	end
	local available, reason = importer:IsAvailable()
	if not available then
		return false, reason
	end

	local ok, result = pcall(importer.Build, importer, profile)
	if not ok or type(result) ~= 'table' then
		if self.logger then
			self.logger.error('Import from ' .. importerID .. ' failed: ' .. tostring(result))
		end
		return false, L['The import failed. Your current settings were not changed.']
	end

	if not options.positions then
		StripSizes(result.settings)
	end

	-- Keep a copy so a failure part way through puts everything back
	local function copy(tbl)
		local out = {}
		for k, v in pairs(tbl) do
			out[k] = type(v) == 'table' and copy(v) or v
		end
		return out
	end
	local snapshot = copy(self.DB)
	local MoveIt = SUI:GetModule('MoveIt', true) ---@type MoveIt
	local moverSnapshot = MoveIt and MoveIt.DB and copy(MoveIt.DB.movers)

	local applied, applyError = pcall(function()
		-- Start from a clean slate so leftovers from an earlier setup do not mix in
		wipe(self.DB)
		SUI.DBM:RefreshSettings(self)

		for section, values in pairs(result.settings) do
			if section == 'bars' then
				for id, barValues in pairs(values) do
					if self.CurrentSettings.bars[id] then
						WriteSection({ 'bars', id }, barValues)
					end
				end
			elseif type(values) == 'table' and type(self.CurrentSettings[section]) == 'table' then
				WriteSection({ section }, values)
			else
				self:SetSetting({}, section, values)
			end
		end
		SUI.DBM:RefreshSettings(self)

		-- Sizes and placement travel together: copying the other addon's positions brings its
		-- button sizes and scale along; otherwise the bars keep the theme's size and slots.
		-- A bar only takes a scale when it also got a position, or it would sit in the
		-- theme's slot at the wrong size.
		if options.positions and MoveIt and MoveIt.DB then
			for key, position in pairs(result.positions) do
				local scale = result.scales[key] or 1
				local moved = self:ConvertImportPosition(key, position, scale)
				if moved then
					MoveIt.DB.movers[key].MovedPoints = moved
					MoveIt.DB.movers[key].AdjustedScale = scale
				end
			end
		end

		if result.vehicleUI ~= nil then
			local artwork = SUI:GetModule('Artwork', true)
			if artwork then
				SUI.DBM:Set(artwork, 'VehicleUI', result.vehicleUI)
			end
		end

		if options.keybinds and next(result.bindings) then
			self:MigrateBindings(result.bindings)
		end
	end)

	if not applied then
		wipe(self.DB)
		for k, v in pairs(snapshot) do
			self.DB[k] = v
		end
		SUI.DBM:RefreshSettings(self)
		if MoveIt and MoveIt.DB and moverSnapshot then
			wipe(MoveIt.DB.movers)
			for k, v in pairs(moverSnapshot) do
				MoveIt.DB.movers[k] = v
			end
		end
		if self.logger then
			self.logger.error('Applying the import from ' .. importerID .. ' failed: ' .. tostring(applyError))
		end
		return false, L['The import failed. Your current settings were not changed.']
	end

	for _, note in ipairs(result.notes) do
		SUI:Print(note)
	end

	if importer.DisableSource then
		importer:DisableSource()
	end

	local BarSystem = SUI.Handlers.BarSystem
	BarSystem:SetChosenSystem('SpartanUI')
	return true
end
