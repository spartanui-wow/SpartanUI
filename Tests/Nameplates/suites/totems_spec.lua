-- @runtime luals
local M, H = ...
local P = H.FreshCore()
M.Login('NameplatesTestHost')

describe('totem plates', function()
	it('keeps spell and NPC maps consistent and gates expansion entries', function()
		local count = 0
		for spell, row in pairs(P.Data.Totems.bySpell) do
			count = count + 1
			assert.equal(spell, row.spellID)
			assert.equal(P.Data.Totems.byNPC[row.npcID], row)
			assert.truthy(row.rank >= 1)
			assert.matches(row.icon, 'Interface')
		end
		assert.truthy(count >= 40)
		assert.is_nil(P.Data.Totems:ForNPC(61245, 'era'))
		assert.equal(P.Data.Totems:ForNPC(61245, 'mists').spellID, 108269)
		assert.is_nil(P.Data.Totems:ForNPC(15438, 'tbc'), 'the elemental is not its totem')
	end)
	it('reads a known readable totem without using its name', function()
		local token = M.ShowPlate({ npcID = 5925, name = 'Localized name' })
		local src = P.Source.NewLive(token)
		assert.matches(src:TotemIconPlain(), 'GroundingTotem')
		assert.is_nil(P.Source.NewLive(M.ShowPlate({ npcID = 123456, playerControlled = true })):TotemIconPlain())
	end)
	it('does not identify another player totem through hidden identity', function()
		local token = M.ShowPlate({ npcID = 5925 })
		M.SetRestricted(true, nil, true)
		local src = P.Source.NewLive(token)
		assert.is_nil(src:CreatureIDPlain())
		assert.is_nil(src:TotemIconPlain())
		M.SetRestricted(false)
	end)
	it('uses own active totem data only after minion and owner checks', function()
		if not P.Caps:Get('secrets') then
			return
		end
		local minion, controlled, owned, info = UnitIsMinion, UnitPlayerControlled, UnitIsOwnerOrControllerOfUnit, GetTotemInfo
		local token = M.ShowPlate({ name = 'My totem' })
		local src = P.Source.NewLive(token)
		src.CreatureIDPlain = function()
			return nil
		end
		UnitIsMinion = function()
			return true
		end
		UnitPlayerControlled = function()
			return true
		end
		UnitIsOwnerOrControllerOfUnit = function()
			return true
		end
		GetTotemInfo = function(slot)
			return slot == 1, 'My totem', 0, 10, 12345
		end
		assert.equal(src:TotemIconPlain(), 12345)
		UnitIsOwnerOrControllerOfUnit = function()
			return false
		end
		assert.is_nil(src:TotemIconPlain())
		UnitIsOwnerOrControllerOfUnit = function()
			return true
		end
		GetTotemInfo = function()
			return M.S.Wrap(true), M.S.Wrap('My totem'), 0, 10, M.S.Wrap(12345)
		end
		assert.is_nil(src:TotemIconPlain())
		UnitIsMinion, UnitPlayerControlled, UnitIsOwnerOrControllerOfUnit, GetTotemInfo = minion, controlled, owned, info
	end)
	it('draws a large sample icon and clears the previous texture on a non-totem', function()
		local texture = UIParent:CreateTexture()
		local widget = { texture = texture, spec = {}, plate = { facts = {} } }
		local src = P.Source.NewSample({ totemIcon = 777 })
		P.IconParts.SOURCES.totem.Fill(widget, src)
		assert.equal(M.Get(texture, 'texture'), 777)
		assert.is_true(M.Get(texture, 'shown'))
		src:SetSample({})
		P.IconParts.SOURCES.totem.Fill(widget, src)
		assert.is_false(M.Get(texture, 'shown'))
	end)
end)
