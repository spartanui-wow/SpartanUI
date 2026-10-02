---@class SUI
local SUI = SUI
local L = SUI.L

-- Releases worth showing off. A hero opens What's new by itself the first time a player logs in on
-- that version or a later one; releases without a hero only add to the What's new count. The
-- picture is one 2:1 image (a setup card works) or a list of them: the first is drawn large, the
-- next two stacked beside it, each cut to its lower part where the bars and frames are.
---@type table<string, {title: string, text?: string, art?: string|string[], action?: {text?: string, step?: string, options?: string|fun()}}>
SUI.WhatsNewHeroes = {
	['8.2.0'] = {
		title = L['Three new styles to celebrate WoW Forever'],
		text = L['Voyager, Grove and Observatory bring painted art to your bars, minimap, frames and windows. Each one can put the minimap in the bar or at the top right.'],
		art = {
			'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Atlas',
			'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Boughs',
			'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Meridian',
		},
		action = { text = L['See the looks'], step = 'theme' },
	},
}
