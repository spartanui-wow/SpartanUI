local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Sharing and profiles page (3.2 #6, 3.6).
--   * Follow my <host> profile (the label names the host through P:HostName()), and the profile
--     picker: AceDBOptions-3.0 when the client has it, a small picker otherwise.
--   * Share what you made: this style, your colors, the "When" list or everything, as a text to copy.
--     More settings: the name written on a style and its version (so a newer version can update
--     the copy others have and keep their changes).
--   * Import: paste a string, see what it is (a live preview card for a style, the preview panel
--     draws it too), then Use it now, Add as a new style, Update (keeps your changes), or Use these
--     colors / this list / these settings. One Undo for the last replace.
-- The work behind it is P.Exchange (Options/Exchange.lua). Strings are never shown back in the
-- paste box: a long string would be sent to the box again on every redraw.

local Registry = P.Styles.Registry
local Store = P.Store
local Exchange = P.Exchange

---@class Plates.SharingPage
local SharingPage = { export = { what = 'style', styleId = nil, version = nil }, generation = 0, cache = nil }
P.SharingPage = SharingPage

----------------------------------------------------------------------------------------------------
-- Export
----------------------------------------------------------------------------------------------------

---Where the Style page's Share and Import buttons land. AceConfigDialog scrolls to real controls
---only, never to an inline group's own key, so each is a path to the first control worth reading
---inside its group: the groups first, the control last (host.OpenOptions takes a path like this).
SharingPage.FOCUS = { export = { 'export', 'exportText' }, import = { 'import', 'importText' } }

---Point the export box at something (the Style page's Share button and the card menu use this).
---@param what? 'style'|'colors'|'when'|'everything'
---@param styleId? string Style value (a style id, or 'host')
function SharingPage:ShowExport(what, styleId)
	self.export.what = what or 'style'
	self.export.styleId = styleId
	self.export.version = nil
	self.cache = nil
	Options:RequestRefresh(false)
end

---@return string
function SharingPage:StyleValue()
	return self.export.styleId or Store:Get('style') or 'host'
end

---The string for the export box, made again only when something it holds has changed.
---@return string|nil text
---@return string|nil reason
function SharingPage:ExportText()
	local export = self.export
	local key = table.concat({ export.what, tostring(self:StyleValue()), tostring(export.version), Exchange:GetAuthor(), self.generation }, '|')
	local cache = self.cache
	if cache and cache.key == key then
		return cache.text, cache.reason
	end
	local text, reason = Exchange:BuildExport(export.what, { styleId = self:StyleValue(), version = export.version })
	self.cache = { key = key, text = text, reason = reason }
	return text, reason
end

local EXPORT_VALUES = {
	style = L['This style'],
	colors = L['My colors'],
	when = L['My special cases'],
	everything = L['Everything'],
}

local function ExportStyleValues()
	local values = {}
	for _, item in ipairs(Registry:List(false)) do
		values[item.matchesHost and 'host' or item.id] = item.matchesHost and L['Match my look'] or item.name
	end
	return values
end

---@return string
local function ExportNote()
	local text, reason = SharingPage:ExportText()
	if text then
		return ''
	end
	if reason == 'unavailable' then
		return P.Share:ReasonText('unavailable')
	end
	return L['This could not be turned into a share string.']
end

----------------------------------------------------------------------------------------------------
-- Profiles
----------------------------------------------------------------------------------------------------

---True while the profile picker should stay still: the profile follows the host's.
local function Following()
	local host = P.host
	return host ~= nil and host.GetHostProfileName ~= nil and Store:Get('followHostProfile') == true
end

local function ProfilesLocked()
	return Options.Locked() or Following()
end

local function Trim(text)
	return (string.gsub(string.gsub(text or '', '^%s+', ''), '%s+$', ''))
end

---The profile picker. AceDBOptions-3.0 brings the usual pick, new, copy, delete and reset; a small
---one stands in where the client does not have it.
---@return table group
local function ProfilePicker()
	local AceDBOptions = LibStub and LibStub('AceDBOptions-3.0', true)
	local db = P.db
	local note = {
		type = 'description',
		name = function()
			return string.format(L['Your nameplates follow your %s profile, so this picker waits. Turn that off above to pick a profile yourself.'], P:HostName())
		end,
		order = 0,
		fontSize = 'medium',
		hidden = function()
			return not Following()
		end,
	}
	if AceDBOptions and db then
		local source = AceDBOptions:GetOptionsTable(db)
		local group = {}
		for key, value in pairs(source) do
			group[key] = value
		end
		-- A copy of the argument list: the library's own table is shared
		local args = { followNote = note }
		for key, value in pairs(source.args or {}) do
			args[key] = value
		end
		group.args = args
		group.name = L['Profiles']
		group.inline = true
		group.order = 30
		group.disabled = ProfilesLocked
		return group
	end
	return {
		type = 'group',
		name = L['Profiles'],
		inline = true,
		order = 30,
		disabled = ProfilesLocked,
		args = {
			followNote = note,
			current = {
				type = 'select',
				name = L['Profile'],
				desc = L['Your nameplate settings are kept in a profile. Pick another one to switch.'],
				order = 1,
				values = function()
					local out = {}
					for _, name in ipairs(db:GetProfiles()) do
						out[name] = name
					end
					return out
				end,
				get = function()
					return db:GetCurrentProfile()
				end,
				set = function(_, value)
					Store:SetProfile(value)
				end,
			},
			new = {
				type = 'input',
				name = L['New profile'],
				desc = L['Type a name to make a new profile and switch to it.'],
				order = 2,
				get = function()
					return ''
				end,
				set = function(_, value)
					value = Trim(value)
					if value ~= '' then
						Store:SetProfile(value)
					end
				end,
			},
			reset = {
				type = 'execute',
				name = L['Reset this profile'],
				desc = L['Puts every nameplate setting in this profile back to how it started.'],
				order = 3,
				confirm = true,
				confirmText = L['Reset all nameplate settings in this profile?'],
				func = function()
					db:ResetProfile()
				end,
			},
		},
	}
end

----------------------------------------------------------------------------------------------------
-- Import
----------------------------------------------------------------------------------------------------

local function Info()
	return Exchange.state.info
end

---The text under the paste box: what the string is, why it failed, or what just happened.
---@return string
local function ImportText()
	local state = Exchange.state
	if state.info then
		return table.concat(Exchange:Describe(state.info), '\n')
	end
	if state.reason then
		return Exchange:ReasonText(state.reason)
	end
	return state.result or L['Paste a share string from another player. You see what it holds before anything changes.']
end

---The label of the main button for a pasted string.
---@return string
local function UseLabel()
	local info = Info()
	if not info then
		return L['Use it now']
	end
	if info.kind == 'style' then
		if info.updateOf and info.isNewer then
			return string.format(L['Update to version %s'], tostring(info.version or 1))
		end
		return L['Use it now']
	elseif info.kind == 'colors' then
		return L['Use these colors']
	elseif info.kind == 'when' then
		return L['Use this list']
	end
	return L['Use these settings']
end

local function UseAction()
	local info = Info()
	if info and info.kind == 'style' then
		return (info.updateOf and info.isNewer) and 'update' or 'use'
	end
	return 'replace'
end

---A one-card grid for the pasted style, drawn by the same card art as the gallery.
---@return table[] cards
local function ImportCards()
	local info = Info()
	if not (info and info.kind == 'style') then
		return {}
	end
	local gallery = P.Gallery
	return {
		{
			value = gallery.PREVIEW_VALUE,
			title = info.name,
			caption = info.author and string.format(L['By %s. Version %s.'], info.author, tostring(info.version or 1)) or '',
			art = gallery:Art(),
		},
	}
end

----------------------------------------------------------------------------------------------------
-- The page
----------------------------------------------------------------------------------------------------

Options:AddPage('sharing', 6, function()
	local getFollow, setFollow = Options.Bind('followHostProfile')
	local cardGrid = P.host and P.host.widgets and P.host.widgets.cardGrid
	local export = SharingPage.export

	local importCard = {
		type = 'select',
		name = L['Preview'],
		order = 2,
		width = 'full',
		values = function()
			local values = {}
			for _, card in ipairs(ImportCards()) do
				values[card.value] = card.title
			end
			return values
		end,
		get = function()
			return nil
		end,
		set = function() end,
		hidden = function()
			local info = Info()
			return not (info and info.kind == 'style')
		end,
	}
	if cardGrid then
		importCard.dialogControl = cardGrid
		importCard.arg = { size = 'look', cards = ImportCards, noToggle = true }
	end

	return {
		type = 'group',
		name = L['Sharing and profiles'],
		args = {
			follow = {
				type = 'toggle',
				name = string.format(L['Follow my %s profile'], P:HostName()),
				desc = L['Your nameplate settings switch when your main profile switches.'],
				order = 1,
				width = 'full',
				hidden = function()
					return not (P.host and P.host.GetHostProfileName)
				end,
				get = getFollow,
				set = function(info, value)
					setFollow(info, value)
					Store:FollowHostProfile()
				end,
				disabled = Options.Locked,
			},
			profiles = ProfilePicker(),
			export = {
				type = 'group',
				name = L['Share what you made'],
				inline = true,
				order = 10,
				args = {
					what = {
						type = 'select',
						name = L['What to share'],
						order = 1,
						values = EXPORT_VALUES,
						sorting = { 'style', 'colors', 'when', 'everything' },
						get = function()
							return export.what
						end,
						set = function(_, value)
							SharingPage:ShowExport(value, export.styleId)
						end,
					},
					style = {
						type = 'select',
						name = L['Style to share'],
						order = 2,
						values = ExportStyleValues,
						hidden = function()
							return export.what ~= 'style'
						end,
						get = function()
							return SharingPage:StyleValue()
						end,
						set = function(_, value)
							SharingPage:ShowExport('style', value)
						end,
					},
					note = {
						type = 'description',
						name = ExportNote,
						order = 3,
						hidden = function()
							return ExportNote() == ''
						end,
					},
					exportText = {
						type = 'input',
						name = L['Share string'],
						desc = L['Select all the text, copy it, and send it. The other player pastes it into Import.'],
						order = 4,
						width = 'full',
						multiline = 6,
						get = function()
							return (SharingPage:ExportText()) or ''
						end,
						set = function() end,
					},
					author = {
						type = 'input',
						name = L['Your name on shared styles'],
						desc = L['Shown to players who import your style. You can leave it empty.'],
						order = 5,
						advanced = true,
						get = function()
							return Exchange:GetAuthor()
						end,
						set = function(_, value)
							Exchange:SetAuthor(value)
							SharingPage.generation = SharingPage.generation + 1
						end,
					},
					version = {
						type = 'input',
						name = L['Style version'],
						desc = L['Raise this number when you change a style you share. Players who imported it can update and keep their own changes.'],
						order = 6,
						advanced = true,
						hidden = function()
							return export.what ~= 'style'
						end,
						get = function()
							if export.version then
								return tostring(export.version)
							end
							local style = Registry:Get(Registry:ResolveId(SharingPage:StyleValue()))
							return tostring(style and style.version or 1)
						end,
						set = function(_, value)
							local number = tonumber(value)
							if number and number >= 1 and number <= 1000000 then
								export.version = math.floor(number)
								SharingPage.cache = nil
							end
						end,
					},
				},
			},
			import = {
				type = 'group',
				name = L['Import'],
				inline = true,
				order = 20,
				args = {
					importText = {
						type = 'input',
						name = L['Paste a share string'],
						desc = L['Paste the text, then press Accept.'],
						order = 1,
						width = 'full',
						multiline = 4,
						get = function()
							return ''
						end,
						set = function(_, value)
							Exchange:Paste(value)
						end,
					},
					importCard = importCard,
					importInfo = {
						type = 'description',
						name = ImportText,
						order = 3,
						fontSize = 'medium',
					},
					importUse = {
						type = 'execute',
						name = UseLabel,
						order = 4,
						primary = true,
						hidden = function()
							return Info() == nil
						end,
						disabled = Options.Locked,
						func = function()
							Exchange:Do(UseAction())
						end,
					},
					importNew = {
						type = 'execute',
						name = L['Add as a new style'],
						desc = L['Saves it as a style of its own. It never changes a style you already have.'],
						order = 5,
						hidden = function()
							local info = Info()
							return not (info and info.kind == 'style')
						end,
						func = function()
							Exchange:Do('new')
						end,
					},
					importUndo = {
						type = 'execute',
						name = function()
							local undo = Exchange.undo
							return string.format(L['Undo: put my %s back'], undo and undo.label or '')
						end,
						order = 6,
						hidden = function()
							return not Exchange:HasUndo()
						end,
						disabled = Options.Locked,
						func = function()
							Exchange:Undo()
						end,
					},
					importClear = {
						type = 'execute',
						name = L['Clear'],
						order = 7,
						hidden = function()
							return Info() == nil and Exchange.state.reason == nil
						end,
						func = function()
							Exchange:Clear()
						end,
					},
				},
			},
		},
	}
end)

P:On('EXCHANGE_CHANGED', function()
	Options:RequestRefresh(false)
end, SharingPage)

P:On('STORE_CHANGED', function()
	SharingPage.generation = SharingPage.generation + 1
end, SharingPage)

P:On('STYLES_CHANGED', function()
	SharingPage.generation = SharingPage.generation + 1
end, SharingPage)
