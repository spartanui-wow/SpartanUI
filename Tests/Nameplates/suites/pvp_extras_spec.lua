-- @runtime luals
local M, H = ...
local P
local saved = {}
local names = { 'GetArenaOpponentSpec', 'GetSpecializationInfoByID', 'UnitFrameUtil', 'GetNumBattlefieldScores', 'GetBattlefieldScore', 'IsActiveBattlefieldArena', 'GetSpecializationInfoForClassID' }
local function Source()
	local token = M.ShowPlate({ name = 'Enemy', isPlayer = true, canAttack = true, class = 'PRIEST' })
	local src = P.Source.NewLive(token)
	src.ArenaIndexPlain = function()
		return 1
	end
	return src
end
local function Icon(source, src)
	local texture = UIParent:CreateTexture()
	P.IconParts.SOURCES[source].Fill({ texture = texture, spec = {}, plate = { facts = {} } }, src)
	return texture
end

describe('PvP extras', function()
	before_each(function()
		for _, key in ipairs(names) do
			saved[key] = _G[key]
		end
		P = H.FreshCore()
		M.Login('NameplatesTestHost')
		GetArenaOpponentSpec = function()
			return 257, 2
		end
		GetSpecializationInfoByID = function(id)
			assert.equal(id, 257)
			return id, 'Holy', '', 12345, 'HEALER'
		end
		IsActiveBattlefieldArena = function()
			return true
		end
		UnitFrameUtil = nil
	end)
	after_each(function()
		M.SetRestricted(false)
		for _, key in ipairs(names) do
			_G[key] = saved[key]
		end
	end)
	it('reads plain arena specs and healer marks on supported clients', function()
		local src = Source()
		if P.Caps:Client() == 'era' then
			assert.is_nil(src:SpecNamePlain())
			return
		end
		assert.equal(src:SpecNamePlain(), 'Holy')
		assert.equal(src:SpecIconPlain(), 12345)
		assert.matches(src:RoleIconPlain(), 'Spell_Holy_Heal')
	end)
	it('applies hidden delegate outputs only to display sinks', function()
		if P.Caps:Client() == 'era' then
			return
		end
		UnitFrameUtil = {
			GetArenaOpponentSpecDisplayInfo = function(index, textures)
				assert.equal(index, 1)
				assert.equal(textures.DAMAGER, '')
				return { specName = M.S.Wrap('Holy'), specIcon = M.S.Wrap(777), hasSpec = M.S.Wrap(true), roleIconTexture = M.S.Wrap(textures.HEALER), showRoleIcon = M.S.Wrap(true) }
			end,
		}
		GetArenaOpponentSpec = function()
			error('raw secret spec must not be read')
		end
		local src = Source()
		local spec, role = Icon('specIcon', src), Icon('roleIcon', src)
		assert.equal(M.S.Reveal(M.Get(spec, 'texture')), 777)
		assert.is_true(M.Get(role, 'alphaSecret'))
		assert.equal(M.Get(role, 'alpha'), 1)
		local text = UIParent:CreateFontString()
		P.TextParts.SOURCES.specName.Fill({ text = text }, src)
		assert.equal(M.S.Reveal(M.Get(text, 'text')), 'Holy')
	end)
	it('does not compare a hidden raw spec when no delegate exists', function()
		if P.Caps:Client() == 'era' then
			return
		end
		GetArenaOpponentSpec = function()
			return M.S.Wrap(257), M.S.Wrap(2)
		end
		GetNumBattlefieldScores = function()
			return 0
		end
		local src = Source()
		assert.no_errors(function()
			src:SpecNamePlain()
			src:RoleIconPlain()
		end)
		assert.is_nil(src:SpecNamePlain())
	end)
	it('stops scores at the first hidden row even when its name is readable', function()
		if not P.Caps:Get('secrets') then
			return
		end
		local old = C_PvP.GetScoreInfo
		local reads = 0
		C_PvP.GetScoreInfo = function(i)
			reads = reads + 1
			if i == 1 then
				return { name = 'Other', talentSpec = 'Frost', damageDone = M.S.Wrap(10) }
			end
			return { name = 'Enemy', talentSpec = 'Holy' }
		end
		GetArenaOpponentSpec = function()
			return nil
		end
		GetNumBattlefieldScores = function()
			return 2
		end
		assert.is_nil(Source():SpecNamePlain())
		assert.equal(reads, 1)
		C_PvP.GetScoreInfo = old
	end)
	it('uses the unit role display delegate when no arena index is available', function()
		if P.Caps:Client() == 'era' then
			return
		end
		UnitFrameUtil = {
			GetUnitRoleIconDisplayInfo = function(unit, options)
				assert.equal(options.displayRoleIcon, true)
				return { roleIconTexture = M.S.Wrap(options.textureMap.TANK), showRoleIcon = M.S.Wrap(true) }
			end,
		}
		GetArenaOpponentSpec = function()
			return nil
		end
		GetNumBattlefieldScores = function()
			return 0
		end
		local src = Source()
		src.ArenaIndexPlain = function()
			return nil
		end
		local role = Icon('roleIcon', src)
		assert.is_true(M.Get(role, 'alphaSecret'))
		assert.matches(M.S.Reveal(M.Get(role, 'texture')), 'DefensiveStance')
	end)
	it('uses plain legacy scores for spec names, icons, and roles', function()
		if P.Caps:Get('secrets') or P.Caps:Client() == 'era' then
			return
		end
		local oldCount = C_SpecializationInfo.GetNumSpecializationsForClassID
		C_SpecializationInfo.GetNumSpecializationsForClassID = function()
			return 1
		end
		GetSpecializationInfoForClassID = function(class, index)
			assert.equal(class, 5)
			assert.equal(index, 1)
			return 257, 'Holy', '', 12345, 'HEALER'
		end
		GetArenaOpponentSpec = function()
			return nil
		end
		GetNumBattlefieldScores = function()
			return 1
		end
		GetBattlefieldScore = function()
			return 'Enemy', 0, 0, 0, 0, 0, '', '', '', 0, 0, 0, 0, 0, 0, 'Holy'
		end
		local src = Source()
		assert.equal(src:SpecNamePlain(), 'Holy')
		assert.equal(src:SpecIconPlain(), 12345)
		assert.matches(src:RoleIconPlain(), 'Spell_Holy_Heal')
		C_SpecializationInfo.GetNumSpecializationsForClassID = oldCount
	end)
	it('keeps marks off NPCs and friendly players', function()
		for _, fields in ipairs({ { isPlayer = false, canAttack = true }, { isPlayer = true, canAttack = false } }) do
			local token = M.ShowPlate(fields)
			local src = P.Source.NewLive(token)
			src.ArenaIndexPlain = function()
				return 1
			end
			assert.is_nil(src:SpecNamePlain())
			assert.is_false(src:ShowRoleIconSecret())
		end
	end)
	it('probes Forever arenas instead of trusting the presence of arena UI', function()
		if P.Caps:Client() ~= 'forever' then
			return
		end
		IsActiveBattlefieldArena = function()
			return false
		end
		assert.is_false(P.Source.ArenasAvailablePlain())
		assert.is_nil(Source():SpecNamePlain())
	end)
	it('draws sample specs and roles without live reads', function()
		local src = P.Source.NewSample({ specName = 'Holy', specIcon = 777, role = 'HEALER' })
		GetArenaOpponentSpec = function()
			error('preview live read')
		end
		GetNumBattlefieldScores = function()
			error('preview score read')
		end
		assert.equal(src:SpecNamePlain(), 'Holy')
		assert.equal(M.Get(Icon('specIcon', src), 'texture'), 777)
		assert.matches(M.Get(Icon('roleIcon', src), 'texture'), 'Spell_Holy_Heal')
		src:SetSample({ role = 'DAMAGER' })
		assert.equal(M.Get(Icon('roleIcon', src), 'alpha'), 0)
	end)
end)
