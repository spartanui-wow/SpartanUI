# Nameplate art

Run with Python 3, Pillow and numpy:

```powershell
python tools/nameplates/make_art.py
python tools/nameplates/preview_art.py
python Tests/Nameplates/lint.py
python Tests/Nameplates/run.py --suite styles
```

The generator has no randomness, timestamps or external inputs beyond art.json. It writes 42 white-on-alpha TGA files. Canvases are powers of two. The explicit TGA writer uses type 2, 32-bit BGRA, straight alpha, top-left origin and no RLE. RGB stays white even in fully transparent pixels, which avoids dark filtering fringes. Catalog preview sizes are game pixels at 1x; contact.png shows those sizes and 2x against dark and light backgrounds. Fine edges are authored as two source pixels; larger canvases leave room for smooth falloffs and clean small-icon filtering.

art.json is the recipe and preview catalog. ArtAliases.ENTRIES carries the same aliases, relative media files, kinds, default tints, draw modes and source-pixel margins. Slice order is left, top, right, bottom. Corners and edge ends stay in their fixed slices; the center stretches. Borders and glows have fully clear centers.

| Sliced texture aliases | Source margins, left/top/right/bottom |
| --- | --- |
| brackets, glow | 8/8/8/8 |
| borderPixel, borderThick, borderShadow, borderBeveled | 8/8/8/8 |
| soft, important, purge, threat | 16/16/16/16 |
| pandemic | 8/8/8/8 |
| auraThin, auraThick, auraRounded | 8/8/8/8 |

The single shared-file hook replaces the Flat-only registration line in Core/Namespace.lua with `self.Data.ArtAliases:Register(media, self.host.mediaPath)`. It still runs only during P:Enable(). Registration is repeatable. Each file has its descriptive neutral LSM name and its short alias. Border files use the `nameplatenineslice` media type and are also exposed as `nameplateart` for decoration parts. Pip shapes use `statusbar`, which is what ClassPower's existing texture lookup reads.

Rounded uses matched alpha-cut fill, background and frame textures through the existing bar and art parts. The current art part stretches its textures, so those three canvases share their aspect ratio. The paired roundedMask is registered for future mask support. Sparks, aura borders and the separate HealAbsorb file are available to pickers and future engine consumers; this change does not add engine fields. The current health part uses absorbTexture for both absorb bars, so the new styles use AbsorbStripes for both.

New TGA files require a full game restart. Check live pixel edges at UI scales 0.64, 0.71 and 1.0; the contact sheet and mock client do not prove those game results.

## Verification in this session

Python commands were blocked: the shell helper could not start, the discovered Store Python executable refused access, and an isolated runtime download was blocked by network permissions. The textures were generated with equivalent JavaScript equations and the contact sheet rendered with System.Drawing, then viewed and refined twice. Python regeneration and the Python lint remain to be run when an accessible interpreter is available. out/art-sha256.json records the delivered texture hashes for that comparison. Re-evaluating the equivalent JavaScript equations reproduced all 42 delivered files byte for byte.

StyLua formatted the owned Lua files. The styles suite ran directly through the existing LuaLS harness on all six clients: 51 passed per client, no failures. It checks every built-in for zero dropped/clamped/fixed fields, all aliases for LSM registration, and every file for a power-of-two raw 32-bit white-on-alpha payload. The broad LuaLS run recorded 4605 passed, 12 failed and 167 skipped; failures were in Config and Store (size defaults and migratedFromOld). See out/luals-validation.json. Other agents were editing migration and engine files during this run. Whole-tree StyLua checking also found formatting differences in files outside this task; those files were preserved.
