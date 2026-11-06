--!strict
-- Khiên Lục Giác (hex_aegis).
--
--   form   29 hexagon tiles (a geodesic-ish hemisphere of radius 7) grow in
--          from the floor up around the caster, over a ForceField bubble and
--          a rotating rune ring on the ground
--   hold   the tiles shimmer in a slow wave and follow the caster; whenever a
--          DamagePopup shows the caster being hit, the dome pulses and the
--          tile facing the nearest enemy throws sparks
--   end    at `duration` the hexes shatter outward with spin and shrink away
--
-- The dome is built once at runtime and pooled. Tiles draw their hexagon with
-- six rotated Frames on a SurfaceGui, or the hex_cell image once uploaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared:WaitForChild("Config"):WaitForChild("AssetIds"))
local Net = require(Shared:WaitForChild("Net"))
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))
local Common = require(script.Parent.Common)
local Impact = require(script.Parent.Impact)

type FxEvent = Common.FxEvent
type Palette = Common.Palette

local HexAegis = {}

local RADIUS = 7
local TILE_SIZE = Vector3.new(3.0, 2.6, 0.05)
local CANVAS = Vector2.new(200, 173)
local FORM_TIME = 0.45
local SHATTER_TIME = 0.55
-- Elevation (degrees) and tile count per ring, bottom to top.
local RINGS = { { 12, 12 }, { 38, 10 }, { 63, 6 }, { 90, 1 } }

type Tile = {
	part: Part,
	gui: SurfaceGui,
	strokes: { GuiObject },
	rel: CFrame, -- relative to the dome centre on the floor
	out: Vector3, -- outward unit vector (dome space)
	order: number, -- 0 at the bottom ring, 1 at the top
	phase: number,
	spin: Vector3,
}

type Dome = { model: Model, tiles: { Tile }, bubble: Part, parts: { BasePart } }

local function buildHexGui(part: Part): (SurfaceGui, { GuiObject })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = part
	local strokes: { GuiObject } = {}
	if AssetIds.has("hex_cell") then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = AssetIds.tex("hex_cell")
		img.Parent = gui
		table.insert(strokes, img)
		return gui, strokes
	end
	-- Flat-top hexagon outline from six rotated bars, plus a faint inner hexagon.
	local cx, cy = CANVAS.X / 2, CANVAS.Y / 2
	for layer = 1, 2 do
		local R = if layer == 1 then 96 else 60
		local thickness = if layer == 1 then 8 else 3
		for k = 0, 5 do
			local a0 = math.rad(60 * k)
			local a1 = math.rad(60 * (k + 1))
			local x0, y0 = cx + math.cos(a0) * R, cy + math.sin(a0) * R
			local x1, y1 = cx + math.cos(a1) * R, cy + math.sin(a1) * R
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
			bar.Size = UDim2.fromOffset(R + thickness * 0.6, thickness)
			bar.Rotation = math.deg(math.atan2(y1 - y0, x1 - x0))
			bar.BorderSizePixel = 0
			bar.BackgroundTransparency = if layer == 1 then 0 else 0.55
			bar.Parent = gui
			table.insert(strokes, bar)
		end
	end
	return gui, strokes
end

