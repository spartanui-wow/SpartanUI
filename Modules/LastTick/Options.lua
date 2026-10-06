---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.LastTick
local module = SUI:GetModule('LastTick')

local function Get(key)
	return SUI.DBM:Get(module, key)
end

local function Set(key, value)
	SUI.DBM:Set(module, key, value, function()
		module:ApplySettings()
	end)
end

local function Color(name, order, key)
	return {
		type = 'color',
		name = name,
		order = order,
		hasAlpha = true,
		get = function()
			local c = Get(key)
			return c[1], c[2], c[3], c[4]
		end,
		set = function(_, r, g, b, a)
			Set(key, { r, g, b, a })
		end,
	}
end

function module:BuildOptions()
	---@type AceConfig.OptionsTable
	local options = {
		type = 'group',
		name = L['Last Tick'],
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			about = {
				type = 'description',
				order = 1,
				fontSize = 'medium',
				name = L['Shows how much damage your damage over time spells still have to deal, right on the health bar. If your health bar color ends inside the marked part, your DoTs will finish the enemy off, and a kill icon appears.'],
			},
			showOn = {
				type = 'group',
				name = L['Show on'],
				inline = true,
				order = 10,
				args = {
					target = {
						type = 'toggle',
						name = L['Target'],
						order = 1,
						get = function()
							return Get('target')
						end,
						set = function(_, val)
							Set('target', val)
						end,
					},
					focus = {
						type = 'toggle',
						name = L['Focus'],
						order = 2,
						hidden = function()
							return not FocusFrame and not (SUI.UF and SUI.UF.Unit and SUI.UF.Unit:Get('focus'))
						end,
						get = function()
							return Get('focus')
						end,
						set = function(_, val)
							Set('focus', val)
						end,
					},
					nameplates = {
						type = 'toggle',
						name = L['Enemy nameplates'],
						order = 3,
						get = function()
							return Get('nameplates')
						end,
						set = function(_, val)
							Set('nameplates', val)
						end,
					},
				},
			},
			marker = {
				type = 'group',
				name = L['Damage marker'],
				inline = true,
				order = 20,
				args = {
					texture = {
						type = 'select',
						name = L['Texture'],
						order = 1,
						dialogControl = 'LSM30_Statusbar',
						values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar or {},
						get = function()
							return Get('marker.texture')
						end,
						set = function(_, val)
							Set('marker.texture', val)
						end,
					},
					color = Color(L['Color'], 2, 'marker.color'),
					edge = {
						type = 'toggle',
						name = L['Line where health will end'],
						order = 3,
						get = function()
							return Get('marker.edge')
						end,
						set = function(_, val)
							Set('marker.edge', val)
						end,
					},
					edgeColor = Color(L['Line color'], 4, 'marker.edgeColor'),
				},
			},
			icon = {
				type = 'group',
				name = L['Kill icon'],
				inline = true,
				order = 30,
				args = {
					style = {
						type = 'select',
						name = L['Icon'],
						order = 1,
						values = {
							skull = '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16|t ' .. L['Skull'],
							cross = '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:16|t ' .. L['Cross'],
							elite = '|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:16|t ' .. L['Boss skull'],
							flame = '|TInterface\\Icons\\Spell_Shadow_Shadowburn:16|t ' .. L['Shadow flame'],
						},
						get = function()
							return Get('icon.style')
						end,
						set = function(_, val)
							Set('icon.style', val)
						end,
					},
					placement = {
						type = 'select',
						name = L['Placement'],
						order = 2,
						values = {
							portrait = L['On the portrait'],
							center = L['Middle of the health bar'],
							right = L['Right of the health bar'],
						},
						get = function()
							return Get('icon.placement')
						end,
						set = function(_, val)
							Set('icon.placement', val)
						end,
					},
					size = {
						type = 'range',
						name = L['Size'],
						order = 3,
						min = 8,
						max = 64,
						step = 1,
						get = function()
							return Get('icon.size')
						end,
						set = function(_, val)
							Set('icon.size', val)
						end,
					},
					x = {
						type = 'range',
						name = L['X offset'],
						order = 4,
						min = -100,
						max = 100,
						step = 1,
						get = function()
							return Get('icon.x')
						end,
						set = function(_, val)
							Set('icon.x', val)
						end,
					},
					y = {
						type = 'range',
						name = L['Y offset'],
						order = 5,
						min = -100,
						max = 100,
						step = 1,
						get = function()
							return Get('icon.y')
						end,
						set = function(_, val)
							Set('icon.y', val)
						end,
					},
					plateIcon = {
						type = 'toggle',
						name = L['Kill icon on nameplates'],
						order = 6,
						get = function()
							return Get('plateIcon.enabled')
						end,
						set = function(_, val)
							Set('plateIcon.enabled', val)
						end,
					},
					plateSize = {
						type = 'range',
						name = L['Nameplate icon size'],
						order = 7,
						min = 6,
						max = 40,
						step = 1,
						disabled = function()
							return not Get('plateIcon.enabled')
						end,
						get = function()
							return Get('plateIcon.size')
						end,
						set = function(_, val)
							Set('plateIcon.size', val)
						end,
					},
				},
			},
			learning = {
				type = 'group',
				name = L['Learning'],
				inline = true,
				order = 40,
				args = {
					about = {
						type = 'description',
						order = 1,
						name = L['Spell tooltips leave out your spell power, so each spell starts as a guess and learns its real tick size the first time it ticks. Clear what was learned after big gear changes.'],
					},
					forget = {
						type = 'execute',
						name = L['Forget learned ticks'],
						order = 2,
						func = function()
							module.Tracker:Forget()
						end,
					},
				},
			},
		},
	}
	SUI.Options:AddOptions(options, 'LastTick')
