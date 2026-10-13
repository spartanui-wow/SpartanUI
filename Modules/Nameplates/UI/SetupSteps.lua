local _, ns = ...
local P = ns.Plates
local L = P.L

-- Setup steps (3.1), defined by the core and added by the host through host.AddSetupSteps.
-- LibAT.Setup rules apply: a pick is staged and applied when the player moves on; get() returns
-- the pending value; never reload from a step.
--
-- One compact "look" step, preselected on "Match my look" so Next accepts it, with the size as a
-- variant row (Small / Medium / Large) on every card: LibAT reads variants per card and calls
-- getVariant(value) and setVariant(value, variant, ctx), where value is the card's style. Picking
-- a size on a card also picks that card. Cards come from P.Gallery:Cards() (live art through the
-- LibAT art.draw hook when the gallery supplies it; otherwise the name and description).
--
-- Leaving the step (not closing the window) applies, in one Store batch:
--   * the style and size;
--   * the role, when the host knows the player's answer from its own setup
--     (host.GetSetupRole() -> 'tank' | 'damage' | 'healer' | nil); nil keeps 'auto' (the spec);
--   * the game settings setup turns on (open question 6): plates do not overlap, friendly players
--     show names only inside instances, plates keep one size (SetupSteps.BEHAVIOR). A behavior key
--     the player already set is left alone;
--   * profile.enabled = true (picking a style turns these plates on for the profile) and the
--     What's new card is marked answered.
-- Migrated profiles never pass through here, so their game settings stay untouched (7.4).
--
-- The host decides where the step sits (order, chapter), when it is hidden and any banner (for
-- example another nameplate addon that the conflicts step can turn off). The step's summary() is
-- the Done page line: the style, the size and the game settings we changed. SetupSteps:RestoreGame
-- backs the Done page's "Give the game back its settings" link.

---@class Plates.SetupSteps
local SetupSteps = { pending = {} }
P.SetupSteps = SetupSteps

SetupSteps.STEP_ID = 'nameplates-look'

---Size choices shown on every card.
SetupSteps.SIZES = {
	{ value = 'small', text = L['Small'] },
	{ value = 'medium', text = L['Medium'] },
	{ value = 'large', text = L['Large'] },
}

---Game settings finishing setup turns on (profile.behavior keys; the Driver writes them).
SetupSteps.BEHAVIOR = {
	stacking = { enemy = true },
	friendlyNames = true,
	pinScale = true,
}

---What each behavior changes, for the Done page, and the game settings it covers (so the list
---does not name them twice).
SetupSteps.BEHAVIOR_TEXT = {
	{ key = 'stacking', text = L['Plates do not overlap'], cvars = { 'nameplateStackingTypes' } },
	{
		key = 'friendlyNames',
		text = L['Friendly players show names only in dungeons and raids'],
		cvars = { 'nameplateShowOnlyNameForFriendlyPlayerUnits', 'nameplateUseClassColorForFriendlyPlayerUnitNames' },
	},
	{ key = 'pinScale', text = L['Plates keep one size at any distance'], cvars = { 'nameplateMinScale', 'nameplateMaxScale', 'nameplateSelectedScale' } },
}

---Roles the host may report from its own setup.
local ROLES = { tank = true, damage = true, healer = true }

---Gallery cards with the size row on each.
---@return table[] cards
function SetupSteps.Cards()
	local cards = P.Gallery:Cards()
	for _, card in ipairs(cards) do
		card.variants = SetupSteps.SIZES
	end
	return cards
end

---The style the step shows as picked: the pending pick, else the profile's.
---@return string
function SetupSteps:Style()
	if self.pending.style ~= nil then
		return self.pending.style
	end
	return P.Store:Get('style') or 'host'
end

---The size the step shows as picked.
---@return string
function SetupSteps:Size()
	return self.pending.size or P.Store:Get('size') or 'medium'
end

