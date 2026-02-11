---@class SUI.Module.BlizzUIFixes : SUI.Module
local _G, SUI = _G, SUI
local module = SUI:NewModule('BlizzUIFixes') ---@type SUI.Module.BlizzUIFixes

---Initialize the BlizzUIFixes module
function module:OnInitialize()
	module:SetupDatabase()
	module:SetupAddonListResize()
end

---Setup module database with default settings
function module:SetupDatabase()
	local defaults = {
		profile = {
			addonListResizable = true,
		},
	}
	module.DB = SUI.SpartanUIDB:RegisterNamespace('BlizzUIFixes', defaults)

	-- Register profile change callbacks
	module.DB.RegisterCallback(module, 'OnProfileChanged', function()
		module.DB = SUI.SpartanUIDB:GetNamespace('BlizzUIFixes')
	end)
	module.DB.RegisterCallback(module, 'OnProfileCopied', function()
		module.DB = SUI.SpartanUIDB:GetNamespace('BlizzUIFixes')
	end)
	module.DB.RegisterCallback(module, 'OnProfileReset', function()
		module.DB = SUI.SpartanUIDB:GetNamespace('BlizzUIFixes')
	end)
end

---Make the addon list frame resizable
function module:SetupAddonListResize()
	-- Wait for the addon list frame to be created
	local function makeAddonListResizable()
		local frame = _G['AddonListFrame']
		if not frame then
			return
		end

		-- Only set up once
		if frame.SUIResizable then
			return
		end
		frame.SUIResizable = true

		-- Make the frame resizable
		frame:SetResizable(true)
		frame:SetResizeBounds(420, 300) -- Minimum size (original is 420x424)
		frame:SetMaxResize(800, 600) -- Maximum reasonable size

		-- Create resize button in bottom right corner
		local sizer = CreateFrame('Button', nil, frame)
		sizer:SetPoint('BOTTOMRIGHT', -6, 7)
		sizer:SetSize(16, 16)
		sizer:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
		sizer:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
		sizer:SetPushedTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])

		-- Handle resize drag
		sizer:SetScript('OnMouseDown', function(_, button)
			if button == 'LeftButton' then
				frame:StartSizing('BOTTOMRIGHT')
				sizer:SetScript('OnUpdate', function()
					-- Continuously update scroll frame during resize
					local scrollFrame = frame.ScrollFrame
					if scrollFrame then
						local _, height = frame:GetSize()
						local newScrollHeight = height - 120
						scrollFrame:SetHeight(math.max(newScrollHeight, 200))
					end
				end)
			end
		end)

		sizer:SetScript('OnMouseUp', function()
			frame:StopMovingOrSizing()
			sizer:SetScript('OnUpdate', nil) -- Stop continuous updates
		end)

		-- Update scroll frame height when resizing
		frame:SetScript('OnSizeChanged', function(self, width, height)
			-- Update the scroll frame to use the new height
			local scrollFrame = frame.ScrollFrame
			if scrollFrame then
				-- Maintain padding from top/bottom (approximately 120 pixels of UI chrome)
				local newScrollHeight = height - 120
				scrollFrame:SetHeight(math.max(newScrollHeight, 200))
			end
		end)

		SUI:Print('Addon List is now resizable - drag the corner to resize!')
	end

	-- Try to set up immediately if frame exists
	makeAddonListResizable()

	-- Also set up when addon loaded or when player logs in
	local eventFrame = CreateFrame('Frame')
	eventFrame:RegisterEvent('ADDON_LOADED')
	eventFrame:RegisterEvent('PLAYER_LOGIN')
	eventFrame:SetScript('OnEvent', function(self, event, ...)
		if event == 'ADDON_LOADED' then
			local addonName = ...
			if addonName == 'Blizzard_AddonList' or addonName == C_AddOns.GetAddOnMetadata('SpartanUI', 'Title') then
				makeAddonListResizable()
			end
		end
	end)
end
