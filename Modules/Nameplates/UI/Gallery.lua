local _, ns = ...
local P = ns.Plates
local L = P.L

-- Style gallery cards (3.4) for the host's card grid widget (host.widgets.cardGrid) on the Style
-- page, and for the setup look step. Owner: Phase 4a (live art). Each card's art.draw hook (LibAT
-- Phase 1 release, feature-detected) draws the real renderer with SampleSource into the card;
-- without it the card shows the style name and its one-line description. Cards are pooled and
-- updated in place. Hovering a card calls arg.onHover(value) so the preview draws that style.

---@class Plates.Gallery
local Gallery = {}
P.Gallery = Gallery

---Card data for every style the player can pick (internal styles left out). "Match my look" is
---the host style marked matchesHost and is badged.
---@return table[] cards { value, title, caption, tag?, recommended?, art? }
function Gallery:Cards()
	local current = P.db and P.db.profile.style
	local cards = {}
	for _, item in ipairs(P.Styles.Registry:List(false)) do
		local tag
		if item.id == current or (current == 'host' and item.matchesHost) then
			tag = L['In use']
		elseif item.matchesHost then
			tag = L['Matches your look']
		end
		cards[#cards + 1] = {
			value = item.matchesHost and 'host' or item.id,
			title = item.name,
			caption = item.description,
			tag = tag,
			recommended = item.matchesHost or nil,
			art = self:Art(item.id),
		}
	end
	return cards
end

---Live art for a card (nil until the art.draw hook is wired in Phase 4a).
---@param styleId string
---@return table|nil
function Gallery:Art(styleId)
	return nil
end
