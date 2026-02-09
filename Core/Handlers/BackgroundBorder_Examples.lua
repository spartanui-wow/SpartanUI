--[[
    BackgroundBorder Integration Examples

    This file demonstrates how to integrate the unified BackgroundBorder system
    into Unit Frames, Nameplates, and other UI elements.
]]
local BackgroundBorder = SUI:GetHandler('BackgroundBorder')

---Example 1: Adding Background/Border to Unit Frame Options
---This shows how to add a "General" section to unit frame options with background/border controls
local function AddToUnitFrameOptions(frameName)
	local UF = SUI.UF
	if not UF or not UF.Options then
		return
	end

	-- Example: Add to player frame options
	local function getSettings()
		-- Get current settings from DB - this would be your actual settings path
		return UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].backgroundBorder or BackgroundBorder.DefaultSettings
	end

	local function setSettings(newSettings)
		-- Save to DB - this would be your actual save path
		UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].backgroundBorder = newSettings
		UF.CurrentSettings[frameName].backgroundBorder = newSettings
	end

	local function updateDisplay()
		-- Update the actual display
		BackgroundBorder:Update('UnitFrame_' .. frameName, getSettings())
		-- Refresh the unit frame
		if UF.Unit[frameName] then
			UF.Unit[frameName]:UpdateAll()
		end
	end

	-- Generate the complete options table
	local backgroundBorderOptions = BackgroundBorder:GenerateCompleteOptions('UnitFrame_' .. frameName, getSettings, setSettings, updateDisplay)

	-- Add to unit frame options (this would go in your actual options building code)
	--[[
    if SUI.opt.args.Modules.args.UnitFrames.args[frameName] then
        SUI.opt.args.Modules.args.UnitFrames.args[frameName].args.General.args.BackgroundBorder = backgroundBorderOptions
    end
    ]]
	return backgroundBorderOptions
end

---Example 2: Adding Background/Border to Nameplate Options
---This shows how to add to the nameplate General options
local function AddToNameplateOptions()
	local module = SUI:GetModule('Nameplates')
	if not module then
		return
	end

	local function getSettings()
		-- Get current settings from nameplate DB
		return module.DB.backgroundBorder or BackgroundBorder.DefaultSettings
	end

	local function setSettings(newSettings)
		-- Save to nameplate DB
		module.DB.backgroundBorder = newSettings
	end

	local function updateDisplay()
		-- Update all nameplate instances
		local nameplateIds = BackgroundBorder:GetInstancesByPrefix('Nameplate_')
		BackgroundBorder:UpdateMultiple(nameplateIds, getSettings())
		-- Refresh nameplates
		if module.UpdateNameplates then
			module:UpdateNameplates()
		end
	end

	-- Generate the complete options table
	local backgroundBorderOptions = BackgroundBorder:GenerateCompleteOptions('Nameplate_General', getSettings, setSettings, updateDisplay)

	-- Add to nameplate options (this would go in your actual options building code)
	--[[
    if SUI.opt.args.Modules.args.Nameplates then
        SUI.opt.args.Modules.args.Nameplates.args.General.args.BackgroundBorder = backgroundBorderOptions
    end
    ]]
	return backgroundBorderOptions
end

---Example 3: Setting up Background/Border on Frame Creation
---This shows how to initialize the background/border when creating frames
local function SetupUnitFrameBackgroundBorder(frame, frameName)
	local UF = SUI.UF

	-- Get settings from DB (with fallback to defaults)
	local settings = UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].backgroundBorder or BackgroundBorder.DefaultSettings

	-- Create the background/border instance
	local instance = BackgroundBorder:SetupUnitFrame(frame, frameName, settings)

	-- Store reference for easy access
	frame.backgroundBorderInstance = instance

	return instance
end

