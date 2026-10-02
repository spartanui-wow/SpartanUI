--[[
# Element: Spartan Artwork handler

## Notes

This element updates by changing the texture.
The `Badge` sub-widget has to be on a lower sub-layer than the `PvP` texture.

	ArtData = {
		path = pathFunc,
		TexCoord = TexCoordFunc,
		heightScale = .0825, (FrameWidth * heightScale)
		yScale = 0.0223, (FrameWidth * yScale)
		PVPAlpha = .7 (applied if not flagged for PVP; User setting of ArtSettings.alpha overrides)
		height = 40,
		y = 40,
		alpha = 1, (default alpha; user setting of ArtSettings.alpha overrides)
		VertexColor = {0, 0, 0, .6},
		position = {Pos table},
		scale = 1,
		slice = { (optional) nine-slice art that follows the frame's size
			file = { width, height },          texture pixels
			margins = { left, right, top, bottom }, texture pixels kept at their size (corners and edges)
			scale = .61,                        UI units per texture pixel
			insets = { left, right, top, bottom }, UI units the art reaches past the frame's edges
			mirror = false,                     flip left and right (the target side)
		},
	}
--]]
local _, ns = ...
local oUF = ns.oUF

local ArtPositions = { 'top', 'bg', 'bottom', 'full' }

-- Nine-slice art: nine textures cut from one picture. Corners keep their size, edges stretch one
-- way and the centre both ways, so the art follows the frame when its width or height changes.
local SLICE_POINTS = {
	{ 'TOPLEFT', 'TOP', 'TOPRIGHT' },
	{ 'LEFT', 'CENTER', 'RIGHT' },
	{ 'BOTTOMLEFT', 'BOTTOM', 'BOTTOMRIGHT' },
}

---@param element table
---@param pos string
---@param artObj Texture
---@return Texture[]
local function GetSlices(element, pos, artObj)
	element.slices = element.slices or {}
	local slices = element.slices[pos]
	if not slices then
		slices = {}
		local layer, sublevel = artObj:GetDrawLayer()
		for i = 1, 9 do
			slices[i] = element:CreateTexture(nil, layer, nil, sublevel)
		end
		element.slices[pos] = slices
	end
	return slices
end

---@param element table
---@param pos string
local function HideSlices(element, pos)
	local slices = element.slices and element.slices[pos]
	if slices then
		for i = 1, 9 do
			slices[i]:Hide()
		end
	end
end

