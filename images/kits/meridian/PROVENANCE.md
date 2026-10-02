# Quiet Meridian art provenance

Created 2026-10-01 using the built-in `image_gen.imagegen` tool. Five original generated paintings were prepared with Pillow under the slicing and enforcement workflow explicitly requested by brief.md. No borrowed addon art, faction symbols, letters or logos are present in the final texture assets.

Reference images: `templates/template_bottom.png`, `templates/template_unitframe.png`, and the owner's `scratchpad/forever_skin/board_5_quiet_meridian.png`. The templates supply geometry; the board supplies the approved material language. Original generated PNGs are retained in the Meridian work folder's `sources/` directory. Default tool copies remain in `C:/Users/jerem/.codex/generated_images/01a0f9d6-130a-7313-8759-db976fc1bfd4/`.

## Exact prompts

### Bottom painting

Source: `sources/bottom-generated.png`; original `exec-672f524c-7844-4cc3-ac6a-a681dc3697b6.png`. Transparent background requested. References: bottom template first, board second.

```text
Paint a production game UI texture, Quiet Meridian. Image 1 is exact silhouette and layout reference; image 2 is material/style reference only. Output wide 2048x512 RGBA transparent canvas matching image 1. Keep the body occupying only bottom ~180px plus central circular dome, centered at (1024,365), outer radius170, hole radius115. Dark matte green-black enamel #17211F, subtle raised enamel #293431, thin worn brass #BBA77C twin perimeter lines, dark supporting edges, tiny round rivet beads only at far ends. Central clean brass minimap bezel with second offset crescent rim, restrained sea glass #89B5AC. Blue guide areas become dark flat recessed rectangular trays; absolutely no individual button sockets, grids, slots, dividers or icons. Yellow guide strips remain quiet shallow grooves. Transparent minimap hole and everything above body. Straight orthographic painted 2D texture, no perspective, no text, no marks, no logos, no shadows outside silhouette. Precise understated physical material, subtle edge wear, calm flat tray centers. Match reference geometry.
```

### Unit plate painting

Source: `sources/unitframe-generated.png`; original `exec-1e5b5ee0-e0ca-407d-87f0-3eeec53fa773.png`. Transparent background requested. References: unit template first, board second.

```text
Production Quiet Meridian game UI unit frame texture, horizontal 4:1 ratio. Image 1 is layout guide, image 2 is material reference only. Dark enamel green-black #17211F, thin worn warm brass #BBA77C paired perimeter seam, physical hand painted quiet material. Full rectangular slim plate with left circular brass portrait bezel centered 14% across,55% down, radius48% height; remaining right 74% wide is plain dark rectangular recessed bar window, with calm name strip above. NO health or mana fill, no words, no runes, no marks. Ring interior plain dark enamel for later cutout. Square clean outer silhouette, transparent outside. Small sea glass accent at very far right end only, subtle brass bead ends. Orthographic flat texture, no perspective, no background shadow. Fill entire plate close to reference canvas. Keep all functional bar areas plain.
```

### Square frame painting

Source: `sources/frame-generated.png`; original `exec-081e3f5d-4eb4-4572-bdfa-65e2047a7dec.png`. Transparent background requested. Reference: board.

```text
Create ONE square 1024x1024 orthographic game UI window frame texture for Quiet Meridian. Reference is material style only. Thin worn warm brass twin lines over matte green-black enamel, restrained precision, tiny round brass rivet bead at each very outer corner, no other ornament. Outer square extends exactly to all four canvas edges. Frame beam EXACTLY 96 pixels wide inward on each side. Inner 832x832 square fully transparent. Straight parallel edges, identical top/bottom/left/right beam cross sections so frame can be cut into seamless 9 slice. Brass line at 12 pixels and 68 pixels from outside edge, calm dark enamel between, subdued physical highlights and hand wear. Corners simple right-angle joins, no elaborate scrolls, no crest, no letters, no symbols, no glow, no perspective, no shadow outside border. Palette #17211F #293431 #BBA77C, tiny sea-glass #89B5AC corner inset allowed. Flat polished production texture, real alpha background.
```

