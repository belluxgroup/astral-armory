--!strict
-- Texture ids for the VFX. Pure data: no Roblox API here.
--
-- The PNGs come from tools/gen_textures.py (assets/textures). After they are
-- uploaded through the Asset Manager, paste each id into CUSTOM as
-- "rbxassetid://<number>". Until then every texture resolves to a built-in
-- Roblox texture, and `AssetIds.has(name)` is false so effects can choose a
-- geometry-based look instead (ring outlines from Beams, solid Beam ribbons,
-- no flipbook layout).

export type TextureName =
	"glow_soft"
	| "glow_star"
	| "spark"
	| "smoke_soft"
	| "ring_runes"
	| "hex_cell"
	| "slash_arc"
	| "beam_core"
	| "explosion_flipbook_4x4"
	| "aura_flame"

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

-- Uploaded with tools/upload_textures.py (ids also in assets/textures/asset_ids.json).
-- Leave a texture out (nil) to keep its fallback.
local CUSTOM: { [string]: string } = {
	glow_soft = "rbxassetid://113246916976596",
	glow_star = "rbxassetid://79995011718568",
	spark = "rbxassetid://122894767985137",
	smoke_soft = "rbxassetid://110332962154087",
	ring_runes = "rbxassetid://81732763898173",
	hex_cell = "rbxassetid://87059961153840",
	slash_arc = "rbxassetid://108978051894085",
	beam_core = "rbxassetid://78693715905516",
	explosion_flipbook_4x4 = "rbxassetid://105749511901802",
	aura_flame = "rbxassetid://81484018039428",
}

-- Built-in fallbacks. An empty string means "no texture": Beams render as a
-- solid ribbon and decal/image layers are skipped.
local FALLBACK: { [string]: string } = {
	glow_soft = SPARKLES,
	glow_star = SPARKLES,
	spark = SPARKLES,
	smoke_soft = SMOKE,
	ring_runes = "",
	hex_cell = "",
	slash_arc = "",
	beam_core = "",
	explosion_flipbook_4x4 = FIRE,
	aura_flame = FIRE,
}

local function resolve(name: string): string
	return CUSTOM[name] or FALLBACK[name]
end

local AssetIds = {
	glow_soft = resolve("glow_soft"),
	glow_star = resolve("glow_star"),
	spark = resolve("spark"),
	smoke_soft = resolve("smoke_soft"),
	ring_runes = resolve("ring_runes"),
	hex_cell = resolve("hex_cell"),
	slash_arc = resolve("slash_arc"),
	beam_core = resolve("beam_core"),
	explosion_flipbook_4x4 = resolve("explosion_flipbook_4x4"),
	aura_flame = resolve("aura_flame"),
}

-- The texture id for `name` (custom when uploaded, built-in fallback otherwise).
function AssetIds.tex(name: TextureName): string
	local id = resolve(name)
	if id == nil then
		error(`AssetIds.tex: unknown texture "{name}"`, 2)
	end
	return id
end

-- True when the custom (uploaded) texture is set for `name`.
function AssetIds.has(name: TextureName): boolean
	return CUSTOM[name] ~= nil
end

return AssetIds
