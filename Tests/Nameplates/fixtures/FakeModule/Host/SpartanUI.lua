local _, ns = ...
local SUI = SUI

-- A fixture host: finds the module the old file created, hands in a logger and adds options
local module = SUI:GetModule('Nameplates', true)
ns.hostFoundModule = module ~= nil
ns.hostLogger = SUI.logger:RegisterCategory('Nameplates')
SUI.Options:AddOptions({ type = 'group', name = 'Nameplates', args = {} }, 'Nameplates', 'Root')
if module then
	module.API = ns
end