local function buildDome(): Dome
	local model = Instance.new("Model")
	model.Name = "HexAegisDome"
	local tiles: { Tile } = {}
	local parts: { BasePart } = {}
	for ringIndex, ring in RINGS do
		local elevation = math.rad(ring[1])
		local count = ring[2]
		for k = 0, count - 1 do
			local azimuth = (k + (if ringIndex % 2 == 0 then 0.5 else 0)) / count * math.pi * 2
			local out = Vector3.new(
				math.cos(elevation) * math.cos(azimuth),
				math.sin(elevation),
				math.cos(elevation) * math.sin(azimuth)
			)
			local pos = out * RADIUS
			local up = if out.Y > 0.99 then Vector3.zAxis else Vector3.yAxis
			local part = Instance.new("Part")
			part.Name = "Hex"
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Transparency = 1
			part.Size = TILE_SIZE
			part.Parent = model
			local gui, strokes = buildHexGui(part)
			table.insert(tiles, {
				part = part,
				gui = gui,
				strokes = strokes,
				rel = CFrame.lookAt(pos, pos + out, up),
				out = out,
				order = (ringIndex - 1) / (#RINGS - 1),
				phase = azimuth * 2 + elevation * 3,
				spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8,
			})
			table.insert(parts, part)
		end
	end
	local bubble = Instance.new("Part")
	bubble.Name = "Bubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.ForceField
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanTouch = false
	bubble.CanQuery = false
	bubble.CastShadow = false
	bubble.Size = Vector3.one * (RADIUS * 2 - 0.4)
	bubble.Parent = model
	table.insert(parts, bubble)
	return { model = model, tiles = tiles, bubble = bubble, parts = parts }
end

-- Pool of whole domes (each built once, reused across casts).
local domePool = {
	free = {} :: { Dome },
}

local function getDome(): Dome
	return table.remove(domePool.free) or buildDome()
end

local function releaseDome(dome: Dome)
	dome.model.Parent = nil
	if #domePool.free < 4 then
		table.insert(domePool.free, dome)
	else
		dome.model:Destroy()
	end
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

function HexAegis.play(event: FxEvent)
	local spec = event.spec
	local palette: Palette = VfxPalette.get(spec.element, spec.radiant)
	local duration = spec.duration or 3
	local age0 = Common.age(event.serverTime)
	if age0 >= duration then
		return
	end
	local fx = Common.effect("HexAegis", duration + SHATTER_TIME + 0.2 - age0)
	local caster = event.casterUserId
	local character = Common.characterOf(caster)
	local root = Common.rootOf(character)
	local floor = Common.ground(event.origin, 20)
	local floorOffset = event.origin.Y - floor.Y

	local dome = getDome()
	fx:onFinish(function()
		releaseDome(dome)
	end)
	for _, tile in dome.tiles do
		for _, s in tile.strokes do
			if s:IsA("ImageLabel") then
				s.ImageColor3 = palette.glow
			else
				s.BackgroundColor3 = palette.glow
			end
		end
		tile.gui.Brightness = 2
		tile.part.Size = Vector3.new(0.05, 0.05, 0.05)
	end
	dome.bubble.Color = palette.glow
	dome.bubble.Transparency = 1
	dome.model.Parent = fx.folder

	local sigil = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.12, 0)), RADIUS + 0.6, {
		rings = { 1, 0.9, 0.5 },
		ringWidth = 0.3,
		star = 0.5,
		spokes = 6,
		color = palette.glow,
		runes = true,
		brightness = 2 * palette.brightness,
	})
	sigil:setScale(0.1)
	sigil:setTransparency(1)

	local light = fx:light(dome.bubble, { Color = palette.glow, Range = 18, Brightness = 0 })

	-- Shards for the shatter: one emitter on the bubble, fired once.
	local shards = fx:emitter(dome.bubble, {
		Enabled = false,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Speed = NumberRange.new(10, 22),
		Drag = 3,
		Acceleration = Vector3.new(0, -18, 0),
		Lifetime = NumberRange.new(0.4, 0.8),
		Size = Common.seq({ { 0, 0.6 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
		Color = Common.colors(palette.core, palette.glow),
		RotSpeed = NumberRange.new(-300, 300),
		Brightness = 2,
	}, "spark")

	local pulseAt = -10
	local function centerNow(): Vector3
		if root and root.Parent then
			return Vector3.new(root.Position.X, root.Position.Y - floorOffset, root.Position.Z)
		end
		return floor
	end

	-- Hits on the caster: Combat fires DamagePopup at head + 1.5 studs.
	local remotes = Net.client()
	fx:connect(remotes[Net.names.DamagePopup].OnClientEvent, function(popup: Net.DamagePopup)
		if type(popup) ~= "table" or typeof(popup.position) ~= "Vector3" or not character then
			return
		end
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return
		end
		if (popup.position - (head.Position + Vector3.new(0, 1.5, 0))).Magnitude > 2 then
			return
		end
		pulseAt = fx:elapsed() + age0
		-- Sparks on the tile that faces the nearest enemy.
		local c = centerNow()
		local enemies = workspace:FindFirstChild("Enemies")
		local bestDir: Vector3? = nil
		local bestDist = math.huge
		if enemies then
			for _, enemy in enemies:GetChildren() do
				if enemy:IsA("Model") then
					local offset = enemy:GetPivot().Position - c
					if offset.Magnitude < bestDist then
						bestDist = offset.Magnitude
						bestDir = offset
					end
				end
			end
		end
		local hitDir = bestDir or (workspace.CurrentCamera.CFrame.Position - c)
		local flat = Vector3.new(hitDir.X, math.max(hitDir.Y, 0) + 2, hitDir.Z)
		local outward = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.yAxis
		Impact.play(c + outward * RADIUS, palette, 0.55, false, {
			ring = false,
			dust = false,
			light = false,
			normal = outward,
		})
	end)

	local shattered = false
	local cfs: { CFrame } = table.create(#dome.parts)

	fx:onStep(function(_dt, elapsed)
		local T = elapsed + age0
		local c = centerNow()
		local base = CFrame.new(c)
		local form = clamp01(T / FORM_TIME)
		local breakT = clamp01((T - duration) / SHATTER_TIME)
		local pulse = math.max(0, 1 - (T - pulseAt) / 0.35)

		if breakT > 0 and not shattered then
			shattered = true
			if shards then
				shards:Emit(40)
			end
			Common.shake(0.3, 0.2, c, caster)
		end

		for i, tile in dome.tiles do
			-- Each tile grows in after the ring below it (bottom to top).
			local local01 = clamp01((form - tile.order * 0.45) / 0.55)
			local grow = 1 - (1 - local01) ^ 3
			local swell = 1 + 0.07 * pulse
			local cf: CFrame
			local scale: number
			if breakT > 0 then
				local e = breakT ^ 0.6
				local fly = tile.out * (RADIUS + 9 * e)
				cf = base
					* CFrame.new(fly)
					* (tile.rel - tile.rel.Position)
					* CFrame.Angles(tile.spin.X * e, tile.spin.Y * e, tile.spin.Z * e)
				scale = 1 - breakT
			else
				local rise = (1 - grow) * 1.5
				cf = base * CFrame.new(tile.out * (RADIUS * swell + rise)) * (tile.rel - tile.rel.Position)
				scale = grow
			end
			cfs[i] = cf
			tile.part.Size = Vector3.new(
				math.max(TILE_SIZE.X * scale, 0.05),
				math.max(TILE_SIZE.Y * scale, 0.05),
				TILE_SIZE.Z
			)
			tile.gui.Brightness = (1.6 + 0.6 * math.sin(T * 3 + tile.phase) + 3 * pulse) * palette.brightness
		end
		cfs[#dome.tiles + 1] = base
		workspace:BulkMoveTo(dome.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)

		dome.bubble.Size = Vector3.one
			* math.max((RADIUS * 2 - 0.4) * (0.2 + 0.8 * form) * (1 + 0.05 * pulse), 0.1)
		dome.bubble.Transparency = math.clamp(math.max(1 - form * 0.95, breakT) - 0.3 * pulse, 0, 1)
		light.Brightness = (1.2 * form + 3 * pulse) * (1 - breakT) * palette.brightness

		sigil:setCFrame(CFrame.new(c + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, T * 0.9, 0))
		sigil:setScale((0.1 + 0.9 * (1 - (1 - form) ^ 3)) * (1 + 0.15 * breakT))
		sigil:setTransparency(math.max(0.2 + 0.8 * (1 - form) - 0.2 * pulse, breakT))
		return breakT >= 1
	end)
end

return HexAegis
