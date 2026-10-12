local _, ns = ...
local P = ns.Plates

-- Glows (kind 'glow') except threat: importantCast, purge, pandemic, target. Owner: Phase 2
-- (pandemic in Phase 5).
--
-- importantCast: shown with P.Secret.SetAlphaFromBoolean(glow, src:IsImportantSecret(), 1, 0)
-- while a cast runs; cast events. purge: removable buffs present (Lua scan on the Classic family;
-- on Retail and Forever only through the removable aura row, never read). The glow texture comes
-- from the art set; color from spec.color.

P.Parts:Register({
	id = 'glow',
	kinds = { 'glow' },
	match = function(spec)
		return spec.source ~= 'threat'
	end,
	events = function(spec)
		if spec.source == 'importantCast' then
			return { 'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_STOP', 'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_CHANNEL_STOP' }
		end
		return {}
	end,
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		holder:Hide()
		return { frame = holder }
	end,
	Layout = function(widget, spec, ctx)
		local size = spec.size or 4
		widget.frame:ClearAllPoints()
		widget.frame:SetPoint('TOPLEFT', ctx.plate.art, 'TOPLEFT', -size, size)
		widget.frame:SetPoint('BOTTOMRIGHT', ctx.plate.art, 'BOTTOMRIGHT', size, -size)
	end,
	Update = function() end,
	Reset = function() end,
})
