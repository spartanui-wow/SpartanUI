# Arcane kit provenance

Generated with the built-in OpenAI image generation tool on 2026-10-01. Each asset call attached `tools/source_refs/arcane-contact-sheet.png`, converted with Pillow from the theme Images folder and setup Style/Style_Frames files. Exact prompts follow.

Processing: `tools/make_kit_art.py --kitart3` calls `tools/build_kitart3.py`. One square frame master is normalized with a shared piecewise coordinate transform then sliced into all eight pieces. Edge padding is genuinely transparent. Transparent frame alpha is reduced to 46 percent; glass nodes to 70 percent. Material is subdued and mirrored in four quadrants for exact matching opposite edges; Transparent frost alpha is 12/255. Backdrop is resized and dimmed, with 16px blur for Transparent.

## all eight frame-*.png pieces

Master: `tools/source_art/arcane/frame-source.png`

```text
Use case: stylized-concept
Asset type: production fantasy game UI frame artwork
Input image: Image 1 is a style reference contact sheet converted from SpartanUI Arcane source art. Use its material and shape language as reference, create unique new artwork. Do not copy text from the contact sheet.
Theme: Arcane blue magic, polished silver and pale blue crystal, glowing abstract runic filigree lines without readable letters, floating motes, starlit violet-blue depth. Restrained elegant curved silver ornament. Marker is a glowing arcane crystal.
Primary request: ONE complete square window border master, front-on orthographic, axis-aligned, centered on a 1024x1024 square canvas. Continuous straight beams connecting all four corners. Beam occupies outer 9 percent of canvas, corners confined to outer 25 percent square regions. Large interior genuinely transparent. Outer bounds tightly meet canvas edges without cropping ornament. Readable at 24px corners and 9px beams. Keep highlights broad and simple; all decoration on the border.
Constraints: no text, letters, numbers, logos, crests, faction symbols, faces, watermark or emoji. No readable runes. Genuinely transparent background, preserve soft translucent details.
```

## divider.png

Master: `tools/source_art/arcane/divider-source.png`

```text
Use case: stylized-concept
Asset type: production fantasy game UI divider artwork
Input image: Image 1 is a style reference contact sheet converted from SpartanUI Arcane source art. Use its material and shape language as reference, create unique new artwork. Do not copy text from the contact sheet.
Theme: Arcane blue magic, polished silver and pale blue crystal, glowing abstract runic filigree lines without readable letters, floating motes, starlit violet-blue depth. Restrained elegant curved silver ornament. Marker is a glowing arcane crystal.
Primary request: ONE long extremely thin horizontal divider with a small centered themed ornament, artwork confined to a narrow band through the exact vertical center of a square canvas. Generous transparent space above and below. Tapered ends. Must stay readable after resizing to 512x32.
Constraints: no text, letters, numbers, logos, crests, faction symbols, faces, watermark or emoji. No readable runes. Genuinely transparent background, preserve soft translucent details.
```

## marker.png

Master: `tools/source_art/arcane/marker-source.png`

```text
Use case: stylized-concept
Asset type: production fantasy game UI marker artwork
Input image: Image 1 is a style reference contact sheet converted from SpartanUI Arcane source art. Use its material and shape language as reference, create unique new artwork. Do not copy text from the contact sheet.
Theme: Arcane blue magic, polished silver and pale blue crystal, glowing abstract runic filigree lines without readable letters, floating motes, starlit violet-blue depth. Restrained elegant curved silver ornament. Marker is a glowing arcane crystal.
Primary request: ONE current-step navigation marker, centered front-on single icon, bold clean silhouette, fills 80 percent of square canvas with transparent padding. Readable at 24px. Use the marker material specified by the theme.
Constraints: no text, letters, numbers, logos, crests, faction symbols, faces, watermark or emoji. No readable runes. Genuinely transparent background, preserve soft translucent details.
```

## node-done.png

Master: `tools/source_art/arcane/node-done-source.png`

