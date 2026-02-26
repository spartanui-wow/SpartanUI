---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local searchBars = {}
local DEBOUNCE_DELAY = 0.3

local chatBG = {
	bgFile = [[Interface\Buttons\WHITE8X8]],
	edgeFile = [[Interface\Buttons\WHITE8X8]],
	tile = true,
	tileSize = 16,
	edgeSize = 1,
}

----------------------------------------------------------------------------------------------------
-- Search Logic
----------------------------------------------------------------------------------------------------

local function FindMatches(chatFrame, query)
	local matches = {}
	if not query or query == '' then
		return matches
	end

	local lowerQuery = query:lower()
	local numMessages = chatFrame:GetNumMessages()

	for i = 1, numMessages do
		local line = chatFrame:GetMessageInfo(i)
		if line and not SUI.BlizzAPI.issecretvalue(line) then
			-- Strip color codes for matching purposes
			local stripped = line:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|H[^|]*|h', ''):gsub('|h', ''):gsub('|T[^|]*|t', '')
			if stripped:lower():find(lowerQuery, 1, true) then
				table.insert(matches, i)
			end
		end
	end

	return matches
end

local function ScrollToMatch(chatFrame, messageIndex)
	local numMessages = chatFrame:GetNumMessages()
	if messageIndex < 1 or messageIndex > numMessages then
		return
	end

	-- SetScrollOffset counts from the bottom (0 = newest)
	local offset = numMessages - messageIndex
	chatFrame:SetScrollOffset(offset)
end

----------------------------------------------------------------------------------------------------
-- Search Bar UI
----------------------------------------------------------------------------------------------------

