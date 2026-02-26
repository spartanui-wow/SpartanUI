---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local chatBG = {
	bgFile = [[Interface\Buttons\WHITE8X8]],
	edgeFile = [[Interface\Buttons\WHITE8X8]],
	tile = true,
	tileSize = 16,
	edgeSize = 2,
}

local DEFAULT_BG = { r = 0.05, g = 0.05, b = 0.05, a = 0.7 }
local MAX_CHAT_LENGTH = 255

-- Strip WoW format codes to get visible character count
local function GetVisibleLength(text)
	if not text then
		return 0
	end
	local stripped = text
	stripped = stripped:gsub('|c%x%x%x%x%x%x%x%x', '')
	stripped = stripped:gsub('|r', '')
	stripped = stripped:gsub('|H[^|]*|h', '')
	stripped = stripped:gsub('|h', '')
	stripped = stripped:gsub('|T[^|]*|t', '')
	stripped = stripped:gsub('|K[^|]*|k', '')
	stripped = stripped:gsub('|A[^|]*|a', '')
	stripped = stripped:gsub('|n', '')
	return strlen(stripped)
end

-- Chat type display names for channel label gutter
local chatTypeLabels = {
	SAY = L['Say'],
	YELL = L['Yell'],
	PARTY = L['Party'],
	RAID = L['Raid'],
	GUILD = L['Guild'],
	OFFICER = L['Officer'],
	WHISPER = L['Tell'],
	EMOTE = L['Emote'],
	INSTANCE_CHAT = L['Instance'],
	CHANNEL = L['Channel'],
	BN_WHISPER = L['BNet'],
}

----------------------------------------------------------------------------------------------------
-- Character Counter
----------------------------------------------------------------------------------------------------

local function CreateCharCounter(editBox, index)
	local frameName = 'SUI_ChatCharCounter' .. index
	if _G[frameName] then
		return _G[frameName]
	end

	local counter = editBox:CreateFontString(frameName, 'OVERLAY', 'GameFontNormalSmall')
	counter:SetPoint('RIGHT', editBox, 'RIGHT', -5, 0)
	counter:SetTextColor(0.6, 0.6, 0.6, 0.8)
	counter:SetJustifyH('RIGHT')
	counter:Hide()

	return counter
end

local function UpdateCharCounter(counter, text, isMultiLine)
	if not module.DB.multiLine.showCharCounter then
		counter:Hide()
		return
	end

	local visLen = GetVisibleLength(text)

	if isMultiLine then
		local lines = 1
		for _ in text:gmatch('\n') do
			lines = lines + 1
		end
		counter:SetFormattedText('%d / %d (%d)', visLen, MAX_CHAT_LENGTH, lines)
	else
		counter:SetFormattedText('%d / %d', visLen, MAX_CHAT_LENGTH)
	end

	if visLen > MAX_CHAT_LENGTH then
		counter:SetTextColor(1, 0.3, 0.3, 1)
	elseif visLen > MAX_CHAT_LENGTH * 0.8 then
		counter:SetTextColor(1, 0.8, 0.3, 1)
	else
		counter:SetTextColor(0.6, 0.6, 0.6, 0.8)
	end

	counter:Show()
end

----------------------------------------------------------------------------------------------------
-- Multi-Line Edit Box Wrapper
----------------------------------------------------------------------------------------------------

local multiLineWrappers = {}

local function GetChatTypeLabel(editBox)
	local chatType = editBox:GetAttribute('chatType') or 'SAY'
	local label = chatTypeLabels[chatType]
	if chatType == 'WHISPER' then
		local tell = editBox:GetAttribute('tellTarget') or ''
		if tell ~= '' then
			label = (label or L['Tell']) .. ' ' .. tell
		end
	elseif chatType == 'CHANNEL' then
		local chanTarget = editBox:GetAttribute('channelTarget')
		if chanTarget then
			label = chanTarget
		end
	end
	return (label or chatType) .. ':'
end

