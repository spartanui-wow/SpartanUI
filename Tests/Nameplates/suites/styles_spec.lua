-- @runtime lua51
-- Styles (plan 5.1, 5.2, 6.6, contracts 6): every built-in passes the import validator untouched,
-- the merge layers (base, host look, overlay, situation) stack in order, overlays add, remove and
-- change parts, lists are replaced whole, removed parts hand their anchors on, and the resolve
-- cache is dropped exactly when a change message says the look may differ.
local M, H = ...

if not H.ModuleExists() then
	describe('styles', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local P = H.FreshCore()
local Styles = P.Styles
local Schema, Registry, Merge = Styles.Schema, Styles.Registry, Styles.Merge
local Store = P.Store

-- The LibAT stand-in answers every call with nothing; give the token fallbacks plain values
P.services.GetAccent = function()
	return 0.2, 0.4, 0.6
end
P.services.FontPath = function()
	return 'Fonts\\Fallback.ttf'
end

local BUILTINS = { 'clean', 'namesOnly', 'mini' }

local function Reset()
	Store:Set('tweaks', nil)
	P.API:SetHostLook(nil)
	Merge:Invalidate()
end

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

describe('styles: built-ins', function()
	for _, id in ipairs(BUILTINS) do
		it(id .. ' passes the import validator with nothing dropped, clamped or fixed', function()
			local style = Registry:Get(id)
			assert.not_nil(style, id .. ' is registered')
			local cleaned, report, reason = Schema:ValidateStyle(Schema:Upgrade(style))
			assert.not_nil(cleaned, 'rejected: ' .. tostring(reason))
			assert.equal(report.dropped, 0, 'dropped: ' .. table.concat(report.droppedKeys, ', '))
			assert.equal(report.clamped, 0, 'clamped')
			assert.equal(report.fixed, 0, 'fixed')
			assert.empty(report.errors, 'errors')
			assert.equal(Count(cleaned.parts), Count(style.parts), 'every part survives')
		end)

		it(id .. ' resolves for every kind of plate and size without anchor loops', function()
			for _, kind in ipairs(P.Situation.KINDS) do
				for _, size in ipairs(Schema.SIZES) do
					local resolved = Merge.ResolveRaw(Registry:Get(id), nil, kind, size, nil)
					assert.not_nil(resolved, kind .. ' ' .. size)
					assert.is_nil(Schema:FindCycle(resolved.parts), 'loop in ' .. kind)
					assert.equal(resolved.width, math.floor(resolved.width), 'whole pixels')
					local seen = {}
					for _, partId in ipairs(resolved.order) do
						local anchor = resolved.parts[partId].anchor
						local target = anchor and anchor[2]
						if target and target ~= 'plate' then
							assert.is_true(seen[target] == true, partId .. ' is laid out before its anchor ' .. target)
						end
						seen[partId] = true
					end
				end
			end
		end)
	end

	it('uses only known candidate keys in the aura rows', function()
		local rows = P.AuraRows and P.AuraRows.ROWS
		assert.not_nil(rows, 'P.AuraRows.ROWS')
		for rowId, row in pairs(rows) do
			for _, group in ipairs(row.groups or {}) do
				for key in pairs(group.candidates or {}) do
					assert.is_true(Schema.CANDIDATE_KEYS[key] == true, rowId .. '.' .. tostring(group.key) .. ' uses unknown key ' .. tostring(key))
				end
			end
		end
	end)

	it('drops unknown candidate keys before they reach the game', function()
		local cleaned, dropped = P.AuraRows.CleanCandidates({ isStealable = true, notAKey = true })
		assert.same(cleaned, { isStealable = true })
		assert.same(dropped, { 'notAKey' })
	end)

	it('lists built-ins in gallery order and hides internal ones unless asked', function()
		local ids = {}
		for _, item in ipairs(Registry:List()) do
			ids[#ids + 1] = item.id
		end
		assert.contains(ids, 'clean')
		assert.not_contains(ids, 'mini')
		assert.not_contains(ids, 'namesOnly')
		local all = {}
		for _, item in ipairs(Registry:List(true)) do
			all[#all + 1] = item.id
		end
		assert.contains(all, 'mini')
	end)
end)

describe('styles: deep merge', function()
	it('merges records by key and replaces lists whole', function()
		local out = Merge.Deep({ font = { size = 10, flags = 'OUTLINE' }, anchor = { 'TOP', 'plate', 'TOP', 0, 2 } }, { font = { size = 12 }, anchor = { 'LEFT', 'plate' } })
		assert.same(out.font, { size = 12, flags = 'OUTLINE' })
		assert.same(out.anchor, { 'LEFT', 'plate' }, 'no leftover entries from the longer list')
	end)

	it('never changes its inputs', function()
		local base = { a = { b = 1 } }
		local over = { a = { c = 2 } }
		local out = Merge.Deep(base, over)
		out.a.b = 9
		assert.same(base, { a = { b = 1 } })
		assert.same(over, { a = { c = 2 } })
	end)
end)

describe('styles: layers', function()
	before_each(Reset)

	it('fills part defaults and resolves tokens to plain values', function()
		local resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.equal(resolved.width, 132)
		assert.equal(resolved.height, 10)
		local health = resolved.parts.health
		assert.equal(health.texture, 'Nameplates Flat', '$bar')
		assert.same(health.border.color, { 0, 0, 0, 1 }, '$ink')
		assert.same(health.bg, { 0, 0, 0, 0.6 }, '$shade')
		assert.is_true(health.interpolate, 'filled from the bar defaults')
		assert.equal(resolved.parts.name.font.face, 'Fonts\\Fallback.ttf', '$font falls back')
		assert.same(resolved.parts.arrows.color, { 0.2, 0.4, 0.6, 1 }, '$accent falls back')
		assert.equal(resolved.parts.hp.font.flags, 'OUTLINE', 'a partial font keeps the default flags')
	end)

	it('lets the host look fill $host tokens', function()
		P.API:SetHostLook({ font = 'Fonts\\Host.ttf', accent = { 1, 0, 0, 1 }, tokens = { shade = { 0.1, 0.1, 0.1, 0.9 } } })
		local resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.equal(resolved.parts.name.font.face, 'Fonts\\Host.ttf')
		assert.same(resolved.parts.arrows.color, { 1, 0, 0, 1 })
		assert.same(resolved.parts.health.bg, { 0, 0, 0, 0.6 }, 'a style that sets shade itself keeps it')
		assert.same(resolved.tokens.accent, { 1, 0, 0, 1 })
	end)

	it('applies the overlay over the base and the host look', function()
		P.API:SetHostLook({ font = 'Fonts\\Host.ttf' })
		Store:Set('tweaks.clean', {
			changes = {
				plate = { sizes = { medium = { 150, 12 } } },
				parts = { name = { font = { size = 14 } }, health = { anchor = { 'TOP', 'plate', 'TOP', 0, -1 } } },
				tokens = { ink = { 1, 1, 1 } },
			},
		})
		local resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.equal(resolved.width, 150)
		assert.equal(resolved.height, 12)
		assert.equal(resolved.parts.name.font.size, 14)
		assert.equal(resolved.parts.name.font.face, 'Fonts\\Host.ttf', 'the host font stays under the change')
		assert.equal(resolved.parts.name.font.flags, 'OUTLINE')
		assert.same(resolved.parts.health.anchor, { 'TOP', 'plate', 'TOP', 0, -1 })
		assert.same(resolved.parts.health.border.color, { 1, 1, 1 }, 'a token list is replaced whole')
		assert.equal(Merge:Resolve('clean', 'enemyNPC', 'small').width, 112, 'other sizes keep the base')
	end)

	it('adds parts with defaults filled', function()
		Store:Set('tweaks.clean.add.level', { order = 33, kind = 'text', source = 'level', anchor = { 'LEFT', 'health', 'RIGHT', 4, 0 } })
		local resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		local level = resolved.parts.level
		assert.not_nil(level)
		assert.equal(level.justify, 'CENTER', 'default filled')
		assert.equal(level.font.size, 10)
		assert.contains(resolved.order, 'level')
	end)

	it('removes parts and hands their anchor to the parts anchored to them', function()
		Store:Set('tweaks.clean.remove.name', true)
		local resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.is_nil(resolved.parts.name)
		-- mine sat 2 px above the name, which sat 2 px above the health bar
		assert.same(resolved.parts.mine.anchor, { 'BOTTOMLEFT', 'health', 'TOPLEFT', 0, 4 })
		Store:Set('tweaks.clean.remove', { health = true })
		resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.is_nil(resolved.parts.health)
		for id, spec in pairs(resolved.parts) do
			local target = spec.anchor and spec.anchor[2]
			assert.is_true(target == nil or target == 'plate' or resolved.parts[target] ~= nil, id .. ' points at a part that is gone')
		end
	end)

	it('treats a hidden part like a removed one', function()
		Store:Set('tweaks.clean.changes.parts.name.hidden', true)
		local resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.is_nil(resolved.parts.name)
		assert.is_true(resolved.hidden.name)
		assert.equal(resolved.parts.mine.anchor[2], 'health')
	end)

	it('applies the style situation, then the overlay situation, adding hide lists up', function()
		local plain = Merge:Resolve('clean', 'friendlyPlayer', 'medium')
		assert.is_nil(plain.parts.health)
		assert.is_nil(plain.parts.cast)
		assert.equal(plain.parts.name.font.size, 12)
		Store:Set('tweaks.clean.situations.friendlyPlayer', { hide = { 'marker' }, parts = { name = { font = { size = 16 } } } })
		local resolved = Merge:Resolve('clean', 'friendlyPlayer', 'medium')
		assert.is_true(resolved.hidden.health, 'the style hide list is kept')
		assert.is_true(resolved.hidden.marker, 'the overlay hide list is added')
		assert.equal(resolved.parts.name.font.size, 16)
		assert.not_nil(Merge:Resolve('clean', 'enemyNPC', 'medium').parts.marker, 'other kinds are untouched')
	end)

	it('breaks an anchor loop made by an overlay and keeps both parts', function()
		Store:Set('tweaks.clean.changes.parts', { hp = { anchor = { 'LEFT', 'forces', 'RIGHT', 0, 0 } }, forces = { anchor = { 'LEFT', 'hp', 'RIGHT', 0, 0 } } })
		local resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.not_nil(resolved.parts.hp)
		assert.not_nil(resolved.parts.forces)
		assert.is_nil(Schema:FindCycle(resolved.parts))
		assert.is_true(resolved.parts.hp.anchor[2] == 'plate' or resolved.parts.forces.anchor[2] == 'plate')
	end)

	it('falls back to Clean for an unknown style id', function()
		local resolved = Merge:Resolve('noSuchStyle', 'enemyNPC', 'medium')
		assert.equal(resolved.id, 'clean')
	end)

	it('works out click and stacking areas with padding, or takes a rect by hand', function()
		local resolved = Merge.ResolveRaw(Registry:Get('mini'), nil, 'enemyNPC', 'medium', nil)
		local click = resolved.regions.click
		-- the 60 x 5 bar plus the 3 px cast bar 1 px below it, padded 4 on every side
		assert.equal(click.left, -34)
		assert.equal(click.right, 34)
		assert.equal(click.top, 7)
		assert.equal(click.bottom, -11)
		local w, h = Merge.SizeForRect(click)
		assert.equal(w, 68)
		assert.equal(h, 18)
		local byHand =
			Merge.ResolveRaw(Registry:Get('mini'), { changes = { regions = { click = { auto = false, rect = { left = -50, right = 40, top = 10, bottom = -10 } } } } }, 'enemyNPC', 'medium', nil)
		assert.same(byHand.regions.click, { left = -50, right = 40, top = 10, bottom = -10 })
		w = Merge.SizeForRect(byHand.regions.click)
		assert.equal(w, 100, 'the base plate covers the wider side on both sides')
	end)
end)

describe('styles: cache', function()
	before_each(Reset)

	it('returns the same resolved style until something changes', function()
		local a = Merge:Resolve('clean', 'enemyNPC', 'medium')
		local b = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.is_true(rawequal(a, b))
		assert.is_false(rawequal(a, Merge:Resolve('clean', 'enemyNPC', 'large')), 'sizes are cached apart')
		assert.is_false(rawequal(a, Merge:Resolve('clean', 'friendlyPlayer', 'medium')), 'kinds are cached apart')
	end)

	it('drops the cache and changes the key on look, size and aura changes', function()
		local a = Merge:Resolve('clean', 'enemyNPC', 'medium')
		Store:Set('tweaks.clean.changes.parts.name.font.size', 13)
		local b = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.is_false(rawequal(a, b))
		assert.not_equal(a.key, b.key)
		assert.equal(b.parts.name.font.size, 13)
		Store:Set('size', 'large')
		local c = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.not_equal(b.key, c.key)
		Store:Set('size', nil)
		local d = Merge:Resolve('clean', 'enemyNPC', 'medium')
		Store:Set('auras.myDebuffs.on', false)
		assert.not_equal(d.key, Merge:Resolve('clean', 'enemyNPC', 'medium').key, 'aura settings')
		Store:Set('auras', nil)
	end)

	it('keeps the cache for color-only and assignment-only changes', function()
		local a = Merge:Resolve('clean', 'enemyNPC', 'medium')
		Store:Set('scheme', 'class')
		Store:Set('modes.friendlyNPC', 'full')
		assert.is_true(rawequal(a, Merge:Resolve('clean', 'enemyNPC', 'medium')))
		Store:Set('scheme', nil)
		Store:Set('modes', nil)
	end)

	it('drops the cache when the host look or the style library changes', function()
		local a = Merge:Resolve('clean', 'enemyNPC', 'medium')
		P.API:SetHostLook({ font = 'Fonts\\Other.ttf' })
		local b = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.not_equal(a.key, b.key)
		assert.equal(b.parts.name.font.face, 'Fonts\\Other.ttf')
		local id = Registry:Save(Merge:Bake('clean'), 'My copy')
		assert.not_equal(b.key, Merge:Resolve('clean', 'enemyNPC', 'medium').key)
		Registry:Delete(id)
	end)

	it('drops the cache when a profile switch changes the overlay', function()
		Store:Set('tweaks.clean.changes.parts.name.font.size', 15)
		local a = Merge:Resolve('clean', 'enemyNPC', 'medium')
		Store:SetProfile('Bare')
		local b = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.not_equal(a.key, b.key)
		assert.equal(b.parts.name.font.size, 10)
		Store:SetProfile('Default')
		assert.equal(Merge:Resolve('clean', 'enemyNPC', 'medium').parts.name.font.size, 15)
	end)
end)

describe('styles: registry', function()
	before_each(Reset)

	it('resolves host to the host style that matches the look, else Clean', function()
		assert.equal(Registry:ResolveId('host'), 'clean')
		local base = Schema:Upgrade(Registry:Get('clean'))
		base.id = 'hostLook'
		base.name = 'Host look'
		base.matchesHost = true
		assert.is_true(P.API:RegisterStyle(base))
		assert.equal(Registry:ResolveId('host'), 'hostLook')
		assert.equal(Merge:Resolve('host', 'enemyNPC', 'medium').id, 'hostLook')
	end)

	it('refuses host styles that loop, that take a built-in id, or that come from a newer version', function()
		local looped = Schema:Upgrade(Registry:Get('mini'))
		looped.id = 'looped'
		looped.parts.marker.anchor = { 'LEFT', 'arrows', 'RIGHT', 0, 0 }
		looped.parts.arrows.anchor = { 'LEFT', 'marker', 'RIGHT', 0, 0 }
		local ok, reason = P.API:RegisterStyle(looped)
		assert.is_false(ok)
		assert.equal(reason, 'cycle')
		local taken = Schema:Upgrade(Registry:Get('mini'))
		ok, reason = P.API:RegisterStyle(taken)
		assert.is_false(ok)
		assert.equal(reason, 'badId')
		local newer = Schema:Upgrade(Registry:Get('mini'))
		newer.id = 'fromTheFuture'
		newer.schema = Schema.CURRENT + 1
		ok, reason = P.API:RegisterStyle(newer)
		assert.is_false(ok)
		assert.equal(reason, 'newer')
	end)

	it('bakes the base and overlay into a copy that keeps its tokens', function()
		Store:Set('tweaks.clean.changes.parts.name.font.size', 13)
		Store:Set('tweaks.clean.remove.forces', true)
		local baked = Merge:Bake('clean')
		assert.equal(baked.parts.name.font.size, 13)
		assert.is_nil(baked.parts.forces)
		assert.equal(baked.parts.health.texture, '$bar', 'tokens are kept for the copy')
		assert.equal(Registry:Get('clean').parts.name.font.size, 10, 'the built-in is untouched')
	end)

	it('saves, renames and deletes copies, and returns an upgraded copy of the saved base', function()
		local id = Registry:Save(Merge:Bake('clean'), 'Mine')
		assert.is_true(Registry:IsSaved(id))
		local style, source = Registry:Get(id)
		assert.equal(source, 'saved')
		assert.equal(style.id, id)
		assert.equal(style.name, 'Mine')
		assert.is_false(rawequal(style, P.db.global.styles[id].base), 'never the stored table itself')
		Registry:Rename(id, 'Renamed')
		assert.equal(Registry:Get(id).name, 'Renamed')
		assert.equal(Registry:ResolveId(id), id)
		Registry:Delete(id)
		assert.is_false(Registry:IsSaved(id))
		assert.equal(Registry:ResolveId(id), 'clean')
		assert.is_nil(P.db.global.styles, 'the empty library table is pruned')
	end)

	it('counts changes that no longer apply and knows when a style was changed', function()
		assert.is_false(Merge:HasChanges('clean'))
		Store:Set('tweaks.clean.changes.parts', { gone = { alpha = 0.5 }, name = { alpha = 0.5 } })
		Store:Set('tweaks.clean.remove', { alsoGone = true })
		assert.is_true(Merge:HasChanges('clean'))
		assert.equal(Merge:StaleChanges('clean'), 2)
	end)
end)

describe('styles: schema checks', function()
	it('drops unknown keys, clamps numbers and re-points anchors at missing parts', function()
		local cleaned, report = Schema:ValidateStyle({
			name = 'Test',
			wrong = 1,
			parts = {
				health = { kind = 'bar', source = 'health', height = 900, mystery = true },
				name = { kind = 'text', source = 'name', anchor = { 'BOTTOM', 'nowhere', 'TOP', 0, 2 } },
			},
		})
		assert.not_nil(cleaned)
		assert.equal(report.dropped, 2)
		assert.equal(report.clamped, 1)
		assert.equal(cleaned.parts.health.height, 128)
		assert.equal(report.fixed, 1)
		assert.equal(cleaned.parts.name.anchor[2], 'plate')
		assert.equal(cleaned.schema, Schema.CURRENT)
	end)

	it('rejects styles with no parts, no name, or a loop', function()
		local _, _, reason = Schema:ValidateStyle({ name = 'Empty', parts = {} })
		assert.equal(reason, 'noParts')
		_, _, reason = Schema:ValidateStyle({ parts = { a = { kind = 'icon' } } })
		assert.equal(reason, 'noName')
		_, _, reason = Schema:ValidateStyle({ name = 'Loop', parts = { a = { kind = 'icon', anchor = { 'LEFT', 'b', 'RIGHT' } }, b = { kind = 'icon', anchor = { 'LEFT', 'a', 'RIGHT' } } } })
		assert.equal(reason, 'cycle')
		_, _, reason = Schema:ValidateStyle('text')
		assert.equal(reason, 'notTable')
	end)

	it('upgrades copies and refuses data from a newer version', function()
		local style = { schema = 1, name = 'x' }
		local copy = Schema:Upgrade(style)
		assert.is_false(rawequal(copy, style))
		local none, why = Schema:Upgrade({ schema = Schema.CURRENT + 1 })
		assert.is_nil(none)
		assert.equal(why, 'newer')
		none, why = Schema:UpgradeOverlay({ schema = Schema.CURRENT + 1 })
		assert.is_nil(none)
		assert.equal(why, 'newer')
	end)

	it('checks overlays, keeping partial changes and dropping unknown sections', function()
		local cleaned, report = Schema:ValidateOverlay({ changes = { parts = { name = { font = { size = 99 } } }, nonsense = {} }, remove = { hp = true }, extra = 1 }, Registry:Get('clean').parts)
		assert.equal(cleaned.changes.parts.name.font.size, 40, 'clamped to the font range')
		assert.same(cleaned.remove, { hp = true })
		assert.equal(report.dropped, 2)
	end)
end)