---Display name of a style id ('host' is "Match my look").
---@param id string|nil
---@return string
function SetupSteps:StyleName(id)
	local Registry = P.Styles.Registry
	local style = Registry:Get(Registry:ResolveId(id))
	if id == 'host' and not (style and style.matchesHost) then
		return L['Match my look']
	end
	return style and style.name or tostring(id)
end

---@param size string|nil
---@return string
function SetupSteps:SizeName(size)
	for _, item in ipairs(self.SIZES) do
		if item.value == size then
			return item.text
		end
	end
	return tostring(size)
end

---The role the host's own setup asked about, or nil.
---@return string|nil
local function HostRole()
	local host = P.host
	if not (host and host.GetSetupRole) then
		return nil
	end
	local ok, role = pcall(host.GetSetupRole)
	if ok and ROLES[role] then
		return role
	end
	return nil
end

---Apply the step: style, size, role, the setup game settings, plates on. One refresh.
function SetupSteps:Apply()
	local pending = self.pending
	local role = HostRole()
	P.Store:Batch(function()
		if pending.style then
			P.Store:Set('style', pending.style)
		end
		if pending.size then
			P.Store:Set('size', pending.size)
		end
		if role then
			P.Store:Set('role', role)
		end
		for key, value in pairs(self.BEHAVIOR) do
			if P.Store:Get({ 'behavior', key }) == nil then
				P.Store:Set({ 'behavior', key }, value)
			end
		end
		P.Store:Set('enabled', true)
	end)
	if P.Migrate and P.Migrate.FinishMakeover then
		P.Migrate:FinishMakeover()
	end
	P.util.Wipe(pending)
end

---Game settings these plates changed (or will change in instances), in plain words.
---@return string[]
function SetupSteps:ChangedSettings()
	local list, covered = {}, {}
	for _, item in ipairs(self.BEHAVIOR_TEXT) do
		local value = P.Store:Get({ 'behavior', item.key })
		if value ~= nil and value ~= false then
			list[#list + 1] = item.text
			for _, name in ipairs(item.cvars) do
				covered[name] = true
			end
		end
	end
	local CVars = P.CVars
	for _, name in ipairs(CVars.order or {}) do
		local def = CVars.defs[name]
		if def and not covered[name] and CVars:GetBackup(name) ~= nil then
			list[#list + 1] = def.label
		end
	end
	return list
end

---The Done page line.
---@return string
function SetupSteps:Summary()
	local text = string.format('%s, %s.', self:StyleName(self:Style()), self:SizeName(self:Size()))
	local changed = self:ChangedSettings()
	if #changed > 0 then
		text = text .. ' ' .. string.format(L['Game settings we change: %s.'], table.concat(changed, ', '))
	end
	return text
end

---"Give the game back its settings" (Done page link): puts back every game setting we changed
---and stops setup's own changes from coming back.
---@return boolean done false when some settings wait for combat to end
function SetupSteps:RestoreGame()
	P.Store:Batch(function()
		for key in pairs(self.BEHAVIOR) do
			P.Store:Set({ 'behavior', key }, nil)
		end
	end)
	return P.CVars:RestoreAll()
end

---The steps for host.AddSetupSteps.
---@return table[] steps
function P:GetSetupSteps()
	return {
		{
			id = SetupSteps.STEP_ID,
			kind = 'look',
			compact = true,
			scope = 'profile',
			name = L['Nameplates'],
			title = L['Pick how your nameplates look'],
			text = L['The bars over enemies and friends. You can change any part later.'],
			cards = SetupSteps.Cards,
			get = function()
				return SetupSteps:Style()
			end,
			set = function(value)
				SetupSteps.pending.style = value
			end,
			-- One size for every style, so the card's style does not change the answer
			getVariant = function()
				return SetupSteps:Size()
			end,
			setVariant = function(value, variant)
				SetupSteps.pending.style = value
				SetupSteps.pending.size = variant
			end,
			onLeave = function(ctx)
				if ctx and ctx.closing then
					return
				end
				SetupSteps:Apply()
			end,
			summary = function()
				return SetupSteps:Summary()
			end,
		},
	}
end
