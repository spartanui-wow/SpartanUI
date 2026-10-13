-- @runtime lua51
-- Last Tick on nameplates (plan 6.11, Phase 2): LastTick reaches the new engine's plates through
-- SpartanUI -> GetModule('Nameplates', true) -> .API:GetHealthBar(base) and draws on that bar.
-- When the engine does not draw a plate it keeps its old path (the old module's plate, then
-- Blizzard's health bar), and a plate the engine draws without a health bar gets no overlay
-- rather than Blizzard's hidden one.
local M, H = ...
local S = M.S

if not (H.ModuleExists() and H.Exists(H.hostFile) and H.Exists(HARNESS_ROOT .. 'Modules/LastTick/Hosts.lua')) then
	describe('LastTick hookup', function()
		pending('all', 'the nameplate module, its host or LastTick does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P, ns = H.FreshCore()
local SUI = H.LoadSpartanUIHost({ ns = ns })
local Merge = P.Styles.Merge

-- LastTick's own files, as LastTick\Load.xml loads them (the tracker and options are not needed)
rawset(SUI, 'UF', {
	FindStatusBarTexture = function()
		return 'Interface\\Buttons\\WHITE8X8'
	end,
})
for _, file in ipairs({ 'LastTick.lua', 'Overlay.lua', 'Hosts.lua' }) do
	H.LoadFile(HARNESS_ROOT .. 'Modules/LastTick/' .. file, 'SpartanUI', {})
end
local LastTick = SUI:GetModule('LastTick')
LastTick:OnInitialize()
local Hosts = LastTick.Hosts

local function Slot(token)
	return { key = token, unit = token, kind = 'plate' }
end

local function EnginePlate(token, base, styleId, kind)
	local plate = P.Plate.New(UIParent, false)
	plate:ApplyStyle(Merge:Resolve(styleId or 'clean', kind or 'enemyNPC', 'medium'))
	plate:Bind(token, P.Source.NewLive(token))
	-- What the Driver does when it binds a plate (its contract: byBase and bound)
	P.Driver.byBase[base] = plate
	P.Driver.bound[plate] = true
	return plate
end

local function Forget(base, plate)
	P.Driver.byBase[base] = nil
	if plate then
		P.Driver.bound[plate] = nil
		plate:Unbind()
	end
end

describe('LastTick hookup', function()
	it('finds the API through the SpartanUI module', function()
		local module = SUI:GetModule('Nameplates', true)
		assert.not_nil(module)
		assert.equal(module.API, P.API)
	end)

	it('draws on the new engine health bar when the engine draws the plate', function()
		local token, base = M.ShowPlate({ name = 'Gnoll', canAttack = true, reaction = 2, health = 400, healthMax = 1000 })
		local plate = EnginePlate(token, base)
		local bar = plate:GetHealthBar()
		assert.not_nil(bar)
		local slot = Slot(token)
		assert.is_true(Hosts:Prepare(slot))
		assert.equal(slot.bar, bar)
		assert.equal(slot.overlay.clip:GetParent(), bar, 'the marker hangs from our health bar')
		local health, maxHealth = 400, 1000
		if M.secrets then
			health, maxHealth = S.Wrap(health), S.Wrap(maxHealth)
		end
		slot.overlay:Show(health, maxHealth, 250)
		assert.is_true(M.Get(slot.overlay.clip, 'shown') == true)
		slot.overlay:Detach()
		Forget(base, plate)
		M.HidePlate(token)
	end)

	it('gives no overlay to a plate the engine draws without a health bar', function()
		local token, base = M.ShowPlate({ name = 'Friend', canAttack = false, reaction = 5, isPlayer = true })
		local plate = EnginePlate(token, base, 'namesOnly', 'friendlyPlayer')
		assert.is_nil(plate:GetHealthBar())
		local slot = Slot(token)
		assert.is_false(Hosts:Prepare(slot))
		assert.is_nil(slot.bar, "never Blizzard's hidden bar")
		Forget(base, plate)
		M.HidePlate(token)
	end)

	it('keeps the old module plate when the engine does not draw it', function()
		local token, base = M.ShowPlate({ name = 'Murloc', canAttack = true, reaction = 2 })
		local old = CreateFrame('Frame', nil, base)
		old.Health = CreateFrame('StatusBar', nil, old)
		old:Show()
		base.unitFrame = old
		local slot = Slot(token)
		assert.is_true(Hosts:Prepare(slot))
		assert.equal(slot.bar, old.Health)
		base.unitFrame = nil
		slot.overlay:Detach()
		M.HidePlate(token)
	end)

	it("falls back to Blizzard's bar when nothing else draws the plate", function()
		local token, base = M.ShowPlate({ name = 'Kobold', canAttack = true, reaction = 2 })
		-- A plate the engine keeps for this base but has not bound (hidden mode, or switched off)
		local idle = P.Plate.New(UIParent, false)
		idle:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		P.Driver.byBase[base] = idle
		local slot = Slot(token)
		assert.is_true(Hosts:Prepare(slot))
		local blizzard = base.UnitFrame.healthBar or (base.UnitFrame.HealthBarsContainer and base.UnitFrame.HealthBarsContainer.healthBar)
		assert.equal(slot.bar, blizzard)
		slot.overlay:Detach()
		Forget(base)
		M.HidePlate(token)
	end)

	it('keeps working when the module or its API is missing', function()
		local module = SUI:GetModule('Nameplates', true)
		local api = module.API
		local token, base = M.ShowPlate({ name = 'Harpy', canAttack = true, reaction = 2 })
		local plate = EnginePlate(token, base)
		module.API = nil
		local slot = Slot(token)
		assert.no_errors(function()
			Hosts:Prepare(slot)
		end)
		assert.not_equal(slot.bar, plate:GetHealthBar(), 'no API: the engine is not asked')
		module.API = {
			GetPlate = function()
				error('broken')
			end,
			GetHealthBar = function()
				error('broken')
			end,
		}
		slot = Slot(token)
		assert.no_errors(function()
			Hosts:Prepare(slot)
		end)
		module.API = api
		if slot.overlay then
			slot.overlay:Detach()
		end
		Forget(base, plate)
		M.HidePlate(token)
	end)
end)

describe('LastTick hookup: with the engine running', function()
	it('draws on the plate the Driver binds', function()
		P:Enable()
		local token, base = M.ShowPlate({ name = 'Ogre', canAttack = true, reaction = 2, health = 900, healthMax = 1000 })
		local plate = P.API:GetPlate(base)
		if not (plate and P.API:GetHealthBar(base)) then
			M.HidePlate(token)
			P:Disable()
			skip('the Driver does not draw a health bar on this plate in this build')
		end
		local slot = Slot(token)
		assert.is_true(Hosts:Prepare(slot))
		assert.equal(slot.bar, P.API:GetHealthBar(base))
		slot.overlay:Detach()
		M.HidePlate(token)
		assert.is_nil(P.API:GetPlate(base), 'a removed plate is not drawn any more')
		P:Disable()
	end)
end)
