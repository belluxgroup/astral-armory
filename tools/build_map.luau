--!strict
-- Generates assets/Arena.rbxm: a floating sunset sky ruin, mapped to Workspace.Arena by Rojo.
-- Run: lune run tools/build_map   (verify with: lune run tools/count_parts)
--
-- Layout (north = +Z, floor top near Y = 0):
--   center rune circle, raised marble ring at r 26-34, flagstone bands out to r 106,
--   10 broken pillars at r 95, inner spawn runes at r 44, outer spawn runes at r 82,
--   boss dais at the north edge (top tier 4 studs up), player spawn at the south edge,
--   a stepped rock underside with crystals, floating debris and distant islands.
-- Contract (plan, contract addendum item 4): PlayerSpawn, InnerSpawns, OuterSpawns, BossAltar,
-- BossSpawn, Bounds and Center are direct children of the Arena model.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local OUT = "assets/Arena.rbxm"
local TAU = math.pi * 2
local rad = math.rad

local FLOOR_RADIUS = 106
local WALL_RADIUS = 107.5
local DAIS_CENTER = Vector3.new(0, 0, 80)

-- Deterministic Park-Miller RNG, so every build produces the same ruin.
local seed = 20261106
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return (seed - 1) / 2147483646
end
local function between(a: number, b: number): number
	return a + (b - a) * rand()
end
local function chance(p: number): boolean
	return rand() < p
end

type RGB = { number }
local function tint(c: RGB, jitter: number): any
	local d = between(-jitter, jitter)
	return Color3.fromRGB(
		math.clamp(c[1] + d, 0, 255),
		math.clamp(c[2] + d, 0, 255),
		math.clamp(c[3] + d, 0, 255)
	)
end

local FLOOR_BASE: RGB = { 46, 50, 66 }
local TILE: RGB = { 70, 74, 94 }
local TILE_ALT: RGB = { 84, 84, 104 }
local MARBLE: RGB = { 198, 184, 172 }
local DARK_STONE: RGB = { 40, 38, 54 }
local DAIS_STONE: RGB = { 48, 40, 58 }
local COBBLE: RGB = { 130, 120, 124 }
local ROCK: RGB = { 74, 66, 76 }
local ROCK_DEEP: RGB = { 46, 40, 52 }
local RUNE_GOLD = Color3.fromRGB(255, 178, 80)
local RUNE_VIOLET = Color3.fromRGB(168, 122, 255)
local RUNE_EMBER = Color3.fromRGB(255, 98, 72)
local ECLIPSE = Color3.fromRGB(255, 52, 70)
local CRYSTAL = Color3.fromRGB(150, 108, 255)
local FLAME = Color3.fromRGB(255, 140, 60)

-- Cylinders run along X; this turns one upright. Size is then (height, diameter, diameter).
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function polar(thetaDeg: number, radius: number, y: number): any
	local t = rad(thetaDeg)
	return Vector3.new(radius * math.sin(t), y, radius * math.cos(t))
end

local function randomRotation(): any
	return CFrame.Angles(between(0, TAU), between(0, TAU), between(0, TAU))
end

local function folder(name: string, parent: any): any
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- floor: walkable and aim-able. wall: invisible collision. decor and marker: no physics at all.
type Kind = "floor" | "wall" | "decor" | "marker"
local function make(kind: Kind, parent: any, class: string, props: { [string]: any }): any
	local p: any = Instance.new(class)
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	if kind == "floor" then
		p.CanCollide = true
		p.CanTouch = false
		p.CanQuery = true
	elseif kind == "wall" then
		p.CanCollide = true
		p.CanTouch = false
		p.CanQuery = false
		p.Transparency = 1
		p.CastShadow = false
	else
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		if kind == "marker" then
			p.Transparency = 1
			p.CastShadow = false
		end
	end
	p.Parent = parent
	return p
end

local function glow(parent: any, class: string, props: { [string]: any }): any
	props.Material = Enum.Material.Neon
	props.CastShadow = false
	return make("decor", parent, class, props)
end

