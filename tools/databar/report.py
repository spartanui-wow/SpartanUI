import json
from pathlib import Path

root=Path(__file__).resolve().parents[2]
out=root/'openspec/databar-art'
data=json.loads((out/'validation.json').read_text())
notes={
 'Arcane-Blue':('Slate, silver celestial cap, icy blue upper edge','Fine arcane engraving is subdued at 31 px.'),
 'Arcane-Red':('Slate, silver celestial cap, crimson upper edge','Fine arcane engraving is subdued at 31 px.'),
 'Classic':('Weathered dark steel/stone, aged gold, layered armor cap','Small plate detail is subdued at 31 px.'),
 'Digital':('Graphite tech panel, cool blue trace, chamfered cap','Thin traces are intentionally restrained.'),
 'Fel':('Scorched iron, fel-green rail, demonic horn cap','Flame and horn detail is compressed at 31 px.'),
 'Tribal':('Dark leather/wood, warm bone trim, bound tusk cap','Bone carving is softened to avoid repetition.'),
 'War-Alliance':('Deep navy steel, gold armor rail, cobalt corner','Armor scratches are softened in the tile.'),
 'War-Horde':('Black iron, crimson rail, short spiked corner','Iron cracks are softened in the tile.'),
 'Midnight':('Deep violet void, silver-violet filigree, violet inset','Small filigree is subdued at 31 px.'),
 'Voyager':('Dark leather, bronze/teal rails, compass/map cap','Stitching is softened to avoid repetition.'),
 'Grove':('Living dark wood, moss/bark rail, leafy branch cap','Fine wood grain is subdued at 31 px.'),
 'Meridian':('Ancient dark stone, bronze/teal rail, carved stone cap','Fine incisions are subdued at 31 px.')}

def hexcolor(values):
    return '#'+''.join(f'{round(v*255):02X}' for v in values)

lines=['# Painted DataBar strips','',
 'Complete: 12 looks, 48 RGBA theme PNGs, 12 dual-resolution previews, contact sheet, setup-card comparison, and 400% joint inspections. Original built-in imagegen paintings and exact prompts are preserved in `sources/`; Voyager reuses the permitted original painting. Existing theme/setup art was inspected as reference only. No status-bar or game-file pixels were used.', '',
 'All caps are 128 x 64. All text colors are `[0.96, 0.95, 0.91]` (`#F5F2E8`). The table gives label and hover accent colors; hover alpha is 0.18. Exact normalized colors, base names and cap widths are in `../../tools/databar/looks.json`. Contrast is value / label against the average middle 60% of the assembled strip, including caps.', '',
 '| Look | Material and end ornament | Cap | Label / hover | Contrast | Remaining small-scale tradeoff |',
 '| --- | --- | --- | --- | --- | --- |']
for r in data['results']:
    desc,note=notes[r['name']]
    lines.append(f"| {r['name']} | {desc} | 128 | {hexcolor(r['labelColor'])} / {hexcolor(r['highlight'][:3])} | {r['textContrast']:.2f} / {r['labelContrast']:.2f}:1 | {note} |")
lines+=['','Validation: all 48 filenames, dimensions, RGBA modes and full alpha passed. Both text colors exceed 4.5:1 for every look. Tiles have identical left/right boundary pixels; cap right edges match tile left edges. The 400% joint sheets, full-width 1920/2560 repeats, and cards beside their existing setup artwork were visually inspected. Repeated standout detail was reduced during assembly; no visible vertical seams or conspicuous recurring motifs remain at preview size.', '',
 'The stronger trim faces upward for a bottom bar; the lower lip stays dark. Both screen crops use aspect-preserving scaled/repeated tiles and mirrored caps with all six requested sample plugins in Roboto Condensed Bold at 11.5 UI units. Cards use a 70 px strip and two sample plugins, kept within the center 70% for cropping. `contact.png` includes all cards at 210 x 148.', '',
 'Checks and measurements: `validation.json`. Inspection: `contact.png`, `card-comparison.png`, `joints-400.png`, and per-look previews/joints. Rebuild instructions: `../../tools/databar/README.md`. No in-game rendering was tested. No commits or pushes were made; unrelated checkout edits were preserved.']
(out/'REPORT.md').write_text('\n'.join(lines)+'\n')
print(out/'REPORT.md')
