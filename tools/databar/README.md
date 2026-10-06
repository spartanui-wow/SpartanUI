# Painted DataBar assets

Run from the SpartanUI checkout:

```powershell
& 'C:\Users\jerem\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/databar/build.py
```

Requires Pillow. Uses the original built-in imagegen paintings, prompts, crop rectangles and job list preserved in `openspec/databar-art/sources/`. No theme reference pixels or status-bar pictures enter the final artwork.

`build.py` cuts paintings, calms the text panel, reduces recurring trim detail, blends periodic boundaries, joins 128-pixel caps, and assembles all 48 theme PNGs. The same aspect-preserving cap/tile renderer makes the 1024-pixel fallback, setup cards, and 1920/2560 previews. The right cap is mirrored. Cards use two sample plugins to keep text readable at setup-card size; screen previews use all six plugins.

`looks.json` has exactly the six requested fields per base. Contrast is the lower of the label and value contrasts, measured using WCAG sRGB relative luminance against the average RGB of assembled-strip rows 13 through 50 (the middle 60%, including caps). Highlight alpha is 0.18. Rebuilding checks dimensions, RGBA, opacity, native boundary pixels and both contrast ratios. Detailed measurements are in `openspec/databar-art/validation.json`.

Previews pack the 1920 x 120 crop above the 2560 x 120 crop in a 2560 x 240 canvas. The unused right side of the upper crop is dark padding. `contact.png` stacks these at native widths and includes all 12 cards shown at 210 x 148. `card-comparison.png` places the existing setup artwork beside each new card. `joints-400.png` contains nearest-neighbor 400% joint inspections.

The three `scaled-joints-400-page-*.png` sheets include every cap/tile and tile/tile joint at both requested screen widths, including the right cap after the final partial repeat. Per-look scaled joint sheets are also saved.

`references.py` and `inspect_sources.py` rebuild the reference and source sheets. They are inspection aids, not painting inputs to the asset builder. These scripts do not change addon wiring, Lua, or manifests.