---Draw the art as nine pieces stretched over the frame plus its insets
---@param self table unit frame
---@param element table
---@param pos string
---@param artObj Texture
---@param path string|number
---@param slice table
---@param alpha number
local function DrawSliced(self, element, pos, artObj, path, slice, alpha)
	artObj:Hide()
	local slices = GetSlices(element, pos, artObj)
	local fw, fh = slice.file.width, slice.file.height
	local m, inset, scale = slice.margins, slice.insets, slice.scale
	-- Texture columns and rows: u/v edges of the three bands
	local u = { 0, m.left / fw, (fw - m.right) / fw, 1 }
	local v = { 0, m.top / fh, (fh - m.bottom) / fh, 1 }
	local widths = { m.left * scale, nil, m.right * scale }
	if slice.mirror then
		widths = { m.right * scale, nil, m.left * scale }
	end
	local heights = { m.top * scale, nil, m.bottom * scale }
	for row = 1, 3 do
		for col = 1, 3 do
			local tex = slices[(row - 1) * 3 + col]
			tex:SetTexture(path)
			local u1, u2
			if slice.mirror then
				-- Screen column col shows texture column 4 - col, flipped
				u1, u2 = u[5 - col], u[4 - col]
			else
				u1, u2 = u[col], u[col + 1]
			end
			tex:SetTexCoord(u1, u2, v[row], v[row + 1])
			tex:SetAlpha(alpha)
			tex:ClearAllPoints()
			tex:Show()
		end
	end
	local function S(row, col)
		return slices[(row - 1) * 3 + col]
	end
	-- Corners sit on the frame's corners pushed out by the insets
	S(1, 1):SetPoint('TOPLEFT', self, 'TOPLEFT', -inset.left, inset.top)
	S(1, 3):SetPoint('TOPRIGHT', self, 'TOPRIGHT', inset.right, inset.top)
	S(3, 1):SetPoint('BOTTOMLEFT', self, 'BOTTOMLEFT', -inset.left, -inset.bottom)
	S(3, 3):SetPoint('BOTTOMRIGHT', self, 'BOTTOMRIGHT', inset.right, -inset.bottom)
	for _, corner in ipairs({ { 1, 1 }, { 1, 3 }, { 3, 1 }, { 3, 3 } }) do
		S(corner[1], corner[2]):SetSize(widths[corner[2]], heights[corner[1]])
	end
	-- Edges and centre fill the space between the corners
	S(1, 2):SetPoint('TOPLEFT', S(1, 1), 'TOPRIGHT')
	S(1, 2):SetPoint('BOTTOMRIGHT', S(1, 3), 'BOTTOMLEFT')
	S(3, 2):SetPoint('TOPLEFT', S(3, 1), 'TOPRIGHT')
	S(3, 2):SetPoint('BOTTOMRIGHT', S(3, 3), 'BOTTOMLEFT')
	S(2, 1):SetPoint('TOPLEFT', S(1, 1), 'BOTTOMLEFT')
	S(2, 1):SetPoint('BOTTOMRIGHT', S(3, 1), 'TOPRIGHT')
	S(2, 3):SetPoint('TOPLEFT', S(1, 3), 'BOTTOMLEFT')
	S(2, 3):SetPoint('BOTTOMRIGHT', S(3, 3), 'TOPRIGHT')
	S(2, 2):SetPoint('TOPLEFT', S(1, 1), 'BOTTOMRIGHT')
	S(2, 2):SetPoint('BOTTOMRIGHT', S(3, 3), 'TOPLEFT')
end

local function Update(self, event, unit)
	if unit and unit ~= self.unit then
		return
	end

	local element = self.SpartanArt
	unit = unit or self.unit

	--[[ Callback: SpartanArt:PreUpdate(unit)
	Called before the element has been updated.

	* self - the SpartanArt element
	* unit - the unit for which the update has been triggered (string)
	--]]
	if element.PreUpdate then
		element:PreUpdate(unit)
	end

	--[[ Update code
	--]]
	for _, pos in ipairs(ArtPositions) do
		local artObj = element[pos]

		if element.ArtSettings then
			local ArtSettings = element.ArtSettings[pos]

			if artObj and artObj.ArtData and ArtSettings and ArtSettings.enabled and ArtSettings.graphic ~= '' and artObj.ArtData.slice then
				local ArtData = artObj.ArtData
				local path = ArtData.path
				if type(path) == 'function' then
					path = path(self, pos)
				end
				local alpha = (ArtSettings.alpha or ArtData.alpha) or 1
				if ArtData.PVPAlpha and not ArtSettings.alpha then
					alpha = (UnitIsPVP(unit) and 1) or ArtData.PVPAlpha
				end
				DrawSliced(self, element, pos, artObj, path, ArtData.slice, alpha)
			elseif artObj and artObj.ArtData and ArtSettings and ArtSettings.enabled and ArtSettings.graphic ~= '' then
				HideSlices(element, pos)
				local ArtData = artObj.ArtData

				-- -- setup a bg width
				local width = ArtData.width or self:GetWidth()
				if ArtData.widthScale then
					width = width * ArtData.widthScale
				end

				-- -- setup a bg height
				local height
				if pos == 'bg' then
					height = (self:GetHeight() + (ArtData.height or 0))
				end
				if ArtData.heightScale then
					height = width * ArtData.heightScale
				end

				-- Setup the Artwork
				if type(ArtData.path) == 'function' then
					artObj:SetTexture(ArtData.path(self, pos))
				else
					artObj:SetTexture(ArtData.path)
				end

				if ArtData.TexCoord then
					if type(ArtData.TexCoord) == 'function' then
						local cords = ArtData.TexCoord(self, pos)
						if cords then
							artObj:SetTexCoord(unpack(cords))
						end
					else
						artObj:SetTexCoord(unpack(ArtData.TexCoord))
					end
				end
				if ArtData.Colorable then
					artObj:SetVertexColor(0, 0, 0, 0.6)
				end

				artObj:SetScale(ArtData.scale or 1)
				if ArtData.PVPAlpha and not ArtSettings.alpha then
					artObj:SetAlpha((UnitIsPVP(unit) and 1) or ArtData.PVPAlpha)
				else
					artObj:SetAlpha((ArtSettings.alpha or ArtData.alpha) or 1)
				end

				artObj:SetWidth(width or 1)
				artObj:SetHeight((height or ArtData.height) or 25)

				-- Position artwork
				local x = (ArtData.x or 0)
				local y = (ArtData.y or 0)
				if ArtData.xScale then
					x = width * ArtData.xScale
				end
				if ArtData.yScale then
					y = width * ArtData.yScale
				end
				local x = (ArtSettings.x + x)
				local y = (ArtSettings.y + y)
				artObj:ClearAllPoints()
				if ArtData.position then
					x = (x + (ArtData.position.x or 0))
					y = (y + (ArtData.position.y or 0))

					artObj:SetPoint(ArtData.position.anchor, self, ArtData.position.anchor, x, y)
				else
					if pos == 'top' then
						artObj:SetPoint('BOTTOM', self, 'TOP', x, y)
					elseif pos == 'bottom' then
						artObj:SetPoint('TOP', self, 'BOTTOM', x, y)
					elseif pos == 'bg' then
						artObj:SetPoint('CENTER', self, 'CENTER', x, y)
					end
				end

				artObj:Show()
			elseif artObj then
				artObj:Hide()
				HideSlices(element, pos)
			end
		else
			artObj:Hide()
			HideSlices(element, pos)
		end
	end

	--[[ Callback: SpartanArt:PostUpdate(unit, status)
	Called after the element has been updated.

	* self   - the SpartanArt element
	* unit   - the unit for which the update has been triggered (string)
	--]]
	if element.PostUpdate then
		return element:PostUpdate(unit)
	end
