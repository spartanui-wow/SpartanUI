local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	local ResurrectIndicator = frame.raised:CreateTexture(nil, 'OVERLAY')
	frame.ResurrectIndicator = ResurrectIndicator
end

---@param frame table
local function Update(frame)
	local element = frame.ResurrectIndicator
	local DB = element.DB
	element:SetSize(DB.size, DB.size)
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	size = 20,
	config = {
		type = 'Indicator',
		DisplayName = 'Resurrect',
	},
}

UF.Elements:Register('ResurrectIndicator', Build, Update, nil, Settings)
