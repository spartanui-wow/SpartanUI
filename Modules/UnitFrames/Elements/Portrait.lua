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

	frame.Portrait = Portrait3D
end

---@param frame table
local function Update(frame)
	local DB = frame.Portrait.DB

	frame.Portrait3D:Hide()
	frame.Portrait2D:Hide()
	frame.Portrait3D:ClearAllPoints()
	frame.Portrait2D:ClearAllPoints()
	if not DB.enabled then
		return
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

	if DB.type == '3D' then
		frame.Portrait = frame.Portrait3D
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
		frame.Portrait = frame.Portrait2D
		frame.Portrait2D:Show()
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
	config = {
		NoBulkUpdate = true,
		type = 'General',
	},
}

UF.Elements:Register('Portrait', Build, Update, Options, Settings)
