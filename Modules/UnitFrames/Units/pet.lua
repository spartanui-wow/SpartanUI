local UF = SUI.UF

local function Builder(frame)
	local elementDB = frame.elementDB

	UF.Elements:Build(frame, 'FrameBackground', elementDB['FrameBackground'])
	UF.Elements:Build(frame, 'Name', elementDB['Name'])
	UF.Elements:Build(frame, 'Health', elementDB['Health'])
	UF.Elements:Build(frame, 'Castbar', elementDB['Castbar'])
	UF.Elements:Build(frame, 'Power', elementDB['Power'])

	UF.Elements:Build(frame, 'Portrait', elementDB['Portrait'])
	UF.Elements:Build(frame, 'Dispel', elementDB['Dispel'])
	UF.Elements:Build(frame, 'SpartanArt', elementDB['SpartanArt'])
	UF.Elements:Build(frame, 'ClassIcon', elementDB['ClassIcon'])
	UF.Elements:Build(frame, 'RaidTargetIndicator', elementDB['RaidTargetIndicator'])
	UF.Elements:Build(frame, 'ThreatIndicator', elementDB['ThreatIndicator'])
	UF.Elements:Build(frame, 'Range', elementDB['Range'])

	if not SUI.IsRetail then
		UF.Elements:Build(frame, 'HappinessIndicator', elementDB['HappinessIndicator'])
	end

	-- Disable Blizzard PetCastingBarFrame to prevent conflicts
	if PetCastingBarFrame then
		if SUI.IsRetail then
			-- Retail 12.0+: Don't use SetUnit() - triggers forbidden table iteration
			-- SetUnit internally calls StopFinishAnims which iterates CastingBarTypeInfo
			-- with secret value keys, causing "forbidden table" errors
			PetCastingBarFrame:UnregisterAllEvents()
			PetCastingBarFrame:Hide()
		else
			-- Classic versions: SetUnit is safe and may be needed
			if PetCastingBarFrame.SetUnit then
				PetCastingBarFrame:SetUnit(nil)
			end
			if PetCastingBarFrame.UnregisterEvent then
				PetCastingBarFrame:UnregisterEvent('UNIT_PET')
			end
		end
	end
end

local function Options() end

---@type SUI.UF.Unit.Settings
local Settings = {
	width = 100,
	elements = {
		Health = {
			height = 35,
			colorSmooth = true,
			colorReaction = false,
			text = {
				['1'] = {
					text = '[SUIHealth(short,displayDead)] [($>SUIHealth<$)(percentage,hideDead)]',
				},
			},
		},
		Power = {
			height = 2,
			text = {
				['1'] = {
					enabled = false,
				},
			},
			position = {
				y = 0,
			},
		},
		Name = {
			enabled = true,
			height = 8,
			text = '[name]',
			position = {
				y = 1,
				anchor = 'BOTTOM',
				relativePoint = 'TOP',
			},
		},
	},
}

UF.Unit:Add('pet', Builder, Settings)