local function light(parent: any, color: any, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

-- A closed polygon of thin neon bars in the XZ plane of `center`.
local function ring(
	parent: any,
	center: any,
	radius: number,
	segments: number,
	width: number,
	thickness: number,
	color: any,
	transparency: number?
)
	local step = TAU / segments
	local length = 2 * (radius + width / 2) * math.tan(step / 2)
	for i = 0, segments - 1 do
		glow(parent, "Part", {
			Size = Vector3.new(length, thickness, width),
			CFrame = center * CFrame.Angles(0, i * step, 0) * CFrame.new(0, 0, -radius),
			Color = color,
			Transparency = transparency or 0,
		})
	end
end

local function line(parent: any, a: any, b: any, width: number, thickness: number, color: any)
	local mid = (a + b) * 0.5
	glow(parent, "Part", {
		Size = Vector3.new(width, thickness, (b - a).Magnitude),
		CFrame = CFrame.lookAt(mid, b),
		Color = color,
	})
end

-- One flagstone of an annular band: a box centered at the band's mid radius.
local function sectorCFrame(angle: number, midRadius: number, y: number): any
	return CFrame.Angles(0, angle, 0) * CFrame.new(0, y, -midRadius)
end

local arena = Instance.new("Model")
arena.Name = "Arena"
arena.WorldPivot = CFrame.new(0, 0, 0)

local floorF = folder("Floor", arena)
local decorF = folder("Decor", arena)
local runesF = folder("Runes", decorF)
local pillarsF = folder("Pillars", decorF)
local rimF = folder("Rim", decorF)
local undersideF = folder("Underside", decorF)
local debrisF = folder("Debris", decorF)
local islandsF = folder("Islands", decorF)
local propsF = folder("Props", decorF)

--------------------------------------------------------------------------------
-- Platform: one big base slab plus three bands of uneven flagstones.
--------------------------------------------------------------------------------

make("floor", floorF, "Part", {
	Name = "Base",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(8, FLOOR_RADIUS * 2, FLOOR_RADIUS * 2),
	CFrame = CFrame.new(0, -4, 0) * UPRIGHT,
	Material = Enum.Material.Slate,
	Color = tint(FLOOR_BASE, 0),
})

local bands = {
	{ inner = 34, outer = 56, count = 16 },
	{ inner = 56, outer = 80, count = 24 },
	{ inner = 80, outer = FLOOR_RADIUS, count = 32 },
}
for b, band in bands do
	local step = TAU / band.count
	local offset = if b % 2 == 0 then 0.5 else 0
	for j = 0, band.count - 1 do
		if chance(0.05) then
			continue -- a missing flagstone: the darker base slab shows through
		end
		local outer = band.outer
		local brokenEdge = b == #bands and chance(0.25)
		if brokenEdge then
			outer = between(96, 102)
		end
		local mid = (band.inner + outer) / 2
		local top = 0.35 + 0.1 * ((j + b) % 3) + between(0, 0.04)
		local width = 2 * mid * math.sin(step / 2) - 0.45
		local depth = outer - band.inner - 0.4
		local cf = sectorCFrame((j + offset) * step, mid, top - 0.5)
		local color = tint(if (j + b) % 2 == 0 then TILE else TILE_ALT, 7)
		if chance(0.12) then
			-- cracked flagstone: two halves, the outer one sunk and tilted
			local half = depth / 2
			make("floor", floorF, "Part", {
				Size = Vector3.new(width, 1, half - 0.2),
				CFrame = cf * CFrame.new(0, 0, half / 2),
				Material = Enum.Material.Slate,
				Color = color,
			})
			make("floor", floorF, "Part", {
				Size = Vector3.new(width, 1, half - 0.2),
				CFrame = cf
					* CFrame.new(0, -0.18, -half / 2)
					* CFrame.Angles(rad(between(-2, 2)), 0, rad(between(-2.5, 2.5))),
				Material = Enum.Material.Slate,
				Color = tint(TILE, 10),
			})
		else
			make("floor", floorF, "Part", {
				Size = Vector3.new(width, 1, depth),
				CFrame = cf,
				Material = Enum.Material.Slate,
				Color = color,
			})
		end
		if brokenEdge then
			-- the snapped-off piece hangs over the rim, tipping into the void
			local angle = (j + offset) * step
			make("decor", rimF, "Part", {
				Size = Vector3.new(width * between(0.5, 0.8), 1.2, between(4, 6)),
				CFrame = sectorCFrame(angle, between(108, 111), between(-1.6, -0.6))
					* CFrame.Angles(rad(between(10, 22)), rad(between(-12, 12)), rad(between(-6, 6))),
				Material = Enum.Material.Slate,
				Color = color,
			})
		end
	end
end

-- Center disc that carries the rune circle.
make("floor", floorF, "Part", {
	Name = "RuneFloor",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(1.2, 52, 52),
	CFrame = CFrame.new(0, 0, 0) * UPRIGHT,
	Material = Enum.Material.Slate,
	Color = tint(DARK_STONE, 0),
})

-- Raised marble ring around the circle, with a gold inlay on each block. Three blocks are cracked.
do
	local count = 24
	local step = TAU / count
	local cracked = { [3] = true, [11] = true, [19] = true }
	for j = 0, count - 1 do
		local width = 2 * 30 * math.sin(step / 2) - 0.3
		local cf = sectorCFrame(j * step, 30, 0.4)
		if cracked[j] then
			cf = cf * CFrame.new(0, -0.45, 0) * CFrame.Angles(rad(between(-4, 4)), 0, rad(between(-5, 5)))
			make("decor", rimF, "Part", {
				Size = Vector3.new(between(1, 2), between(0.8, 1.4), between(1, 2)),
				CFrame = sectorCFrame(j * step + between(-0.05, 0.05), between(35.5, 37), 0.9)
					* randomRotation(),
				Material = Enum.Material.Marble,
				Color = tint(MARBLE, 10),
			})
		end
		local block = make("floor", floorF, "Part", {
			Size = Vector3.new(width, 2, 8),
			CFrame = cf,
			Material = Enum.Material.Marble,
			Color = tint(MARBLE, 8),
		})
		if not cracked[j] then
			glow(runesF, "Part", {
				Size = Vector3.new(width - 0.9, 0.08, 0.35),
				CFrame = block.CFrame * CFrame.new(0, 1.02, 0),
				Color = RUNE_GOLD,
			})
		end
	end
end

--------------------------------------------------------------------------------
-- Rune circle: rings, a hexagram, glyphs, spokes, a floating focus crystal and orbiting shards.
--------------------------------------------------------------------------------

do
	local y = 0.64
	local center = CFrame.new(0, y, 0)
	ring(runesF, center, 23, 36, 0.7, 0.08, RUNE_GOLD)
	ring(runesF, center, 19.5, 32, 0.35, 0.08, RUNE_GOLD)
	ring(runesF, center, 11, 24, 0.45, 0.08, RUNE_GOLD)
	ring(runesF, center, 5, 16, 0.3, 0.08, RUNE_GOLD)

	for tri = 0, 1 do
		local corners = {}
		for k = 0, 2 do
			table.insert(corners, polar(tri * 60 + k * 120, 19.5, y))
		end
		for k = 1, 3 do
			line(runesF, corners[k], corners[k % 3 + 1], 0.35, 0.08, RUNE_GOLD)
		end
	end

	-- 24 glyphs between the two outer rings: a radial stroke with an offset cross tick.
	for k = 0, 23 do
		local theta = k * 15 + 7.5
		local length = between(1.2, 2.4)
		local inner = 20.1
		local a = polar(theta, inner, y)
		local b = polar(theta, inner + length, y)
		line(runesF, a, b, 0.25, 0.08, RUNE_GOLD)
		local tickAt = polar(theta, inner + length * between(0.3, 0.9), y)
		local tick = between(0.8, 1.6)
		local tangent = CFrame.lookAt(tickAt, Vector3.new(0, y, 0)) * CFrame.Angles(0, math.pi / 2, 0)
		glow(runesF, "Part", {
			Size = Vector3.new(0.25, 0.08, tick),
			CFrame = tangent * CFrame.new(0, 0, between(-0.3, 0.3)),
			Color = RUNE_GOLD,
		})
	end

	for k = 0, 7 do
		line(runesF, polar(k * 45 + 22.5, 5.3, y), polar(k * 45 + 22.5, 10.7, y), 0.3, 0.08, RUNE_GOLD)
	end
	for k = 0, 11 do
		glow(runesF, "Part", {
			Size = Vector3.new(0.9, 0.08, 0.9),
			CFrame = CFrame.new(polar(k * 30 + 15, 15.2, y)) * CFrame.Angles(0, rad(k * 30 + 60), 0),
			Color = RUNE_GOLD,
		})
	end
	glow(runesF, "Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 4, 4),
		CFrame = CFrame.new(0, y, 0) * UPRIGHT,
		Color = RUNE_GOLD,
	})

	local focus = glow(runesF, "Part", {
		Name = "FocusCrystal",
		Size = Vector3.new(2.2, 2.2, 2.2),
		CFrame = CFrame.new(0, 8, 0) * CFrame.Angles(rad(45), 0, rad(35.26)),
		Color = RUNE_GOLD,
	})
	light(focus, RUNE_GOLD, 32, 2.2)

	for k = 0, 5 do
		local theta = k * 60 + 30
		local height = between(5.5, 8.5)
		local base = CFrame.new(polar(theta, 8.5, height))
			* CFrame.Angles(0, rad(theta), 0)
			* CFrame.Angles(rad(between(-25, -12)), 0, rad(between(-10, 10)))
		make("decor", runesF, "Part", {
			Size = Vector3.new(1.1, 3.4, 0.9),
			CFrame = base,
			Material = Enum.Material.Basalt,
			Color = tint(DARK_STONE, 6),
		})
		glow(runesF, "Part", {
			Size = Vector3.new(0.45, 0.7, 0.45),
			CFrame = base * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, rad(45), 0),
			Color = RUNE_GOLD,
		})
	end
