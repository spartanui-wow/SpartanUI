# War Horde kit image provenance

Generated with OpenAI's built-in image generation tool on 2026-10-01. The image inputs were the local Horde contact sheet in `tools/source_refs` and, for the frame repaint, the generated Alliance frame master. The Alliance alpha is reapplied during processing so both faction frames have one exact silhouette. `tools/make_kit_art.py` performs all deterministic resizing, alpha handling, one-master frame slicing, seamless tiling, dimming, and preview rendering.

## frame-top-left.png, frame-top-right.png, frame-bottom-left.png, frame-bottom-right.png, frame-top.png, frame-bottom.png, frame-left.png, frame-right.png

Generated master: `tools/source_art/war-horde/frame-source.png`

```text
Use case: precise-object-edit
Asset type: Horde material repaint of a shared-shape game UI 9-slice frame
Primary request: Repaint only the supplied Alliance frame's materials and surface detailing into a Horde treatment while preserving its exact geometry, silhouette, beam widths, corner locations, transparent center and overall alignment. Replace polished blue steel with blackened rough iron, gold trim with dark hammered iron edges, white stone insets with worn deep-red leather or cloth panels, and clean rivets with heavier irregular iron rivets. Add a few restrained blunt spikes only where they fit inside the existing corner silhouette; do not change the outer bounds. Rugged, brutal and hand-forged. Do not add any faction crest, emblem, logo or symbol.
Input images: Image 1 is the edit target and exact shared frame shape; Image 2 is a supporting SpartanUI Horde material reference.
Constraints: change materials and surface treatment only; preserve Image 1 geometry exactly; keep genuinely transparent background and transparent center; no text, letters, logos, crests, faction symbols, heraldic animals, runes, faces, skulls, watermark, or emoji.
```

## divider.png

Generated master: `tools/source_art/war-horde/divider-source.png`

```text
Use case: stylized-concept
Asset type: centered Horde divider ornament for a War game UI
Primary request: A long thin blackened-iron divider wrapped with a narrow strip of worn deep-red leather, rough rivets, chipped edges and a small centered angular iron spike cluster. Brutal and hand-forged, crisp at 512x32, but fully abstract with no faction crest, emblem, logo or symbol.
Input image: Image 1 is a style reference contact sheet of SpartanUI's War Horde materials.
Composition/framing: perfectly horizontal and centered on a square canvas, artwork confined to a narrow band through the vertical center with generous transparency.
Constraints: genuinely transparent background; no text, letters, logos, crests, faction symbols, heraldic animals, runes, faces, skulls, watermark, or emoji.
```

## marker.png

Generated master: `tools/source_art/war-horde/marker-source.png`

```text
Use case: stylized-concept
Asset type: current-step marker icon for a Horde War game UI rail
Primary request: A compact rough marker made from a glowing dark-red ember core, blackened iron bands, heavy rivets and four short blunt spike tabs. It should feel brutal and martial but remain an abstract ornament, not a crest or emblem. Strong readable silhouette at 20 pixels.
Input image: Image 1 is a style reference contact sheet of SpartanUI's War Horde materials.
Composition/framing: one icon only, centered, front-on, filling about 82 percent of a square canvas with transparent padding.
Constraints: genuinely transparent background; no text, letters, logos, crests, faction symbols, heraldic animals, runes, faces, skulls, watermark, or emoji.
```

## node-done.png

Generated master: `tools/source_art/war-horde/node-done-source.png`

```text
Use case: stylized-concept
Asset type: completed-step node icon for a Horde War game UI rail
Primary request: A compact solid blackened-iron rivet node with a filled glowing dark-red center, rough hammered rim and tiny leather detail. It communicates completed through a solid hot center, not a checkmark. Brutal silhouette at 16 pixels; abstract hardware, not a crest or emblem.
Input image: Image 1 is a style reference contact sheet of SpartanUI's War Horde materials.
Composition/framing: one icon only, centered, front-on, filling about 68 percent of a square canvas with transparent padding.
Constraints: genuinely transparent background; no text, letters, numerals, checkmarks, logos, crests, faction symbols, heraldic animals, runes, faces, skulls, watermark, or emoji.
```

## node-upcoming.png

Generated master: `tools/source_art/war-horde/node-upcoming-source.png`

