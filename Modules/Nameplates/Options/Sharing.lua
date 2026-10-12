local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Sharing and profiles page (3.2 #6). Launch: the profile picker and "Follow my <host> profile"
-- (the label names the host through P:HostName()). Phase 5: export a style, colors, the "When"
-- list or everything; paste to import with a live preview card (P.Share:InspectStyle), Add as a
-- new style or Use it now, update-keeps-your-changes.

Options:AddPage('sharing', 6, function()
	local getFollow, setFollow = Options.Bind('followHostProfile')
	return {
		type = 'group',
		name = L['Sharing and profiles'],
		args = {
			follow = {
				type = 'toggle',
				name = string.format(L['Follow my %s profile'], P:HostName()),
				desc = L['Your nameplate settings switch when your main profile switches.'],
				order = 1,
				width = 'full',
				hidden = function()
					return not (P.host and P.host.GetHostProfileName)
				end,
				get = getFollow,
				set = function(info, value)
					setFollow(info, value)
					P.Store:FollowHostProfile()
				end,
				disabled = Options.Locked,
			},
		},
	}
end)
