local _, ns = ...
local P = ns.Plates

-- The options preview provider for the host's side-panel Stage (3.2, 5.6). Owner: Phase 4a.
-- The host registers what P:BuildPreviewProvider returns through host.RegisterPreview. Until it
-- is built, it returns nil and the host registers nothing (Phase 2 testers get plain pages).
--
-- Provider shape (the host Stage contract, plus the Phase 1 additions in 3.2):
--   path      = host.OptionsPath() (the Nameplates root), zoomable = true, refit = true (the
--               scenes fit themselves to the canvas, so a new canvas size needs a new drawing)
--   GetHeight(ctx) -> height wanted, Render(ctx), Hide(), Close()
--   Action(ctx)  -> the "Show all parts" eye toggle
--   Footer(ctx)  -> "Undo move" on Customize
--   Toolbar(ctx) -> "Show: Enemy NPC" (Preview as) and Enlarge (Phase 1 Stage addition 6)
--   Hint(ctx)    -> page hint text (addition 5)
--   width        -> about 560 when Enlarge is on and the screen has room (addition 8)
-- Each drawn part registers a region with ctx.Region(frame, { path, option, label, detail,
-- selected, onClick, drag = { Start, Move(dx, dy), Stop } }) (additions 1-4), large parts first.
-- Scenes by page come from P.Scenes. Preview cast loops redraw through the Scheduler only while
-- the panel is shown.

---@return table|nil provider
function P:BuildPreviewProvider()
	return nil
end
