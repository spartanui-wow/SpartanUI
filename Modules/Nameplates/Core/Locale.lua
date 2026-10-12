local _, ns = ...
local P = ns.Plates

-- The core's own strings. Keys are the English text; a missing translation shows the key.
-- Hosts may add translations with P:AddTranslations, but never replace this table. Write every
-- string for a 6th grade reader, with no em dashes and no symbols the game cannot draw.
-- Strings that name the host use %s and P.host.name, never a fixed addon name.

---@type table<string, string>
P.L = setmetatable({}, {
	__index = function(t, k)
		t[k] = k
		return k
	end,
})

---Add translations for the current locale. Existing keys are overwritten, the table is kept.
---@param locale string|nil Only applied when it matches GetLocale() (nil applies always)
---@param strings table<string, string>
function P:AddTranslations(locale, strings)
	if locale and GetLocale and GetLocale() ~= locale then
		return
	end
	for key, text in pairs(strings) do
		rawset(self.L, key, text)
	end
end

---The host's name for strings such as "Follow my %s profile".
---@return string
function P:HostName()
	return (self.host and self.host.name) or ''
end
