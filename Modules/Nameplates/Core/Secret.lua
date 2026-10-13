local _, ns = ...
local P = ns.Plates

-- Secret-value helpers (6.3). On Retail and Forever, many unit values are "secret" for addon code:
-- they may be stored in a local and handed to an engine sink, but never compared, tested for
-- truth (booleans), used in arithmetic, concatenated for logic, or used as table keys.
--
-- Rules every file follows (the token lint checks them):
--   * A value returned by a Source method ending in `Secret` may only be passed straight to an
--     approved sink, or kept in a local whose name ends in `Secret` that is only used as a sink
--     argument. Approved sinks are listed in Secret.SINKS and in .context/nameplates.md.
--   * The only allowed presence test on a secret is `type(x) == 'nil'` (or `~=`).
--   * To use a value in Lua logic, call the matching `Plain` method instead: it returns
--     `value, true` when readable and `nil, false` when the game hides it.
-- On the Classic family nothing is secret, so the same code just sees plain values.

---@class Plates.Secret
local Secret = {}
P.Secret = Secret

---Sink methods and functions that accept secret values from addon code (documentation for the
---lint and for reviewers; the helpers below are sinks too).
Secret.SINKS = {
	'SetMinMaxValues',
	'SetValue',
	'SetStatusBarColor',
	'SetTimerDuration',
	'SetText',
	'SetFormattedText',
	'SetTextColor',
	'SetVertexColor',
	'SetAlphaFromBoolean',
	'SetVertexColorFromBoolean',
	'SetSpriteSheetCell',
	'SetTexture',
	'C_CurveUtil.EvaluateColorFromBoolean',
	'C_CurveUtil.EvaluateColorValueFromBoolean',
	'UnitHealthPercent',
	'AbbreviateNumbers',
	'C_StringUtil.TruncateWhenZero',
	'C_ClassColor.GetClassColor',
	'C_Spell.IsSpellImportant',
	'DurationTextBinding:SetDuration',
	-- SetAlpha is documented to take secrets on frames and regions, but it stays off this list
	-- until an in-game check confirms it (plan 6.3); the lint refuses it (notSinks)
	'P.Secret.ChooseValue',
	'P.Secret.ChooseColor',
	'P.Secret.SetAlphaFromBoolean',
	'P.Secret.SetVertexColorFromBoolean',
	'P.Secret.SetRaidMarker',
	'P.Secret.Plain',
	'P.Secret.CanAccess',
	'P.Secret.CanIndex',
	'P.Secret.IsSecret',
	'P.Colors:Apply',
	'P.Conditions:FoldSecret',
	'P.Conditions:FoldColorSecret',
}

local canaccessvalue = canaccessvalue
local canaccesstable = canaccesstable
local issecretvalue = issecretvalue

---True when addon code may operate on the value (always true on clients without secrets).
---@param value any
---@return boolean
function Secret.CanAccess(value)
	if canaccessvalue then
		return canaccessvalue(value) and true or false
	end
	return true
end

---True when the value is secret (never true on clients without secrets).
---@param value any
---@return boolean
function Secret.IsSecret(value)
	if issecretvalue then
		return issecretvalue(value) and true or false
	end
	return false
end

---True when a table may be indexed (canaccesstable): a table can pass canaccessvalue and still be
---forbidden to index. Always true on clients without the function.
---@param value any
---@return boolean
function Secret.CanIndex(value)
	if type(value) ~= 'table' then
		return false
	end
	if canaccessvalue and not canaccessvalue(value) then
		return false
	end
	if canaccesstable then
		return canaccesstable(value) and true or false
	end
	return true
end

---Readable value or nil, plus whether it was readable. The building block of every Plain method.
---@param value any
---@return any value
---@return boolean readable
function Secret.Plain(value)
	if canaccessvalue and not canaccessvalue(value) then
		return nil, false
	end
	return value, true
end

---@return boolean
function Secret.HasRestrictions()
	return P.Caps:Get('secrets')
end

local function Ask(fnName, ...)
	local fn = C_Secrets and C_Secrets[fnName]
	if not fn then
		return false
	end
	local ok, result = pcall(fn, ...)
	return ok and result == true
end

---@param unit string
---@param mobUnit? string
---@return boolean
function Secret.ShouldUnitThreatStateBeSecret(unit, mobUnit)
	return Ask('ShouldUnitThreatStateBeSecret', unit, mobUnit)
end

---@param unit string
---@param mobUnit string
---@return boolean
function Secret.ShouldUnitThreatValuesBeSecret(unit, mobUnit)
	return Ask('ShouldUnitThreatValuesBeSecret', unit, mobUnit)
end

---@param unit string
---@return boolean
function Secret.ShouldUnitIdentityBeSecret(unit)
	return Ask('ShouldUnitIdentityBeSecret', unit)
end

---@param unit1 string
---@param unit2 string
---@return boolean
function Secret.ShouldUnitComparisonBeSecret(unit1, unit2)
	return Ask('ShouldUnitComparisonBeSecret', unit1, unit2)
end

---@param unit string
---@return boolean
function Secret.ShouldUnitSpellCastingBeSecret(unit)
	return Ask('ShouldUnitSpellCastingBeSecret', unit)
end

---@return boolean
function Secret.ShouldAurasBeSecret()
	return Ask('ShouldAurasBeSecret')
