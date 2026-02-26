---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local compiledPatterns = {}
local playerName = ''
local lastSoundTime = 0

local function CompilePatterns()
	wipe(compiledPatterns)

	if not module.DB.highlights.enabled then
		return
	end

	for _, keyword in ipairs(module.DB.highlights.keywords) do
		if keyword and keyword ~= '' then
			-- Escape pattern special characters then make case-insensitive
			local escaped = keyword:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1')
			table.insert(compiledPatterns, {
				pattern = escaped:lower(),
				display = keyword,
			})
		end
	end
end

local function ColorWrap(text, color)
	return string.format('|cff%02x%02x%02x%s|r', color.r * 255, color.g * 255, color.b * 255, text)
end

local function HighlightMessage(self, event, msg, ...)
	if not module.DB.highlights.enabled then
		return
	end
	if SUI.BlizzAPI.issecretvalue(msg) then
		return
	end

	local modified = false
	local newMsg = msg

	-- Keyword highlighting
	if #compiledPatterns > 0 then
		local lowerMsg = newMsg:lower()
		for _, entry in ipairs(compiledPatterns) do
			local startPos, endPos = lowerMsg:find(entry.pattern)
			if startPos then
				-- Wrap the original-case match with highlight color
				local original = newMsg:sub(startPos, endPos)
				local highlighted = ColorWrap(original, module.DB.highlights.highlightColor)
				newMsg = newMsg:sub(1, startPos - 1) .. highlighted .. newMsg:sub(endPos + 1)
				modified = true
			end
		end
	end

	-- Mentions (player name)
	if module.DB.highlights.mentionsEnabled and playerName ~= '' then
		local lowerMsg = newMsg:lower()
		local lowerName = playerName:lower()
		local startPos, endPos = lowerMsg:find(lowerName, 1, true)
		if startPos then
			local original = newMsg:sub(startPos, endPos)
			local highlighted = ColorWrap(original, module.DB.highlights.mentionsColor)
			newMsg = newMsg:sub(1, startPos - 1) .. highlighted .. newMsg:sub(endPos + 1)
			modified = true

			-- Play sound alert
			if module.DB.highlights.mentionsSound and module.DB.highlights.mentionsSound ~= 'None' then
				local now = GetTime()
				if now - lastSoundTime >= module.DB.highlights.soundThrottle then
					if not (module.DB.highlights.suppressInCombat and InCombatLockdown()) then
						PlaySound(SOUNDKIT[module.DB.highlights.mentionsSound] or 3081, 'Master')
						lastSoundTime = now
					end
				end
			end
		end
	end

	if modified then
		return false, newMsg, ...
	end
end

function module:SetupHighlights()
	if SUI:IsModuleDisabled(module) then
		return
	end

	playerName = UnitName('player') or ''

	CompilePatterns()

	-- Store compile function on module for options to call
	module.CompileHighlightPatterns = CompilePatterns

	if not module.DB.highlights.enabled and not module.DB.highlights.mentionsEnabled then
		return
	end

	-- Register filter on all chat message types
	local chatEvents = {
		'CHAT_MSG_SAY',
		'CHAT_MSG_YELL',
		'CHAT_MSG_GUILD',
		'CHAT_MSG_OFFICER',
		'CHAT_MSG_PARTY',
		'CHAT_MSG_PARTY_LEADER',
		'CHAT_MSG_RAID',
		'CHAT_MSG_RAID_LEADER',
		'CHAT_MSG_INSTANCE_CHAT',
		'CHAT_MSG_INSTANCE_CHAT_LEADER',
		'CHAT_MSG_WHISPER',
		'CHAT_MSG_BN_WHISPER',
		'CHAT_MSG_CHANNEL',
		'CHAT_MSG_COMMUNITIES_CHANNEL',
	}

	for _, event in ipairs(chatEvents) do
		ChatFrame_AddMessageEventFilter(event, HighlightMessage)
	end
end
