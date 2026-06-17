--[[
	BlizzAPI.lua - Blizzard API Compatibility Layer

	PURPOSE:
	This file provides wrapper functions for Blizzard APIs that have DIFFERENT signatures
	or return values between WoW versions (Retail vs Classic variants).

	IMPORTANT NOTES:
	- As of Patch 1.15.2 (Dec 2024), many APIs were unified across all WoW versions
	- C_Item.*, C_Spell.*, and C_Container.* APIs are now IDENTICAL across all versions
	- These unified APIs should be called DIRECTLY - no wrapper needed
	- This file should ONLY contain wrappers for APIs that still differ between versions

	UNIFIED APIs (use directly, no wrapper):
	- C_Item.GetItemInfo() - Available in ALL versions (1.15.2+)
	- C_Item.GetDetailedItemLevelInfo() - Available in ALL versions (1.15.2+)
	- C_Spell.GetSpellInfo() - Available in ALL versions
	- C_Container.GetContainerItemInfo() - Available in ALL versions (1.15.0+)
	- C_Container.GetContainerNumSlots() - Available in ALL versions (1.15.0+)

	APIs THAT STILL NEED WRAPPERS:
	- Merchant APIs (C_MerchantFrame vs GetMerchantItemInfo - different return structures)

	USAGE:
	Only add wrappers here when an API has genuinely different signatures or return types
	across WoW versions. Document the differences clearly.
]]
---@class SUI
local SUI = SUI

---@class SUI.BlizzAPI
local BlizzAPI = {}

-- ============================================
-- MERCHANT API
-- ============================================

---@class MerchantItemInfo
---@field name string?
---@field texture number
---@field price number
---@field stackCount number
---@field numAvailable number
---@field isPurchasable boolean
---@field isUsable boolean
---@field hasExtendedCost boolean
---@field currencyID number?
---@field spellID number?
---@field isQuestStartItem boolean?

---Get merchant item info (normalized to retail MerchantItemInfo structure)
---@param index number
---@return MerchantItemInfo
function BlizzAPI.GetMerchantItemInfo(index)
	-- Use modern API if available (retail, or backported to classic)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		return C_MerchantFrame.GetItemInfo(index)
	end

	-- Fallback to classic API, wrap in retail-style table
	---@diagnostic disable-next-line: deprecated
	local name, texture, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost, currencyID, spellID = GetMerchantItemInfo(index)
	return {
		name = name,
		texture = texture,
		price = price,
		stackCount = quantity,
		numAvailable = numAvailable,
		isPurchasable = isPurchasable,
		isUsable = isUsable,
		hasExtendedCost = extendedCost and true or false,
		currencyID = currencyID,
		spellID = spellID,
		isQuestStartItem = false, -- Not available in classic
	}
end

-- ============================================
-- FEATURE DETECTION
-- ============================================

---Check if EditMode is available (being progressively backported to classic clients)
---Prefer checking C_EditMode directly where needed rather than using this wrapper
---@return boolean
function BlizzAPI.HasEditMode()
	return C_EditMode ~= nil
end

-- ============================================
-- SECRET VALUE API (Retail 12.0.0+)
-- ============================================
-- In Retail WoW 12.0.0+, certain aura properties become "secret values" during combat
-- when viewing other players' auras. These functions provide safe access patterns.
--
-- Classic/TBC/Wrath/Cata/MoP do NOT have secret values - all aura data is accessible.
-- These wrappers return safe defaults when the API doesn't exist.
--
-- Blizzard API reference: https://warcraft.wiki.gg/wiki/API_issecretvalue
-- ============================================

---Check if a value is a "secret value" (inaccessible during combat in Retail)
---Secret values cannot be used in comparisons, arithmetic, or string concatenation.
---@param value any The value to check
---@return boolean isSecret True if the value is secret and cannot be accessed
function BlizzAPI.issecretvalue(value)
	if not issecretvalue then
		return false -- Classic: no secret values exist, value is NOT secret
	end
	return issecretvalue(value)
end

---Check if a single value can be accessed (not a secret value)
---@param value any The value to check
---@return boolean canAccess True if the value can be safely read and used
function BlizzAPI.canaccessvalue(value)
	if not canaccessvalue then
		return true -- Classic: no secret values exist, value IS accessible
	end
	return canaccessvalue(value)
end

---Check if a table's contents can be accessed (no secret values within)
---Used primarily for aura data tables from C_UnitAuras functions.
---@param tbl table The table to check
---@return boolean canAccess True if the table contents can be safely read
function BlizzAPI.canaccesstable(tbl)
	if not canaccesstable then
		return true -- Classic: no secret values exist, table IS accessible
	end
	return canaccesstable(tbl)
end

-- ============================================
-- DURATION TEXT BINDING (Retail 12.0.7+)
-- ============================================

---@class LuaDurationObject
---@field SetTimeSpan fun(self: LuaDurationObject, startTime: number, endTime: number)
---@field SetTimeFromEnd fun(self: LuaDurationObject, endTime: number, duration: number, modRate?: number)
---@field SetTimeFromStart fun(self: LuaDurationObject, startTime: number, duration: number, modRate?: number)

