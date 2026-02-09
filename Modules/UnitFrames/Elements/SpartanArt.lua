local _G, SUI, L, UF = _G, SUI, SUI.L, SUI.UF
local ArtPositions = { ['full'] = 'Full frame skin', ['top'] = 'Top', ['bg'] = 'Background', ['bottom'] = 'Bottom' }

---@param frame table
---@param DB table
local function Build(frame, DB)
	local unitName = frame.unitOnCreate

	local SpartanArt = CreateFrame('Frame', nil, frame)
	SpartanArt:SetFrameStrata('BACKGROUND')
	SpartanArt:SetFrameLevel(2)
	SpartanArt:SetAllPoints()
	SpartanArt.top = SpartanArt:CreateTexture(nil, 'BORDER')
	SpartanArt.bg = SpartanArt:CreateTexture(nil, 'BACKGROUND')
	SpartanArt.bottom = SpartanArt:CreateTexture(nil, 'BORDER')
	SpartanArt.full = SpartanArt:CreateTexture(nil, 'BACKGROUND')
	SpartanArt.ArtSettings = frame.DB

	SpartanArt.PreUpdate = function(self, unit)
		if not unit or unit == 'vehicle' then
			return
		end
		SpartanArt.ArtSettings = self.DB

		for pos, _ in pairs(ArtPositions) do
			local ArtSettings = self.DB[pos]

			if ArtSettings and ArtSettings.enabled and ArtSettings.graphic ~= '' then
				local ufArt = UF.Style:Get(ArtSettings.graphic).artwork
				self[pos].ArtData = ufArt[pos]
				self[pos].ArtData.graphic = ArtSettings.graphic
				--Grab the settings for the frame specifically if defined (classic skin)
				if self[pos].ArtData.perUnit and self[pos].ArtData[unitName] then
					self[pos].ArtData = self[pos].ArtData[unitName]
				end
			end
		end
	end

	SpartanArt.PostUpdate = function(self, unit)
		for pos, _ in pairs(ArtPositions) do
			local ArtSettings = self.DB[pos]

			if ArtSettings and ArtSettings.enabled and ArtSettings.graphic ~= '' then
				local ufArt = UF.Style:Get(ArtSettings.graphic).artwork
				if ufArt[pos].UnitFrameCallback then
					ufArt[pos].UnitFrameCallback(self:GetParent(), unit)
				end
			end
		end
	end

	frame.SpartanArt = SpartanArt
end

---@param frame table
local function Update(frame)
	local element = frame.SpartanArt
	local DB = element.DB
	if not DB.enabled or not element.ForceUpdate then
		return
	end
	element.ArtSettings = element.DB
	element.ForceUpdate(element)
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	OptionSet.args.position = nil

	for position, DisplayName in pairs(ArtPositions) do
		OptionSet.args[position] = {
			name = DisplayName,
			type = 'group',
			disabled = true,
			get = function(info)
				return UF.CurrentSettings[unitName].elements.SpartanArt[position][info[#info]]
			end,
			set = function(info, val)
				if val == 0 then
					val = false
				end
				--Update memory
				UF.CurrentSettings[unitName].elements.SpartanArt[position][info[#info]] = val
				--Update the DB
				UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.SpartanArt[position][info[#info]] = val
				--Update the screen
				UF.Unit:Get(unitName):ElementUpdate('SpartanArt')
			end,
			args = {
				enabled = {
					name = L['Enabled'],
					type = 'toggle',
					order = 1,
				},
				graphic = {
					name = L['Current Style'],
					type = 'select',
					order = 2,
					values = { [''] = 'None' },
				},
				style = {
					name = L['Style'],
					type = 'group',
					order = 3,
					inline = true,
					args = {},
				},
				settings = {
					name = L['Settings'],
					type = 'group',
					inline = true,
					order = 500,
					args = {
						alpha = {
							name = L['Custom alpha'],
							desc = "This setting will override your art's default settings. Set to 0 to disable custom Alpha.",
							type = 'range',
							width = 'double',
							min = 0,
							max = 1,
							step = 0.01,
						},
					},
				},
			},
		}
	end

	for Name, styleDB in pairs(UF.Style:GetList()) do
		local data = styleDB.settings.artwork
		for position, _ in pairs(ArtPositions) do
			if data[position] then
				local options = OptionSet.args[position].args
				local dataObj = data[position]
				if dataObj.perUnit and data[unitName] then
					dataObj = data[unitName]
				end

				if dataObj then
					--Enable art option
					OptionSet.args[position].disabled = false
					--Add to dropdown
					options.graphic.values[Name] = (data.name or Name)
					--Create example
					options.style.args[Name] = {
						name = (data.name or Name),
						width = 'normal',
						type = 'description',
						image = function()
							if type(dataObj.path) == 'function' then
								local path = dataObj.path(nil, position)
								if path then
									return path, (dataObj.exampleWidth or 160), (dataObj.exampleHeight or 40)
								end
							else
								return dataObj.path, (dataObj.exampleWidth or 160), (dataObj.exampleHeight or 40)
							end
						end,
						imageCoords = function()
							if type(dataObj.TexCoord) == 'function' then
								local cords = dataObj.TexCoord(nil, position)
								if cords then
									return cords
								end
							else
								return dataObj.TexCoord
							end
						end,
					}
				end
			end
		end
	end
end

local sectiondefault = {
	enabled = false,
	x = 0,
	y = 0,
	alpha = 1,
	graphic = '',
}
---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	full = sectiondefault,
	top = sectiondefault,
	bg = sectiondefault,
	bottom = sectiondefault,
	config = {
		NoBulkUpdate = true,
		DisplayName = 'SUI Artwork',
	},
}

UF.Elements:Register('SpartanArt', Build, Update, Options, Settings)
