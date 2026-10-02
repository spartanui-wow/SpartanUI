-- SUICardGrid: picture cards for a select option in the settings window, drawn with the same cards
-- as setup but smaller (four across). Use on a select option:
--   dialogControl = 'SUICardGrid',
--   arg = { cards = fun(): card[], size = 'look'|'compact'|'swatch', setVariant = fun(value, variant) }
-- Cards take the setup card fields: value, title, tag, tagStyle, art, variants, variant, recommended.
-- values/get/set work as on any select; the option's values only need the card values as keys.

local AceGUI = LibStub('AceGUI-3.0', true)
if not AceGUI then
	return
end

local widgetType = 'SUICardGrid'
local widgetVersion = 1

local SIZES = {
	look = { artHeight = 88, minWidth = 165, maxColumns = 4, cardHeight = 150, spacing = 10 },
	compact = { artHeight = 46, minWidth = 165, maxColumns = 4, cardHeight = 84, spacing = 8 },
	swatch = { artHeight = 64, minWidth = 165, maxColumns = 4, cardHeight = 104, spacing = 8 },
}

local WHITE = 'Interface\\Buttons\\WHITE8X8'

---A small window in a kit's look over the card's picture: its frame, title bar, crest, a primary
---button and four colour swatches
---@param card Frame
---@param kit table a normalized window kit
local function DrawWindowPreview(card, kit)
	local p = card.windowPreview
	if not p then
		p = CreateFrame('Frame', nil, card)
		p:SetAllPoints(card.art)
		-- Level with the card so its badges stay on top
		p:SetFrameLevel(card:GetFrameLevel())
		p.fill = p:CreateTexture(nil, 'BACKGROUND', nil, 1)
		p.fill:SetPoint('TOPLEFT', 8, -6)
		p.fill:SetPoint('BOTTOMRIGHT', -8, 4)
		p.title = p:CreateTexture(nil, 'BORDER')
		p.title:SetPoint('TOPLEFT', p.fill, 'TOPLEFT', 0, 0)
		p.title:SetPoint('TOPRIGHT', p.fill, 'TOPRIGHT', 0, 0)
		p.title:SetHeight(8)
		p.pieces = {}
		for _, key in ipairs({ 'topLeft', 'topRight', 'bottomLeft', 'bottomRight', 'top', 'bottom', 'left', 'right' }) do
			p.pieces[key] = p:CreateTexture(nil, 'ARTWORK')
		end
		p.crest = p:CreateTexture(nil, 'OVERLAY', nil, 2)
		p.button = p:CreateTexture(nil, 'ARTWORK', nil, 2)
		p.button:SetSize(30, 8)
		p.button:SetPoint('BOTTOMRIGHT', p.fill, 'BOTTOMRIGHT', -5, 5)
		p.swatches = {}
		for i = 1, 4 do
			local swatch = p:CreateTexture(nil, 'ARTWORK', nil, 3)
			swatch:SetSize(9, 9)
			swatch:SetPoint('BOTTOMLEFT', p.fill, 'BOTTOMLEFT', 5 + (i - 1) * 12, 5)
			p.swatches[i] = swatch
		end
		card.windowPreview = p
	end
	local colors = kit.colors or {}
	local function Color(texture, color, alpha)
		texture:SetTexture(WHITE)
		texture:SetVertexColor(color[1] or 0, color[2] or 0, color[3] or 0, alpha or color[4] or 1)
		texture:Show()
	end
	-- The window's own background picture when it has one, dimmed like the real window
	local backdrop = kit.assets and kit.assets.backdrop
	if type(backdrop) == 'string' then
		p.fill:SetTexture(backdrop)
		p.fill:SetTexCoord(0.2, 0.8, 0.2, 0.8)
		p.fill:SetVertexColor(0.55, 0.55, 0.55, 1)
		p.fill:Show()
	else
		p.fill:SetTexCoord(0, 1, 0, 1)
		Color(p.fill, colors.panel or { 0.1, 0.1, 0.1 }, 1)
	end
	Color(p.title, colors.surface and colors.surface[3] or colors.trim, 1)
	-- The kit's own frame pieces, shrunk; flat kits get a 1px line in their trim colour
	local border = kit.assets and kit.assets.windowBorder
	local pieces = border and border.pieces
	local corner = 8
	local edge = math.max(math.floor(((border and border.edgeSize) or 1) * 0.5 + 0.5), 1)
	local function Place(key, ...)
		local tex = p.pieces[key]
		tex:ClearAllPoints()
		if pieces and pieces[key] then
			tex:SetTexture(pieces[key])
			tex:SetVertexColor(1, 1, 1, 1)
			if (key == 'top' or key == 'bottom') and border.edgeCrop then
				tex:SetTexCoord(0, 1, key == 'top' and 0 or (1 - border.edgeCrop), key == 'top' and border.edgeCrop or 1)
			elseif (key == 'left' or key == 'right') and border.edgeCrop then
				tex:SetTexCoord(key == 'left' and 0 or (1 - border.edgeCrop), key == 'left' and border.edgeCrop or 1, 0, 1)
			else
				tex:SetTexCoord(0, 1, 0, 1)
			end
		else
			Color(tex, colors.trim or { 0.6, 0.6, 0.6 }, 0.85)
		end
		for i = 1, select('#', ...), 5 do
			local point, relative, relativePoint, x, y = select(i, ...)
			tex:SetPoint(point, relative, relativePoint, x, y)
		end
		tex:Show()
	end
	local fill = p.fill
	if pieces then
		for _, key in ipairs({ 'topLeft', 'topRight', 'bottomLeft', 'bottomRight' }) do
			p.pieces[key]:SetSize(corner, corner)
		end
		Place('topLeft', 'TOPLEFT', fill, 'TOPLEFT', -2, 2)
		Place('topRight', 'TOPRIGHT', fill, 'TOPRIGHT', 2, 2)
		Place('bottomLeft', 'BOTTOMLEFT', fill, 'BOTTOMLEFT', -2, -2)
		Place('bottomRight', 'BOTTOMRIGHT', fill, 'BOTTOMRIGHT', 2, -2)
		p.pieces.top:SetHeight(edge + 1)
		p.pieces.bottom:SetHeight(edge + 1)
		p.pieces.left:SetWidth(edge + 1)
		p.pieces.right:SetWidth(edge + 1)
		Place('top', 'TOPLEFT', p.pieces.topLeft, 'TOPRIGHT', 0, 0, 'TOPRIGHT', p.pieces.topRight, 'TOPLEFT', 0, 0)
		Place('bottom', 'BOTTOMLEFT', p.pieces.bottomLeft, 'BOTTOMRIGHT', 0, 0, 'BOTTOMRIGHT', p.pieces.bottomRight, 'BOTTOMLEFT', 0, 0)
		Place('left', 'TOPLEFT', p.pieces.topLeft, 'BOTTOMLEFT', 0, 0, 'BOTTOMLEFT', p.pieces.bottomLeft, 'TOPLEFT', 0, 0)
		Place('right', 'TOPRIGHT', p.pieces.topRight, 'BOTTOMRIGHT', 0, 0, 'BOTTOMRIGHT', p.pieces.bottomRight, 'TOPRIGHT', 0, 0)
	else
		for _, key in ipairs({ 'topLeft', 'topRight', 'bottomLeft', 'bottomRight' }) do
			p.pieces[key]:Hide()
		end
		p.pieces.top:SetHeight(1)
		p.pieces.bottom:SetHeight(1)
		p.pieces.left:SetWidth(1)
		p.pieces.right:SetWidth(1)
		Place('top', 'TOPLEFT', fill, 'TOPLEFT', 0, 0, 'TOPRIGHT', fill, 'TOPRIGHT', 0, 0)
		Place('bottom', 'BOTTOMLEFT', fill, 'BOTTOMLEFT', 0, 0, 'BOTTOMRIGHT', fill, 'BOTTOMRIGHT', 0, 0)
		Place('left', 'TOPLEFT', fill, 'TOPLEFT', 0, 0, 'BOTTOMLEFT', fill, 'BOTTOMLEFT', 0, 0)
		Place('right', 'TOPRIGHT', fill, 'TOPRIGHT', 0, 0, 'BOTTOMRIGHT', fill, 'BOTTOMRIGHT', 0, 0)
	end
	-- The topper, scaled to the little window and resting on its top edge
	local crest = kit.assets and kit.assets.crest
	if type(crest) == 'table' and crest.texture then
		local height = 14
		local width = height * (crest.width or 128) / math.max(crest.height or 64, 1)
		p.crest:SetTexture(crest.texture)
		p.crest:SetSize(width, height)
		p.crest:ClearAllPoints()
		p.crest:SetPoint('BOTTOM', fill, 'TOP', 0, -height * ((crest.overlap or 0) / math.max(crest.height or 64, 1)) - 1)
		p.crest:Show()
	else
		p.crest:Hide()
	end
	local primary = kit.button and kit.button.primary or {}
	Color(p.button, primary.top or colors.trim or { 0.3, 0.6, 0.6 }, 1)
	local swatchColors = { colors.surface and colors.surface[1] or colors.panel, colors.trim, primary.top or colors.trimHi, colors.text }
	for i, swatch in ipairs(p.swatches) do
		Color(swatch, swatchColors[i] or { 0.5, 0.5, 0.5 }, 1)
	end
	p:Show()
