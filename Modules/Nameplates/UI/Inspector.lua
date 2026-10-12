local _, ns = ...
local P = ns.Plates
local L = P.L

-- "Why this color" (3.2 hover in the preview, 3.7 Alt-hover in the world from Phase 5). Plain
-- chains name the winning row; when hidden rows could have decided, it says "One of: X, Y",
-- because Lua cannot read the result. In the preview the answer is always exact (samples are plain).

---@class Plates.Inspector
local Inspector = {}
P.Inspector = Inspector

---One line explaining a piece's color on a plate, e.g. "Red: threat (you are not tanking)".
---@param plate Plates.Plate
---@param piece string 'health' | 'border' | 'name' | 'cast'
---@return string
function Inspector:Explain(plate, piece)
	local Colors = P.Colors
	local program = Colors:Program(piece, plate.env.ctx)
	local winner, maybe = Colors:Explain(program, plate.env)
	if #maybe > 0 then
		local names = {}
		for _, row in ipairs(maybe) do
			names[#names + 1] = Colors:Sentence(row)
		end
		if winner then
			names[#names + 1] = Colors:Sentence(winner)
		end
		return L['One of:'] .. ' ' .. table.concat(names, ', ')
	end
	if winner then
		return Colors:Sentence(winner)
	end
	return L['Default color']
end