end

--------------------------------------------------------------------------------
-- Spawn rings: invisible spawn markers, each on a stone pad with a faint rune.
--------------------------------------------------------------------------------

local innerSpawns = folder("InnerSpawns", arena)
for k = 0, 7 do
	local pos = polar(k * 45 + 22.5, 44, 0)
	make("floor", floorF, "Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 7, 7),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * UPRIGHT,
		Material = Enum.Material.Slate,
		Color = tint(DARK_STONE, 4),
	})
	ring(runesF, CFrame.new(pos + Vector3.new(0, 0.79, 0)), 2.6, 6, 0.25, 0.08, RUNE_VIOLET, 0.35)
	glow(runesF, "Part", {
		Size = Vector3.new(0.6, 0.08, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.79, 0)) * CFrame.Angles(0, rad(45), 0),
		Color = RUNE_VIOLET,
		Transparency = 0.35,
	})
	make("marker", innerSpawns, "Part", {
		Name = `Inner{k + 1}`,
		Size = Vector3.new(4, 1, 4),
		CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)),
	})
end

local outerSpawns = folder("OuterSpawns", arena)
do
	local index = 0
	for k = 1, 9 do
		if k == 5 then
			continue -- south: keep the player spawn clear
		end
		index += 1
		local theta = k * 36
		local pos = polar(theta, 82, 0)
		make("floor", floorF, "Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 8, 8),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * UPRIGHT,
			Material = Enum.Material.Slate,
			Color = tint(DARK_STONE, 4),
		})
		local runeCenter = CFrame.new(pos + Vector3.new(0, 0.84, 0)) * CFrame.Angles(0, rad(theta), 0)
		ring(runesF, runeCenter, 3, 8, 0.25, 0.08, RUNE_EMBER, 0.35)
		for t = 0, 3 do
			glow(runesF, "Part", {
				Size = Vector3.new(0.22, 0.08, 1.1),
				CFrame = runeCenter * CFrame.Angles(0, t * math.pi / 2, 0) * CFrame.new(0, 0, -1.6),
				Color = RUNE_EMBER,
				Transparency = 0.35,
			})
		end
		make("marker", outerSpawns, "Part", {
			Name = `Outer{index}`,
			Size = Vector3.new(4, 1, 4),
			CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)),
		})
	end