---Example 4: Setting up Background/Border on Nameplate Creation
---This shows how to initialize the background/border when creating nameplate frames
local function SetupNameplateBackgroundBorder(frame)
	local module = SUI:GetModule('Nameplates')
	if not module then
		return
	end

	-- Get settings from nameplate DB (with fallback to defaults)
	local settings = module.DB.backgroundBorder or BackgroundBorder.DefaultSettings

	-- Create the background/border instance
	local instance = BackgroundBorder:SetupNameplate(frame, settings)

	-- Store reference for easy access
	frame.backgroundBorderInstance = instance

	return instance
end

---Example 5: Preset Usage
---This shows how to use the convenience preset methods
local function ExamplePresets()
	-- Simple dark background
	local darkBg = BackgroundBorder:CreateColorBackground({ 0.1, 0.1, 0.1, 0.8 })

	-- Background with white border
	local bgWithBorder = BackgroundBorder:CreateBackgroundWithBorder(
		{ 0.2, 0.2, 0.2, 0.9 }, -- background color
		{ 1, 1, 1, 1 }, -- border color
		2 -- border size
	)

	-- Class-colored background with class-colored border
	local classColored = BackgroundBorder:CreateClassColoredBackground(true, 0.7)

	-- Apply to multiple frames
	BackgroundBorder:Create(someFrame1, 'frame1', darkBg)
	BackgroundBorder:Create(someFrame2, 'frame2', bgWithBorder)
	BackgroundBorder:Create(someFrame3, 'frame3', classColored)
end

---Example 6: Integration with Existing Systems
---This shows how to migrate from existing background/border systems
local function MigrateArtworkSystem()
	local Artwork = SUI:GetModule('Artwork')
	if not Artwork or not Artwork.BarBG then
		return
	end

	-- Migrate existing artwork backgrounds to unified system
	for styleName, barBGs in pairs(Artwork.BarBG) do
		for barId, barFrame in pairs(barBGs) do
			-- Extract current settings
			local userSettings = Artwork.ActiveStyle.Artwork.barBG[barId]

			-- Convert to new format
			local newSettings = {
				enabled = userSettings.enabled,
				displayLevel = 0,
				background = {
					enabled = true,
					type = 'texture', -- artwork typically uses textures
					texture = barFrame.skinSettings.TexturePath,
					alpha = userSettings.alpha or 1,
					classColor = userSettings.classColorBG or false,
				},
				border = {
					enabled = userSettings.borderEnabled or false,
					sides = userSettings.borderSides or { top = true, bottom = true, left = true, right = true },
					size = userSettings.borderSize or 1,
					colors = userSettings.borderColors or {},
					classColors = userSettings.classColorBorders or {},
				},
			}

			-- Create new unified instance
			local id = 'Artwork_' .. styleName .. '_' .. barId
			BackgroundBorder:Create(barFrame, id, newSettings)
		end
	end
end

---Example 7: Dynamic Updates
---This shows how to dynamically update backgrounds/borders
local function ExampleDynamicUpdates()
	-- Update single instance
	BackgroundBorder:Update('UnitFrame_player', {
		background = {
			enabled = true,
			type = 'color',
			classColor = true,
			alpha = 0.5,
		},
	})

	-- Update multiple instances at once
	local unitFrameIds = BackgroundBorder:GetInstancesByPrefix('UnitFrame_')
	BackgroundBorder:UpdateMultiple(unitFrameIds, {
		border = {
			enabled = true,
			size = 3,
			colors = {
				top = { 1, 0, 0, 1 }, -- red top
				bottom = { 0, 1, 0, 1 }, -- green bottom
				left = { 0, 0, 1, 1 }, -- blue left
				right = { 1, 1, 0, 1 }, -- yellow right
			},
		},
	})
end

-- Export examples for documentation
return {
	AddToUnitFrameOptions = AddToUnitFrameOptions,
	AddToNameplateOptions = AddToNameplateOptions,
	SetupUnitFrameBackgroundBorder = SetupUnitFrameBackgroundBorder,
	SetupNameplateBackgroundBorder = SetupNameplateBackgroundBorder,
	ExamplePresets = ExamplePresets,
	MigrateArtworkSystem = MigrateArtworkSystem,
	ExampleDynamicUpdates = ExampleDynamicUpdates,
}