end

---True when the two unit tokens may be compared (UnitIsUnit gives a usable answer). Clients
---without the function have no secrets, so the answer is yes there.
---@param unit1 string
---@param unit2 string
---@return boolean
function Secret.CanCompareUnitTokens(unit1, unit2)
	local fn = C_Secrets and C_Secrets.CanCompareUnitTokens
	if not fn then
		return true
	end
	local ok, result = pcall(fn, unit1, unit2)
	return ok and result == true
end

---Secrecy level of a spell's cooldown (Enum.SecrecyLevel), or nil when unknown.
---@param spellID number
---@return number|nil
function Secret.GetSpellCooldownSecrecy(spellID)
	local fn = C_Secrets and C_Secrets.GetSpellCooldownSecrecy
	if not fn then
		return nil
	end
	local ok, level = pcall(fn, spellID)
	return ok and level or nil
end

---The gate for every settings lock (3.2) and every aura container change (6.6): true while in
---combat lockdown, or while the game keeps auras secret (which can hold out of combat in
---restricted instances). Only after login and only where secrets exist.
---@return boolean
function Secret.IsRestricted()
	if IsLoggedIn and not IsLoggedIn() then
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		return true
	end
	if not Secret.HasRestrictions() then
		return false
	end
	return Secret.ShouldAurasBeSecret()
end

----------------------------------------------------------------------------------------------------
-- Sink helpers. Each takes possibly-secret input and never inspects it in Lua.
----------------------------------------------------------------------------------------------------

---Pick one of two numbers by a possibly-secret boolean. The result may be secret; feed it only
---to another sink (including this one). Plain fallback on clients without the curve API.
---@param conditionSecret any boolean, possibly secret
---@param ifTrue any number, possibly secret
---@param ifFalse any number, possibly secret
---@return any valueSecret
function Secret.ChooseValue(conditionSecret, ifTrue, ifFalse)
	-- No answer (a unit that is not on the threat list, for example) counts as false; the engine
	-- function does not take nil
	if type(conditionSecret) == 'nil' then
		return ifFalse
	end
	local fn = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
	if fn then
		return fn(conditionSecret, ifTrue, ifFalse)
	end
	if conditionSecret then
		return ifTrue
	end
	return ifFalse
end

---Pick one of two ColorMixin by a possibly-secret boolean (whole-color form, S3 optimization).
---@param conditionSecret any
---@param ifTrue table ColorMixin
---@param ifFalse table ColorMixin
---@return table colorSecret
function Secret.ChooseColor(conditionSecret, ifTrue, ifFalse)
	if type(conditionSecret) == 'nil' then
		return ifFalse
	end
	local fn = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean
	if fn then
		return fn(conditionSecret, ifTrue, ifFalse)
	end
	if conditionSecret then
		return ifTrue
	end
	return ifFalse
end

---Show or fade a region by a possibly-secret boolean. Always passes both alphas: the documented
---default for alphaIfTrue is a doc artifact (Appendix C).
---@param region table Region or Frame
---@param conditionSecret any
---@param alphaIfTrue? number default 1
---@param alphaIfFalse? number default 0
function Secret.SetAlphaFromBoolean(region, conditionSecret, alphaIfTrue, alphaIfFalse)
	alphaIfTrue = alphaIfTrue or 1
	alphaIfFalse = alphaIfFalse or 0
	if type(conditionSecret) == 'nil' then
		region:SetAlpha(alphaIfFalse)
		return
	end
	if region.SetAlphaFromBoolean then
		region:SetAlphaFromBoolean(conditionSecret, alphaIfTrue, alphaIfFalse)
		return
	end
	-- Clients without the method have no secrets
	if conditionSecret then
		region:SetAlpha(alphaIfTrue)
	else
		region:SetAlpha(alphaIfFalse)
	end
end

---Tint a texture by a possibly-secret boolean.
---@param texture table
---@param conditionSecret any
---@param colorIfTrue table ColorMixin
---@param colorIfFalse table ColorMixin
function Secret.SetVertexColorFromBoolean(texture, conditionSecret, colorIfTrue, colorIfFalse)
	if type(conditionSecret) == 'nil' then
		texture:SetVertexColor(colorIfFalse.r, colorIfFalse.g, colorIfFalse.b, colorIfFalse.a or 1)
		return
	end
	if texture.SetVertexColorFromBoolean then
		texture:SetVertexColorFromBoolean(conditionSecret, colorIfTrue, colorIfFalse)
		return
	end
	local color = conditionSecret and colorIfTrue or colorIfFalse
	texture:SetVertexColor(color.r, color.g, color.b, color.a or 1)
end

---Raid marker icon from a possibly-secret index. Hides the texture when there is no marker,
---using the approved presence test.
---@param texture table
---@param indexSecret any number 1-8 or nil, possibly secret
function Secret.SetRaidMarker(texture, indexSecret)
	if type(indexSecret) == 'nil' then
		texture:Hide()
		return
	end
	if texture.SetSpriteSheetCell then
		texture:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons')
		texture:SetSpriteSheetCell(indexSecret, 4, 4)
	elseif SetRaidTargetIconTexture then
		texture:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons')
		SetRaidTargetIconTexture(texture, indexSecret)
	end
	texture:Show()
end
