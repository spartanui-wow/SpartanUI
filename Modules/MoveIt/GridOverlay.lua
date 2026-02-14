---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt

---@class SUI.MoveIt.GridOverlay
---@field container Frame|nil Container frame for grid lines
---@field lines table Array of line textures
---@field isShown boolean Whether the grid is currently visible
local GridOverlay = {}
MoveIt.GridOverlay = GridOverlay

-- Visual configuration
local LINE_COLOR = { 1, 1, 1, 0.08 } -- Subtle white grid lines
local CENTER_LINE_COLOR = { 1, 0.82, 0, 0.15 } -- Slightly brighter gold for center crosshair
local LINE_THICKNESS = 1

-- State
GridOverlay.container = nil
GridOverlay.lines = {}
GridOverlay.isShown = false

---Create the grid overlay container frame
function GridOverlay:Initialize()
	if self.container then
		return
	end

	-- CreateLine API required (Retail only)
	if not UIParent.CreateLine then
		if MoveIt.logger then
			MoveIt.logger.debug('GridOverlay: CreateLine API not available')
		end
		return
	end

	self.container = CreateFrame('Frame', 'SUI_MoveIt_GridOverlay', UIParent)
	self.container:SetAllPoints()
	self.container:SetFrameStrata('BACKGROUND')
	self.container:SetFrameLevel(0)
	self.container:Hide()

	-- Redraw grid on resolution/scale changes
	self.container:SetScript('OnSizeChanged', function()
		if self.isShown then
			self:DrawGrid()
		end
	end)

	if MoveIt.logger then
		MoveIt.logger.info('Grid overlay initialized')
	end
end

---Draw the grid lines based on current spacing
function GridOverlay:DrawGrid()
	if not self.container then
		return
	end

	-- Hide existing lines
	for _, line in ipairs(self.lines) do
		line:Hide()
	end

	local spacing = MoveIt.DB and MoveIt.DB.GridSpacing or 32
	local screenWidth = UIParent:GetWidth()
	local screenHeight = UIParent:GetHeight()
	local centerX, centerY = UIParent:GetCenter()

	local halfNumVertical = math.floor((screenWidth / spacing) / 2)
	local halfNumHorizontal = math.floor((screenHeight / spacing) / 2)

	local lineIndex = 0

	-- Draw vertical lines (from center outward)
	for i = -halfNumVertical, halfNumVertical do
		lineIndex = lineIndex + 1
		local xPos = centerX + (i * spacing)

		-- Reuse existing line or create new one
		local line = self.lines[lineIndex]
		if not line then
			line = self.container:CreateLine(nil, 'BACKGROUND')
			line:SetThickness(LINE_THICKNESS)
			self.lines[lineIndex] = line
		end

		if i == 0 then
			line:SetColorTexture(unpack(CENTER_LINE_COLOR))
		else
			line:SetColorTexture(unpack(LINE_COLOR))
		end

		line:ClearAllPoints()
		line:SetStartPoint('BOTTOMLEFT', UIParent, xPos, 0)
		line:SetEndPoint('TOPLEFT', UIParent, xPos, 0)
		line:Show()
	end

	-- Draw horizontal lines (from center outward)
	for i = -halfNumHorizontal, halfNumHorizontal do
		lineIndex = lineIndex + 1
		local yPos = centerY + (i * spacing)

		local line = self.lines[lineIndex]
		if not line then
			line = self.container:CreateLine(nil, 'BACKGROUND')
			line:SetThickness(LINE_THICKNESS)
			self.lines[lineIndex] = line
		end

		if i == 0 then
			line:SetColorTexture(unpack(CENTER_LINE_COLOR))
		else
			line:SetColorTexture(unpack(LINE_COLOR))
		end

		line:ClearAllPoints()
		line:SetStartPoint('BOTTOMLEFT', UIParent, 0, yPos)
		line:SetEndPoint('BOTTOMRIGHT', UIParent, 0, yPos)
		line:Show()
	end

	-- Hide any extra lines from previous draw (e.g. spacing changed to larger value)
	for i = lineIndex + 1, #self.lines do
		self.lines[i]:Hide()
	end

	if MoveIt.logger then
		MoveIt.logger.debug(('GridOverlay: Drew %d lines (spacing=%d)'):format(lineIndex, spacing))
	end
end

---Show the grid overlay
function GridOverlay:Show()
	if not self.container then
		self:Initialize()
	end
	if not self.container then
		return
	end

	self:DrawGrid()
	self.container:Show()
	self.isShown = true
end

---Hide the grid overlay
function GridOverlay:Hide()
	if self.container then
		self.container:Hide()
	end
	self.isShown = false
end

---Refresh the grid (e.g., when spacing changes while visible)
function GridOverlay:Refresh()
	if self.isShown then
		self:DrawGrid()
	end
end
