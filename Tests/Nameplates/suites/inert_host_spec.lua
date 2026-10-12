-- @runtime lua51
-- "Inert when off" with the SpartanUI host loaded (Decision 21, 6.11): the old Nameplates module
-- exists, the tester switch is off, so neither the core nor the host may touch the game. Runs in its
-- own process so the core-only check stays independent.
local M, H = ...

local function where(rec)
	return (rec.event or rec.name or rec.label or '?') .. ' at ' .. (rec.where or '?')
end

describe('inert when off, with the SpartanUI host', function()
	if not H.ModuleExists() then
		pending('core and host', 'Modules/Nameplates/Load.xml does not exist yet')
		return
	end
	if not H.Exists(H.hostFile) then
		pending('core and host', 'Modules/Nameplates/Host/SpartanUI.lua does not exist yet')
		return
	end

	it('loads core and host, logs in, and leaves the game alone', function()
		H.LoadLibs()
		H.InstallLibATStub()
		H.InstallSUIMock({})
		M.ResetRecords()
		local ns = H.LoadCore({ libs = false, addonName = 'SpartanUI' })
		H.LoadSpartanUIHost({ ns = ns })
		M.Login('SpartanUI')
		M.Advance(5)
		local token = M.ShowPlate({ name = 'Mob' })
		M.Advance(1)
		M.HidePlate(token)
		local P = ns.Plates
		assert.is_false(P and P.enabled == true, 'the engine stays off while the tester switch is off')
		assert.empty(M.rec.events, 'registered game events', where)
		assert.empty(M.rec.hooks, 'installed hooksecurefunc', where)
		assert.empty(M.rec.cvarWrites, 'wrote CVars', where)
		local frames = {}
		for _, g in ipairs(M.rec.globals) do
			frames[#frames + 1] = g
		end
		assert.empty(frames, 'created named (global) frames', where)
		local missing = {}
		for key in pairs(H.suiMissing or {}) do
			missing[#missing + 1] = key
		end
		table.sort(missing)
		if #missing > 0 then
			io.write('@@NOTE the host read SUI fields the mock does not have: ' .. table.concat(missing, ', ') .. '\n')
		end
	end)
end)