local function CreateMultiLineWrapper(editBox, chatFrame, index)
	local wrapperName = 'SUI_MultiLineWrapper' .. index
	if _G[wrapperName] then
		return _G[wrapperName]
	end

	local wrapper = CreateFrame('Frame', wrapperName, UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
	wrapper:SetFrameStrata('DIALOG')
	wrapper:SetClampedToScreen(true)
	wrapper:Hide()

	if wrapper.SetBackdrop then
		wrapper:SetBackdrop(chatBG)
		wrapper:SetBackdropColor(DEFAULT_BG.r, DEFAULT_BG.g, DEFAULT_BG.b, module.DB.multiLine.opacity or 0.9)
		wrapper:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
	end

	-- Channel label
	wrapper.channelLabel = wrapper:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	wrapper.channelLabel:SetPoint('TOPLEFT', wrapper, 'TOPLEFT', 6, -4)
	wrapper.channelLabel:SetTextColor(0.8, 0.8, 0.2, 1)
	wrapper.channelLabel:SetText('Say:')

	-- Multi-line input
	wrapper.input = CreateFrame('EditBox', wrapperName .. 'Input', wrapper)
	wrapper.input:SetMultiLine(true)
	wrapper.input:SetAutoFocus(false)
	wrapper.input:SetFontObject('ChatFontNormal')
	wrapper.input:SetPoint('TOPLEFT', wrapper.channelLabel, 'TOPRIGHT', 4, 2)
	wrapper.input:SetPoint('BOTTOMRIGHT', wrapper, 'BOTTOMRIGHT', -6, 4)
	wrapper.input:SetTextInsets(2, 2, 2, 2)
	wrapper.input:SetMaxLetters(0)

	-- Character counter for multi-line
	wrapper.counter = wrapper:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	wrapper.counter:SetPoint('BOTTOMRIGHT', wrapper, 'BOTTOMRIGHT', -6, -14)
	wrapper.counter:SetTextColor(0.6, 0.6, 0.6, 0.8)

	-- Line break hint button
	wrapper.lineBreakBtn = CreateFrame('Button', nil, wrapper)
	wrapper.lineBreakBtn:SetSize(16, 16)
	wrapper.lineBreakBtn:SetPoint('BOTTOMLEFT', wrapper, 'BOTTOMLEFT', 4, -14)
	wrapper.lineBreakBtn:SetNormalFontObject('GameFontNormalSmall')
	wrapper.lineBreakBtn:SetText('\\n')
	wrapper.lineBreakBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5, 0.8)
	wrapper.lineBreakBtn:SetScript('OnClick', function()
		wrapper.input:Insert('\n')
		wrapper.input:SetFocus()
	end)
	wrapper.lineBreakBtn:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Insert line break (Shift+Enter)', 1, 1, 1)
		GameTooltip:Show()
	end)
	wrapper.lineBreakBtn:SetScript('OnLeave', GameTooltip_Hide)

	-- Dynamic height resize
	wrapper.input:SetScript('OnTextChanged', function(self)
		local maxLines = module.DB.multiLine.maxLines or 5
		local lineHeight = select(2, self:GetFont()) or 14
		local numLines = math.min(self:GetNumLetters() > 0 and math.max(1, select(2, self:GetText():gsub('\n', '\n')) + 1) or 1, maxLines)
		local newHeight = math.max(30, (numLines * (lineHeight + 2)) + 12)
		wrapper:SetHeight(newHeight)

		UpdateCharCounter(wrapper.counter, self:GetText(), true)
	end)

	-- Shift+Enter inserts newline, Enter sends
	wrapper.input:SetScript('OnKeyDown', function(self, key)
		if key == 'ENTER' then
			if IsShiftKeyDown() then
				self:Insert('\n')
			else
				local text = strtrim(self:GetText())
				if text ~= '' then
					-- Split on newlines and send each line through the real edit box
					local lines = { strsplit('\n', text) }
					for _, line in ipairs(lines) do
						line = strtrim(line)
						if line ~= '' then
							editBox:SetText(line)
							ChatEdit_SendText(editBox)
						end
					end
				end
				self:SetText('')
				wrapper:Hide()
				editBox:Hide()
			end
		elseif key == 'ESCAPE' then
			self:SetText('')
			wrapper:Hide()
			editBox:Hide()
		elseif key == 'UP' and IsAltKeyDown() then
			-- Alt+Up for history
			local history = SUI.CharDB.ChatEditHistory
			if history and #history > 0 then
				wrapper.historyIndex = (wrapper.historyIndex or 0) + 1
				if wrapper.historyIndex > #history then
					wrapper.historyIndex = #history
				end
				self:SetText(strtrim(history[#history - (wrapper.historyIndex - 1)]))
			end
		elseif key == 'DOWN' and IsAltKeyDown() then
			local history = SUI.CharDB.ChatEditHistory
			if history and #history > 0 then
				wrapper.historyIndex = (wrapper.historyIndex or 0) - 1
				if wrapper.historyIndex < 1 then
					wrapper.historyIndex = 0
					self:SetText('')
				else
					self:SetText(strtrim(history[#history - (wrapper.historyIndex - 1)]))
				end
			end
		end
	end)
	wrapper.input:SetPropagateKeyboardInput(true)
	wrapper.input:SetScript('OnKeyDown', function(self, key)
		if key == 'ENTER' or key == 'ESCAPE' or (IsAltKeyDown() and (key == 'UP' or key == 'DOWN')) then
			self:SetPropagateKeyboardInput(false)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	-- Wire up the Enter/Escape/History via OnKeyUp to allow propagation control
	wrapper.input:HookScript('OnKeyUp', function(self, key)
		if key == 'ENTER' and not IsShiftKeyDown() then
			local text = strtrim(self:GetText())
			if text ~= '' then
				local lines = { strsplit('\n', text) }
				for _, line in ipairs(lines) do
					line = strtrim(line)
					if line ~= '' then
						editBox:SetText(line)
						ChatEdit_SendText(editBox)
					end
				end
			end
			self:SetText('')
			wrapper:Hide()
			editBox:Hide()
		elseif key == 'ESCAPE' then
			self:SetText('')
			wrapper:Hide()
			editBox:Hide()
		end
	end)

	wrapper.editBox = editBox
	wrapper.chatFrame = chatFrame
	wrapper.historyIndex = 0

	return wrapper
end

local function ShowMultiLineWrapper(editBox, index)
	if not module.DB.multiLine.enabled then
		return false
	end

	local chatFrame = _G['ChatFrame' .. index]
	if not chatFrame then
		return false
	end

	local wrapper = multiLineWrappers[index]
	if not wrapper then
		wrapper = CreateMultiLineWrapper(editBox, chatFrame, index)
		multiLineWrappers[index] = wrapper
	end

	-- Position at the edit box location
	wrapper:ClearAllPoints()
	wrapper:SetPoint('BOTTOMLEFT', editBox, 'BOTTOMLEFT', 0, 0)
	wrapper:SetPoint('BOTTOMRIGHT', editBox, 'BOTTOMRIGHT', 0, 0)
	wrapper:SetHeight(30)

	-- Update channel label
	if module.DB.multiLine.showChannelLabel then
		wrapper.channelLabel:SetText(GetChatTypeLabel(editBox))
		wrapper.channelLabel:Show()
	else
		wrapper.channelLabel:Hide()
	end

	-- Show/hide line break button
	if module.DB.multiLine.showLineBreakButton then
		wrapper.lineBreakBtn:Show()
	else
		wrapper.lineBreakBtn:Hide()
	end

	wrapper.historyIndex = 0
	wrapper:Show()
	wrapper.input:SetFocus()

	return true
end

----------------------------------------------------------------------------------------------------
-- Edit Box Position (Phase 5 supports 4 modes)
----------------------------------------------------------------------------------------------------

function module:EditBoxPosition()
	for i = 1, 10 do
		local ChatFrameName = ('%s%d'):format('ChatFrame', i)
		local ChatFrame = _G[ChatFrameName]
		local ChatFrameEdit = _G[ChatFrameName .. 'EditBox']

		ChatFrameEdit:ClearAllPoints()

		local pos = module.DB.editBoxPosition or 'BELOW'
		-- Legacy toggle support
		if module.DB.EditBoxTop then
			pos = 'ABOVE'
		end

		if pos == 'ABOVE' then
			local GDM = _G['GeneralDockManager']
			ChatFrameEdit:SetPoint('BOTTOMLEFT', GDM, 'TOPLEFT', 0, 1)
			ChatFrameEdit:SetPoint('BOTTOMRIGHT', GDM, 'TOPRIGHT', 0, 1)
		elseif pos == 'ABOVE_INSIDE' then
			ChatFrameEdit:SetPoint('BOTTOMLEFT', ChatFrame.Background, 'TOPLEFT', -1, -22)
			ChatFrameEdit:SetPoint('BOTTOMRIGHT', ChatFrame.Background, 'TOPRIGHT', 1, -22)
		elseif pos == 'BELOW_INSIDE' then
			ChatFrameEdit:SetPoint('BOTTOMLEFT', ChatFrame.Background, 'BOTTOMLEFT', -1, 0)
			ChatFrameEdit:SetPoint('BOTTOMRIGHT', ChatFrame.Background, 'BOTTOMRIGHT', 1, 0)
		else -- BELOW (default)
			ChatFrameEdit:SetPoint('TOPLEFT', ChatFrame.Background, 'BOTTOMLEFT', -1, -1)
			ChatFrameEdit:SetPoint('TOPRIGHT', ChatFrame.Background, 'BOTTOMRIGHT', 1, -1)
		end
	end
end

---@param key string
function module:ChatEdit_OnKeyDown(key)
	local history = SUI.CharDB.ChatEditHistory
	if (not history) or #history == 0 then
		return
	end

	if key == 'DOWN' then
		self.historyIndex = self.historyIndex - 1
		if self.historyIndex < 1 then
			self.historyIndex = 0
			self:SetText('')
			return
		end
	elseif key == 'UP' then
		self.historyIndex = self.historyIndex + 1
		if self.historyIndex > #history then
			self.historyIndex = #history
		end
	else
		return
	end

	self:SetText(strtrim(history[#history - (self.historyIndex - 1)]))
end

---@param line string
function module:ChatEdit_AddHistory(_, line)
	line = line and strtrim(line)

	if line and strlen(line) > 0 then
		local cmd = strmatch(line, '^/%w+')
		if cmd and IsSecureCmd(cmd) then
			return
		end

		for index, text in pairs(SUI.CharDB.ChatEditHistory) do
			if text == line then
				tremove(SUI.CharDB.ChatEditHistory, index)
				break
			end
		end

		tinsert(SUI.CharDB.ChatEditHistory, line)

		local maxHistory = module.DB.multiLine.historySize or 250
		while #SUI.CharDB.ChatEditHistory > maxHistory do
			tremove(SUI.CharDB.ChatEditHistory, 1)
		end
	end
end

function module:SetupEditBox()
	if SUI:IsModuleDisabled(module) then
		return
	end

	for i = 1, 10 do
		local ChatFrameName = ('%s%d'):format('ChatFrame', i)
		local ChatFrame = _G[ChatFrameName]
		local ChatFrameEdit = _G[ChatFrameName .. 'EditBox']

		-- Arrow key editing
		ChatFrameEdit:SetAltArrowKeyMode(false)
		ChatFrameEdit.historyIndex = 0

		ChatFrameEdit:HookScript('OnKeyDown', module.ChatEdit_OnKeyDown)
		module:SecureHook(ChatFrameEdit, 'AddHistoryLine', 'ChatEdit_AddHistory')

		-- Character counter (always available)
		local charCounter = CreateCharCounter(ChatFrameEdit, i)

		-- Update counter when text changes
		ChatFrameEdit:HookScript('OnTextChanged', function(self)
			UpdateCharCounter(charCounter, self:GetText(), false)
		end)

		-- Show counter when edit box is shown
		ChatFrameEdit:HookScript('OnShow', function(self)
			if module.DB.multiLine.showCharCounter then
				charCounter:Show()
			end
			-- Intercept for multi-line mode
			if module.DB.multiLine.enabled then
				ShowMultiLineWrapper(self, i)
			end
		end)

		ChatFrameEdit:HookScript('OnHide', function()
			charCounter:Hide()
			if multiLineWrappers[i] then
				multiLineWrappers[i]:Hide()
			end
		end)

		-- Edit box visual styling
		local EBLeft = _G[ChatFrameName .. 'EditBoxLeft']
		local EBMid = _G[ChatFrameName .. 'EditBoxMid']
		local EBRight = _G[ChatFrameName .. 'EditBoxRight']
		EBLeft:Hide()
		EBRight:Hide()
		EBMid:Hide()

		local header = _G[ChatFrameName .. 'EditBoxHeader']
		local _, s, m = header:GetFont()
		SUI.Font:Format(header, s, 'Chatbox')
		SUI.Font:Format(ChatFrameEdit, module.DB.fontSize, 'Chatbox')

		if _G[ChatFrameName .. 'EditBoxFocusLeft'] ~= nil then
			_G[ChatFrameName .. 'EditBoxFocusLeft']:SetTexture(nil)
		end
		if _G[ChatFrameName .. 'EditBoxFocusRight'] ~= nil then
			_G[ChatFrameName .. 'EditBoxFocusRight']:SetTexture(nil)
		end
		if _G[ChatFrameName .. 'EditBoxFocusMid'] ~= nil then
			_G[ChatFrameName .. 'EditBoxFocusMid']:SetTexture(nil)
		end

		ChatFrameEdit:Hide()
		ChatFrameEdit:SetHeight(22)

		if not ChatFrameEdit.SetBackdrop then
			Mixin(ChatFrameEdit, BackdropTemplateMixin)
		end
		if ChatFrameEdit.SetBackdrop then
			ChatFrameEdit:SetBackdrop(chatBG)
			local bg = { ChatFrame.Background:GetVertexColor() }
			ChatFrameEdit:SetBackdropColor(unpack(bg))
			ChatFrameEdit:SetBackdropBorderColor(unpack(bg))
		end

		local function BackdropColorUpdate(frame, r, g, b)
			local bg = { ChatFrame.Background:GetVertexColor() }
			if ChatFrameEdit.SetBackdrop then
				ChatFrameEdit:SetBackdropColor(unpack(bg))
				ChatFrameEdit:SetBackdropBorderColor(unpack(bg))
			end
		end
		hooksecurefunc(ChatFrame.Background, 'SetVertexColor', BackdropColorUpdate)

		-- Edit box focus textures (retail only)
		local EBFocusLeft = _G[ChatFrameName .. 'EditBoxFocusLeft']
		local EBFocusMid = _G[ChatFrameName .. 'EditBoxFocusMid']
		local EBFocusRight = _G[ChatFrameName .. 'EditBoxFocusRight']
		if EBFocusLeft and EBFocusMid and EBFocusRight then
			EBFocusLeft:SetVertexColor(DEFAULT_BG.r, DEFAULT_BG.g, DEFAULT_BG.b, DEFAULT_BG.a)
			EBFocusMid:SetVertexColor(DEFAULT_BG.r, DEFAULT_BG.g, DEFAULT_BG.b, DEFAULT_BG.a)
			EBFocusRight:SetVertexColor(DEFAULT_BG.r, DEFAULT_BG.g, DEFAULT_BG.b, DEFAULT_BG.a)

			local EditBoxFocusHide = function(frame)
				ChatFrameEdit:Hide()
			end
			hooksecurefunc(EBFocusMid, 'Hide', EditBoxFocusHide)
		end
	end

	module:EditBoxPosition()
end