end

local function Render(self)
	local data = self.customData
	local Kit = LibAT and LibAT.UI and LibAT.UI.Kit
	if not data or not Kit then
		return
	end
	local size = data.size or 'look'
	if not self.grid or self.gridSize ~= size then
		if self.grid then
			self.grid:Hide()
		end
		self.grid = Kit:CreateCardGrid(self.frame, SIZES[size] or SIZES.look)
		self.grid:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, 0)
		self.gridSize = size
	end
	local grid = self.grid
	local cards = type(data.cards) == 'function' and data.cards() or data.cards or {}
	local list = {}
	for _, card in ipairs(cards) do
		list[#list + 1] = {
			value = card.value,
			title = card.title,
			tag = card.tag,
			tagStyle = card.tagStyle,
			art = card.art,
			accent = card.accent,
			variants = card.variants,
			variant = card.variant,
			kit = card.kit,
		}
	end
	local owner = self
	grid.opts.onClick = function(_, value)
		if value ~= owner.value then
			owner.value = value
			owner:Fire('OnValueChanged', value)
		end
	end
	grid.opts.onVariant = function(_, value, variant)
		if data.setVariant then
			data.setVariant(value, variant)
		end
		owner.value = value
		owner:Fire('OnValueChanged', value)
	end
	grid.opts.onCheck = nil
	grid:SetCards(list)
	for _, card in ipairs(grid.cards) do
		local selected = card.data.value == self.value
		card:SetState(selected, not self.disabled, selected and 'In use' or nil)
		if card.data.kit then
			DrawWindowPreview(card, card.data.kit)
		elseif card.windowPreview then
			card.windowPreview:Hide()
		end
	end
	grid:Show()
	local height = grid:Layout(math.max(self.frame:GetWidth() or 0, 340))
	self:SetHeight(math.max(height, 20))
end

local methods = {
	OnAcquire = function(self)
		self:SetFullWidth(true)
		self:SetHeight(20)
		self.disabled = false
	end,
	OnRelease = function(self)
		self.value = nil
		self.customData = nil
		if self.grid then
			self.grid:Hide()
		end
	end,
	OnWidthSet = function(self)
		Render(self)
	end,
	SetLabel = function() end,
	SetText = function() end,
	SetList = function(self, list)
		self.list = list
	end,
	SetValue = function(self, value)
		self.value = value
		Render(self)
	end,
	GetValue = function(self)
		return self.value
	end,
	SetCustomData = function(self, data)
		self.customData = data
		Render(self)
	end,
	SetDisabled = function(self, disabled)
		self.disabled = disabled and true or false
		Render(self)
	end,
	SetItemValue = function() end,
	SetItemDisabled = function() end,
	SetMultiselect = function() end,
	GetMultiselect = function()
		return false
	end,
	AddItem = function() end,
}

local function Constructor()
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()
	local widget = { frame = frame, type = widgetType }
	for name, method in pairs(methods) do
		widget[name] = method
	end
	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)