end

--------------------------------------------------------------------------------
-- Broken pillars at r 95: stacked drums that lean and slip, snapped crowns, fallen drums, rubble.
--------------------------------------------------------------------------------

for index = 1, 10 do
	local theta = 18 + (index - 1) * 36
	local base = polar(theta, 95, 0)
	local group = folder(`Pillar{index}`, pillarsF)
	local yaw = between(0, TAU)
	make("decor", group, "Part", {
		Size = Vector3.new(8, 1.6, 8),
		CFrame = CFrame.new(base + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, yaw, 0),
		Material = Enum.Material.Cobblestone,
		Color = tint(COBBLE, 8),
	})
	make("decor", group, "Part", {
		Size = Vector3.new(6.6, 1, 6.6),
		CFrame = CFrame.new(base + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, yaw + rad(45), 0),
		Material = Enum.Material.Cobblestone,
		Color = tint(COBBLE, 8),
	})

	local intact = index % 3 == 0
	local drums = if intact then 5 else 3 + math.floor(rand() * 3)
	local cf = CFrame.new(base + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, yaw, 0)
	local diameter = 5
	local height = 0
	for i = 1, drums do
		height = between(3.6, 5.2)
		if i == drums and not intact then
			height *= between(0.5, 0.8)
		end
		local tilt = if intact then 1 else 3
		cf = cf
			* CFrame.Angles(rad(between(-tilt, tilt)), rad(between(-20, 20)), rad(between(-tilt, tilt)))
			* CFrame.new(between(-0.25, 0.25), height / 2, between(-0.25, 0.25))
		make("decor", group, "Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = cf * UPRIGHT,
			Material = Enum.Material.Cobblestone,
			Color = tint(COBBLE, 10),
		})
		if i == 2 and index % 2 == 1 then
			local band = glow(group, "Part", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.35, diameter + 0.3, diameter + 0.3),
				CFrame = cf * UPRIGHT,
				Color = RUNE_GOLD,
			})
			light(band, RUNE_GOLD, 12, 1)
		end
		cf = cf * CFrame.new(0, height / 2, 0)
		diameter -= 0.15
	end

	if intact then
		make("decor", group, "Part", {
			Size = Vector3.new(6.8, 1.2, 6.8),
			CFrame = cf * CFrame.new(0, 0.6, 0),
			Material = Enum.Material.Cobblestone,
			Color = tint(COBBLE, 8),
		})
	else
		-- jagged snapped crown
		make("decor", group, "WedgePart", {
			Size = Vector3.new(diameter * 0.9, between(1.2, 2.2), diameter * 0.55),
			CFrame = cf * CFrame.new(0, 0.6, diameter * 0.18) * CFrame.Angles(0, rad(between(-15, 15)), 0),
			Material = Enum.Material.Cobblestone,
			Color = tint(COBBLE, 10),
		})
		if chance(0.5) then
			-- a fragment the old magic still holds in the air
			make("decor", group, "Part", {
				Size = Vector3.new(diameter * 0.7, 1.4, diameter * 0.5),
				CFrame = cf
					* CFrame.new(between(-0.5, 0.5), between(3, 4.5), 0)
					* CFrame.Angles(rad(between(-20, 20)), rad(between(0, 90)), rad(between(-20, 20))),
				Material = Enum.Material.Cobblestone,
				Color = tint(COBBLE, 10),
			})
		end
	end

	-- a fallen drum, toppled inward so it stays on the platform
	local inward = rad(theta + 180 + between(-70, 70))
	local fallDistance = between(6, 9)
	local fallPos = base + Vector3.new(math.sin(inward) * fallDistance, 1.9, math.cos(inward) * fallDistance)
	make("decor", group, "Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(between(3.5, 5), 4.6, 4.6),
		CFrame = CFrame.new(fallPos) * CFrame.Angles(0, between(0, TAU), rad(between(-6, 6))),
		Material = Enum.Material.Cobblestone,
		Color = tint(COBBLE, 10),
	})
	for _ = 1, 3 do
		local size = Vector3.new(between(0.8, 2), between(0.6, 1.4), between(0.8, 2))
		local angle = between(0, TAU)
		local distance = between(4.5, 7)
		make("decor", group, "Part", {
			Size = size,
			CFrame = CFrame.new(
				base + Vector3.new(math.sin(angle) * distance, size.Y * 0.35, math.cos(angle) * distance)
			) * CFrame.Angles(rad(between(-25, 25)), between(0, TAU), rad(between(-25, 25))),
			Material = Enum.Material.Rock,
			Color = tint(ROCK, 8),
		})
	end