end

local function Path(self, ...)
	--[[Override: SpartanArt.Override(self, event, ...)
	Used to completely override the internal update function.

	* self  - the parent object
	* event - the event triggering the update (string)
	* ...   - the arguments accompanying the event
	--]]
	return (self.SpartanArt.Override or Update)(self, ...)
end

local function ForceUpdate(element)
	return Path(element.__owner, 'ForceUpdate', element.__owner.unit)
end
-- The options preview draws the art on a stand-in frame that oUF never enables
ns.SpartanArtForceUpdate = ForceUpdate

local function Enable(self)
	local element = self.SpartanArt
	if element then
		element.__owner = self
		element.ForceUpdate = ForceUpdate

		element.top = element.top or element:CreateTexture(nil, 'BORDER')
		element.bg = element.bg or element:CreateTexture(nil, 'BACKGROUND')
		element.bottom = element.bottom or element:CreateTexture(nil, 'BORDER')
		element.full = element.full or element:CreateTexture(nil, 'BACKGROUND')
		-- Disable hides the whole element; a look that turns the art back on must show it again
		element:Show()

		self:RegisterEvent('UNIT_FACTION', Path)
		if oUF.IsRetail then
			self:RegisterEvent('HONOR_LEVEL_UPDATE', Path, true)
		end

		return true
	end
end

local function Disable(self)
	local element = self.SpartanArt
	if element then
		element:Hide()

		if element.Badge then
			element.Badge:Hide()
		end

		self:UnregisterEvent('UNIT_FACTION', Path)
		self:UnregisterEvent('PLAYER_REGEN_DISABLED', Path)
		self:UnregisterEvent('PLAYER_REGEN_ENABLED', Path)
		if oUF.IsRetail then
			self:UnregisterEvent('HONOR_LEVEL_UPDATE', Path)
		end
	end
end

oUF:AddElement('SpartanArt', Path, Enable, Disable)
