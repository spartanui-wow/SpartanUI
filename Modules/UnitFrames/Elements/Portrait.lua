local UF, L = SUI.UF, SUI.L

---@param frame table
---@param DB table
local function Build(frame, DB)
	-- 3D Portrait
	local Portrait3D = CreateFrame('PlayerModel', nil, frame)
	Portrait3D:SetSize(frame:GetHeight(), frame:GetHeight())
	Portrait3D:SetScale(DB.scale)
	Portrait3D:SetFrameStrata('BACKGROUND')
	Portrait3D:SetFrameLevel(2)
	Portrait3D.PostUpdate = function(unit, event, shouldUpdate)
		if frame:IsObjectType('PlayerModel') then
			frame:SetAlpha(DB.alpha)

			local rotation = DB.rotation

			if frame:GetFacing() ~= (rotation / 57.29573671972358) then
				frame:SetFacing(rotation / 57.29573671972358) -- because 1 degree is equal 0,0174533 radian. Credit: Hndrxuprt
			end

			frame:SetCamDistanceScale(DB.camDistanceScale)
			frame:SetPosition(DB.xOffset, DB.xOffset, DB.yOffset)

			--Refresh model to fix incorrect display issues
			frame:ClearModel()
			frame:SetUnit(unit)
		end
	end
	Portrait3D:Hide()
	frame.Portrait3D = Portrait3D

	-- 2D Portrait
	local Portrait2D = frame:CreateTexture(nil, 'OVERLAY')
	Portrait2D:SetSize(frame:GetHeight(), frame:GetHeight())
	Portrait2D:SetScale(DB.scale)
	Portrait2D:Hide()
	frame.Portrait2D = Portrait2D

	-- Click overlay: transparent secure button on top of the portrait for right-click targeting/menu
	local clickOverlay = CreateFrame('Button', nil, frame, 'SecureUnitButtonTemplate')
	clickOverlay:SetAttribute('unit', frame.unitOnCreate)
	clickOverlay:SetAttribute('*type1', 'target')
	clickOverlay:SetAttribute('*type2', 'togglemenu')
	clickOverlay:RegisterForClicks('AnyDown')
	clickOverlay:SetFrameStrata('LOW')
	clickOverlay:SetFrameLevel(10)
	clickOverlay:EnableMouse(true)
	clickOverlay:Hide()

	-- Register with Clique for click-casting support
	_G.ClickCastFrames = _G.ClickCastFrames or {}
	_G.ClickCastFrames[clickOverlay] = true

	-- Tooltip support: show unit tooltip on hover
	clickOverlay:SetScript('OnEnter', function()
		UF.UnitFrame_OnEnter(frame)
	end)
	clickOverlay:SetScript('OnLeave', function()
		UF.UnitFrame_OnLeave(frame)
	end)

	frame.PortraitClickOverlay = clickOverlay
	frame.Portrait = Portrait3D
end

-- A portrait beside the frame is outside the unit button, so clicking it did nothing. Widening the
-- frame's own click area over the portrait makes it target on left click and open the unit menu on
-- right click, like the rest of the frame. The area of a secure frame can only change out of combat.
local pendingHitRects = {}
local hitRectWatcher

---Make the frame clickable this far past each edge (0 to stop at the frame)
---@param frame table unit frame
---@param left number
---@param right number
---@param top number
---@param bottom number
function UF:SetPortraitHitRect(frame, left, right, top, bottom)
	if not frame.SetHitRectInsets then
		return
	end
	if InCombatLockdown() then
		pendingHitRects[frame] = { left, right, top, bottom }
		if not hitRectWatcher then
			hitRectWatcher = CreateFrame('Frame')
			hitRectWatcher:SetScript('OnEvent', function(self)
				self:UnregisterEvent('PLAYER_REGEN_ENABLED')
				for pendingFrame, insets in pairs(pendingHitRects) do
					pendingFrame:SetHitRectInsets(-insets[1], -insets[2], -insets[3], -insets[4])
				end
				wipe(pendingHitRects)
			end)
		end
		hitRectWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
		return
	end
	pendingHitRects[frame] = nil
	frame:SetHitRectInsets(-left, -right, -top, -bottom)
end

