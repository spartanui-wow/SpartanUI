-- Offline rendering helper: execute the same layout and fitting functions as lupa.
local root, native = arg[1], tonumber(arg[2])
SUI = nil
local painted = dofile(root .. '/Themes/Painted.lua')
local data = painted.LAYOUT
local rw, rh = painted.BarSize(false)
local bw, bh = painted.BarSize(true)
data.barSize = { row = { rw, rh }, block = { bw, bh } }
data.frameHeight = painted.FrameHeight()
local result = { layout = data, bars = { default = painted.FitBars('', native) }, specs = {} }
SUI = {}
local health, lower = dofile(root .. '/Themes/Painted.lua').BarPoints()
result.barPoints = { health = health, lower = lower }
SUI = { ThemePainted = {
	Register = function(spec)
		result.specs[spec.name] = spec
	end,
} }
for _, name in ipairs({ 'Atlas', 'Boughs', 'Meridian' }) do
	dofile(root .. '/Themes/' .. name .. '/Style.lua')
	result.bars[name] = painted.FitBars(name, native)
end
local function json(value)
	if type(value) == 'table' then
		local parts = {}
		if #value > 0 then
			for _, item in ipairs(value) do
				parts[#parts + 1] = json(item)
			end
			return '[' .. table.concat(parts, ',') .. ']'
		end
		for key, item in pairs(value) do
			parts[#parts + 1] = string.format('%q', key) .. ':' .. json(item)
		end
		return '{' .. table.concat(parts, ',') .. '}'
	elseif type(value) == 'string' then
		return string.format('%q', value)
	end
	return tostring(value)
end
io.write(json(result))
