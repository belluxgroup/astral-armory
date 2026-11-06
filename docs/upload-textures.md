# Uploading the VFX textures

Every effect runs without custom textures (built-in fallbacks). Uploading them makes the rune rings,
hex shield, slash arcs, beams, explosions and the transformation aura look the way they were designed.

Roblox gives a texture its `rbxassetid://` only after it is uploaded under your account, and there is
no way to do that headless without an Open Cloud API key, so this step is manual (about 3 minutes).

1. In Roblox Studio, open **Window → Asset Manager**, then **Bulk Import**.
2. Select every PNG in `assets/textures/` except `ring_runes.png` (the hero version replaces it).
3. When the import finishes, right-click each image in Asset Manager → **Copy Asset ID**.
4. Paste each id into `CUSTOM` in `src/shared/Config/AssetIds.luau`, using this mapping:

| File | Slot in `CUSTOM` |
|---|---|
| `glow_soft.png` | `glow_soft` |
| `glow_star.png` | `glow_star` |
| `spark.png` | `spark` |
| `smoke_soft.png` | `smoke_soft` |
| `hero_ring_runes.png` | `ring_runes` |
| `hex_cell.png` | `hex_cell` |
| `slash_arc.png` | `slash_arc` |
| `beam_core.png` | `beam_core` |
| `explosion_flipbook_4x4.png` | `explosion_flipbook_4x4` |
| `hero_aura_flame.png` | `aura_flame` |

Each line looks like `ring_runes = "rbxassetid://1234567890",`.

5. Rebuild: `rojo build -o AstralArmory.rbxl`.

`hero_ring_runes.png` and `hero_aura_flame.png` were generated with ChatGPT image generation from
original prompts (invented glyphs, no existing IP) and converted to white-with-alpha by
`tools/prep_hero.py`. The other nine come from `tools/gen_textures.py`.