end

--------------------------------------------------------------------------------
-- Broken rim: a curb with gaps and snapped stones, and jagged rock under the lip.
--------------------------------------------------------------------------------

do
	local count = 44
	local step = 360 / count
	for k = 0, count - 1 do
		local theta = k * step
		local fromNorth = math.min(theta, 360 - theta)
		if fromNorth < 17 or chance(0.25) then
			continue -- no curb along the dais, and gaps elsewhere
		end
		local chord = 2 * 104.5 * math.sin(rad(step / 2)) - 0.5
		local height = between(1.4, 2.6)
		local cf = CFrame.lookAt(polar(theta, 104.5, height / 2), Vector3.new(0, height / 2, 0))
		if chance(0.25) then
			local length = chord * between(0.4, 0.7)
			cf = cf
				* CFrame.new(between(-(chord - length) / 2, (chord - length) / 2), -height * 0.2, 0)
				* CFrame.Angles(rad(between(-10, 10)), 0, rad(between(-14, 14)))
			chord = length
		end
		make("decor", rimF, "Part", {
			Size = Vector3.new(chord, height, 2.4),
			CFrame = cf,
			Material = Enum.Material.Cobblestone,
			Color = tint(COBBLE, 10),
		})
	end

	for _ = 1, 40 do
		local size = Vector3.new(between(5, 12), between(4, 10), between(5, 12))
		make("decor", rimF, "Part", {
			Size = size,
			CFrame = CFrame.new(polar(between(0, 360), between(99, 107), between(-10, -3)))
				* randomRotation(),
			Material = Enum.Material.Rock,
			Color = tint(ROCK, 10),
		})
	end
end

--------------------------------------------------------------------------------
-- Underside: stepped rock tiers narrowing to a crystal tip, stalactites and glowing veins.
--------------------------------------------------------------------------------