end

-- ============================================================================
-- Options preview: two sample health bars, one the DoTs will not finish and one they will
-- ============================================================================

local Stage = SUI.OptionsWindow and SUI.OptionsWindow.Stage
if not Stage then
	return
end

local SAMPLES = {
	{ health = 0.62, remaining = 0.38, label = L['Survives'] },
	{ health = 0.34, remaining = 0.41, label = L['Dies to your DoTs'] },
}
local preview

local function CreatePreview(canvas)
	local holder = CreateFrame('Frame', nil, canvas)
	holder.rows = {}
	for i, sample in ipairs(SAMPLES) do
		local row = CreateFrame('Frame', nil, holder)
		row:SetSize(240, 26)
		row:SetPoint('TOPLEFT', holder, 'TOPLEFT', 0, -(i - 1) * 40)

		local portrait = row:CreateTexture(nil, 'ARTWORK')
		portrait:SetSize(26, 26)
		portrait:SetPoint('LEFT', row, 'LEFT')
		portrait:SetTexture('Interface\\Icons\\INV_Misc_Head_Orc_01')
		portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		local bar = CreateFrame('StatusBar', nil, row)
		bar:SetPoint('TOPLEFT', portrait, 'TOPRIGHT', 4, 0)
		bar:SetPoint('BOTTOMRIGHT', row, 'BOTTOMRIGHT')
		bar:SetStatusBarTexture(SUI.UF:FindStatusBarTexture('SpartanUI Default'))
		bar:SetStatusBarColor(0.1, 0.75, 0.2)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(sample.health)
		local bg = bar:CreateTexture(nil, 'BACKGROUND')
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.6)

		local label = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
		label:SetPoint('BOTTOMLEFT', bar, 'TOPLEFT', 0, 2)
		label:SetText(sample.label)

		row.bar, row.portrait, row.sample = bar, portrait, sample
		row.overlay = module.Overlay.New(bar)
		holder.rows[i] = row
	end
	holder:SetSize(240, 66)
	return holder
end

---@type SUI.OptionsWindow.StageProvider
local provider = { path = { 'Modules', 'LastTick' } }

function provider:GetHeight()
	return 110
end

function provider:Render(ctx)
	preview = preview or CreatePreview(ctx.canvas)
	preview:SetParent(ctx.canvas)
	preview:SetFrameLevel(ctx.canvas:GetFrameLevel() + 5)
	preview:ClearAllPoints()
	preview:SetPoint('CENTER', ctx.canvas, 'CENTER', 0, -4)
	preview:Show()

	local settings = module.CurrentSettings
	local icon = module.ICONS[settings.icon.style] or module.ICONS.skull
	local look = {
		texture = settings.marker.texture,
		color = settings.marker.color,
		edge = settings.marker.edge,
		edgeColor = settings.marker.edgeColor,
		iconTexture = icon.texture,
		iconCoords = icon.coords,
		iconSize = math.min(settings.icon.size, 40),
		showIcon = true,
	}
	for _, row in ipairs(preview.rows) do
		local anchor, point, relative = row.bar, 'LEFT', 'RIGHT'
		if settings.icon.placement == 'portrait' then
			anchor, point, relative = row.portrait, 'CENTER', 'CENTER'
		elseif settings.icon.placement == 'center' then
			point, relative = 'CENTER', 'CENTER'
		end
		row.overlay:Attach(row.bar, anchor, point, relative, settings.icon.x, settings.icon.y, look)
		row.overlay:Show(row.sample.health, 1, row.sample.remaining)
		ctx.Region(row, { path = { 'Modules', 'LastTick' }, option = 'marker', label = L['Damage marker'] })
	end
end

function provider:Hide()
	if preview then
		preview:Hide()
	end
end

Stage:Register(provider)
