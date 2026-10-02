---@class SUI
local SUI = SUI
local L = SUI.L

-- Releases worth showing off. A hero opens What's new by itself the first time a player logs in on
-- that version or a later one; releases without a hero only add to the What's new count. The
-- picture is one 2:1 image (a setup card works) or a list of them: the first is drawn large, the
-- next two stacked beside it, each cut to its lower part where the bars and frames are.
---@alias SUI.WhatsNewHero {title: string, text?: string, art?: string|string[], action?: {text?: string, step?: string, options?: string|fun()}}
---@type table<string, SUI.WhatsNewHero|SUI.WhatsNewHero[]>
SUI.WhatsNewHeroes = {
	-- A release can show more than one hero: a list draws them one after another
	['8.2.0'] = {
		{
			title = L['Three new styles to celebrate WoW Forever'],
			text = L['Voyager, Grove and Observatory bring painted art to your bars, minimap, frames and windows. Each one can put the minimap in the bar or at the top right.'],
			art = {
				'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Atlas',
				'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Boughs',
				'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Meridian',
			},
			action = { text = L['See the looks'], step = 'theme' },
		},
		{
			title = L['Messenger: your whispers as conversations'],
			text = L['Every whisper and Battle.net chat gets its own conversation, with its history, nicknames, pop-out windows and an alert when a group chat says your name. Already use another whisper addon? Turn it off and Messenger takes over.'],
			art = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Hero_Messenger',
			action = {
				text = L['Open Messenger'],
				options = function()
					local messenger = SUI:GetModule('Messenger', true)
					if messenger and not messenger.Override and SUI:IsModuleEnabled('Messenger') and SUIMessenger_Toggle then
						SUIMessenger_Toggle()
					else
						SUI.Options:OpenTo({ 'Modules', 'Messenger' })
					end
				end,
			},
		},
	},
}