do
	local tiers = {
		{ diameter = 200, height = 10, y = -13 },
		{ diameter = 172, height = 11, y = -23 },
		{ diameter = 136, height = 10, y = -32 },
		{ diameter = 92, height = 8, y = -39 },
		{ diameter = 48, height = 6, y = -44 },
	}
	for i, tier in tiers do
		local mix = (i - 1) / (#tiers - 1)
		local color: RGB = {
			ROCK[1] + (ROCK_DEEP[1] - ROCK[1]) * mix,
			ROCK[2] + (ROCK_DEEP[2] - ROCK[2]) * mix,
			ROCK[3] + (ROCK_DEEP[3] - ROCK[3]) * mix,
		}
		make("decor", undersideF, "Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(tier.height, tier.diameter, tier.diameter),
			CFrame = CFrame.new(0, tier.y, 0) * CFrame.Angles(0, between(0, TAU), 0) * UPRIGHT,
			Material = Enum.Material.Rock,
			Color = tint(color, 4),
		})
		local stalactites = if i < #tiers then 9 else 4
		for _ = 1, stalactites do
			local length = between(6, 15)
			local edge = tier.diameter / 2 - between(2, 8)
			local bottom = tier.y - tier.height / 2
			make("decor", undersideF, "Part", {
				Size = Vector3.new(between(4, 9), length, between(4, 9)),
				CFrame = CFrame.new(polar(between(0, 360), edge, bottom - length * 0.3))
					* CFrame.Angles(rad(between(-18, 18)), between(0, TAU), rad(between(-18, 18))),
				Material = Enum.Material.Rock,
				Color = tint(color, 8),
			})
		end
	end

	for k = 0, 7 do
		local theta = k * 45 + between(-15, 15)
		local tier = tiers[2 + k % 3]
		local root = polar(theta, tier.diameter / 2 - 1, tier.y - tier.height / 2 + 1)
		local tip = polar(theta, tier.diameter / 2 + between(3, 7), tier.y - tier.height / 2 - between(5, 10))
		local length = (tip - root).Magnitude
		glow(undersideF, "Part", {
			Size = Vector3.new(0.9, 0.9, length),
			CFrame = CFrame.lookAt((root + tip) * 0.5, tip) * CFrame.Angles(0, 0, rad(45)),
			Color = CRYSTAL,
		})
	end

	local tipCrystal = glow(undersideF, "Part", {
		Name = "HeartCrystal",
		Size = Vector3.new(3, 7, 3),
		CFrame = CFrame.new(0, -46, 0) * CFrame.Angles(0, rad(45), 0),
		Color = CRYSTAL,
	})
	light(tipCrystal, CRYSTAL, 40, 2)
end

--------------------------------------------------------------------------------
-- Floating debris around the island, some sprouting crystals.
--------------------------------------------------------------------------------

for index = 1, 30 do
	local size = Vector3.new(between(3, 13), between(2, 8), between(3, 13))
	local pos = polar(between(0, 360), between(118, 200), between(-42, 14))
	local rock = make("decor", debrisF, "Part", {
		Size = size,
		CFrame = CFrame.new(pos)
			* CFrame.Angles(rad(between(-30, 30)), between(0, TAU), rad(between(-30, 30))),
		Material = if index % 2 == 0 then Enum.Material.Slate else Enum.Material.Rock,
		Color = tint(ROCK, 12),
	})
	if index % 3 == 0 then
		glow(debrisF, "Part", {
			Size = Vector3.new(0.8, between(2, 4), 0.8),
			CFrame = rock.CFrame
				* CFrame.new(0, size.Y / 2 + 0.8, 0)
				* CFrame.Angles(rad(between(-20, 20)), rad(45), rad(between(-20, 20))),
			Color = CRYSTAL,
		})
	end
end

--------------------------------------------------------------------------------
-- Distant islands for depth against the sunset.
--------------------------------------------------------------------------------

for _, island in
	{
		{ theta = 60, radius = 300, y = -10, diameter = 60 },
		{ theta = 205, radius = 330, y = 18, diameter = 44 },
		{ theta = 300, radius = 260, y = -32, diameter = 36 },
		{ theta = 130, radius = 380, y = 30, diameter = 28 },
	}
