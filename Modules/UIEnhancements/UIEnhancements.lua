local SUI, L = SUI, SUI.L
---@class SUI.Module.UIEnhancements : SUI.Module
local module = SUI:NewModule('UIEnhancements')
module.DisplayName = L['UI Enhancements']
module.description = 'Add and improve UI functionality'
----------------------------------------------------------------------------------------------------

---@class SUI.Module.UIEnhancements.DB
local DBDefaults = {
	-- DecorMerchant
	decorMerchantBulkBuy = true,
	-- LootAlertPopup
	lootAlertPopup = true,
	lootAlertChat = true,
	lootAlertSound = false,
	lootAlertSoundName = 'None',
	-- Mouse Ring Settings
	mouseRing = {
		enabled = false,
		circleStyle = 1, -- 1=circle.tga, 2=ChallengeMode-KeystoneSlotFrameGlow, 3=GarrLanding-CircleGlow, 4=ShipMission-RedGlowRing
		size = 32,
		alpha = 0.8,
		color = { mode = 'class', r = 1, g = 1, b = 1 },
		showCenterDot = false,
		centerDotSize = 4,
		combatOnly = false,
		-- GCD Mode
		gcdEnabled = false,
		gcdAlpha = 0.8,
		gcdReverse = false, -- false = swipe empties, true = swipe fills
	},
	-- Mouse Trail Settings
	mouseTrail = {
		enabled = false,
		density = 'medium',
		size = 8,
		alpha = 0.6,
		color = { mode = 'class', r = 1, g = 1, b = 1 },
		combatOnly = false,
	},
}

local DB

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('UIEnhancements', { profile = DBDefaults })
	DB = module.Database.profile
	module.DB = DB

	-- Register profile change callbacks
	module.Database.RegisterCallback(module, 'OnProfileChanged', function()
		DB = module.Database.profile
		module.DB = DB
	end)
	module.Database.RegisterCallback(module, 'OnProfileCopied', function()
		DB = module.Database.profile
		module.DB = DB
	end)
	module.Database.RegisterCallback(module, 'OnProfileReset', function()
		DB = module.Database.profile
		module.DB = DB
	end)
end

function module:GetDB()
	return DB
end

function module:OnEnable()
	if SUI:IsModuleDisabled(module) then
		return
	end

	-- Initialize sub-modules
	module:InitializeDecorMerchant()
	module:InitializeLootAlertPopup()
	module:InitializeMouseEffects()

	-- Build options
	module:BuildOptions()

	-- Register wizard page
	module:RegisterSetupWizardPage()
end