local function CreateSearchBar(chatFrame, index)
	local barName = 'SUI_ChatSearchBar' .. index
	if _G[barName] then
		return _G[barName]
	end

	local bar = CreateFrame('Frame', barName, chatFrame, BackdropTemplateMixin and 'BackdropTemplate' or nil)
	bar:SetHeight(26)
	bar:SetPoint('BOTTOMLEFT', chatFrame, 'TOPLEFT', 0, 2)
	bar:SetPoint('BOTTOMRIGHT', chatFrame, 'TOPRIGHT', 0, 2)
	bar:SetFrameStrata(chatFrame:GetFrameStrata())
	bar:SetFrameLevel(chatFrame:GetFrameLevel() + 20)

	if bar.SetBackdrop then
		bar:SetBackdrop(chatBG)
		bar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
		bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
	end

	bar:Hide()

	-- Search icon label
	bar.icon = bar:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	bar.icon:SetPoint('LEFT', bar, 'LEFT', 6, 0)
	bar.icon:SetText('Search:')
	bar.icon:SetTextColor(0.6, 0.6, 0.6, 1)

	-- Input field
	bar.input = CreateFrame('EditBox', barName .. 'Input', bar)
	bar.input:SetPoint('LEFT', bar.icon, 'RIGHT', 4, 0)
	bar.input:SetPoint('RIGHT', bar, 'RIGHT', -120, 0)
	bar.input:SetHeight(20)
	bar.input:SetAutoFocus(false)
	bar.input:SetFontObject('ChatFontNormal')
	bar.input:SetTextInsets(2, 2, 0, 0)

	-- Match counter
	bar.counter = bar:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	bar.counter:SetPoint('RIGHT', bar, 'RIGHT', -50, 0)
	bar.counter:SetTextColor(0.7, 0.7, 0.7, 1)
	bar.counter:SetText('')

	-- Navigation buttons
	bar.prevBtn = CreateFrame('Button', nil, bar)
	bar.prevBtn:SetSize(16, 16)
	bar.prevBtn:SetPoint('RIGHT', bar, 'RIGHT', -30, 0)
	bar.prevBtn:SetNormalFontObject('GameFontNormalSmall')
	bar.prevBtn:SetText('<')
	bar.prevBtn:GetFontString():SetTextColor(0.8, 0.8, 0.8, 1)

	bar.nextBtn = CreateFrame('Button', nil, bar)
	bar.nextBtn:SetSize(16, 16)
	bar.nextBtn:SetPoint('RIGHT', bar, 'RIGHT', -16, 0)
	bar.nextBtn:SetNormalFontObject('GameFontNormalSmall')
	bar.nextBtn:SetText('>')
	bar.nextBtn:GetFontString():SetTextColor(0.8, 0.8, 0.8, 1)

	-- Close button
	bar.closeBtn = CreateFrame('Button', nil, bar)
	bar.closeBtn:SetSize(16, 16)
	bar.closeBtn:SetPoint('RIGHT', bar, 'RIGHT', -2, 0)
	bar.closeBtn:SetNormalFontObject('GameFontNormalSmall')
	bar.closeBtn:SetText('x')
	bar.closeBtn:GetFontString():SetTextColor(1, 0.3, 0.3, 1)

	-- State
	bar.matches = {}
	bar.currentMatch = 0
	bar.chatFrame = chatFrame
	bar.debounceTimer = nil

	-- Update match display
	local function UpdateCounter()
		if #bar.matches == 0 then
			if bar.input:GetText() ~= '' then
				bar.counter:SetText('0 matches')
				bar.counter:SetTextColor(1, 0.4, 0.4, 1)
			else
				bar.counter:SetText('')
			end
		else
			bar.counter:SetFormattedText('%d of %d', bar.currentMatch, #bar.matches)
			bar.counter:SetTextColor(0.7, 0.7, 0.7, 1)
		end
	end

	local function DoSearch()
		local query = bar.input:GetText()
		bar.matches = FindMatches(chatFrame, query)
		if #bar.matches > 0 then
			bar.currentMatch = #bar.matches
			ScrollToMatch(chatFrame, bar.matches[bar.currentMatch])
		else
			bar.currentMatch = 0
		end
		UpdateCounter()
	end

	local function NavigateMatch(direction)
		if #bar.matches == 0 then
			return
		end
		bar.currentMatch = bar.currentMatch + direction
		if bar.currentMatch < 1 then
			bar.currentMatch = #bar.matches
		elseif bar.currentMatch > #bar.matches then
			bar.currentMatch = 1
		end
		ScrollToMatch(chatFrame, bar.matches[bar.currentMatch])
		UpdateCounter()
	end

	-- Debounced search on text change
	bar.input:SetScript('OnTextChanged', function(self)
		if bar.debounceTimer then
			bar.debounceTimer:Cancel()
		end
		bar.debounceTimer = C_Timer.NewTimer(DEBOUNCE_DELAY, DoSearch)
	end)

	bar.input:SetScript('OnEnterPressed', function(self)
		if IsShiftKeyDown() then
			NavigateMatch(-1)
		else
			NavigateMatch(1)
		end
	end)

	bar.input:SetScript('OnEscapePressed', function()
		bar:Hide()
	end)

	bar.prevBtn:SetScript('OnClick', function()
		NavigateMatch(-1)
	end)

	bar.nextBtn:SetScript('OnClick', function()
		NavigateMatch(1)
	end)

	bar.closeBtn:SetScript('OnClick', function()
		bar:Hide()
	end)

	bar:SetScript('OnHide', function(self)
		self.input:SetText('')
		self.matches = {}
		self.currentMatch = 0
		self.counter:SetText('')
		if self.debounceTimer then
			self.debounceTimer:Cancel()
			self.debounceTimer = nil
		end
		-- Scroll back to bottom
		chatFrame:ScrollToBottom()
	end)

	bar:SetScript('OnShow', function(self)
		self.input:SetFocus()
	end)

	return bar
end

----------------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------------

function module:ToggleChatSearch(chatFrameIndex)
	local index = chatFrameIndex or 1
	local chatFrame = _G['ChatFrame' .. index]
	if not chatFrame then
		return
	end

	local bar = searchBars[index]
	if not bar then
		bar = CreateSearchBar(chatFrame, index)
		searchBars[index] = bar
	end

	if bar:IsShown() then
		bar:Hide()
	else
		bar:Show()
	end
end

----------------------------------------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------------------------------------

function module:SetupSearch()
	if SUI:IsModuleDisabled(module) then
		return
	end
	if not module.DB.search.enabled then
		return
	end

	-- Hook Ctrl+F on chat edit boxes to open search
	for i = 1, 10 do
		local editBox = _G['ChatFrame' .. i .. 'EditBox']
		if editBox then
			editBox:HookScript('OnKeyDown', function(self, key)
				if key == 'F' and IsControlKeyDown() then
					module:ToggleChatSearch(i)
				end
			end)
		end
	end
end