---@class NumericFormatter
---@field SetDefaultAbbreviation fun(self: NumericFormatter, abbreviation: number)
---@field SetStripIntervalWhitespace fun(self: NumericFormatter, strip: number)
---@field SetMillisecondsThreshold fun(self: NumericFormatter, threshold: number)

---@class DurationTextBindingObject
---@field SetFontString fun(self: DurationTextBindingObject, fontString: FontString)
---@field SetFormatter fun(self: DurationTextBindingObject, formatter: NumericFormatter)
---@field SetDuration fun(self: DurationTextBindingObject, duration: LuaDurationObject)
---@field SetExpiredText fun(self: DurationTextBindingObject, text: string)
---@field SetZeroDurationText fun(self: DurationTextBindingObject, text: string)
---@field SetEnabled fun(self: DurationTextBindingObject, enabled: boolean)
---@field UpdateFontString fun(self: DurationTextBindingObject)

--[[
	Secret-safe live countdown text.

	WoW 12.0 makes aura expirationTime/duration secret values, so addons can no
	longer do arithmetic on them to draw "12s" countdown text on aura icons. Retail
	12.0.7 adds C_DurationUtil.CreateDurationTextBinding: we hand the engine a font
	string plus a (possibly secret) start/end time span, and the engine formats and
	updates the text itself. Our code never reads the secret value.

	Returns nil when the API is unavailable (older Retail / Classic), so callers can
	fall back to their existing OnUpdate path.
]]
local durationBindingAvailable = (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding and C_StringUtil and C_StringUtil.CreateSecondsFormatter) and true or false

---Whether secret-safe duration text binding is supported on this client.
---@return boolean
function BlizzAPI.HasDurationTextBinding()
	return durationBindingAvailable
end

---Build a SecondsFormatter that renders short countdowns (e.g. "1h", "5m", "12", "3.4").
---Enum/method availability is feature-detected: the formatter still works if a
---given knob is missing on the current build, it just uses the engine default.
---@return NumericFormatter|nil
local function CreateCountdownFormatter()
	local formatter = C_StringUtil.CreateSecondsFormatter()
	if not formatter then
		return nil
	end
	if formatter.SetDefaultAbbreviation and Enum.SecondsFormatterAbbreviation then
		formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
	end
	if formatter.SetStripIntervalWhitespace and Enum.SecondsFormatterIntervalWhitespace then
		formatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.Strip)
	end
	if formatter.SetMillisecondsThreshold then
		formatter:SetMillisecondsThreshold(5)
	end
	return formatter
end

---Create a reusable duration text binding bound to a FontString.
---The binding persists on the FontString; call BindDuration to (re)point it at a span.
---@param fontString FontString The text region to drive
---@return DurationTextBindingObject|nil binding nil if unsupported
function BlizzAPI.CreateDurationText(fontString)
	if not durationBindingAvailable or not fontString then
		return nil
	end
	local binding = C_DurationUtil.CreateDurationTextBinding()
	binding:SetFontString(fontString)
	local formatter = CreateCountdownFormatter()
	if formatter then
		binding:SetFormatter(formatter)
	end
	binding:SetExpiredText('')
	binding:SetZeroDurationText('')
	binding:SetEnabled(true)
	return binding
end

---Point an existing binding at a start/end time span and start updating.
---startTime/endTime may be secret values (e.g. aura.expirationTime) - the engine
---consumes them natively without exposing the value to addon code.
---@param binding DurationTextBindingObject The binding from CreateDurationText
---@param startTime number Span start (GetTime-relative, may be secret)
---@param endTime number Span end (GetTime-relative, may be secret)
function BlizzAPI.BindDuration(binding, startTime, endTime)
	if not binding then
		return
	end
	local duration = C_DurationUtil.CreateDuration()
	duration:SetTimeSpan(startTime, endTime)
	binding:SetDuration(duration)
	binding:SetEnabled(true)
end

---Point a binding at an end time plus a length (the shape aura data comes in).
---expirationTime/length may be secret values (aura.expirationTime / aura.duration);
---the engine consumes them natively, so addon code never reads the secret.
---@param binding DurationTextBindingObject The binding from CreateDurationText
---@param expirationTime number When the span ends (GetTime-relative, may be secret)
---@param length number Total length of the span in seconds (may be secret)
function BlizzAPI.BindDurationFromEnd(binding, expirationTime, length)
	if not binding then
		return
	end
	local duration = C_DurationUtil.CreateDuration()
	duration:SetTimeFromEnd(expirationTime, length)
	binding:SetDuration(duration)
	binding:SetEnabled(true)
end

---Stop a binding from updating and clear its text.
---@param binding DurationTextBindingObject|nil
function BlizzAPI.ClearDuration(binding)
	if not binding then
		return
	end
	binding:SetEnabled(false)
	binding:UpdateFontString()
end

SUI.BlizzAPI = BlizzAPI
