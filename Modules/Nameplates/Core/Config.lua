local _, ns = ...
local P = ns.Plates

-- The core's own database (6.10). Defaults are scalars only and live in code; built-in styles,
-- default color orders and default assignments live in their own files, never in AceDB defaults.
-- The schema number is never a default: AceDB answers with the default for any profile that never
-- stored a value, so a changed default would let old profiles skip a migration. Instead:
--   * profile.schema / global.schema stay out of defaults; nil reads as "oldest".
--   * OnNewProfile and OnProfileReset stamp the current number (registered before the first read
--     of db.profile, because AceDB fires OnNewProfile on that first access).
--   * Every migration stamps its number when it finishes.

---@class Plates.Config
local Config = {}
P.Config = Config

---Current data format numbers. Raise one together with a new patch in Migrate.
Config.SCHEMA = { profile = 1, global = 1 }

---Fresh defaults table (pitfalls 2026-10-08: RegisterDefaults must never get an edited table).
---Host-only defaults (such as followHostProfile) are copied in from the host config.
---@return table
function Config:Defaults()
	local defaults = {
		profile = {
			-- false: the Driver stands down for this profile (Blizzard plates, no suppression, our
			-- place settings given back) until it is true again
			enabled = true,
			style = 'host', -- 'host' resolves to the host look, or Clean when there is none
			size = 'medium',
			role = 'auto', -- 'auto' | 'tank' | 'damage' | 'healer'
			scheme = 'auto', -- 'auto' | 'threat' | 'mobType' | 'class' | 'custom'
			colorBlind = false,
		},
		global = {},
		char = {},
	}
	local host = P.host
	if host then
		for key, value in pairs(host.profileDefaults or {}) do
			if type(value) ~= 'table' then
				defaults.profile[key] = value
			end
		end
		for key, value in pairs(host.globalDefaults or {}) do
			if type(value) ~= 'table' then
				defaults.global[key] = value
			end
		end
	end
	return defaults
end

local function Stamp(db)
	local profile = rawget(db, 'profile') or db.profile
	profile.schema = Config.SCHEMA.profile
end

---Open the database. Sets P.db and captures the session engine choice (reload-gated).
function Config:Open()
	local host = P.host
	local AceDB = LibStub('AceDB-3.0')
	-- Every character starts on one shared "Default" profile (Messenger pattern), so a new Forever
	-- character never gets its own "Unknown" profile (pitfalls 2026-10-05).
	local db = AceDB:New(host.savedVariable, self:Defaults(), true)
	P.db = db

	db.RegisterCallback(Config, 'OnNewProfile', function(_, database)
		Stamp(database)
	end)
	db.RegisterCallback(Config, 'OnProfileReset', function(_, database)
		Stamp(database)
		P.Migrate:RunProfile()
		P.Store:ProfileSwapped(P.ALL_REASONS)
	end)
	db.RegisterCallback(Config, 'OnProfileChanged', function()
		P.Migrate:RunProfile()
		P.Store:ProfileSwapped()
	end)
	db.RegisterCallback(Config, 'OnProfileCopied', function()
		P.Migrate:RunProfile()
		P.Store:ProfileSwapped(P.ALL_REASONS)
	end)
	db.RegisterCallback(Config, 'OnProfileDeleted', function()
		P:Fire('PROFILES_CHANGED')
	end)

	-- First read after the callbacks exist, so a brand-new profile is stamped
	local _ = db.profile
	P.Store:Track()

	self.sessionEngine = db.char.engine
end

---The tester switch value saved for this character: 'new' | 'old' | nil (Phases 2 to 4a only).
---@return string|nil
function Config:GetEngineChoice()
	return P.db and P.db.char.engine or nil
end

---Change the tester switch. Takes effect after a reload (the session value never changes).
---@param value 'new'|'old'|nil
function Config:SetEngineChoice(value)
	if P.db then
		P.db.char.engine = value
	end
end

---The tester switch value this session started with.
---@return string|nil
function Config:GetSessionEngine()
	return self.sessionEngine
end
