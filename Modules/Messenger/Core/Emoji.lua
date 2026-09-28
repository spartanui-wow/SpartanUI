local _, ns = ...
local M = ns.Messenger

-- Emoji: typed codes such as :) or :fire: show as pictures. Messages are stored and sent as the
-- plain codes, so other players see whatever their own chat shows. The images come from the
-- host (M.host.emojiPath); without them the codes simply stay as text.

---@class Messenger.Emoji
local E = {}
M.Emoji = E

-- Picker order. Every code here also renders in messages.
E.list = {
	{ code = ':)', file = 'SlightSmile', aliases = { ':-)', ':slight_smile:' } },
	{ code = ':D', file = 'Grin', aliases = { ':-D', ';D', ';-D', '=D', ':grin:' } },
	{ code = ':smile:', file = 'Smile', aliases = { ':murloc:' } },
	{ code = 'XD', file = 'Joy', aliases = { 'xD', ':joy:' } },
	{ code = ';)', file = 'Wink', aliases = { ';-)', ':wink:' } },
	{ code = ':blush:', file = 'Blush' },
	{ code = ':heart_eyes:', file = 'HeartEyes' },
	{ code = ':smirk:', file = 'Smirk' },
	{ code = '8)', file = 'Sunglasses', aliases = { '8-)', ':sunglasses:' } },
	{ code = ':thinking:', file = 'Thinking' },
	{ code = ':(', file = 'SlightFrown', aliases = { ':-(', ':S', ':-S', ':slight_frown:' } },
	{ code = ':o', file = 'OpenMouth', aliases = { ':-o', ':O', ':-O', ':-0', ':open_mouth:' } },
	{ code = ':P', file = 'StuckOutTongue', aliases = { ':-P', ':p', ':-p', '=P', '=p', ':stuck_out_tongue:' } },
	{ code = ';P', file = 'StuckOutTongueClosedEyes', aliases = { ';p', ';-p', ';-P', 'XP', ':stuck_out_tongue_closed_eyes:' } },
	{ code = ":'(", file = 'Cry', aliases = { ":'-(", ':,(', ':,-(', ':cry:' } },
	{ code = ':sob:', file = 'Sob' },
	{ code = ':@', file = 'Angry', aliases = { ':-@', '>:(', ':angry:' } },
	{ code = 'D:<', file = 'Rage', aliases = { ':rage:' } },
	{ code = ':scream:', file = 'Scream' },
	{ code = ':facepalm:', file = 'Facepalm' },
	{ code = ':kappa:', file = 'Kappa' },
	{ code = ':poop:', file = 'Poop' },
	{ code = ':skull:', file = 'Skull' },
	{ code = ':zzz:', file = 'ZZZ' },
	{ code = '<3', file = 'Heart', aliases = { ':heart:' } },
	{ code = '</3', file = 'BrokenHeart', aliases = { ':broken_heart:' } },
	{ code = ':fire:', file = 'Fire' },
	{ code = ':party:', file = 'PartyPopper' },
	{ code = ':+1:', file = 'ThumbsUp', aliases = { ':thumbs_up:' } },
	{ code = ':thumbs_down:', file = 'ThumbsDown' },
	{ code = ':ok_hand:', file = 'OkHand' },
	{ code = ':clap:', file = 'Clap' },
	{ code = ':wave:', file = 'Wave' },
	{ code = ':pray:', file = 'Pray' },
	{ code = ':call_me:', file = 'CallMe' },
	{ code = ':middle_finger:', file = 'MiddleFinger' },
	{ code = ':meaw:', file = 'Meaw' },
	{ code = ':scream_cat:', file = 'ScreamCat' },
	{ code = ':sadkitty:', file = 'SadKitty' },
	{ code = ':semi_colon:', file = 'SemiColon' },
}

local byCode

local function Build()
	byCode = {}
	for _, entry in ipairs(E.list) do
		byCode[entry.code] = entry.file
		for _, alias in ipairs(entry.aliases or {}) do
			byCode[alias] = entry.file
		end
	end
end

---@return boolean
function E:IsAvailable()
	return M.host ~= nil and M.host.emojiPath ~= nil and M.settings ~= nil and M.settings.emoji ~= false
end

---Texture path for an emoji image. The images are PNG, which the game only finds with the
---extension spelled out (it guesses .blp and .tga only).
---@param file string
---@return string
function E:Path(file)
	return M.host.emojiPath .. file .. '.png'
end

---@param file string
---@return string
local function Markup(file)
	return '|T' .. E:Path(file) .. ':0|t'
end

---Swaps whole-word codes for pictures in a run of text with no links in it.
---@param text string
---@return string
local function RenderPlain(text)
	return (
		text:gsub('(%S+)', function(word)
			local file = byCode[word]
			if not file then
				-- Allow trailing punctuation after shortcodes, as in "nice :fire:!"
				local core, tail = word:match('^(:[%w_+]+:)([%p]*)$')
				file = core and byCode[core]
				if file then
					return Markup(file) .. tail
				end
				return nil
			end
			return Markup(file)
		end)
	)
end

---Replaces emoji codes with pictures, leaving links untouched.
---@param text string
---@return string
function E:Render(text)
	if not self:IsAvailable() or text:find('^/') then
		return text
	end
	if not byCode then
		Build()
	end
	local out = {}
	local pos = 1
	local len = #text
	while pos <= len do
		local linkStart = text:find('|H', pos, true)
		if not linkStart then
			out[#out + 1] = RenderPlain(text:sub(pos))
			break
		end
		-- Keep a color code that opens the link attached to it
		local segmentEnd = linkStart - 1
		if linkStart > 10 and text:sub(linkStart - 10, linkStart - 9) == '|c' then
			segmentEnd = linkStart - 11
		end
		if segmentEnd >= pos then
			out[#out + 1] = RenderPlain(text:sub(pos, segmentEnd))
		end
		local _, linkEnd = text:find('|h.-|h', linkStart + 2)
		if not linkEnd then
			out[#out + 1] = text:sub(segmentEnd + 1)
			break
		end
		out[#out + 1] = text:sub(segmentEnd + 1, linkEnd)
		pos = linkEnd + 1
	end
	return table.concat(out)
end
