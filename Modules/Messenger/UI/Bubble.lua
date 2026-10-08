local _, ns = ...
local M = ns.Messenger
local T = M.Theme

-- A rounded message bubble. Each corner has its own radius, so bubbles in a run from one person
-- keep a tight corner on the sender's side and read as one group. Drawn from a quarter of the
-- circle art per corner plus flat fills, all tinted with one color.
--
-- The pieces are textures on the owner (a message row), not a frame of their own, so the row's
-- text stays on top and keeps its links and mouse handling.

---@class Messenger.Bubble
local B = {}
M.Bubble = B

local CORNERS = {
	-- point, x direction into the bubble, y direction into the bubble, texture coordinates
	{ 'TOPLEFT', 1, -1, 0, 0.5, 0, 0.5 },
	{ 'TOPRIGHT', -1, -1, 0.5, 1, 0, 0.5 },
	{ 'BOTTOMLEFT', 1, 1, 0, 0.5, 0.5, 1 },
	{ 'BOTTOMRIGHT', -1, 1, 0.5, 1, 0.5, 1 },
}

---@class MessengerBubble
---@field box Texture Invisible region the bubble fills; place it with SetPoint
local Bubble = {}
Bubble.__index = Bubble

---@param owner Frame
---@return MessengerBubble
function B.Create(owner)
	local bubble = setmetatable({ parts = {}, corners = {} }, Bubble)
	local function Part(file)
		local tex = owner:CreateTexture(nil, 'BACKGROUND', nil, 2)
		tex:SetTexture(file or T.WHITE)
		bubble.parts[#bubble.parts + 1] = tex
		return tex
	end
	bubble.box = owner:CreateTexture(nil, 'BACKGROUND')
	bubble.box:SetColorTexture(0, 0, 0, 0)
	bubble.middle = Part()
	bubble.top = Part()
	bubble.bottom = Part()
	for i, spec in ipairs(CORNERS) do
		local arc = Part(M.mediaPath .. 'Circle')
		arc:SetTexCoord(spec[4], spec[5], spec[6], spec[7])
		bubble.corners[i] = { arc = arc, across = Part(), down = Part() }
	end
	bubble:Hide()
	return bubble
end

function Bubble:Hide()
	self.box:Hide()
	for _, tex in ipairs(self.parts) do
		tex:Hide()
	end
	self.shown = false
end

---@param r number
---@param g number
---@param b number
---@param a? number
function Bubble:SetColor(r, g, b, a)
	for _, tex in ipairs(self.parts) do
		tex:SetVertexColor(r, g, b, a or 1)
	end
end

---Sizes the bubble, rounds its corners and shows it. radii holds four radii in the order top
---left, top right, bottom left, bottom right; the largest sets the band the corners sit in.
---@param width number
---@param height number
---@param radii number[]
function Bubble:Layout(width, height, radii)
	width, height = math.floor(width + 0.5), math.floor(height + 0.5)
	local box = self.box
	box:SetSize(width, height)
	box:Show()
	local big = math.max(radii[1], radii[2], radii[3], radii[4])
	big = math.max(1, math.min(big, math.floor(height / 2), math.floor(width / 2)))

	local wide = width > big * 2
	self.top:ClearAllPoints()
	self.top:SetPoint('TOPLEFT', box, 'TOPLEFT', big, 0)
	self.top:SetPoint('TOPRIGHT', box, 'TOPRIGHT', -big, 0)
	self.top:SetHeight(big)
	self.top:SetShown(wide)
	self.bottom:ClearAllPoints()
	self.bottom:SetPoint('BOTTOMLEFT', box, 'BOTTOMLEFT', big, 0)
	self.bottom:SetPoint('BOTTOMRIGHT', box, 'BOTTOMRIGHT', -big, 0)
	self.bottom:SetHeight(big)
	self.bottom:SetShown(wide)

	self.middle:ClearAllPoints()
	self.middle:SetPoint('TOPLEFT', box, 'TOPLEFT', 0, -big)
	self.middle:SetPoint('BOTTOMRIGHT', box, 'BOTTOMRIGHT', 0, big)
	self.middle:SetShown(height > big * 2)

	for i, spec in ipairs(CORNERS) do
		local point, dx, dy = spec[1], spec[2], spec[3]
		local corner = self.corners[i]
		local r = math.max(1, math.min(radii[i], big))
		corner.arc:ClearAllPoints()
		corner.arc:SetPoint(point, box, point, 0, 0)
		corner.arc:SetSize(r, r)
		corner.arc:Show()
		-- The rest of the corner's square, around a smaller curve
		local rest = big - r
		corner.across:ClearAllPoints()
		corner.across:SetPoint(point, box, point, dx * r, 0)
		corner.across:SetSize(math.max(rest, 1), big)
		corner.across:SetShown(rest > 0)
		corner.down:ClearAllPoints()
		corner.down:SetPoint(point, box, point, 0, dy * r)
		corner.down:SetSize(r, math.max(rest, 1))
		corner.down:SetShown(rest > 0)
	end
	self.shown = true
end