```text
Use case: stylized-concept
Asset type: upcoming-step hollow node icon for a Horde War game UI rail
Primary request: A compact hollow blackened-iron rivet ring with rough edges, four tiny blunt tabs, a dim red leather inner rim and a genuinely open transparent center. Dormant and dimmer than the completed node, readable at 16 pixels; abstract hardware, not a crest or emblem.
Input image: Image 1 is a style reference contact sheet of SpartanUI's War Horde materials.
Composition/framing: one icon only, centered, front-on, filling about 68 percent of a square canvas with transparent padding.
Constraints: genuinely transparent background and genuinely transparent inner opening; no text, letters, numerals, checkmarks, logos, crests, faction symbols, heraldic animals, runes, faces, skulls, watermark, or emoji.
```

## material.png

Generated master: `tools/source_art/war-horde/material-source.png`

```text
Use case: stylized-concept
Asset type: seamless low-contrast Horde material texture for War game UI panels
Primary request: A subtle tileable field combining soot-black hammered iron, worn deep-red leather or cloth fibers, faint scratches and sparse dark rivet impressions. Quiet enough beneath white UI text. No emblems, objects, borders, focal points or directional lighting.
Input image: Image 1 is a style reference contact sheet of SpartanUI's War Horde materials; use only its material and color language.
Composition/framing: flat straight-on texture field, uniform edge-to-edge, seamless tiling on all four edges.
Constraints: no text, letters, logos, crests, faction symbols, heraldic animals, runes, faces, skulls, watermark, or emoji.
```

## backdrop.png

Generated master: `tools/source_art/war-horde/backdrop-source.png`

```text
Use case: stylized-concept
Asset type: wide dim Horde War scene backdrop behind a fantasy game UI window
Primary request: A unique rough Horde-inspired war foundry built from blackened iron, heavy timber, worn deep-red unmarked cloth and blunt spikes, with hot orange battlefield fire glowing only near the far lower corners and smoke hanging in the rafters. Brutal, martial and low contrast.
Input image: Image 1 is a style reference contact sheet of SpartanUI's War Horde materials and existing fire; follow its colors and material language without copying its composition.
Composition/framing: cinematic 2:1 wide scene, broad quiet dark center for UI content, architecture and fire held near far edges, no central focal object.
Constraints: no characters, text, letters, logos, crests, faction symbols, heraldic animals, emblems, runes, faces, skulls, marked banners, watermark, or emoji.
```

## crest.png

Generated with OpenAI's built-in image generation tool on 2026-10-01.

Generated master: `tools/source_art/war-horde/crest-source.png`. References: `tools/source_refs/crest-horde-materials.png` and `tools/source_refs/crest-unitframes.png` (converted from `Themes/War/Images/UnitFrames.blp`).

Alpha-preserving LANCZOS normalization to 240x124 with 8px side padding and 4px top padding on a 256x128 canvas; drawn at 128x64, centered at top -44px, bottom 40 canvas rows overlap the window. Solid mounting width: 64 canvas pixels.

Exact prompt:

```text
Use case: stylized-concept
Asset type: original painted fantasy game UI crest ornament with alpha, mounted above a window frame.
Input images: Image 1 is the existing faction frame material reference; image 2 is the converted SpartanUI War UnitFrames atlas, reference for lighting and paint style ONLY. Do not copy any emblem in image 2.
Composition: a single front-facing crest, wide 2:1 transparent canvas. Design in normalized 256x128 coordinates. Artwork occupies x=18..238 and y=4..126. A broad decorative upper silhouette tapers into a NARROW integrated mounting clasp in the bottom 40 rows (y=88..127), no wider than 120 pixels there. The bottom clasp must be solid continuous hardware through the beam crossing at y=88, with two short vertical feet that wrap down the front of a horizontal frame beam. No separate beam in the delivered asset. No floating gaps between crest and clasp. It will be displayed at 128x64, with the canvas top 44 pixels above the window and its bottom 20 pixels overlapping the beam and title bar. Keep the entire ornament within canvas. Bold shapes and restrained detail readable at real UI size.
Style: polished hand-painted fantasy inventory artwork, crisp material bevels, soft antialiased alpha edges, front-facing orthographic, light from upper left matching reference frame.
Constraints: genuinely transparent background, one ornament only, no text, letters, logos, watermarks, official faction emblems, official Alliance lion shield, or official Horde fist/tusk sigil. Original heraldry only.
Subject: Horde-inspired original angular blackened iron shield with a dark red leather inset, a faceted glowing red ember at its center (no sigil or animal), two outward curved ivory tusks held entirely above the bottom clasp zone, short dark chains, iron spikes and chunky rivets. Compact squared forged iron mounting jaws at the bottom with red leather between them, tapering to a narrow flat bottom. Match the reference's dark worn iron, restrained warm silver bevels and crimson red.
```
