local SUI = SUI

-- SpartanUI's options window draws its own widgets (Core/Options), so AceGUI is no longer
-- restyled globally; other addons keep their own look. The 'Ace3' skin stays registered
-- because SpartanUI buttons look up their colors by that name.

---@param optTable AceConfig.OptionsTable
local function Options(optTable) end

SUI.Skins:Register('Ace3', function() end, nil, Options)
