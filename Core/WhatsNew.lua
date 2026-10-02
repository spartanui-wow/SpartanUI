---@class SUI
local SUI = SUI
local module = SUI:NewModule('Handler.WhatsNew') ---@type SUI.Module

-- Hands the release history (WhatsNew/Changelog.lua, generated from the commit log) and the
-- releases worth showing off (WhatsNew/Heroes.lua) to the setup window's What's new page.
function module:OnEnable()
	local reg = SUI.Setup and SUI.Setup.registration
	if not reg or not reg.AddWhatsNew or type(SUI.Changelog) ~= 'table' then
		return
	end
	local heroes = SUI.WhatsNewHeroes or {}
	for _, release in ipairs(SUI.Changelog) do
		local hero = heroes[release.version]
		-- A list of heroes is titled by its first one
		local lead = hero and (hero[1] or hero)
		local first = release.lines and release.lines[1]
		reg:AddWhatsNew(release.version, {
			title = (lead and lead.title) or (first and first.text) or ('SpartanUI ' .. release.version),
			date = release.date,
			lines = release.lines,
			fixes = release.fixes,
			hero = hero,
		})
	end
end