```text
Use case: stylized-concept
Asset type: production fantasy game UI node-done artwork
Input image: Image 1 is a style reference contact sheet converted from SpartanUI Arcane source art. Use its material and shape language as reference, create unique new artwork. Do not copy text from the contact sheet.
Theme: Arcane blue magic, polished silver and pale blue crystal, glowing abstract runic filigree lines without readable letters, floating motes, starlit violet-blue depth. Restrained elegant curved silver ornament. Marker is a glowing arcane crystal.
Primary request: ONE tiny completed-step navigation node, centered front-on single icon, compact filled bead of the theme material, no checkmark. Fills 70 percent of square canvas with transparent padding. Readable at 16px, simpler and less bright than marker.
Constraints: no text, letters, numbers, logos, crests, faction symbols, faces, watermark or emoji. No readable runes. Genuinely transparent background, preserve soft translucent details.
```

## node-upcoming.png

Master: `tools/source_art/arcane/node-upcoming-source.png`

```text
Use case: stylized-concept
Asset type: production fantasy game UI node-upcoming artwork
Input image: Image 1 is a style reference contact sheet converted from SpartanUI Arcane source art. Use its material and shape language as reference, create unique new artwork. Do not copy text from the contact sheet.
Theme: Arcane blue magic, polished silver and pale blue crystal, glowing abstract runic filigree lines without readable letters, floating motes, starlit violet-blue depth. Restrained elegant curved silver ornament. Marker is a glowing arcane crystal.
Primary request: ONE tiny upcoming-step navigation node, centered front-on single icon, compact dim hollow ring of theme material, genuinely transparent inner opening. Fills 70 percent of square canvas with transparent padding. Readable at 18px. Much dimmer than marker.
Constraints: no text, letters, numbers, logos, crests, faction symbols, faces, watermark or emoji. No readable runes. Genuinely transparent background, preserve soft translucent details.
```

## material.png

Master: `tools/source_art/arcane/material-source.png`

```text
Use case: stylized-concept
Asset type: production fantasy game UI material artwork
Input image: Image 1 is a style reference contact sheet converted from SpartanUI Arcane source art. Use its material and shape language as reference, create unique new artwork. Do not copy text from the contact sheet.
Theme: Arcane blue magic, polished silver and pale blue crystal, glowing abstract runic filigree lines without readable letters, floating motes, starlit violet-blue depth. Restrained elegant curved silver ornament. Marker is a glowing arcane crystal.
Primary request: ONE flat seamless tileable low-contrast material texture for UI panels, square canvas. Uniform edge to edge, extremely subdued, no objects, focal points, borders or directional lighting. Arcane: pale blue crystalline mist on dark navy. Tribal: dark warm wood and leather grain. Transparent: extremely faint soft frost on transparent glass. Designed to sit beneath readable text.
Constraints: no text, letters, numbers, logos, crests, faction symbols, faces, watermark or emoji. No readable runes. Dim low-contrast full-bleed image.
```

## backdrop.png

Master: `tools/source_art/arcane/backdrop-source.png`

```text
Use case: stylized-concept
Asset type: production fantasy game UI backdrop artwork
Input image: Image 1 is a style reference contact sheet converted from SpartanUI Arcane source art. Use its material and shape language as reference, create unique new artwork. Do not copy text from the contact sheet.
Theme: Arcane blue magic, polished silver and pale blue crystal, glowing abstract runic filigree lines without readable letters, floating motes, starlit violet-blue depth. Restrained elegant curved silver ornament. Marker is a glowing arcane crystal.
Primary request: ONE unique cinematic 2:1 wide dim low-contrast scene behind a UI window, broad quiet center and interest only at far edges. Arcane: shadowed silver arches opening onto violet-blue starlit magical depth, sparse motes. Tribal: dim timber and leather interior, carved warm wood posts and amber ambient glow at far corners. Transparent: near-black soft defocused blurred blue-grey light, abstract, no recognizable objects. No central focal object.
Constraints: no text, letters, numbers, logos, crests, faction symbols, faces, watermark or emoji. No readable runes. Dim low-contrast full-bleed image.
```
