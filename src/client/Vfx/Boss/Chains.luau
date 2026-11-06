--!strict
-- chains: the binding.
--   telegraph  a crimson rune ring at the target's feet; its fill grows to the edge over
--              `delay` under a blinking outline (faster as it closes)
--   erupt      at `delay`, five gold chains of part links burst from the ring's edge, arc up
--              and wrap in onto whoever stands inside (or snap shut on the centre)
--   bind       a pair of spinning gold rings lock around each rooted player for `duration`
--              while the chains quiver under tension
--   release    the links shatter outward into sparks and the rings burst

local Players = game:GetService("Players")

local Common = require(script.Parent.Parent.Common)
local Impact = require(script.Parent.Parent.Impact)
local Kit = require(script.Parent.Kit)

type Effect = Common.Effect
type Sigil = Common.Sigil
type Payload = Kit.Payload

local Chains = {}

local CHAIN_COUNT = 5
local LINKS = 12
local ERUPT_TIME = 0.24
local BREAK_TIME = 0.35
local LINK_SIZE = Vector3.new(0.16, 0.46, 0.78)

type Chain = {
	links: { Part },
	start: Vector3,
	outward: Vector3,
	victim: BasePart?,
	offset: Vector3,
	burst: { Vector3 },
}

type Bind = { root: BasePart, rings: { Sigil } }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): (Vector3, Vector3)
	local u = 1 - t
	local pos = p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
	local tangent = (p1 - p0) * (2 * u) + (p2 - p1) * (2 * t)
	return pos, tangent
end

-- Players whose root stands inside the ring when it closes.
local function rootsInside(center: Vector3, radius: number): { BasePart }
	local list: { BasePart } = {}
	for _, player in Players:GetPlayers() do
		local root = Common.rootOf(player.Character)
		if root then
			local d = root.Position - center
			if Vector3.new(d.X, 0, d.Z).Magnitude <= radius and math.abs(d.Y) <= 10 then
				table.insert(list, root)
			end
		end
	end
	return list
end

local function telegraph(fx: Effect, floor: Vector3, radius: number, delay: number)
	local outline = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.15, 0)), radius, {
		rings = { 1, 0.95 },
		ringWidth = 0.3,
		color = Kit.CRIMSON_HOT,
		brightness = 3,
	})
	local runes = Common.sigil(fx, CFrame.new(floor + Vector3.new(0, 0.13, 0)), radius * 0.86, {
		rings = { 1, 0.62 },
		ringWidth = 0.14,
		star = 0.6,
		spokes = 6,
		color = Kit.CRIMSON,
		runes = true,
		runeColor = Kit.CRIMSON_HOT,
		brightness = 2,
	})
	local flat = CFrame.Angles(0, 0, math.pi / 2)
	local fill = fx:part({
		Shape = Enum.PartType.Cylinder,
		Color = Kit.CRIMSON,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		Size = Vector3.new(0.08, 0.1, 0.1),
		CFrame = CFrame.new(floor + Vector3.new(0, 0.1, 0)) * flat,
	})
	local base = fx:part({
		Shape = Enum.PartType.Cylinder,
		Color = Kit.CRIMSON_DEEP,
		Material = Enum.Material.Neon,
		Transparency = 0.82,
		Size = Vector3.new(0.06, radius * 2, radius * 2),
		CFrame = CFrame.new(floor + Vector3.new(0, 0.09, 0)) * flat,
	})
	outline:setScale(1.3)
	fx:onStep(function(_dt, elapsed)
		local snap = clamp01(elapsed / 0.14)
		outline:setScale(1.3 - 0.3 * (1 - (1 - snap) ^ 2))
		local t = clamp01(elapsed / delay)
		local blink = 0.5 + 0.5 * math.sin(elapsed * (7 + 20 * t))
		local after = clamp01((elapsed - delay) / 0.25)
		outline:setTransparency(math.max(0.3 * blink * (1 - t) + (1 - snap), after))
		runes:setCFrame(CFrame.new(floor + Vector3.new(0, 0.13, 0)) * CFrame.Angles(0, -elapsed * 0.9, 0))
		runes:setTransparency(math.max(0.35 - 0.25 * t, after))
		local d = radius * 2 * (1 - (1 - t) ^ 2)
		fill.Size = Vector3.new(0.08, math.max(d, 0.1), math.max(d, 0.1))
		fill.Transparency = if elapsed < delay then 0.6 - 0.25 * t else 0.35 + 0.65 * after
		base.Transparency = 0.82 + 0.18 * after
		return after >= 1
	end)
end

-- The chain ends on the victim (spread around it) or, with nobody inside, snaps shut
-- just above the ring's centre.
local function buildChain(fx: Effect, start: Vector3, outward: Vector3, victim: BasePart?): Chain
	local links: { Part } = {}
	for k = 1, LINKS do
		links[k] = fx:part({
			Size = LINK_SIZE,
			Color = if k % 2 == 0 then Kit.GOLD else Kit.DEEP_GOLD,
			Material = Enum.Material.Metal,
			Reflectance = 0.25,
			Transparency = 1,
		})
	end
	local offset = if victim
		then outward * 0.9 + Vector3.new(0, (math.random() - 0.5) * 1.6, 0)
		else outward * 0.4 + Vector3.new(0, 2.2, 0)
	return { links = links, start = start, outward = outward, victim = victim, offset = offset, burst = {} }
end

