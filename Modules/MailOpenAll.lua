local SUI, L, print = SUI, SUI.L, SUI.print
local module = SUI:NewModule('MailOpenAll') ---@type SUI.Module
module.Displayname = L['Open all mail']
module.description = 'Quality of life update to the open all mail button'

local OpenButton = nil
module.RefreshMailTimer = nil

function module:OnInitialize()
	local defaults = {
		profile = {
			FirstLaunch = true,
			Silent = false,
			FreeSpace = 0,
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('MailOpenAll', defaults)
	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)

	-- Migrate old settings
	if SUI.DB.MailOpenAll then
		print('Mail enhancements DB Migration')
		module.DB = SUI:MergeData(module.DB, SUI.DB.MailOpenAll, true)
		SUI.DB.MailOpenAll = nil
	end
end

function module:OnEnable()
	module:BuildOptions()
	if SUI:IsModuleDisabled('MailOpenAll') then
		return
	end
	module:Enable()
end

function module:Enable()
	if not OpenButton then
		OpenButton = CreateFrame('Button', 'SUI_OpenAllMail', InboxFrame, 'UIPanelButtonTemplate')
		OpenButton:SetWidth(120)
		OpenButton:SetHeight(25)
		OpenButton:SetAllPoints(OpenAllMail)
		--button:SetPoint("CENTER", OpenAllMail, "TOP", 0, -42)
		OpenButton:SetText(OPEN_ALL_MAIL_BUTTON)
		OpenButton:SetFrameLevel(OpenButton:GetFrameLevel() + 1)
		OpenAllMail:Hide()
		Mixin(OpenButton, OpenAllMailMixin)

		function OpenButton:ProcessNextItem()
			local _, _, _, subject, money, CODAmount, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(self.mailIndex)
			if isGM or (CODAmount and CODAmount > 0) then
				self:AdvanceAndProcessNextItem()
				return
			end

			if money > 0 then
				if not module.DB.Silent then
					local moneyString = money > 0 and ' [' .. module:FormatMoney(money) .. ']' or ''
					local playerName
					if mailType == 'AHSuccess' or mailType == 'AHWon' then
						playerName = select(3, GetInboxInvoiceInfo(self.mailIndex))
						playerName = playerName and (' (' .. playerName .. ')')
					end
					SUI:Print(format('%s: %s%s%s', L['Mail'], subject or '', moneyString, (playerName or '')))
				end
				TakeInboxMoney(self.mailIndex)
				self.timeUntilNextRetrieval = 0.6
			elseif itemCount and itemCount > 0 then
				if not module.DB.Silent then
					SUI:Print(format('%s: %s', L['Mail'], subject or ''))
				end

				TakeInboxItem(self.mailIndex, self.attachmentIndex)
				self.timeUntilNextRetrieval = 0.6
			else
				self:AdvanceAndProcessNextItem()
			end
		end
		OpenButton:SetScript('OnLoad', OpenButton.OnLoad)
		OpenButton:SetScript('OnEvent', OpenButton.OnEvent)
		OpenButton:SetScript('OnClick', OpenButton.OnClick)
		OpenButton:SetScript('OnUpdate', OpenButton.OnUpdate)
		OpenButton:SetScript('OnHide', OpenButton.OnHide)
	end

	self:RegisterEvent('MAIL_SHOW')
end

function module:Disable()
	SUI:Print('Auto open mail disabled')
	OpenButton:Hide()
end

function module:MAIL_SHOW() end

function module:FormatMoney(money)
	local gold = floor(money / 10000)
	local silver = floor((money - gold * 10000) / 100)
	local copper = mod(money, 100)
	if gold > 0 then
		return format(GOLD_AMOUNT_TEXTURE .. ' ' .. SILVER_AMOUNT_TEXTURE .. ' ' .. COPPER_AMOUNT_TEXTURE, gold, 0, 0, silver, 0, 0, copper, 0, 0)
	elseif silver > 0 then
		return format(SILVER_AMOUNT_TEXTURE .. ' ' .. COPPER_AMOUNT_TEXTURE, silver, 0, 0, copper, 0, 0)
	else
		return format(COPPER_AMOUNT_TEXTURE, copper, 0, 0)
	end
end

function module:BuildOptions()
	SUI.opt.args['Modules'].args['MailOpenAll'] = {
		type = 'group',
		name = L['Open all mail'],
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			Silent = {
				name = L['Silently open mail'],
				type = 'toggle',
				order = 1,
				width = 'full',
				get = function(info)
					return module.DB.Silent
				end,
				set = function(info, val)
					module.DB.Silent = val
				end,
			},
			FreeSpace = {
				name = L['Bag free space to maintain'],
				type = 'range',
				order = 10,
				width = 'full',
				min = 0,
				max = 50,
				step = 1,
				set = function(info, val)
					module.DB.FreeSpace = val
				end,
				get = function(info)
					return module.DB.FreeSpace
				end,
			},
		},
	}
end