function module:RegisterSetupWizardPage()
	local reg = SUI.Setup and SUI.Setup.registration
	if not reg or reg:GetStep('uienhancements') then
		return
	end

	reg:AddStep({
		id = 'uienhancements',
		kind = 'custom',
		name = L['UI Enhancements'],
		order = 55,
		title = L['UI Enhancements'],
		hidden = function()
			return SUI:IsModuleDisabled('UIEnhancements')
		end,
		build = function(contentFrame)
			local width = contentFrame:GetWidth()
			local totalY = 0 -- tracks downward offset (negative y from TOPLEFT)
			local SPACING = 5

			-- ---- Mouse Ring section ----
			local ringSub = CreateFrame('Frame', nil, contentFrame)
			ringSub:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, 0)
			ringSub:SetSize(width, 1)

			local _, ringH = LibAT.UI.BuildWidgets(ringSub, {
				mouseRingHeader = {
					type = 'header',
					name = 'Mouse Ring',
					order = 1,
				},
				mouseRingEnabled = {
					type = 'checkbox',
					name = 'Enable mouse ring',
					desc = 'Shows a ring around your mouse cursor',
					order = 2,
					get = function()
						return DB.mouseRing.enabled
					end,
					set = function(_, val)
						DB.mouseRing.enabled = val
						module:ApplyMouseEffectSettings()
					end,
				},
				mouseRingSize = {
					type = 'slider',
					name = 'Ring size',
					min = 16,
					max = 64,
					step = 1,
					order = 3,
					get = function()
						return DB.mouseRing.size
					end,
					set = function(_, val)
						DB.mouseRing.size = val
					end,
				},
				mouseRingAlpha = {
					type = 'slider',
					name = 'Ring opacity',
					min = 0.1,
					max = 1.0,
					step = 0.05,
					order = 4,
					get = function()
						return DB.mouseRing.alpha
					end,
					set = function(_, val)
						DB.mouseRing.alpha = val
					end,
				},
			}, width)
			ringSub:SetHeight(ringH)
			totalY = totalY + ringH + SPACING

			-- ---- Circle style picker ----
			local styleLabel = contentFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			styleLabel:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)
			styleLabel:SetText('Ring style')
			styleLabel:SetTextColor(1, 0.82, 0)
			totalY = totalY + 14 + SPACING

			local styleCount = module:GetCircleStyleCount()
			local imgSize = 48
			local imgPad = 8
			local styleRow = CreateFrame('Frame', nil, contentFrame)
			styleRow:SetSize(width, imgSize + 4)
			styleRow:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)

			local selectedBorder = CreateFrame('Frame', nil, styleRow, BackdropTemplateMixin and 'BackdropTemplate')
			selectedBorder:SetBackdrop({
				edgeFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
				edgeSize = 2,
			})
			selectedBorder:SetBackdropBorderColor(0, 0.7, 1, 1)
			selectedBorder:SetFrameLevel(10)
			selectedBorder:Hide()

			local function SelectStyleBtn(btn)
				selectedBorder:ClearAllPoints()
				selectedBorder:SetPoint('TOPLEFT', btn, 'TOPLEFT', -3, 3)
				selectedBorder:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', 3, -3)
				selectedBorder:Show()
			end

			local styleBtns = {}
			for i = 1, styleCount do
				local tex = module:GetCircleStyleImage(i)
				local coords = module:GetCircleStyleImageCoords(i)

				local btn = CreateFrame('Button', nil, styleRow)
				btn:SetSize(imgSize + 4, imgSize + 4)
				btn:SetPoint('LEFT', styleRow, 'LEFT', (i - 1) * (imgSize + imgPad), 0)

				local icon = btn:CreateTexture(nil, 'ARTWORK')
				icon:SetPoint('CENTER')
				icon:SetSize(imgSize, imgSize)
				if tex and tex ~= '' then
					icon:SetTexture(tex)
					if coords then
						icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
					end
				end

				local hl = btn:CreateTexture(nil, 'HIGHLIGHT')
				hl:SetAllPoints()
				hl:SetColorTexture(1, 1, 1, 0.15)
				btn:SetHighlightTexture(hl)

				local styleNum = i
				btn:SetScript('OnClick', function()
					DB.mouseRing.circleStyle = styleNum
					module:UpdateCircleStyle()
					SelectStyleBtn(btn)
				end)
				btn:SetScript('OnEnter', function(self)
					GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
					GameTooltip:SetText('Style ' .. styleNum, 1, 1, 1)
					GameTooltip:Show()
				end)
				btn:SetScript('OnLeave', function()
					GameTooltip:Hide()
				end)

				styleBtns[i] = btn
			end

			local currentStyle = DB.mouseRing.circleStyle or 1
			if styleBtns[currentStyle] then
				SelectStyleBtn(styleBtns[currentStyle])
			end
			totalY = totalY + imgSize + 4 + SPACING

			-- ---- Mouse Trail section ----
			local trailSub = CreateFrame('Frame', nil, contentFrame)
			trailSub:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)
			trailSub:SetSize(width, 1)

			local _, trailH = LibAT.UI.BuildWidgets(trailSub, {
				mouseTrailHeader = {
					type = 'header',
					name = 'Mouse Trail',
					order = 1,
				},
				mouseTrailEnabled = {
					type = 'checkbox',
					name = 'Enable mouse trail',
					desc = 'Shows a particle trail behind your mouse cursor',
					order = 2,
					get = function()
						return DB.mouseTrail.enabled
					end,
					set = function(_, val)
						DB.mouseTrail.enabled = val
						module:ApplyMouseEffectSettings()
					end,
				},
				mouseTrailDensity = {
					type = 'dropdown',
					name = 'Trail density',
					order = 3,
					values = {
						['low'] = 'Low',
						['medium'] = 'Medium',
						['high'] = 'High',
					},
					get = function()
						return DB.mouseTrail.density
					end,
					set = function(_, val)
						DB.mouseTrail.density = val
					end,
				},
				mouseTrailSize = {
					type = 'slider',
					name = 'Trail particle size',
					min = 4,
					max = 16,
					step = 1,
					order = 4,
					get = function()
						return DB.mouseTrail.size
					end,
					set = function(_, val)
						DB.mouseTrail.size = val
					end,
				},
			}, width)
			trailSub:SetHeight(trailH)
			totalY = totalY + trailH + SPACING

			-- ---- Loot Alerts section (horizontal checkboxes) ----
			local lootSub = CreateFrame('Frame', nil, contentFrame)
			lootSub:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)
			lootSub:SetSize(width, 1)

			local _, lootHeaderH = LibAT.UI.BuildWidgets(lootSub, {
				lootHeader = {
					type = 'header',
					name = 'Loot Alerts',
					order = 1,
				},
			}, width)

			-- Three checkboxes side by side below the header
			local lootDefs = {
				{
					label = 'Show popup',
					get = function()
						return DB.lootAlertPopup
					end,
					set = function(v)
						DB.lootAlertPopup = v
					end,
				},
				{
					label = 'Show in chat',
					get = function()
						return DB.lootAlertChat
					end,
					set = function(v)
						DB.lootAlertChat = v
					end,
				},
				{
					label = 'Play sound',
					get = function()
						return DB.lootAlertSound
					end,
					set = function(v)
						DB.lootAlertSound = v
					end,
				},
			}
			local colW = math.floor(width / #lootDefs)
			for i, def in ipairs(lootDefs) do
				local cb = LibAT.UI.CreateCheckbox(lootSub, def.label)
				cb:SetPoint('TOPLEFT', lootSub, 'TOPLEFT', (i - 1) * colW, -(lootHeaderH + SPACING))
				cb:SetChecked(def.get())
				cb:SetScript('OnClick', function(self)
					def.set(self:GetChecked())
				end)
			end

			local lootTotalH = lootHeaderH + SPACING + 22
			lootSub:SetHeight(lootTotalH)
			totalY = totalY + lootTotalH + SPACING

			-- ---- Decor Merchant section ----
			local decorSub = CreateFrame('Frame', nil, contentFrame)
			decorSub:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)
			decorSub:SetSize(width, 1)

			local _, decorH = LibAT.UI.BuildWidgets(decorSub, {
				decorHeader = {
					type = 'header',
					name = 'Decor Merchant',
					order = 1,
				},
				decorMerchantBulkBuy = {
					type = 'checkbox',
					name = 'Enable bulk buy',
					desc = 'Adds a bulk buy option to the decor merchant',
					order = 2,
					get = function()
						return DB.decorMerchantBulkBuy
					end,
					set = function(_, val)
						DB.decorMerchantBulkBuy = val
					end,
				},
			}, width)
			decorSub:SetHeight(decorH)
			totalY = totalY + decorH + SPACING

			contentFrame.totalHeight = totalY
		end,
	})
end

function module:OnDisable()
	-- Restore default behavior for all enhancement elements
	module:RestoreDecorMerchant()
	module:RestoreLootAlertPopup()
	module:RestoreMouseEffects()
end