function Chains.play(evt: Payload)
	local position = Kit.vec(evt, "position")
	if not position then
		return
	end
	local radius = math.max(Kit.num(evt, "radius", Kit.Config.chains.radius), 1)
	local delay = math.max(Kit.num(evt, "delay", Kit.Config.chains.telegraph), 0.05)
	local duration = math.max(Kit.num(evt, "duration", Kit.Config.chains.duration), 0.1)
	local floor = Common.ground(position, 30)
	local fx = Common.effect("BossChains", delay + duration + BREAK_TIME + 0.6)
	telegraph(fx, floor, radius, delay)

	local sparkHolder = fx:part({ Size = Vector3.new(1, 1, 1) })
	local sparks = fx:emitter(sparkHolder, {
		Enabled = false,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(4, 12),
		Drag = 3,
		Acceleration = Vector3.new(0, -12, 0),
		Lifetime = NumberRange.new(0.35, 0.7),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Size = Common.seq({ { 0, 0.3 }, { 1, 0 } }),
		Transparency = Common.seq({ { 0, 0 }, { 1, 1 } }),
		Color = Common.colors(Kit.WHITE_GOLD, Kit.GOLD),
		Brightness = 3,
		RotSpeed = NumberRange.new(0),
	}, "spark")

	local chains: { Chain } = {}
	local binds: { Bind } = {}
	local center = floor

	fx:at(delay, function()
		local victims = rootsInside(position, radius + 0.5)
		Impact.play(floor, Kit.CRIMSON_PALETTE, 1.1, false, { light = true })
		Impact.shockwave(floor, radius * 1.1, Kit.GOLD, 0.4, { width = 0.4, disc = false })
		Common.shake(0.5, 0.25, floor, nil, Kit.SHAKE_RADIUS)
		local spin = math.random() * math.pi * 2
		for j = 1, CHAIN_COUNT do
			local a = spin + (j - 1) / CHAIN_COUNT * math.pi * 2
			local outward = Vector3.new(math.cos(a), 0, math.sin(a))
			local start = floor + outward * (radius * 0.95)
			local victim = if #victims > 0 then victims[(j - 1) % #victims + 1] else nil
			table.insert(chains, buildChain(fx, start, outward, victim))
			Impact.play(start, Kit.GOLD_PALETTE, 0.45, false, { light = false, ring = false })
		end
		for _, root in victims do
			local rings: { Sigil } = {}
			for r = 1, 2 do
				local ring = Common.sigil(fx, CFrame.new(root.Position), 2.1 - r * 0.25, {
					rings = { 1, 0.86 },
					ringWidth = 0.2,
					star = if r == 1 then 0.86 else nil,
					color = Kit.GOLD,
					runes = r == 1,
					runeColor = Kit.WHITE_GOLD,
					brightness = 3,
				})
				ring:setScale(1.8)
				table.insert(rings, ring)
			end
			table.insert(binds, { root = root, rings = rings })
		end
	end)

	local releaseAt = delay + duration
	local released = false
	fx:onStep(function(_dt, elapsed)
		local t = elapsed - delay
		if t < 0 or #chains == 0 then
			return false
		end
		local erupt = clamp01(t / ERUPT_TIME)
		local head = 1 - (1 - erupt) ^ 2
		local broke = clamp01((elapsed - releaseAt) / BREAK_TIME)
		if broke > 0 and not released then
			released = true
			for _, chain in chains do
				for k, link in chain.links do
					chain.burst[k] = (link.Position - (chain.victim and chain.victim.Position or center)).Unit
						+ Vector3.new(0, 0.6, 0)
				end
				if sparks then
					local mid = chain.links[math.floor(LINKS / 2)]
					sparkHolder.Size = Vector3.new(1.5, 1.5, 6)
					sparkHolder.CFrame = mid.CFrame
					sparks:Emit(10)
				end
			end
			for _, bind in binds do
				Impact.play(bind.root.Position, Kit.GOLD_PALETTE, 0.8, false, { ring = false, dust = false })
			end
		end
		for _, chain in chains do
			local target = if chain.victim and chain.victim.Parent
				then chain.victim.Position + chain.offset
				else center + chain.offset
			local p0 = chain.start
			local p1 = (p0 + target) / 2 + Vector3.new(0, 4.5, 0) + chain.outward * 1.6
			local quiver = if erupt >= 1 and broke == 0
				then math.sin(elapsed * 38 + chain.start.X) * 0.12
				else 0
			for k, link in chain.links do
				local s = (k - 0.5) / LINKS
				if s > head then
					link.Transparency = 1
					continue
				end
				local pos, tangent = bezier(p0, p1, target, s)
				pos += Vector3.new(0, quiver * math.sin(s * math.pi), 0)
				local cf = CFrame.lookAt(pos, pos + tangent)
					* CFrame.Angles(0, 0, if k % 2 == 0 then math.pi / 2 else 0)
				if broke > 0 then
					local push = chain.burst[k] or Vector3.zero
					cf = CFrame.new(push * (broke * 4) + Vector3.new(0, -broke * broke * 3, 0))
						* cf
						* CFrame.Angles(broke * 4, broke * 3, 0)
				end
				link.CFrame = cf
				link.Transparency = broke
			end
		end
		for i, bind in binds do
			if bind.root.Parent then
				for r, ring in bind.rings do
					local lock = clamp01(t / 0.18)
					local y = if r == 1 then 0.2 else -1.3
					ring:setCFrame(
						CFrame.new(bind.root.Position + Vector3.new(0, y, 0))
							* CFrame.Angles(0, elapsed * (if r == 1 then 3 else -4) + i, 0)
					)
					ring:setScale((1.8 - 0.8 * (1 - (1 - lock) ^ 3)) * (1 + 0.6 * broke))
					ring:setTransparency(math.max(0.1 + 0.15 * math.sin(elapsed * 10), broke))
				end
			end
		end
		return broke >= 1
	end)
end

return Chains
