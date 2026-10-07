# Theme flourish artwork

Original artwork generated with Codex's built-in image tool on October 6, 2026 for Forever Ledger. No third-party addon artwork or code used. The revised filigree used our original accepted concept board as its sole style reference.

## Sources and export

- `tools/art/theme-flourishes/ledger-grain.png`: original generated material.
- `tools/art/theme-flourishes/ledger-filigree.png`: revised open transparent upper-left filigree, closer to the accepted concept.
- `tools/art/theme-flourishes/ledger-corner.png`: archived first-attempt artwork, no longer used at runtime.
- `tools/export-theme-assets.py`: Pillow RGBA conversion and Lanczos downscale only; sources unchanged. Run `python tools/export-theme-assets.py`.
- Runtime files: `media/themes/ledger-grain.tga` (256 × 256), `ledger-filigree.tga` (128 × 128), uncompressed 32-bit RGBA. Total approximately 320 KiB.

Theme.lua uses neutral/warm material tints: a quiet Clean surface and more visible leather in the Default/Gilded headers. Window-only double edges catch the light in silver (Clean), bronze (Default) and gold (Gilded), leaving widget borders alone. Gilded mirrors open filigree at 32 UI pixels and tints it gold. The revision follows owner feedback that the first pass was too faint compared with the accepted concept. Coin/logo branding remains separate. Selected accent colours remain on the existing active controls; the material does not impose an accent. Grain is stretched across each region, not repeated: seamless tiling has not been established. These are static texture regions, with no timers, input handlers or new settings. The shared DecorateWindow hook covers the main window, auction house side panel and trainer advice panel. Other popup/widget styling is unchanged in this first pass. In-game rendering, scale and contrast still need checking after integration.

## Exact generation prompts

### Grain

Use case: stylized-concept. Asset type: production game UI material texture. Generate one square seamless tile of very fine dark neutral charcoal leather/book-cover grain for a restrained fantasy ledger interface. Orthographic flat material only, fills entire image edge to edge. Tiny shallow irregular pores and subtle fibres; matte, very low contrast and even illumination. Grayscale only, mid-dark gray surface with no colored highlights, no metallic objects. The same tile must be usable under a near-black neutral UI and warm bronze UI at low opacity. No vignette, no gradient, no directional lighting, no seams, no borders, no lettering, no logos, no symbols, no illustration, no objects, no cracks or large scratches, no dramatic leather wrinkles. Seamless repeating edges. 1024 by 1024 square.

### Corner

Use case: stylized-concept. Asset type: a single small game UI corner ornament on a genuinely transparent background. An original restrained engraved metal corner cap for the upper-left corner of a fantasy merchant ledger frame. L-shaped with horizontal arm to the right and vertical arm downward, balanced arms. Narrow straight outer edges and a modest inward curling leaf/scroll engraving near the elbow; elegant simple medieval book-binding hardware, appropriate for a Warcraft-like interface but original. Flat orthographic front view, no perspective. Bright neutral silver/grayscale only so the game can tint bronze at runtime, subtle etched shading, no coloured metals. Both arms end cleanly within the canvas; compact ornament isolated with transparency around and inside its open space. No whole frame, no background, no shadow outside the object, no text, no letters, no emblem, no skull, no jewel, no dragon, no glow. One upper-left corner only, not a sheet of alternatives. Square canvas.

### Revised filigree

Use case: stylized-concept. Asset type: one original transparent upper-left game UI corner flourish. Reference image is a style guide only: match the FL Gilded column's delicate open line filigree seen in its header/corner detail, NOT a whole UI screenshot. Create a single elegant upper-left corner ornament with slender interlaced curved metal ribbons, a small diamond at the elbow and two fine tapered arms pointing right and down. Airy negative space between strokes: mostly transparent, NOT a solid heavy L-shaped plate, NOT thick leather-book hardware. Square canvas, ornament near top-left but entirely inside the canvas with small padding; ends taper within about two-thirds of the square. Front orthographic view. Neutral pale silver/grayscale metal with restrained etched highlights; no gold colour baked in because addon will tint it gold. Clean edges that remain legible at 32 UI pixels. Genuinely transparent background and open spaces. No text, no logos, no frame, no coins, no skulls, no jewels, no dragons, no external drop shadow, no glow. One corner only.