### Backdrop painting

Source: `sources/backdrop-generated.png`; original `exec-8e91e133-9c58-4f9b-918b-631c3d24a5ad.png`. Opaque background requested. No image references.

```text
Quiet Meridian game settings window backdrop painting, wide 2:1 composition 1024x512. Original misty coastal horizon with a second gently offset distant horizon, sparse low rugged hills at left and right, empty calm center, sea stretching into haze. Extremely dim low contrast green-black ink #17211F, matte enamel green #293431, faint desaturated sea-glass #89B5AC reflections. Almost monochrome; entire image dark enough for ivory text placed above. Fine painterly natural physical surface, quiet long-session mood. No frame, no UI, no sun flare, no bright highlights, no text, no symbols, no characters, no logos. Subdued painted landscape, not photographic and not a copy of any game scene.
```

### Crest painting

Source: `sources/crest-generated.png`; original `exec-04f43757-dd27-439b-9bc1-b035efe737f1.png`. Transparent background requested. Reference: board.

```text
Quiet Meridian window crest isolated on fully transparent canvas, horizontal 2:1. A small instrument ornament made of ONLY two thin displaced worn brass crescent arcs cradling one small round matte sea-glass bead. Match upper-right window crest motif of reference but reduce ornament: NO central large brass disc, no diamond, no symbol. Two open crescent arcs offset slightly from one another, one taller at left and one shorter at right, green-black enamel supporting edge, brass #BBA77C, sea glass #89B5AC, soft restrained physical highlights. Flat front-view hand painted game UI texture, centered, occupies most canvas, crisp silhouette, no cast shadow, no text, no letters, no logo, no faction symbol, no glow. Legible when reduced to128x64.
```

## Preparation and asset derivation

The reproducible preparation code is `make_art.py` in the Meridian work folder. `verify_art.py` checks dimensions, RGBA mode, frame beam margins, tile edges, split reconstruction and hole transparency, and renders the kit at its intended small scale.

- `raw/bottom.png`: uniformly scaled original painting aligned to the guide's minimap center; dark backing is restricted to functional beds and the ring. No painted button sockets. The fixed minimap hole is cut by the supplied enforcer.
- `raw/unitframe.png`: portrait, calm name strip and uninterrupted lower tray are sliced from the generated plate and placed against the template. The silhouette follows the portrait ring plus the rectangular bar plate. The portrait hole is cut by the enforcer.
- All eight `frame-*.png`: one corner and one straight edge sliced from the square painting; reflections preserve construction. Corners are 64x64. Horizontal and vertical edges are 256x32 and 32x256 with exactly 24px beams first and transparent remaining margins.
- `raw/button.png`: square painting reduced over a dark enamel backing. The supplied enforcer cuts the exact icon window.
- `raw/statusbar.png`: top/bottom rails and end caps sliced from the frame's straight beam, with a flat dark recessed center.
- `crest.png`: alpha-bounded crest painting fitted proportionally to a 128x64 transparent canvas.
- `marker.png`, `node-done.png`: the crest's sea-glass bead, isolated with a circular alpha mask at two sizes.
- `node-upcoming.png`: a brass corner rivet isolated from the square painting, with a transparent center.
- `divider.png`: twin thin frame rails, reflected at center around the isolated sea-glass bead.
- `material.png`: a low-contrast enamel sample from the bottom painting, reflected in both axes into a tile whose opposite edges match exactly.
- `backdrop.png`: original coastal painting resized to 1024x512 and blended toward ink enamel for low contrast.

Palette and button colors are recorded in the work folder's `colors.json`. The static previews contain stand-in text and controls; final texture assets contain none. This pass delivers art only. Live game rendering remains for the supervisor after integration.
