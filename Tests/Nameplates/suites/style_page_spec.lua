-- @runtime lua51
-- The Style page (plan 3.2 #1) and the style gallery (3.4): live cards drawn by the real renderer
-- on sample plates, hover to try, the right-click menu, Customize / Undo / Make a copy / Share /
-- Import, and the More settings that write the style's overlay (width, height, bar texture, font,
-- text size). Runs on every client; the picture hook is LibAT's art.draw (stubbed here).
local M, H = ...

if not H.ModuleExists() then
	describe('style page', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')

local P = H.FreshCore({
	host = {
		GetHostProfileName = function()
			return 'Default'
		end,
	},
})
local Registry, Merge, Schema = P.Styles.Registry, P.Styles.Merge, P.Styles.Schema
local Store, Gallery, Style = P.Store, P.Gallery, P.StylePage
local Options = P.Options

P.services.GetAccent = function()
	return 1, 1, 1
end
P.services.FontPath = function()
	return 'Fonts\\Test.ttf'
end

-- The host registers a "Match my look" style
local hostStyle = Merge:Bake('clean')
hostStyle.id = 'hosted'
hostStyle.name = 'Hosted look'
hostStyle.matchesHost = true
hostStyle.order = 5
assert(P.API:RegisterStyle(hostStyle))

local function Page()
	return P:BuildOptionsTable().args.style
end

local function Reset()
	Store:Set('tweaks', nil)
	Store:Set('styles', nil, 'global')
	Store:Reset('style')
	Store:Reset('size')
	Store:Set('assign', nil)
	Store:Set('when', nil)
	Gallery:SetHover(nil)
	Gallery:ClearPreview()
	Style.pending, Style.notice = nil, nil
end

local locked = false
P.Secret.IsRestricted = function()
	return locked
end

local function Values(cards)
	local out = {}
	for i, card in ipairs(cards) do
		out[i] = card.value
	end
	return out
end

local function ArtOn()
	LibAT.Capabilities = { cardArtDraw = 1 }
end

local function ArtOff()
	LibAT.Capabilities = false
end

local function Fresh()
	Reset()
	locked = false
	ArtOff()
end

----------------------------------------------------------------------------------------------------

local EM_DASH = '\226\128\148'
local BANNED_WORDS = { 'overlay', 'schema', 'cvar', 'token', 'payload', 'lsm', 'widget', 'elvui', 'weakauras', 'platynator' }

---Every text a page can show: names, descriptions and prompts (functions are called).
local function Texts(value, out, depth)
	out = out or {}
	depth = depth or 0
	if depth > 10 or type(value) ~= 'table' then
		return out
	end
	for key, item in pairs(value) do
		if key == 'name' or key == 'desc' or key == 'confirmText' then
			if type(item) == 'function' then
				local ok, text = pcall(item, {})
				item = ok and text or nil
			end
			if type(item) == 'string' then
				out[#out + 1] = item
			end
		elseif type(item) == 'table' and key ~= 'arg' and key ~= 'handler' then
			Texts(item, out, depth + 1)
		end
	end
	return out
end

---Copy of an options table without the two keys the settings window adds to AceConfig.
local function WithoutWindowKeys(value, depth)
	if type(value) ~= 'table' or (depth or 0) > 12 then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		if key ~= 'advanced' and key ~= 'primary' then
			out[key] = WithoutWindowKeys(item, (depth or 0) + 1)
		end
	end
	return out
end

describe('style page: wording and validity', function()
	before_each(Fresh)

	it('uses plain words: no em dashes, no symbols the game cannot draw, no jargon, no other addons', function()
		local page = Page()
		local texts = Texts(page)
		assert.truthy(#texts > 20, 'the page has text to check')
		-- The menu rows, the badges, the captions and the lines the page says after an action
		for _, item in ipairs(Gallery:MenuItems('clean')) do
			texts[#texts + 1] = item.text
		end
		for _, item in ipairs(Gallery:Cards()) do
			texts[#texts + 1] = item.title
			texts[#texts + 1] = item.caption
			texts[#texts + 1] = item.tag
		end
		for _, text in ipairs(texts) do
			assert.is_nil(text:find(EM_DASH, 1, true), 'em dash in: ' .. text)
			assert.is_nil(text:find('[\128-\255]'), 'non-ASCII character in: ' .. text)
			for _, word in ipairs(BANNED_WORDS) do
				assert.is_nil(text:lower():find(word, 1, true), word .. ' in: ' .. text)
			end
		end
	end)

	it('is a valid AceConfig table', function()
		local registry = LibStub('AceConfigRegistry-3.0')
		local root = { type = 'group', name = 'Test', args = { style = Page() } }
		registry:RegisterOptionsTable('NameplateStylePageTest', WithoutWindowKeys(root))
		local options = registry:GetOptionsTable('NameplateStylePageTest')('dialog', 'TestUI-1.0')
		assert.not_nil(options.args.style.args.style)
	end)
end)

describe('style page: layout', function()
	before_each(Fresh)
	it('has at most eight main controls and folds the rest', function()
		local page = Page()
		local main, folded = 0, 0
		for key, option in pairs(page.args) do
			if option.type ~= 'description' then
				if option.advanced then
					folded = folded + 1
				else
					main = main + 1
				end
			end
		end
		assert.truthy(main <= 8, 'main controls: ' .. main)
		assert.truthy(main >= 6, 'the page has its buttons')
		assert.equal(folded, 5, 'width, height, bar texture, font, text size')
		for _, key in ipairs({ 'width', 'height', 'barTexture', 'font', 'textSize' }) do
			assert.is_true(page.args[key].advanced, key .. ' is under More settings')
		end
	end)

	it('uses the host card grid for the style option and a dropdown otherwise', function()
		local gridPage = Page()
		assert.equal(gridPage.args.style.dialogControl, H.HostStub().widgets.cardGrid)
		assert.equal(type(gridPage.args.style.arg.onHover), 'function')
		assert.equal(type(gridPage.args.style.arg.onContext), 'function')
		local bare = H.FreshCore({ host = { widgets = {} } })
		local page = bare:BuildOptionsTable().args.style
		assert.is_nil(page.args.style.dialogControl)
		assert.equal(page.args.style.values().clean, 'Clean')
	end)

	it('makes Customize the primary button and shows Undo only with changes', function()
		local page = Page()
		assert.is_true(page.args.customize.primary)
		assert.is_true(page.args.undo.hidden(), 'no changes yet')
		Style.SetPlateSize(150, nil)
		assert.is_false(page.args.undo.hidden(), 'shown once the plate size changed')
		page.args.undo.func()
		assert.is_true(page.args.undo.hidden())
		assert.is_nil(Store:Get('tweaks'), 'the overlay is gone')
	end)

	it('opens the Customize and Sharing pages through the host', function()
		H.hostCalls = H.hostCalls or {}
		local calls = {}
		P.host.OpenOptions = function(page, key)
			calls[#calls + 1] = { page, key }
		end
		local page = Page()
		page.args.customize.func()
		page.args.import.func()
		page.args.share.func()
		assert.same(calls[1], { 'customize' })
		-- A path to the first control inside the inline group: the window never scrolls to a group's own key
		assert.same(calls[2], { 'sharing', { 'import', 'importText' } })
		assert.same(calls[3], { 'sharing', { 'export', 'exportText' } })
		assert.equal(P.SharingPage.export.what, 'style')
	end)

	it('picks the size', function()
		local page = Page()
		assert.same(page.args.size.sorting, { 'small', 'medium', 'large' })
		page.args.size.set({}, 'large')
		assert.equal(Store:Get('size'), 'large')
		assert.equal(page.args.size.get(), 'large')
	end)
end)

describe('style page: locked while the game restricts changes', function()
	before_each(Fresh)
	it('disables what changes the plates and says why', function()
		local page = Page()
		locked = true
		for _, key in ipairs({ 'style', 'size', 'undo', 'copy', 'width', 'height', 'barTexture', 'font', 'textSize' }) do
			assert.is_true(page.args[key].disabled(), key .. ' is locked')
		end
		assert.is_false(page.args.status.hidden(), 'the reason is on the page')
		assert.equal(page.args.status.args.locked.name, Options.LOCKED_REASON)
		assert.matches(page.args.style.desc(), 'unlocks when that is over')
		locked = false
		assert.is_false(page.args.style.disabled())
		assert.is_true(page.args.status.hidden())
	end)
end)

----------------------------------------------------------------------------------------------------

describe('gallery: cards', function()
	before_each(Fresh)
	it('lists built-in and host styles, then the player styles, skipping internal ones', function()
		local id = Gallery:Copy('clean')
		local values = Values(Gallery:Cards({ page = true }))
		assert.contains(values, 'clean')
		assert.contains(values, 'host')
		assert.not_contains(values, 'mini', 'Mini is internal')
		assert.equal(values[#values], id, 'the player style comes last')
	end)

	it('calls the host card Match my look and badges it', function()
		local card
		for _, item in ipairs(Gallery:Cards({ page = true })) do
			if item.value == 'host' then
				card = item
			end
		end
		assert.not_nil(card)
		assert.equal(card.title, 'Match my look')
		assert.equal(card.tag, 'Matches your look')
		assert.is_nil(card.recommended, 'the settings page shows the two badges of the plan, not Recommended')
		assert.matches(card.caption, P:HostName())
	end)

	it('recommends the host look on the setup cards', function()
		local card
		for _, item in ipairs(Gallery:Cards()) do
			if item.value == 'host' then
				card = item
			end
		end
		assert.is_true(card.recommended)
	end)

	it('reads the style in use through the store', function()
		Store:Set('style', 'bold')
		local tags = {}
		for _, item in ipairs(Gallery:Cards()) do
			tags[item.value] = item.tag
		end
		assert.equal(tags.bold, 'In use')
		assert.not_equal(tags.clean, 'In use')
	end)

	it('tags the style in use when asked for the setup cards, not on the page', function()
		Store:Set('style', 'clean')
		local function Tag(cards, value)
			for _, card in ipairs(cards) do
				if card.value == value then
					return card.tag
				end
			end
		end
		assert.equal(Tag(Gallery:Cards(), 'clean'), 'In use')
		assert.is_nil(Tag(Gallery:Cards({ page = true }), 'clean'), 'the grid marks the picked card itself')
		Store:Set('style', 'host')
		assert.equal(Tag(Gallery:Cards(), 'host'), 'In use')
	end)

	it('describes saved and imported styles', function()
		local copy = Gallery:Copy('clean')
		local card
		for _, item in ipairs(Gallery:Cards({ page = true })) do
			if item.value == copy then
				card = item
			end
		end
		assert.equal(card.caption, 'A style you made.')
		Store:Set({ 'styles', copy, 'source' }, { kind = 'import', author = 'Jane', version = 3 }, 'global')
		for _, item in ipairs(Gallery:Cards({ page = true })) do
			if item.value == copy then
				card = item
			end
		end
		assert.equal(card.caption, 'By Jane. Version 3.')
	end)

	it('offers live art only when LibAT can draw it', function()
		for _, card in ipairs(Gallery:Cards()) do
			assert.is_nil(card.art, 'no hook, no art: ' .. card.value)
		end
		ArtOn()
		for _, card in ipairs(Gallery:Cards()) do
			assert.equal(type(card.art.draw), 'function')
			assert.equal(type(card.art.release), 'function')
		end
		assert.equal(Gallery:Art('clean'), Gallery.ART)
	end)

	it('shows plain cards with a name and a description on a LibAT that lists no capabilities', function()
		LibAT.Capabilities = {}
		assert.is_false(Gallery:CanDraw())
		local cards = Gallery:Cards()
		assert.truthy(#cards > 0)
		for _, card in ipairs(cards) do
			assert.is_nil(card.art, 'no art hook: ' .. card.value)
			assert.truthy(type(card.title) == 'string' and card.title ~= '', card.value .. ' has a name')
			assert.truthy(type(card.caption) == 'string' and card.caption ~= '', card.value .. ' has a description')
		end
		LibAT.Capabilities = { cardArtDraw = false }
		assert.is_false(Gallery:CanDraw(), 'a hook that is turned off draws nothing')
	end)
end)

----------------------------------------------------------------------------------------------------

describe('gallery: live pictures', function()
	before_each(Fresh)
	local function Holder()
		local card = CreateFrame('Frame', nil, UIParent)
		local holder = CreateFrame('Frame', nil, card)
		holder:SetSize(150, 88)
		return holder, card
	end

	it('draws the real plates on sample sources and scales them to the picture', function()
		local holder, card = Holder()
		Gallery.Draw(holder, { value = 'clean' }, card, 150, 88, {})
		local view = Gallery.views[holder]
		assert.not_nil(view)
		assert.truthy(#view.plates >= 2 and #view.plates <= 3, 'plates: ' .. #view.plates)
		for _, plate in ipairs(view.plates) do
			assert.is_true(plate.isPreview)
			assert.not_nil(plate.src, 'bound to a sample')
			assert.equal(plate.src.sample ~= nil, true)
			assert.is_true(M.Get(plate.root, 'shown') ~= false)
		end
		local scale = M.Get(view.scaler, 'scale')
		assert.truthy(scale > 0 and scale <= 1, 'scale ' .. tostring(scale))
	end)

	it('shows the target arrows on the target sample and not on the others', function()
		local holder, card = Holder()
		Gallery.Draw(holder, { value = 'clean' }, card, 220, 150, {})
		local view = Gallery.views[holder]
		local target, other
		for _, plate in ipairs(view.plates) do
			if plate.src.sample.id == 'casterTarget' then
				target = plate
			elseif plate.src.sample.id == 'eliteMiniBoss' then
				other = plate
			end
		end
		assert.not_nil(target)
		assert.is_true(target.states.target)
		local arrows = target:GetWidget('arrows')
		assert.not_nil(arrows)
		assert.is_true(M.Get(arrows.frame, 'shown') ~= false, 'arrows on the target')
		if other and other:GetWidget('arrows') then
			assert.is_false(M.Get(other:GetWidget('arrows').frame, 'shown') ~= false)
		end
	end)

	it('shows each sample name, its health and the cast on the plate that is casting', function()
		local holder, card = Holder()
		Gallery.Draw(holder, { value = 'clean' }, card, 300, 200, {})
		local names = {}
		for _, plate in ipairs(Gallery.views[holder].plates) do
			local name = plate:GetWidget('name')
			names[#names + 1] = M.Get(name.text, 'text')
			local cast = plate:GetWidget('cast')
			if plate.src.sample.cast then
				assert.not_nil(cast, 'a cast bar on a casting sample')
				assert.not_nil(M.Get(cast.frame, 'shown'))
			end
		end
		assert.same(names, { 'Shadowguard Caster', 'Bonecrusher Brute', 'Arannis' })
	end)

	it('draws fewer samples when the picture is small', function()
		local small, card = Holder()
		Gallery.Draw(small, { value = 'clean' }, card, 150, 50, {})
		local big = Holder()
		Gallery.Draw(big, { value = 'clean' }, card, 300, 200, {})
		assert.truthy(#Gallery.views[small].plates <= #Gallery.views[big].plates)
	end)

	it('redraws in place: the same plates are reused', function()
		local holder, card = Holder()
		Gallery.Draw(holder, { value = 'clean' }, card, 150, 88, {})
		local view = Gallery.views[holder]
		local first = {}
		for i, plate in ipairs(view.plates) do
			first[i] = plate
		end
		Gallery.Draw(holder, { value = 'clean' }, card, 150, 88, {})
		Gallery.Draw(holder, { value = 'clean', variant = 'large' }, card, 150, 88, {})
		for i, plate in ipairs(first) do
			assert.equal(view.plates[i], plate)
		end
		assert.truthy(view.plates[1].style.width > 132, 'the large size')
	end)

	it('shows the player changes and the host look', function()
		local holder, card = Holder()
		Store:Set('style', 'clean')
		Style.SetPlateSize(180, nil)
		Gallery.Draw(holder, { value = 'clean' }, card, 150, 88, {})
		assert.equal(Gallery.views[holder].plates[1].style.width, 180)
		Gallery.Draw(holder, { value = 'host' }, card, 150, 88, {})
		assert.equal(Gallery.views[holder].plates[1].style.id, 'hosted')
	end)

	it('stops everything when the card is reused or hidden', function()
		local holder, card = Holder()
		Gallery.Draw(holder, { value = 'clean' }, card, 150, 88, {})
		local view = Gallery.views[holder]
		Gallery.Release(holder, { value = 'clean' }, card)
		for _, plate in ipairs(view.plates) do
			assert.is_nil(plate.src, 'unbound')
		end
		assert.is_false(M.Get(view.scaler, 'shown') ~= false)
		-- and a hide does the same
		Gallery.Draw(holder, { value = 'clean' }, card, 150, 88, {})
		assert.not_nil(view.plates[1].src)
		M.RunScript(holder, 'OnHide')
		assert.is_nil(view.plates[1].src)
	end)

	it('does not fail the card when a style cannot be drawn', function()
		local holder, card = Holder()
		local before = Merge.Resolve
		Merge.Resolve = function()
			error('broken style')
		end
		Gallery.Draw(holder, { value = 'clean' }, card, 150, 88, {})
		Merge.Resolve = before
		assert.is_false(M.Get(Gallery.views[holder].scaler, 'shown') ~= false)
	end)

	it('makes no timers or events while a card is hidden', function()
		local holder, card = Holder()
		Gallery.Draw(holder, { value = 'clean' }, card, 150, 88, {})
		Gallery.Release(holder)
		for _, plate in ipairs(Gallery.views[holder].plates) do
			assert.is_nil(plate.events)
		end
	end)
end)

----------------------------------------------------------------------------------------------------

describe('gallery: hover to try and pasted styles', function()
	before_each(Fresh)
	it('fires one message per change and remembers the card', function()
		local seen = {}
		P:On('GALLERY_HOVER', function(value)
			seen[#seen + 1] = value or 'none'
		end, seen)
		Gallery:SetHover('mini')
		Gallery:SetHover('mini')
		Gallery:SetHover(nil)
		P:Off('GALLERY_HOVER', seen)
		assert.same(seen, { 'mini', 'none' })
		assert.is_nil(Gallery.hover)
	end)

	it('tells the Pull scene which style to draw: pasted, then hovered, then none', function()
		assert.is_nil(Gallery:ResolveShown('enemyNPC', 'medium'))
		Gallery:SetHover('mini')
		assert.equal(Gallery:ResolveShown('enemyNPC', 'medium').id, 'mini')
		local pasted = Merge:Bake('clean')
		pasted.name = 'Pasted'
		pasted.plate = { sizes = { small = { 90, 8 }, medium = { 99, 10 }, large = { 120, 12 } } }
		local messages = 0
		P:On('GALLERY_PREVIEW', function()
			messages = messages + 1
		end, Gallery)
		Gallery:SetPreview({ style = pasted, name = 'Pasted' })
		local resolved = Gallery:ResolveShown('enemyNPC', 'medium')
		assert.equal(resolved.width, 99)
		assert.equal(resolved.id, '@preview')
		assert.equal(Gallery:ResolveShown('enemyNPC', 'medium'), resolved, 'cached')
		Gallery:ClearPreview()
		P:Off('GALLERY_PREVIEW', Gallery)
		assert.equal(messages, 2)
		assert.equal(Gallery:ResolveShown('enemyNPC', 'medium').id, 'mini', 'back to the hovered style')
	end)

	it('gives a new plate key to every new pasted style', function()
		local style = Merge:Bake('clean')
		Gallery:SetPreview({ style = style, name = 'A' })
		local a = Gallery:ResolvePreview('enemyNPC', 'medium').key
		Gallery:SetPreview({ style = style, name = 'B' })
		local b = Gallery:ResolvePreview('enemyNPC', 'medium').key
		assert.not_equal(a, b)
	end)

	it('draws a pasted style on its card', function()
		local card = CreateFrame('Frame', nil, UIParent)
		local holder = CreateFrame('Frame', nil, card)
		local style = Merge:Bake('clean')
		style.plate = { sizes = { small = { 90, 8 }, medium = { 177, 10 }, large = { 120, 12 } } }
		Gallery:SetPreview({ style = style, name = 'Pasted' })
		Gallery.Draw(holder, { value = Gallery.PREVIEW_VALUE }, card, 150, 88, {})
		assert.equal(Gallery.views[holder].plates[1].style.width, 177)
	end)

	it('hooks the grid: the style option reports hover to the gallery', function()
		local page = Page()
		page.args.style.arg.onHover('mini')
		assert.equal(Gallery.hover, 'mini')
		page.args.style.arg.onHover(nil)
		assert.is_nil(Gallery.hover)
	end)
end)

----------------------------------------------------------------------------------------------------

describe('gallery: the player styles', function()
	before_each(Fresh)
	it('copies a style with the player changes baked in', function()
		Store:Set('style', 'clean')
		Style.SetPlateSize(170, nil)
		local id, name = Gallery:Copy('clean')
		assert.is_true(Registry:IsSaved(id))
		assert.equal(name, 'Clean copy')
		assert.equal(Merge:Resolve(id, 'enemyNPC', 'medium').width, 170)
		local _, again = Gallery:Copy('clean')
		assert.equal(again, 'Clean copy 2', 'names stay different')
	end)

	it('renames only the player styles and keeps names apart', function()
		local id = Gallery:Copy('clean')
		local ok, name = Gallery:Rename(id, '  My bars  ')
		assert.is_true(ok)
		assert.equal(name, 'My bars')
		assert.equal(Registry:Get(id).name, 'My bars')
		ok, name = Gallery:Rename(id, 'Clean')
		assert.equal(name, 'Clean 2', 'not the same as a built-in')
		assert.is_false((Gallery:Rename('clean', 'Other')))
		assert.is_false((Gallery:Rename(id, '   ')))
	end)

	it('deletes a style and stops the profile using it', function()
		local id = Gallery:Copy('clean')
		Store:Set('style', id)
		Store:Set({ 'assign', 'minor' }, id)
		Store:Set('when', { { conditions = { { id = 'place', args = 'raid' } }, style = id, size = 'small' } })
		Store:Set({ 'tweaks', id, 'changes', 'plate', 'sizes', 'medium' }, { 150, 10 })
		Gallery:SetHover(id)
		assert.is_true(Gallery:Delete(id))
		assert.is_false(Registry:IsSaved(id))
		assert.equal(Store:Get('style'), 'host', 'back to the default')
		assert.is_nil(Store:Get({ 'assign', 'minor' }))
		assert.is_nil(Store:Get('when')[1].style)
		assert.equal(Store:Get('when')[1].size, 'small', 'the rest of the entry stays')
		assert.is_nil(Store:Get({ 'tweaks', id }))
		assert.is_nil(Gallery.hover)
		assert.is_false(Gallery:Delete('clean'), 'built-ins cannot be deleted')
	end)

	it('drops the special cases that only used the deleted style and keeps the rest', function()
		local id = Gallery:Copy('clean')
		local other = { conditions = { { id = 'place', args = 'dungeon' } }, style = 'mini' }
		Store:Set('when', {
			{ conditions = { { id = 'place', args = 'raid' } }, style = id },
			other,
			{ conditions = { { id = 'place', args = 'pvp' } }, style = id, mode = 'hidden' },
		})
		assert.is_true(Gallery:Delete(id))
		local when = Store:Get('when')
		assert.equal(#when, 2)
		assert.equal(when[1].style, 'mini')
		assert.is_nil(when[2].style)
		assert.equal(when[2].mode, 'hidden')
		local second = Gallery:Copy('clean')
		Store:Set('when', { { conditions = { { id = 'place', args = 'raid' } }, style = second } })
		Gallery:Delete(second)
		assert.is_nil(Store:Get('when'), 'an empty list is not kept')
	end)

	it('offers Rename and Delete on the player styles only', function()
		local function Actions(value)
			local out = {}
			for _, item in ipairs(Gallery:MenuItems(value)) do
				out[#out + 1] = item.value
			end
			return out
		end
		assert.same(Actions('clean'), { 'use', 'copy', 'share' })
		assert.same(Actions('host'), { 'use', 'copy', 'share' })
		local id = Gallery:Copy('clean')
		assert.same(Actions(id), { 'use', 'copy', 'share', 'rename', 'delete' })
	end)

	it('opens the menu under the card and answers a pick', function()
		local card = CreateFrame('Button', nil, UIParent)
		card:SetSize(150, 150)
		local picks = {}
		Gallery.OnMenuPick = function(action, value)
			picks[#picks + 1] = action .. ':' .. value
		end
		assert.is_true(Gallery:OpenMenu('clean', card))
		local items = P.Widgets.Draw.MenuItems()
		assert.equal(#items, 3)
		assert.is_true(P.Widgets.Draw.PickMenuIndex(2))
		assert.same(picks, { 'copy:clean' })
		assert.is_false(Gallery:OpenMenu(Gallery.PREVIEW_VALUE, card), 'no menu on the pasted card')
		Style.Do = Style.Do
		Gallery.OnMenuPick = function(action, value)
			Style:Do(action, value)
		end
	end)
end)

describe('style page: card menu answers', function()
	before_each(Fresh)
	it('copies, then asks before renaming or deleting, on the page itself', function()
		local page = Page()
		local status = page.args.status
		Style:Do('copy', 'clean')
		assert.matches(status.args.notice.name(), 'Clean copy')
		assert.is_false(status.hidden())
		local id
		for _, item in ipairs(Registry:List(false)) do
			if item.source == 'saved' then
				id = item.id
			end
		end
		Style:Do('rename', id)
		assert.is_false(status.args.rename.hidden())
		assert.is_true(status.args.deleteYes.hidden())
		assert.equal(status.args.rename.get(), 'Clean copy')
		status.args.rename.set({}, 'Fancy')
		assert.equal(Registry:Get(id).name, 'Fancy')
		assert.is_true(status.args.rename.hidden(), 'the prompt is gone')
		assert.matches(status.args.notice.name(), 'Fancy')

		Style:Do('delete', id)
		assert.is_false(status.args.deleteYes.hidden())
		assert.matches(status.args.deleteAsk.name(), 'Fancy')
		status.args.deleteNo.func()
		assert.is_true(Registry:IsSaved(id), 'kept')
		Style:Do('delete', id)
		status.args.deleteYes.func()
		assert.is_false(Registry:IsSaved(id))
		assert.is_true(status.args.deleteYes.hidden())
	end)

	it('takes the notice off the page by itself and asks the window to redraw once', function()
		local page = Page()
		local redraws = 0
		local original = P.host.RefreshOptions
		P.host.RefreshOptions = function()
			redraws = redraws + 1
		end
		Style:Notify('Hello there.')
		M.Advance(0.2)
		assert.equal(redraws, 1, 'drawn when it arrives')
		assert.equal(page.args.status.args.notice.name(), 'Hello there.')
		M.Advance(19)
		assert.equal(redraws, 1, 'nothing while it is fresh')
		M.Advance(2)
		assert.equal(redraws, 2, 'one more redraw when it is old')
		assert.equal(page.args.status.args.notice.name(), '')
		assert.is_true(page.args.status.hidden())
		M.Advance(30)
		assert.equal(redraws, 2, 'and then it is quiet')
		P.host.RefreshOptions = original
	end)

	it('waits with a redraw while a slider is dragged or the color picker is open', function()
		local redraws = 0
		local original = P.host.RefreshOptions
		P.host.RefreshOptions = function()
			redraws = redraws + 1
		end
		local mouseDown, pickerShown = true, false
		local savedMouse, savedPicker = _G.IsMouseButtonDown, _G.ColorPickerFrame
		_G.IsMouseButtonDown = function()
			return mouseDown
		end
		_G.ColorPickerFrame = {
			IsShown = function()
				return pickerShown
			end,
		}
		P.Options:RequestRefresh(false)
		M.Advance(0.5)
		assert.equal(redraws, 0, 'not while the slider is held')
		mouseDown, pickerShown = false, true
		M.Advance(0.5)
		assert.equal(redraws, 0, 'not while the color picker is open')
		pickerShown = false
		M.Advance(0.2)
		assert.equal(redraws, 1, 'once both are let go')
		_G.IsMouseButtonDown, _G.ColorPickerFrame = savedMouse, savedPicker
		P.host.RefreshOptions = original
	end)

	it('uses a style from the menu unless the game restricts changes', function()
		Style:Do('use', 'mini')
		assert.equal(Store:Get('style'), 'mini')
		Store:Reset('style')
		locked = true
		Style:Do('use', 'mini')
		assert.equal(Store:Get('style'), 'host')
		assert.equal(Style:NoticeText(), Options.LOCKED_REASON)
	end)

	it('does not let a locked page delete the style in use', function()
		local page = Page()
		local id = Gallery:Copy('clean')
		Store:Set('style', id)
		Style:Do('delete', id)
		locked = true
		assert.is_true(page.args.status.args.deleteYes.disabled())
		locked = false
		assert.is_false(page.args.status.args.deleteYes.disabled())
	end)

	it('Make a copy saves the style and starts using the copy', function()
		local page = Page()
		Store:Set('style', 'clean')
		Style.SetPlateSize(160, nil)
		page.args.copy.func()
		local using = Store:Get('style')
		assert.is_true(Registry:IsSaved(using))
		assert.equal(Merge:Resolve(using, 'enemyNPC', 'medium').width, 160)
		assert.is_true(Merge:HasChanges('clean'), 'the original keeps its changes until undone')
	end)
end)

----------------------------------------------------------------------------------------------------

describe('style page: more settings', function()
	before_each(Fresh)
	local function Plain()
		return Merge:Resolve('clean', 'enemyNPC', 'medium')
	end

	before_each(function()
		Store:Set('style', 'clean')
	end)

	it('reads the plate size of the picked size and writes only real changes', function()
		local page = Page()
		assert.equal(page.args.width.get(), 132)
		assert.equal(page.args.height.get(), 10)
		page.args.width.set({}, 150)
		assert.equal(Plain().width, 150)
		assert.equal(Plain().height, 10)
		assert.same(Store:Get({ 'tweaks', 'clean', 'changes', 'plate', 'sizes', 'medium' }), { 150, 10 })
		assert.equal(Store:Get({ 'tweaks', 'clean', 'schema' }), Schema.CURRENT)
		page.args.height.set({}, 14)
		assert.same(Store:Get({ 'tweaks', 'clean', 'changes', 'plate', 'sizes', 'medium' }), { 150, 14 })
		page.args.width.set({}, 132)
		page.args.height.set({}, 10)
		assert.is_nil(Store:Get('tweaks'), 'back to the style: nothing is kept')
		assert.is_true(page.args.undo.hidden())
	end)

	it('writes the size for the size picked', function()
		Store:Set('size', 'large')
		local page = Page()
		assert.equal(page.args.width.get(), 156)
		page.args.width.set({}, 170)
		assert.same(Store:Get({ 'tweaks', 'clean', 'changes', 'plate', 'sizes', 'large' }), { 170, 12 })
		Store:Set('size', 'small')
		assert.equal(page.args.width.get(), 112, 'the other sizes are untouched')
	end)

	it('every written overlay passes the schema check', function()
		local page = Page()
		page.args.width.set({}, 150)
		page.args.textSize.set({}, 3)
		page.args.barTexture.set({}, 'Some Bar')
		page.args.font.set({}, 'Some Font')
		local overlay = Store:Get({ 'tweaks', 'clean' })
		local cleaned, report = Schema:ValidateOverlay(overlay, Registry:Get('clean').parts)
		assert.not_nil(cleaned)
		assert.equal(report.dropped, 0)
		assert.equal(report.clamped, 0)
	end)

	it('makes all text bigger or smaller together and takes it back', function()
		local page = Page()
		assert.equal(page.args.textSize.get(), 0)
		local before = Plain()
		page.args.textSize.set({}, 2)
		local after = Plain()
		assert.equal(after.parts.name.font.size, before.parts.name.font.size + 2)
		assert.equal(after.parts.hp.font.size, before.parts.hp.font.size + 2)
		assert.equal(after.parts.cast.font.size, before.parts.cast.font.size + 2)
		assert.equal(after.parts.mine.font.size, before.parts.mine.font.size + 2)
		assert.equal(page.args.textSize.get(), 2)
		page.args.textSize.set({}, -4)
		assert.equal(page.args.textSize.get(), -4)
		page.args.textSize.set({}, 0)
		assert.is_nil(Store:Get('tweaks'))
		assert.equal(Plain().parts.name.font.size, before.parts.name.font.size)
	end)

	it('also moves the text sizes a style sets for one kind of plate', function()
		local function FriendlyName()
			return Merge:Resolve('clean', 'friendlyPlayer', 'medium').parts.name.font.size
		end
		local page = Page()
		assert.equal(FriendlyName(), 12, 'Clean sets its own size for friendly players')
		page.args.textSize.set({}, 3)
		assert.equal(FriendlyName(), 15)
		assert.equal(Store:Get({ 'tweaks', 'clean', 'situations', 'friendlyPlayer', 'parts', 'name', 'font', 'size' }), 15)
		assert.equal(Plain().parts.name.font.size, 13, 'the other plates follow too')
		local overlay = Store:Get({ 'tweaks', 'clean' })
		local cleaned, report = Schema:ValidateOverlay(overlay, Registry:Get('clean').parts)
		assert.not_nil(cleaned)
		assert.equal(report.dropped + report.clamped, 0)
		page.args.textSize.set({}, 0)
		assert.is_nil(Store:Get('tweaks'), 'back to the style: nothing is kept')
		assert.equal(FriendlyName(), 12)
	end)

	it('moves aura timer and stack text that have sizes of their own', function()
		if not Registry:Get('auraSized') then
			local sized = Merge:Bake('clean')
			sized.id, sized.name, sized.order, sized.internal = 'auraSized', 'Aura sized', 995, true
			sized.parts.mine.timerAnchor = { size = 11 }
			sized.situations.enemyPlayer.parts.cc.stackAnchor = { size = 13 }
			local cleaned, report = Schema:ValidateStyle(sized)
			assert.not_nil(cleaned)
			assert.equal(report.dropped + report.clamped + report.fixed, 0)
			Registry:RegisterBuiltin(sized)
		end
		Store:Set('style', 'auraSized')
		local function Size(kind, part, field)
			return Merge.AuraText(Merge:Resolve('auraSized', kind, 'medium').parts[part], field).size
		end
		assert.equal(Size('enemyNPC', 'mine', 'timerAnchor'), 11)
		assert.equal(Size('enemyNPC', 'mine', 'stackAnchor'), 9, 'without a size of its own it follows the row')
		assert.equal(Size('enemyPlayer', 'cc', 'stackAnchor'), 13)
		local page = Page()
		page.args.textSize.set({}, 2)
		assert.equal(page.args.textSize.get(), 2)
		assert.equal(Size('enemyNPC', 'mine', 'timerAnchor'), 13)
		assert.equal(Size('enemyNPC', 'mine', 'stackAnchor'), 11)
		assert.equal(Size('enemyPlayer', 'cc', 'stackAnchor'), 15, 'a size one kind of plate sets moves too')
		assert.equal(Size('enemyPlayer', 'cc', 'timerAnchor'), 11)
		assert.is_nil(Store:Get({ 'tweaks', 'auraSized', 'changes', 'parts', 'mine', 'stackAnchor' }), 'nothing is written for text that follows its row')
		local overlay = Store:Get({ 'tweaks', 'auraSized' })
		local cleaned, report = Schema:ValidateOverlay(overlay, Registry:Get('auraSized').parts)
		assert.not_nil(cleaned)
		assert.equal(report.dropped + report.clamped, 0)
		page.args.textSize.set({}, -4)
		assert.equal(Size('enemyNPC', 'mine', 'timerAnchor'), 7)
		assert.equal(Size('enemyPlayer', 'cc', 'stackAnchor'), 9)
		page.args.textSize.set({}, 0)
		assert.is_nil(Store:Get('tweaks'), 'back to the style: nothing is kept')
		assert.equal(Size('enemyNPC', 'mine', 'timerAnchor'), 11)
		assert.equal(Size('enemyPlayer', 'cc', 'stackAnchor'), 13)
	end)

	it('takes back an aura text size changed by hand when all text moves', function()
		Store:Set({ 'tweaks', 'clean' }, { schema = Schema.CURRENT, baseVersion = 1, changes = { parts = { mine = { timerAnchor = { size = 16 } } } } })
		local page = Page()
		page.args.textSize.set({}, 1)
		local mine = Plain().parts.mine
		assert.equal(Merge.AuraText(mine, 'timerAnchor').size, mine.font.size, 'it follows the row again, like every other text size')
		page.args.textSize.set({}, 0)
		assert.is_nil(Store:Get('tweaks'))
	end)

	it('keeps text sizes inside the range the schema allows', function()
		local page = Page()
		page.args.textSize.set({}, Style.TEXT_DELTA_MAX)
		for _, part in pairs(Plain().parts) do
			if part.font then
				assert.truthy(part.font.size >= 6 and part.font.size <= 40)
			end
		end
		assert.equal(page.args.textSize.max, Style.TEXT_DELTA_MAX)
	end)

	it('picks the bar texture and the font through the style tokens', function()
		local page = Page()
		assert.equal(page.args.barTexture.get(), 'Nameplates Flat')
		page.args.barTexture.set({}, 'Smooth')
		assert.equal(Plain().tokens.bar, 'Smooth')
		assert.equal(Plain().parts.health.texture, 'Smooth')
		page.args.font.set({}, 'Friz Quadrata TT')
		assert.equal(Plain().tokens.font, 'Friz Quadrata TT')
		assert.equal(Plain().parts.name.font.face, 'Friz Quadrata TT')
		page.args.barTexture.set({}, 'Nameplates Flat')
		page.args.font.set({}, 'Fonts\\Test.ttf')
		assert.is_nil(Store:Get('tweaks'), 'the style own values are not kept as changes')
	end)

	it('shows the media name for the file a token holds', function()
		local media = P.services.media
		media:Register('font', 'Test Face', 'Interface\\AddOns\\Test\\Face.ttf')
		local page = Page()
		Style.SetToken('font', 'Interface\\AddOns\\Test\\Face.ttf')
		assert.equal(page.args.font.get(), 'Test Face')
	end)

	it('offers the library lists to the pickers', function()
		local page = Page()
		P.services.media:Register('statusbar', 'Listed Bar', 'Interface\\AddOns\\Test\\Bar.tga')
		assert.equal(page.args.barTexture.values()['Listed Bar'], 'Listed Bar')
	end)

	it('uses the picture pickers when the client has them', function()
		local AceGUI = LibStub('AceGUI-3.0')
		AceGUI:RegisterWidgetType('LSM30_Font', function()
			return { frame = CreateFrame('Frame'), type = 'LSM30_Font' }
		end, 1)
		AceGUI:RegisterWidgetType('LSM30_Statusbar', function()
			return { frame = CreateFrame('Frame'), type = 'LSM30_Statusbar' }
		end, 1)
		local page = Page()
		assert.equal(page.args.font.dialogControl, 'LSM30_Font')
		assert.equal(page.args.barTexture.dialogControl, 'LSM30_Statusbar')
	end)
end)

describe('style page: overlay writes', function()
	before_each(Fresh)
	local Overlay = Style.Overlay

	it('sets and clears deep values and prunes the tables left empty', function()
		local root = {}
		Overlay.SetIn(root, { 'changes', 'parts', 'name', 'font', 'size' }, 12)
		assert.equal(root.changes.parts.name.font.size, 12)
		Overlay.SetIn(root, { 'changes', 'parts', 'name', 'font', 'size' }, nil)
		assert.is_nil(root.changes)
		Overlay.SetIn(root, { 'nothing', 'here' }, nil)
		assert.same(root, {})
	end)

	it('keeps the schema and base version on a style with changes only', function()
		Overlay.Edit('clean', function(overlay)
			Overlay.SetIn(overlay, { 'changes', 'tokens', 'bar' }, 'X')
		end)
		local overlay = Store:Get({ 'tweaks', 'clean' })
		assert.equal(overlay.schema, Schema.CURRENT)
		assert.equal(overlay.baseVersion, 1)
		Overlay.Edit('clean', function(o)
			Overlay.SetIn(o, { 'changes', 'tokens', 'bar' }, nil)
		end)
		assert.is_nil(Store:Get('tweaks'))
	end)

	it('keeps other changes (parts added or removed) when the settings here are cleared', function()
		Store:Set({ 'tweaks', 'clean', 'remove', 'forces' }, true)
		Overlay.Edit('clean', function(overlay)
			Overlay.SetIn(overlay, { 'changes', 'tokens', 'bar' }, 'X')
		end)
		Overlay.Edit('clean', function(overlay)
			Overlay.SetIn(overlay, { 'changes', 'tokens', 'bar' }, nil)
		end)
		assert.is_true(Store:Get({ 'tweaks', 'clean', 'remove', 'forces' }))
	end)
end)

----------------------------------------------------------------------------------------------------
-- Polish: where Share and Import land, and the style a game suggests first
----------------------------------------------------------------------------------------------------

describe('style page: Share and Import buttons', function()
	before_each(Fresh)

	it('land on real controls inside the Sharing page groups', function()
		local sharing = P:BuildOptionsTable().args.sharing
		for _, which in ipairs({ 'export', 'import' }) do
			local path = P.SharingPage.FOCUS[which]
			assert.truthy(#path >= 2, 'a path: the group first, a control last')
			local node = sharing
			for _, key in ipairs(path) do
				node = node.args and node.args[key]
				assert.not_nil(node, which .. ': ' .. key .. ' is on the page')
			end
			assert.not_equal(node.type, 'group', which .. ' ends on a control')
			assert.is_nil(node.args, which .. ' ends on a control')
		end
	end)

	it('send the host that path, not the key of the group', function()
		local calls = {}
		local before = P.host.OpenOptions
		P.host.OpenOptions = function(page, key)
			calls[#calls + 1] = { page, key }
		end
		local page = Page()
		page.args.share.func()
		page.args.import.func()
		P.host.OpenOptions = before
		assert.same(calls[1], { 'sharing', { 'export', 'exportText' } })
		assert.same(calls[2], { 'sharing', { 'import', 'importText' } })
	end)

	it('send the card menu Share there too', function()
		local calls = {}
		local before = P.host.OpenOptions
		P.host.OpenOptions = function(page, key)
			calls[#calls + 1] = { page, key }
		end
		Style:Do('share', 'clean')
		P.host.OpenOptions = before
		assert.same(calls[1], { 'sharing', { 'export', 'exportText' } })
		assert.equal(P.SharingPage.export.styleId, 'clean')
	end)
end)

describe('gallery: the style a game suggests first', function()
	before_each(Fresh)
	local suggests = FLAVOR == 'era' or FLAVOR == 'tbc' or FLAVOR == 'forever'

	local function Find(cards, value)
		for index, card in ipairs(cards) do
			if card.value == value then
				return index, card
			end
		end
	end

	it('puts Bordered right after Match my look on Era, TBC and Forever only', function()
		local values = Values(Gallery:Cards())
		assert.equal(values[1], 'host', 'Match my look stays first')
		local at, card = Find(Gallery:Cards(), 'bordered')
		if suggests then
			assert.equal(at, 2)
			assert.equal(card.tag, 'Suggested')
			assert.equal(values[3], 'clean')
		else
			assert.equal(values[2], 'clean')
			assert.truthy(at > 2, 'in its usual place')
			assert.is_nil(card.tag)
		end
	end)

	it('does the same on the Style page and in the setup cards', function()
		local at = Find(Gallery:Cards({ page = true }), 'bordered')
		local cards = P.SetupSteps.Cards()
		local inSetup = Find(cards, 'bordered')
		assert.not_nil(inSetup, 'Bordered is one of the setup looks')
		if suggests then
			assert.equal(at, 2)
			assert.equal(inSetup, 2)
		else
			assert.truthy(at > 2)
			assert.truthy(inSetup > 2)
		end
	end)

	it('shows In use instead of the suggestion on the card in use', function()
		Store:Set('style', 'bordered')
		local _, card = Find(Gallery:Cards(), 'bordered')
		assert.equal(card.tag, 'In use')
	end)

	it('keeps every other card where the list puts it', function()
		local values = Values(Gallery:Cards())
		local without = {}
		for _, value in ipairs(values) do
			if value ~= 'bordered' then
				without[#without + 1] = value
			end
		end
		local order = {}
		for _, item in ipairs(Registry:List(false)) do
			if item.id ~= 'bordered' then
				order[#order + 1] = item.matchesHost and 'host' or item.id
			end
		end
		assert.same(without, order)
	end)
end)

describe('style page: clean enemy players', function()
	it('gives Clean a larger crowd control row for enemy players only', function()
		local player = Merge:Resolve('clean', 'enemyPlayer', 'medium')
		local npc = Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.truthy(player.parts.cc.size > npc.parts.cc.size)
		assert.truthy(player.parts.cc.max > npc.parts.cc.max)
		local friend = Merge:Resolve('clean', 'friendlyPlayer', 'medium')
		assert.equal(friend.parts.cc.size, npc.parts.cc.size)
	end)
end)
