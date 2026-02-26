---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt

---@class SUI.MoveIt.Migration
local Migration = {}
MoveIt.Migration = Migration

---Clean up EditMode positioning integration (one-time migration)
---Runs once on first login after update to preserve user data while removing obsolete features
function Migration:CleanupEditModePositioning()
	-- Only run once
	if MoveIt.DBG and MoveIt.DBG.EditModePositioningRemoved then
		return
	end

	if MoveIt.logger then
		MoveIt.logger.info('Running EditMode positioning cleanup migration...')
	end

	-- Initialize DBG if needed
	if not MoveIt.DBG then
		if MoveIt.logger then
			MoveIt.logger.warning('Migration: MoveIt.DBG not initialized yet')
		end
		return
	end

	-- Clean up wizard-specific tracking (no longer used)
	-- EditModeSetupCharacters was only used by the wizard system
	if MoveIt.DBG.EditModeSetupCharacters then
		if MoveIt.logger then
			MoveIt.logger.debug('Removing EditModeSetupCharacters (wizard-specific, obsolete)')
		end
		MoveIt.DBG.EditModeSetupCharacters = nil
	end

	-- KEEP CurrentProfiles table (needed for optional profile sync feature)
	-- This table tracks which EditMode profile each character is using
	-- The EditModeProfileSync feature still uses this when enabled
	if MoveIt.DBG.CurrentProfiles then
		if MoveIt.logger then
			MoveIt.logger.debug('Preserving CurrentProfiles (used by EditMode profile sync)')
		end
	end

	-- Clean up old profile settings that are no longer used
	if MoveIt.DB then
		-- Remove old EditMode wizard tracking
		if MoveIt.DB.EditModeWizard then
			if MoveIt.logger then
				MoveIt.logger.debug('Removing EditModeWizard (obsolete)')
			end
			MoveIt.DB.EditModeWizard = nil
		end

		-- Remove old EditMode control settings
		if MoveIt.DB.EditModeControl then
			if MoveIt.logger then
				MoveIt.logger.debug('Removing EditModeControl (obsolete)')
			end
			MoveIt.DB.EditModeControl = nil
		end
	end

	-- Clean up old global preferences
	if MoveIt.DBG.EditModePreferences then
		if MoveIt.logger then
			MoveIt.logger.debug('Removing EditModePreferences (obsolete)')
		end
		MoveIt.DBG.EditModePreferences = nil
	end

	-- Set migration flag to prevent re-running
	MoveIt.DBG.EditModePositioningRemoved = true

	-- Show one-time notice to user
	local LibEMO = LibStub and LibStub('LibEditModeOverride-1.0', true)
	if LibEMO then
		if MoveIt.logger then
			MoveIt.logger.info('Migration complete - EditMode positioning removed, optional profile sync available')
		end
		SUI:Print('EditMode positioning integration has been removed. Frame positions now use custom movers. Optional EditMode profile sync is still available in settings.')
	else
		if MoveIt.logger then
			MoveIt.logger.info('Migration complete - EditMode positioning removed')
		end
		SUI:Print('EditMode positioning integration has been removed. Frame positions now use custom movers.')
	end
end

---Adjust saved minimap mover position to compensate for MinimapContainer offset removal in 6.19.0.
---The container offset changed from (-30, 32) to (0, 0). Saved mover positions must shift by
---(-30, +32) in WoW coordinates so the visual minimap appears in the same screen location.
function Migration:FixMinimapContainerOffset()
	if not SUI.IsRetail then
		return
	end

	local migrationVersion = '6.19.0'
	if MoveIt.DBG.MinimapOffsetMigrationVersion == migrationVersion then
		return
	end

	if MoveIt.DB and MoveIt.DB.movers and MoveIt.DB.movers['Minimap'] then
		local movedPoints = MoveIt.DB.movers['Minimap'].MovedPoints
		if movedPoints then
			local point, anchor, secondaryPoint, x, y = strsplit(',', movedPoints)
			x = tonumber(x)
			y = tonumber(y)
			if x and y then
				x = x - 30
				y = y + 32
				MoveIt.DB.movers['Minimap'].MovedPoints = format('%s,%s,%s,%d,%d', point, anchor, secondaryPoint, x, y)
				if MoveIt.logger then
					MoveIt.logger.info('6.19.0: Adjusted minimap mover position for container offset fix')
				end
			end
		end
	end

	MoveIt.DBG.MinimapOffsetMigrationVersion = migrationVersion
end

---Initialize migration system
---Called during MoveIt:OnEnable()
function Migration:Initialize()
	-- Run cleanup migration if needed
	self:CleanupEditModePositioning()
	self:FixMinimapContainerOffset()
end