do
	local center = polar(island.theta, island.radius, island.y)
	local d = island.diameter
	make("decor", islandsF, "Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, d, d),
		CFrame = CFrame.new(center) * UPRIGHT,
		Material = Enum.Material.Slate,
		Color = tint(TILE, 6),
	})
	make("decor", islandsF, "Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, d * 0.72, d * 0.72),
		CFrame = CFrame.new(center + Vector3.new(0, -6.5, 0)) * UPRIGHT,
		Material = Enum.Material.Rock,
		Color = tint(ROCK, 6),
	})
	make("decor", islandsF, "Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, d * 0.42, d * 0.42),
		CFrame = CFrame.new(center + Vector3.new(0, -14, 0)) * UPRIGHT,
		Material = Enum.Material.Rock,
		Color = tint(ROCK_DEEP, 6),
	})
	make("decor", islandsF, "Part", {
		Size = Vector3.new(d * 0.2, 10, d * 0.2),
		CFrame = CFrame.new(center + Vector3.new(0, -21, 0)) * CFrame.Angles(0, rad(45), rad(8)),
		Material = Enum.Material.Rock,
		Color = tint(ROCK_DEEP, 6),
	})
	for p = 1, 2 do
		local height = between(5, 12)
		local offset = Vector3.new(between(-d * 0.3, d * 0.3), 2.5 + height / 2, between(-d * 0.3, d * 0.3))
		make("decor", islandsF, "Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, 3.4, 3.4),
			CFrame = CFrame.new(center + offset)
				* CFrame.Angles(rad(between(-6, 6)), 0, rad(between(-6, 6)))
				* UPRIGHT,
			Material = Enum.Material.Cobblestone,
			Color = tint(COBBLE, 10),
		})
		if p == 1 then
			glow(islandsF, "Part", {
				Size = Vector3.new(1.2, 3.5, 1.2),
				CFrame = CFrame.new(center + Vector3.new(-offset.X * 0.5, 4.2, -offset.Z * 0.5))
					* CFrame.Angles(0, rad(45), rad(15)),
				Color = CRYSTAL,
			})
		end
	end
end

--------------------------------------------------------------------------------
-- Boss dais (north): four tiers to 4 studs, crimson lips, altar, obelisks and an eclipse.
--------------------------------------------------------------------------------

do
	local tiers = { { 50, 1.3 }, { 42, 2.2 }, { 34, 3.1 }, { 26, 4.0 } }
	for i, tier in tiers do
		local diameter, top = tier[1], tier[2]
		local height = top + 1
		make("floor", floorF, "Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(DAIS_CENTER + Vector3.new(0, top - height / 2, 0)) * UPRIGHT,
			Material = Enum.Material.Basalt,
			Color = tint(DAIS_STONE, 3),
		})
		if i == 1 or i == #tiers then
			glow(runesF, "Part", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, diameter + 0.35, diameter + 0.35),
				CFrame = CFrame.new(DAIS_CENTER + Vector3.new(0, top - 0.4, 0)) * UPRIGHT,
				Color = ECLIPSE,
			})
		end
	end
end

local bossAltar = Instance.new("Model")
bossAltar.Name = "BossAltar"
bossAltar.Parent = arena
do
	local top = 4
	local altarPos = DAIS_CENTER + Vector3.new(0, top + 1.5, 2)
	local altar = make("floor", bossAltar, "Part", {
		Name = "Altar",
		Size = Vector3.new(7, 3, 4.5),
		CFrame = CFrame.new(altarPos),
		Material = Enum.Material.Marble,
		Color = tint(MARBLE, 0),
	})
	bossAltar.PrimaryPart = altar

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SummonPrompt"
	prompt.ActionText = "Triệu hồi Boss"
	prompt.ObjectText = "Hộ Vệ Nhật Thực"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	-- E is a skill key, so the prompt uses B (for Boss).
	prompt.KeyboardKeyCode = Enum.KeyCode.B
	prompt.Parent = altar

	make("decor", bossAltar, "Part", {
		Size = Vector3.new(7.8, 0.6, 5.2),
		CFrame = CFrame.new(altarPos + Vector3.new(0, 1.8, 0)),
		Material = Enum.Material.Basalt,
		Color = tint(DARK_STONE, 0),
	})
	glow(bossAltar, "Part", {
		Size = Vector3.new(7.9, 0.2, 0.2),
		CFrame = CFrame.new(altarPos + Vector3.new(0, 1.45, -2.62)),
		Color = ECLIPSE,
	})
	local crystal = glow(bossAltar, "Part", {
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = CFrame.new(altarPos + Vector3.new(0, 4.2, 0)) * CFrame.Angles(rad(45), 0, rad(35.26)),
		Color = CRYSTAL,
	})
	light(crystal, CRYSTAL, 24, 2)

	-- Eclipse: a dark disc ringed by a crimson corona, hanging behind the altar.
	local eclipseCenter = DAIS_CENTER + Vector3.new(0, 17, 10)
	local disc = make("decor", bossAltar, "Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 15, 15),
		CFrame = CFrame.new(eclipseCenter) * CFrame.Angles(0, math.pi / 2, 0),
		Material = Enum.Material.Basalt,
		Color = Color3.fromRGB(18, 14, 22),
		CastShadow = false,
	})
	light(disc, ECLIPSE, 30, 3)
	local facing = CFrame.new(eclipseCenter + Vector3.new(0, 0, -0.2)) * CFrame.Angles(math.pi / 2, 0, 0)
	ring(bossAltar, facing, 8.1, 28, 0.9, 0.6, ECLIPSE)
	ring(bossAltar, facing, 9.7, 28, 0.35, 0.3, ECLIPSE, 0.45)

	for side = -1, 1, 2 do
		local obeliskPos = DAIS_CENTER + Vector3.new(side * 12, top + 6.5, 3)
		make("decor", bossAltar, "Part", {
			Size = Vector3.new(2.6, 13, 2.6),
			CFrame = CFrame.new(obeliskPos) * CFrame.Angles(0, 0, rad(side * -2)),
			Material = Enum.Material.Basalt,
			Color = tint(DAIS_STONE, 4),
		})
		glow(bossAltar, "Part", {
			Size = Vector3.new(1.9, 1.9, 1.9),
			CFrame = CFrame.new(obeliskPos + Vector3.new(side * -0.25, 7.6, 0))
				* CFrame.Angles(rad(45), 0, rad(45)),
			Color = ECLIPSE,
		})
		glow(bossAltar, "Part", {
			Size = Vector3.new(0.45, 9, 0.12),
			CFrame = CFrame.new(obeliskPos + Vector3.new(0, 0.5, -1.33))
				* CFrame.Angles(0, 0, rad(side * -2)),
			Color = ECLIPSE,
		})
	end
