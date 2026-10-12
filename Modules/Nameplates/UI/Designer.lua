local _, ns = ...
local P = ns.Plates

-- Drag-to-move on the Customize page (Phase 4a) and the full designer (Phase 7), in the preview
-- panel. Never a control inside an options page (pages are torn down on every change).
--
-- Phase 4a: select a part (click), then drag it; snap guides to plate edges and centers; on drop
-- the anchor is chosen for the player: the side of the nearest part edge or the plate center the
-- part sits on, snapping to a center within about 2 px, offsets rounded to half pixels. The cursor
-- delta is turned into plate units with the dragged part's GetEffectiveScale(). Arrow keys nudge
-- by 0.5 px (Shift 2 px) only while a part is selected, the cursor is over the panel and the
-- player is out of combat; Delete hides the part; Ctrl-Z or "Undo move" undoes the last move.
-- Every edit writes the overlay (profile.tweaks[styleId].changes.parts[id].anchor) through
-- P.Store, so "Undo my changes" and "Reset this part" always work.
-- Phase 7: resize handles, part palette, multi-select, aura text positioner, editable regions,
-- 20-step undo and redo (the style table is copied when a drag starts).

---@class Plates.Designer
local Designer = { undo = {} }
P.Designer = Designer

---Pick the anchor for a dropped part (pure). Rects are relative to the plate center.
---@param partRect Plates.Rect Where the part was dropped
---@param targets table<string, Plates.Rect> Other parts and 'plate'
---@return table anchor { point, relativeTo, relPoint, x, y }
function Designer.DropAnchor(partRect, targets)
	local cx = (partRect.left + partRect.right) / 2
	local cy = (partRect.top + partRect.bottom) / 2
	local function Half(v)
		return math.floor(v * 2 + 0.5) / 2
	end
	return { 'CENTER', 'plate', 'CENTER', Half(cx), Half(cy) }
end

---Remember an overlay state before an edit (one step at launch).
---@param styleId string
function Designer:Push(styleId)
	self.undo[1] = { styleId = styleId, tweaks = P.util.Copy(P.Store:Get({ 'tweaks', styleId })) }
end

---Undo the last move.
function Designer:Undo()
	local step = table.remove(self.undo)
	if step then
		P.Store:Set({ 'tweaks', step.styleId }, step.tweaks)
	end
end
