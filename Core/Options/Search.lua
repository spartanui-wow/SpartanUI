---@class SUI
local SUI = SUI
local L = SUI.L

-- Settings search for the options window. Walks the options table once, then matches every
-- typed word against the option name, its description and where it lives.

---@class SUI.OptionsWindow.Search
local Search = {}
SUI.OptionsWindow = SUI.OptionsWindow or {}
SUI.OptionsWindow.Search = Search

local APP = 'SpartanUI'
local MAX_RESULTS = 40
local MAX_DEPTH = 7

-- Everyday words mapped to the words the settings use
local SYNONYMS = {
	hp = 'health',
	life = 'health',
	mana = 'power',
	energy = 'power',
	mp = 'power',
	colour = 'color',
	size = 'scale',
	bigger = 'scale',
	smaller = 'scale',
	move = 'position',
	moving = 'position',
	place = 'position',
	buffs = 'buff',
	debuffs = 'debuff',
	auras = 'aura',
	hotkey = 'keybind',
	keybinds = 'keybind',
	bars = 'bar',
	castbar = 'cast',
	portraits = 'portrait',
	see = 'alpha',
	transparency = 'alpha',
	opacity = 'alpha',
}

---@class SUI.OptionsWindow.SearchEntry
---@field name string
---@field lowerName string
---@field lowerDesc string
---@field lowerCrumb string
---@field crumb string
---@field path string[]
---@field isGroup boolean

---@type SUI.OptionsWindow.SearchEntry[]|nil
local index

local function Clean(text)
	if type(text) ~= 'string' then
		return nil
	end
	text = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|T.-|t', ''):gsub('|A.-|a', ''):gsub('\n', ' ')
	text = strtrim(text)
	if text == '' then
		return nil
	end
	return text
end

---Resolve a name/desc/hidden member the way AceConfig does, without letting errors escape
local function Resolve(value, info)
	if type(value) == 'function' then
		local ok, result = pcall(value, info)
		if ok then
			return result
		end
		return nil
	end
	return value
end

local function IsHidden(option, info)
	return Resolve(option.hidden, info) == true or Resolve(option.dialogHidden, info) == true
end

local function Walk(root, group, path, crumbs, depth, out)
	if depth > MAX_DEPTH or type(group.args) ~= 'table' then
		return
	end
	for key, option in pairs(group.args) do
		if type(option) == 'table' and type(key) == 'string' then
			local childPath = {}
			for i = 1, #path do
				childPath[i] = path[i]
			end
			childPath[#childPath + 1] = key
			local info = { options = root, option = option, arg = option.arg, handler = option.handler, type = option.type, [0] = APP }
			for i = 1, #childPath do
				info[i] = childPath[i]
			end

			if not IsHidden(option, info) then
				local name = Clean(Resolve(option.name, info))
				local isGroup = option.type == 'group'
				local isInline = isGroup and (option.inline or option.guiInline or option.dialogInline)
				local skip = option.type == 'description' or option.type == 'header'

				if name and not skip and not isInline then
					local desc = Clean(Resolve(option.desc, info)) or ''
					local crumb = table.concat(crumbs, ' > ')
					out[#out + 1] = {
						name = name,
						lowerName = name:lower(),
						lowerDesc = desc:lower(),
						lowerCrumb = crumb:lower(),
						crumb = crumb,
						path = childPath,
						isGroup = isGroup,
					}
				end

				if isGroup then
					local childCrumbs = {}
					for i = 1, #crumbs do
						childCrumbs[i] = crumbs[i]
					end
					if name and not isInline then
						childCrumbs[#childCrumbs + 1] = name
					end
					Walk(root, option, childPath, childCrumbs, depth + 1, out)
				end
			end
		end
	end
end

---@return SUI.OptionsWindow.SearchEntry[]
function Search:GetIndex()
	if index then
		return index
	end
	local registry = LibStub('AceConfigRegistry-3.0')
	local app = registry:GetOptionsTable(APP)
	index = {}
	if app then
		local root = app('dialog', 'AceConfigDialog-3.0-SUI')
		Walk(root, root, {}, {}, 1, index)
	end
	return index
end

function Search:Invalidate()
	index = nil
end

---Score an entry against the query words (0 = no match)
---@param entry SUI.OptionsWindow.SearchEntry
---@param words string[]
---@return number
local function Score(entry, words)
	local total = 0
	for _, word in ipairs(words) do
		local best = 0
		local alt = SYNONYMS[word]
		for _, w in ipairs({ word, alt }) do
			if w then
				if entry.lowerName == w then
					best = math.max(best, 100)
				elseif entry.lowerName:sub(1, #w) == w then
					best = math.max(best, 60)
				elseif entry.lowerName:find(w, 1, true) then
					best = math.max(best, 40)
				elseif entry.lowerDesc:find(w, 1, true) then
					best = math.max(best, 12)
				elseif entry.lowerCrumb:find(w, 1, true) then
					best = math.max(best, 6)
				end
			end
		end
		if best == 0 then
			return 0
		end
		total = total + best
	end
	if entry.isGroup then
		total = total + 5
	end
	-- Shallower settings first when scores tie
	return total - #entry.path * 0.5
end

---Search and return ranked entries
---@param text string
---@return SUI.OptionsWindow.SearchEntry[]
function Search:Find(text)
	local words = {}
	for word in text:lower():gmatch('%S+') do
		if #word >= 2 then
			words[#words + 1] = word
		end
	end
	local results = {}
	if #words == 0 then
		return results
	end
	local scored = {}
	for _, entry in ipairs(self:GetIndex()) do
		local score = Score(entry, words)
		if score > 0 then
			scored[#scored + 1] = { entry = entry, score = score }
		end
	end
	table.sort(scored, function(a, b)
		if a.score == b.score then
			return a.entry.name < b.entry.name
		end
		return a.score > b.score
	end)
	for i = 1, math.min(MAX_RESULTS, #scored) do
		results[i] = scored[i].entry
	end
	return results
end

---Open the page holding an entry and bring the setting into view
---@param entry SUI.OptionsWindow.SearchEntry
function Search:Go(entry)
	local ACD = LibStub('AceConfigDialog-3.0-SUI')
	local groupPath = {}
	local optionKey
	if entry.isGroup then
		groupPath = entry.path
	else
		for i = 1, #entry.path - 1 do
			groupPath[i] = entry.path[i]
		end
		optionKey = entry.path[#entry.path]
	end
	ACD:Navigate(APP, groupPath, optionKey)
end

---Run a search for the window's search box
---@param window table The SUI-Window widget
---@param text string
function Search:Run(window, text)
	if not text or strtrim(text) == '' then
		window:ClearSearch()
		return
	end
	local results = {}
	for i, entry in ipairs(self:Find(text)) do
		results[i] = {
			text = entry.name,
			sub = entry.crumb ~= '' and entry.crumb or L['Main page'],
			onClick = function()
				Search:Go(entry)
			end,
		}
	end
	window:ShowResults(results)
end

local registry = LibStub('AceConfigRegistry-3.0', true)
if registry then
	registry.RegisterCallback(Search, 'ConfigTableChange', function(_, appName)
		if appName == APP then
			Search:Invalidate()
		end
	end)
end
