--!strict
-- Element and variant colors for every effect and for UI that matches them
-- (damage numbers). VFX modules never hard-code element colors: they read a
-- palette from here using `spec.element` and `spec.radiant`.

export type Palette = {
	core: Color3, -- hottest centre (beam cores, blade edges), near white
	glow: Color3, -- main tint for particles, beams and lights
	accent: Color3, -- deeper secondary tone (smoke, rims, falloff)
	brightness: number, -- light / emission multiplier (radiant is brighter)
}

local VfxPalette = {}

local BASE: { [string]: Palette } = {
	none = {
		core = Color3.fromRGB(255, 249, 228),
		glow = Color3.fromRGB(255, 204, 102),
		accent = Color3.fromRGB(255, 146, 48),
		brightness = 1,
	},
	frost = {
		core = Color3.fromRGB(236, 251, 255),
		glow = Color3.fromRGB(112, 206, 255),
		accent = Color3.fromRGB(58, 118, 255),
		brightness = 1,
	},
	flame = {
		core = Color3.fromRGB(255, 236, 196),
		glow = Color3.fromRGB(255, 118, 38),
		accent = Color3.fromRGB(214, 36, 18),
		brightness = 1.1,
	},
	storm = {
		core = Color3.fromRGB(246, 232, 255),
		glow = Color3.fromRGB(178, 112, 255),
		accent = Color3.fromRGB(104, 58, 255),
		brightness = 1.05,
	},
}

-- Fixed colors for effects that are not element driven.
VfxPalette.named = {
	crimson = Color3.fromRGB(230, 28, 58),
	crimsonDeep = Color3.fromRGB(120, 6, 24),
	crimsonCore = Color3.fromRGB(255, 196, 202),
	radiantGold = Color3.fromRGB(255, 226, 140),
	radiantWhite = Color3.fromRGB(255, 252, 240),
	telegraph = Color3.fromRGB(255, 46, 46),
	telegraphCore = Color3.fromRGB(255, 160, 140),
	shadow = Color3.fromRGB(40, 10, 60),
	shadowGlow = Color3.fromRGB(150, 60, 255),
	enrage = Color3.fromRGB(110, 20, 150),
	dust = Color3.fromRGB(176, 158, 140),
}

local RADIANT_GLOW = Color3.fromRGB(255, 230, 150)
local RADIANT_ACCENT = Color3.fromRGB(255, 206, 110)

local cache: { [string]: Palette } = {}

-- Returns the palette for an element ("none" | "frost" | "flame" | "storm").
-- Unknown elements fall back to "none". `radiant` (Ascension active) shifts
-- every tone toward white-gold and raises brightness.
function VfxPalette.get(element: string, radiant: boolean): Palette
	local key = element .. (if radiant then "+r" else "")
	local hit = cache[key]
	if hit then
		return hit
	end
	local base = BASE[element] or BASE.none
	local palette: Palette
	if radiant then
		palette = {
			core = base.core:Lerp(VfxPalette.named.radiantWhite, 0.6),
			glow = base.glow:Lerp(RADIANT_GLOW, 0.45),
			accent = base.accent:Lerp(RADIANT_ACCENT, 0.35),
			brightness = base.brightness * 1.6,
		}
	else
		palette = base
	end
	cache[key] = palette
	return palette
end

return VfxPalette
