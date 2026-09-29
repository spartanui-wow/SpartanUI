---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- Screen dim and alignment grid shown behind the movers while moving frames. Lines are plain
-- textures one physical pixel wide, drawn outward from the screen center so the center lines
-- always exist.

---@class SUI.MoveIt.GridOverlay
local GridOverlay = {}
MoveIt.GridOverlay = GridOverlay

local DIM_ALPHA = 0.25
local PICK_DIM_ALPHA = 0.5
local LINE_ALPHA = { dim = 0.10, bright = 0.24 }
local CENTER_ALPHA = { dim = 0.35, bright = 0.6 }

GridOverlay.lines = {}
GridOverlay.isShown = false

local function GetMode()
	local mode = MoveIt.DB and MoveIt.DB.GridMode
	if mode ~= 'off' and mode ~= 'bright' then
		mode = 'dim'
	end
	return mode
end

function GridOverlay:Initialize()
	if self.container then
		return
	end
	local container = _G['SUI_MoveIt_Backdrop'] or CreateFrame('Frame', 'SUI_MoveIt_Backdrop', UIParent)
	container:SetAllPoints(UIParent)
	container:SetFrameStrata('HIGH')
	container:SetFrameLevel(1)
	container:EnableMouse(false)
	container:Hide()

	local dim = container:CreateTexture(nil, 'BACKGROUND')
	dim:SetTexture(Style.WHITE)
	dim:SetAllPoints()
	dim:SetVertexColor(Style.color.dim[1], Style.color.dim[2], Style.color.dim[3], 1)
	dim:SetAlpha(0)
	container.dim = dim

	container:SetScript('OnSizeChanged', function()
		if GridOverlay.isShown then
			GridOverlay:DrawGrid()
		end
	end)
	self.container = container

	Style:OnAccentChanged(self, function()
		if GridOverlay.isShown then
			GridOverlay:DrawGrid()
		end
	end)
end

---@param index number
---@return Texture
function GridOverlay:GetLine(index)
	local line = self.lines[index]
	if not line then
		line = self.container:CreateTexture(nil, 'ARTWORK')
		line:SetTexture(Style.WHITE)
		self.lines[index] = line
	end
	return line
end

function GridOverlay:DrawGrid()
	if not self.container then
		return
	end
	local mode = GetMode()
	local used = 0
	if mode ~= 'off' then
		local spacing = (MoveIt.DB and MoveIt.DB.GridSpacing) or 32
		local width, height = UIParent:GetSize()
		local px = Style:PixelSize(self.container)
		local r, g, b = Style:GetAccent()
		local halfW, halfH = width / 2, height / 2

		local function Vertical(x, alpha)
			used = used + 1
			local line = self:GetLine(used)
			line:ClearAllPoints()
			line:SetPoint('TOP', self.container, 'TOPLEFT', x, 0)
			line:SetPoint('BOTTOM', self.container, 'BOTTOMLEFT', x, 0)
			line:SetWidth(px)
			line:SetVertexColor(r, g, b, alpha)
			line:Show()
		end
		local function Horizontal(y, alpha)
			used = used + 1
			local line = self:GetLine(used)
			line:ClearAllPoints()
			line:SetPoint('LEFT', self.container, 'BOTTOMLEFT', 0, y)
			line:SetPoint('RIGHT', self.container, 'BOTTOMRIGHT', 0, y)
			line:SetHeight(px)
			line:SetVertexColor(r, g, b, alpha)
			line:Show()
		end

		for i = 1, math.floor(halfW / spacing) do
			Vertical(halfW + i * spacing, LINE_ALPHA[mode])
			Vertical(halfW - i * spacing, LINE_ALPHA[mode])
		end
		for i = 1, math.floor(halfH / spacing) do
			Horizontal(halfH + i * spacing, LINE_ALPHA[mode])
			Horizontal(halfH - i * spacing, LINE_ALPHA[mode])
		end
		Vertical(halfW, CENTER_ALPHA[mode])
		Horizontal(halfH, CENTER_ALPHA[mode])
	end
	for i = used + 1, #self.lines do
		self.lines[i]:Hide()
	end
end

function GridOverlay:Show()
	self:Initialize()
	self:DrawGrid()
	self.container:Show()
	self.isShown = true
	self:SetPickDim(false)
end

function GridOverlay:Hide()
	if self.container then
		Style:Stop(self.container.dim)
		self.container.dim:SetAlpha(0)
		self.container:Hide()
	end
	self.isShown = false
end

function GridOverlay:Refresh()
	if self.isShown then
		self:DrawGrid()
	end
end

---Deepen the dim while the player is choosing a frame to attach to
---@param picking boolean
function GridOverlay:SetPickDim(picking)
	if not self.container then
		return
	end
	local dim = self.container.dim
	Style:Tween(dim, picking and 0.2 or 0.6, dim:GetAlpha(), picking and PICK_DIM_ALPHA or DIM_ALPHA, function(value)
		dim:SetAlpha(value)
	end)
end

---Cycle off -> dim -> bright
function GridOverlay:CycleMode()
	local order = { off = 'dim', dim = 'bright', bright = 'off' }
	MoveIt.DB.GridMode = order[GetMode()]
	self:Refresh()
	return MoveIt.DB.GridMode
end

---@return 'off'|'dim'|'bright'
function GridOverlay:GetMode()
	return GetMode()
end