---@param frame table
local function Update(frame)
	local DB = frame.Portrait.DB
	local clickOverlay = frame.PortraitClickOverlay

	frame.Portrait3D:Hide()
	frame.Portrait2D:Hide()
	frame.Portrait3D:ClearAllPoints()
	frame.Portrait2D:ClearAllPoints()
	if clickOverlay then
		clickOverlay:Hide()
		clickOverlay:ClearAllPoints()
	end
	if not DB.enabled then
		if not frame.isPreview then
			UF:SetPortraitHitRect(frame, 0, 0, 0, 0)
		end
		return
	end

	-- Click area over the portrait (not for the options preview, which is no unit button); looks
	-- that place the portrait themselves set their own afterwards
	if not frame.isPreview then
		local reach = frame.Portrait2D:GetWidth() * (DB.scale or 1)
		if DB.position == 'left' then
			UF:SetPortraitHitRect(frame, reach, 0, 0, 0)
		elseif DB.position == 'right' then
			UF:SetPortraitHitRect(frame, 0, reach, 0, 0)
		else
			UF:SetPortraitHitRect(frame, 0, 0, 0, 0)
		end
	end

	if DB.position == 'left' then
		frame.Portrait3D:SetPoint('RIGHT', frame, 'LEFT')
		frame.Portrait2D:SetPoint('RIGHT', frame, 'LEFT')
	elseif DB.position == 'overlay' then
		frame.Portrait3D:SetAllPoints(frame)
	else
		frame.Portrait3D:SetPoint('LEFT', frame, 'RIGHT')
		frame.Portrait2D:SetPoint('LEFT', frame, 'RIGHT')
	end

	-- oUF keeps the portrait's state per widget and only creates it when the element is
	-- enabled, so swapping the widget on a live frame leaves the new one without state.
	-- Cycle the element around the swap so oUF sets the new widget up.
	local target = DB.type == '3D' and frame.Portrait3D or frame.Portrait2D
	if frame.Portrait ~= target then
		local cycle = frame.IsBuilt and frame:IsElementEnabled('Portrait')
		if cycle then
			frame:DisableElement('Portrait')
		end
		frame.Portrait = target
		if cycle then
			frame:EnableElement('Portrait')
		end
	end

	if DB.type == '3D' then
		frame.Portrait3D:Show()
		frame.Portrait:SetAlpha(DB.alpha)

		local rotation = DB.rotation

		if frame.Portrait:GetFacing() ~= (rotation / 57.29573671972358) then
			frame.Portrait:SetFacing(rotation / 57.29573671972358) -- because 1 degree is equal 0,0174533 radian. Credit: Hndrxuprt
		end

		frame.Portrait:SetCamDistanceScale(DB.camDistanceScale)
		frame.Portrait:SetPosition(DB.xOffset, DB.xOffset, DB.yOffset)

		--Refresh model to fix incorrect display issues
		frame.Portrait:ClearModel()
		frame.Portrait:SetUnit(frame.unitOnCreate)
	else
		frame.Portrait2D:Show()
	end

	if clickOverlay and DB.clickOverlay and DB.position ~= 'overlay' then
		local portrait = frame.Portrait
		clickOverlay:SetPoint('TOPLEFT', portrait, 'TOPLEFT')
		clickOverlay:SetPoint('BOTTOMRIGHT', portrait, 'BOTTOMRIGHT')
		clickOverlay:SetScale(DB.scale)
		clickOverlay:Show()
	end
end

---@param frameName string
---@param OptionSet AceConfig.OptionsTable
local function Options(frameName, OptionSet)
	UF.Options:IndicatorAddDisplay(OptionSet)
	OptionSet.args.display.args.size = nil
	OptionSet.args.display.args.scale = nil

	OptionSet.args.general = {
		name = '',
		type = 'group',
		inline = true,
		order = 10,
		args = {
			header = {
				type = 'header',
				name = 'General',
				order = 0.1,
			},
			type = {
				name = L['Portrait type'],
				type = 'select',
				order = 20,
				values = {
					['3D'] = '3D',
					['2D'] = '2D',
				},
			},
			rotation = {
				name = L['Rotation'],
				type = 'range',
				min = -1,
				max = 1,
				step = 0.01,
				order = 21,
			},
			camDistanceScale = {
				name = L['Camera Distance Scale'],
				type = 'range',
				min = 0.01,
				max = 5,
				step = 0.1,
				order = 22,
			},
			position = {
				name = L['Position'],
				type = 'select',
				order = 30,
				values = {
					['left'] = L['Left'],
					['right'] = L['Right'],
					['overlay'] = 'Overlay',
				},
				set = function(info, val)
					if val == 'overlay' then
						UF.CurrentSettings[frameName].elements.Portrait.type = '3D'
						UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Portrait.type = '3D'
					end

					--Update memory
					UF.CurrentSettings[frameName].elements.Portrait.position = val
					--Update the DB
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Portrait.position = val
					--Update the screen
					UF.Unit[frameName]:ElementUpdate('Portrait')
				end,
			},
			clickOverlay = {
				name = L['Click overlay'],
				desc = L['Adds a clickable layer on top of the portrait for targeting and right-click menu'],
				type = 'toggle',
				order = 31,
				hidden = function()
					return UF.CurrentSettings[frameName].elements.Portrait.position == 'overlay'
				end,
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	type = '3D',
	scaleWithFrame = true,
	width = 50,
	height = 100,
	rotation = 0,
	camDistanceScale = 1,
	xOffset = 0,
	yOffset = 0,
	position = 'left',
	clickOverlay = false,
	config = {
		NoBulkUpdate = true,
		type = 'General',
	},
}

UF.Elements:Register('Portrait', Build, Update, Options, Settings)
