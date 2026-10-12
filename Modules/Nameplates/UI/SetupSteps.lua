local _, ns = ...
local P = ns.Plates
local L = P.L

-- Setup steps (3.1), defined by the core and added by the host through host.AddSetupSteps in
-- Phase 4a (not during the tester phases). LibAT.Setup rules apply: a pick is staged and applied
-- when the player moves on; get() returns the pending value; never reload from a step.
--
-- One compact "look" step, preselected on "Match my look" so Next accepts it, with the size as a
-- variant row (Small / Medium / Large) on every card: LibAT reads variants per card and calls
-- getVariant(value) and setVariant(value, variant, ctx), where value is the card's style. Picking
-- a size on a card also picks that card. Cards come from P.Gallery:Cards(); live card art needs the
-- LibAT art.draw hook, otherwise the card shows the name and description. Role is not asked: the
-- host reads its unit frames answer. Other nameplate addons are handled by the host's own
-- conflicts step (host.conflicts / module.ConflictsWith).

---@class Plates.SetupSteps
local SetupSteps = { pending = {} }
P.SetupSteps = SetupSteps

---Size choices shown on every card.
SetupSteps.SIZES = {
	{ value = 'small', text = L['Small'] },
	{ value = 'medium', text = L['Medium'] },
	{ value = 'large', text = L['Large'] },
}

---Gallery cards with the size row on each.
---@return table[] cards
function SetupSteps.Cards()
	local cards = P.Gallery:Cards()
	for _, card in ipairs(cards) do
		card.variants = SetupSteps.SIZES
	end
	return cards
end

---The steps for host.AddSetupSteps.
---@return table[] steps
function P:GetSetupSteps()
	return {
		{
			id = 'nameplates-look',
			kind = 'look',
			scope = 'profile',
			title = L['Pick how your nameplates look'],
			cards = SetupSteps.Cards,
			get = function()
				if SetupSteps.pending.style ~= nil then
					return SetupSteps.pending.style
				end
				return P.Store:Get('style') or 'host'
			end,
			set = function(value)
				SetupSteps.pending.style = value
			end,
			-- One size for every style, so the card's style does not change the answer
			getVariant = function()
				return SetupSteps.pending.size or P.Store:Get('size') or 'medium'
			end,
			setVariant = function(value, variant)
				SetupSteps.pending.style = value
				SetupSteps.pending.size = variant
			end,
			onLeave = function(ctx)
				if ctx and ctx.closing then
					return
				end
				P.Store:Batch(function()
					if SetupSteps.pending.style then
						P.Store:Set('style', SetupSteps.pending.style)
					end
					if SetupSteps.pending.size then
						P.Store:Set('size', SetupSteps.pending.size)
					end
				end)
				P.util.Wipe(SetupSteps.pending)
			end,
		},
	}
end