end

make("marker", arena, "Part", {
	Name = "BossSpawn",
	Size = Vector3.new(6, 1, 6),
	CFrame = CFrame.new(0, 3, 60),
})

--------------------------------------------------------------------------------
-- Player spawn (south): a marble pad facing north, a gold rune ring and two braziers.
--------------------------------------------------------------------------------

do
	local spawnPos = Vector3.new(0, 0, -92)
	make("floor", floorF, "Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, 20, 20),
		CFrame = CFrame.new(spawnPos + Vector3.new(0, 0.1, 0)) * UPRIGHT,
		Material = Enum.Material.Slate,
		Color = tint(DARK_STONE, 0),
	})
	make("floor", arena, "SpawnLocation", {
		Name = "PlayerSpawn",
		Size = Vector3.new(12, 1, 12),
		CFrame = CFrame.new(spawnPos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.pi, 0),
		Material = Enum.Material.Marble,
		Color = tint(MARBLE, 0),
		Neutral = true,
		Duration = 0,
		AllowTeamChangeOnTouch = false,
		Enabled = true,
	})
	ring(runesF, CFrame.new(spawnPos + Vector3.new(0, 0.84, 0)), 8.6, 24, 0.35, 0.08, RUNE_GOLD)

	for side = -1, 1, 2 do
		local pos = spawnPos + Vector3.new(side * 11, 0, 0)
		make("decor", propsF, "Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6, 1.6, 1.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 2.1, 0)) * UPRIGHT,
			Material = Enum.Material.Basalt,
			Color = tint(DARK_STONE, 0),
		})
		make("decor", propsF, "Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 3.2, 3.2),
			CFrame = CFrame.new(pos + Vector3.new(0, 3.8, 0)) * UPRIGHT,
			Material = Enum.Material.Basalt,
			Color = tint(DARK_STONE, 0),
		})
		local flame = glow(propsF, "Part", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = CFrame.new(pos + Vector3.new(0, 4.9, 0)),
			Color = FLAME,
		})
		light(flame, FLAME, 18, 1.8)
	end
end

--------------------------------------------------------------------------------
-- Contract markers and bounds.
--------------------------------------------------------------------------------

make("marker", arena, "Part", {
	Name = "Center",
	Size = Vector3.new(4, 1, 4),
	CFrame = CFrame.new(0, 1.5, 0),
})

local bounds = folder("Bounds", arena)
do
	local count = 16
	local step = TAU / count
	local width = 2 * WALL_RADIUS * math.tan(step / 2) + 2
	for k = 0, count - 1 do
		make("wall", bounds, "Part", {
			Name = `Wall{k + 1}`,
			Size = Vector3.new(width, 90, 2),
			CFrame = CFrame.Angles(0, k * step, 0) * CFrame.new(0, 41, -(WALL_RADIUS + 1)),
		})
	end
end

local partCount = 0
for _, inst: any in arena:GetDescendants() do
	if inst:IsA("BasePart") then
		partCount += 1
	end
end

fs.writeFile(OUT, roblox.serializeModel({ arena }))
print(`wrote {OUT}: {partCount} BaseParts`)
