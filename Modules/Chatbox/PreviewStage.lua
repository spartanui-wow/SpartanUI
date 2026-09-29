---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')
local Style = SUI.UI.Style

-- Chat preview for the options window: a few sample lines built with the same prefix code the
-- chat uses, so the time stamp, channel label, name color and layout match your settings.

local Stage = SUI.OptionsWindow and SUI.OptionsWindow.Stage
if not Stage then
	return
end

local SAMPLES = {
	{ event = 'CHAT_MSG_GUILD', chatType = 'GUILD', name = 'Brokmar', class = 'WARRIOR', text = 'Anyone up for a key tonight?' },
	{ event = 'CHAT_MSG_CHANNEL', chatType = 'CHANNEL', name = 'Sylvaera', class = 'PRIEST', text = 'Selling crafted gear, send me a message', channelIndex = 2, channelBaseName = 'Trade - City' },
	{ event = 'CHAT_MSG_WHISPER', chatType = 'WHISPER', name = 'Iskarielle', class = 'MAGE', text = 'Thanks for the invite!' },
	{ event = 'CHAT_MSG_PARTY', chatType = 'PARTY', name = 'Thornhelm', class = 'PALADIN', text = 'Pulling in three' },
}
local LINE_GAP = 3
local preview ---@type Frame|nil

local function IsEnabled()
	return module.buildPrefix and module.CurrentSettings and SUI:IsModuleEnabled('Chatbox')
end

---@param sample table
---@return string
local function BuildLine(sample)
	local data = {
		event = sample.event,
		senderName = sample.name,
		senderClass = sample.class,
		timestamp = time(),
		channelIndex = sample.channelIndex,
		channelBaseName = sample.channelBaseName,
		lineID = 0,
	}
	local prefix, playerLink, placeholder = module.buildPrefix(data)
	local head = module.wrapPrefix and module.wrapPrefix(prefix, 0, playerLink, placeholder) or ''
	local info = ChatTypeInfo and ChatTypeInfo[sample.chatType]
	local r, g, b = 1, 1, 1
	if info then
		r, g, b = info.r or 1, info.g or 1, info.b or 1
	end
	return head .. ('|cff%02x%02x%02x'):format(r * 255, g * 255, b * 255) .. sample.text .. '|r'
end

local function GetFont()
	local chatFrame = _G.ChatFrame1
	if chatFrame and chatFrame.GetFont then
		local face, size, flags = chatFrame:GetFont()
		if face then
			return face, size or 13, flags or ''
		end
	end
	return Style:GetFontFace(), module.CurrentSettings.fontSize or 13, ''
end

local function CreatePreview(canvas)
	local frame = CreateFrame('Frame', nil, canvas)
	Style:CreateFill(frame, { 0, 0, 0, 0.35 })
	frame.lines = {}
	for i = 1, #SAMPLES do
		local line = frame:CreateFontString(nil, 'OVERLAY')
		line:SetJustifyH('LEFT')
		line:SetWordWrap(true)
		frame.lines[i] = line
	end
	return frame
end

---@type SUI.OptionsWindow.StageProvider
local provider = { path = { 'Modules', 'Chatbox' } }

function provider:GetHeight()
	if not IsEnabled() then
		return 0
	end
	local _, size = GetFont()
	return #SAMPLES * (size + LINE_GAP) + 26
end

function provider:Render(ctx)
	if not IsEnabled() then
		self:Hide()
		return
	end
	local canvas = ctx.canvas
	preview = preview or CreatePreview(canvas)
	preview:SetParent(canvas)
	preview:SetFrameStrata(canvas:GetFrameStrata())
	preview:SetFrameLevel(canvas:GetFrameLevel() + 5)
	preview:ClearAllPoints()
	preview:SetPoint('TOPLEFT', canvas, 'TOPLEFT', 12, -8)
	preview:SetPoint('BOTTOMRIGHT', canvas, 'BOTTOMRIGHT', -12, 8)

	local face, size, flags = GetFont()
	local previous
	for i, sample in ipairs(SAMPLES) do
		local line = preview.lines[i]
		line:SetFont(face, size, flags)
		line:SetShadowColor(0, 0, 0, 1)
		line:SetShadowOffset(1, -1)
		line:SetText(BuildLine(sample))
		line:ClearAllPoints()
		if previous then
			line:SetPoint('TOPLEFT', previous, 'BOTTOMLEFT', 0, -LINE_GAP)
		else
			line:SetPoint('TOPLEFT', preview, 'TOPLEFT', 6, -4)
		end
		line:SetPoint('RIGHT', preview, 'RIGHT', -6, 0)
		previous = line
	end
	preview:Show()

	ctx.Region(preview, { path = { 'Modules', 'Chatbox', 'general' }, option = 'messageFormatPreset', label = L['Message format'] })
end

function provider:Hide()
	if preview then
		preview:Hide()
	end
end

Stage:Register(provider)
