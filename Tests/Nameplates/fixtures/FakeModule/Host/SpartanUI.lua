local _, ns = ...
local SUI = SUI

-- A fixture host: creates the module, hands in a logger and adds options
local module = SUI:NewModule('Nameplates')
ns.hostMadeModule = module ~= nil
ns.hostLogger = SUI.logger:RegisterCategory('Nameplates')
SUI.Options:AddOptions({ type = 'group', name = 'Nameplates', args = {} }, 'Nameplates', 'Root')
if module then
	module.API = ns
end
