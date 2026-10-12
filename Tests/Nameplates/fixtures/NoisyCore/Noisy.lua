local _, ns = ...

ns.frame = CreateFrame('Frame', 'NoisyCoreFrame', UIParent)
ns.frame:RegisterEvent('PLAYER_LOGIN')
hooksecurefunc(NamePlateDriverFrame, 'UpdateNamePlateOptions', function() end)
C_CVar.SetCVar('nameplateShowEnemies', '0')
ns.ticker = C_Timer.NewTicker(1, function() end)
