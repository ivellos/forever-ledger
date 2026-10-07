# Theme flourish artwork

Original artwork generated with Codex's built-in image tool on October 6, 2026 for Forever Ledger. No third-party addon artwork, screenshots or code used as generation inputs.

## Sources and export

- `tools/art/theme-flourishes/ledger-grain.png`: original generated material.
- `tools/art/theme-flourishes/ledger-corner.png`: original generated transparent upper-left ornament.
- `tools/export-theme-assets.py`: Pillow RGBA conversion and Lanczos downscale only; sources unchanged. Run `python tools/export-theme-assets.py`.
- Runtime files: `media/themes/ledger-grain.tga` (256 × 256), `ledger-corner.tga` (128 × 128), uncompressed 32-bit RGBA. Total approximately 320 KiB.

Theme.lua uses a quiet neutral/warm material tint and low alpha. Gilded mirrors the corner at 24 UI pixels and tints it bronze. Selected accent colours remain on the existing active controls; the material does not impose an accent. Grain is stretched across each region, not repeated: seamless tiling has not been established. These are static texture regions, with no timers, input handlers or new settings. The shared DecorateWindow hook covers the main window, auction house side panel and trainer advice panel. Other popup/widget styling is unchanged in this first pass. In-game rendering, scale and contrast still need checking after integration.

## Exact generation prompts

### Grain

Use case: stylized-concept. Asset type: production game UI material texture. Generate one square seamless tile of very fine dark neutral charcoal leather/book-cover grain for a restrained fantasy ledger interface. Orthographic flat material only, fills entire image edge to edge. Tiny shallow irregular pores and subtle fibres; matte, very low contrast and even illumination. Grayscale only, mid-dark gray surface with no colored highlights, no metallic objects. The same tile must be usable under a near-black neutral UI and warm bronze UI at low opacity. No vignette, no gradient, no directional lighting, no seams, no borders, no lettering, no logos, no symbols, no illustration, no objects, no cracks or large scratches, no dramatic leather wrinkles. Seamless repeating edges. 1024 by 1024 square.

### Corner

Use case: stylized-concept. Asset type: a single small game UI corner ornament on a genuinely transparent background. An original restrained engraved metal corner cap for the upper-left corner of a fantasy merchant ledger frame. L-shaped with horizontal arm to the right and vertical arm downward, balanced arms. Narrow straight outer edges and a modest inward curling leaf/scroll engraving near the elbow; elegant simple medieval book-binding hardware, appropriate for a Warcraft-like interface but original. Flat orthographic front view, no perspective. Bright neutral silver/grayscale only so the game can tint bronze at runtime, subtle etched shading, no coloured metals. Both arms end cleanly within the canvas; compact ornament isolated with transparency around and inside its open space. No whole frame, no background, no shadow outside the object, no text, no letters, no emblem, no skull, no jewel, no dragon, no glow. One upper-left corner only, not a sheet of alternatives. Square canvas.
