--!strict
-- Bạo Quân Hoàng Kim (Golden Tyrant) costume, built from parts on the server (boss spec §1).
--
-- `TyrantArmor.dress(rig)` decorates an R15 rig from Enemies.spawnRig: an obsidian
-- undersuit under gold plate with crimson accents, swept-back gold hair, crimson eye
-- slits, a circlet, a floating halo of 8 blades, a 3-panel crimson cape and a gold
-- longsword in the right hand. Every piece is sized from the body part it sits on, so
-- the costume fits before or after Model:ScaleTo. Every armor part is Massless with
-- CanCollide, CanTouch and CanQuery off, welded with WeldConstraint to its body part.
--
-- Two kinds of joint are Motor6Ds so clients can animate them locally (Motor6D
-- Transform does not replicate and needs no network): the cape hinges
-- ("CapeHinge1..3", on UpperTorso) and the halo anchor ("HaloSpin", on UpperTorso).
-- Names the client effects look for are in TyrantArmor.NAMES.

local TyrantArmor = {}

TyrantArmor.MODEL_NAME = "GoldenTyrant"
TyrantArmor.FOLDER_NAME = "TyrantArmor"
-- Parts in the whole boss model, rig included (spec §1).
TyrantArmor.PART_BUDGET = 140

TyrantArmor.COLORS = {
	gold = Color3.fromHex("E8B84A"),
	goldDeep = Color3.fromHex("A9792C"),
	obsidian = Color3.fromHex("1A1420"),
	crimson = Color3.fromHex("8E1B24"),
	crimsonInner = Color3.fromHex("450C14"),
	skin = Color3.fromHex("D9A27C"),
	eye = Color3.fromHex("FF2440"),
	eyeEnraged = Color3.fromHex("FF8A6A"),
	edge = Color3.fromHex("FFE6A0"),
}

TyrantArmor.NAMES = {
	eye = "Eye",
	capeTrim = "CapeTrim",
	capePanel = "CapePanel",
	capeHinge = "CapeHinge", -- followed by 1, 2, 3 (left, centre, right)
	haloSpin = "HaloSpin",
	haloEdge = "HaloEdge",
	sword = "TyrantSword",
	swordEdge = "SwordEdge",
	swordCore = "BladeCore",
}

local C = TyrantArmor.COLORS
local N = TyrantArmor.NAMES

local GOLD_REFLECT = 0.2
local CAPE_TILT = math.rad(-10)
local rad = math.rad

type Kind = "block" | "wedge" | "ball" | "cylinder"

type Builder = {
	folder: Instance,
	k: number, -- global scale: 1 on a default-size R15 rig
}

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function newPart(kind: Kind): BasePart
	if kind == "wedge" then
		return Instance.new("WedgePart")
	end
	local p = Instance.new("Part")
	if kind == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif kind == "cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	return p
end

-- One armor piece at `cf` (world space) welded to `body`.
local function piece(
	b: Builder,
	body: BasePart,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	kind: Kind?
): BasePart
	local p = newPart(kind or "block")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if material == Enum.Material.Metal then
		p.Reflectance = GOLD_REFLECT
	end
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = material ~= Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = b.folder
	weld(body, p)
	return p
end

local function gold(
	b: Builder,
	body: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	kind: Kind?
): BasePart
	return piece(b, body, name, size, body.CFrame * offset, C.gold, Enum.Material.Metal, kind)
end

local function deep(
	b: Builder,
	body: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	kind: Kind?
): BasePart
	return piece(b, body, name, size, body.CFrame * offset, C.goldDeep, Enum.Material.Metal, kind)
end

local function bodyPart(rig: Model, name: string): BasePart?
	local p = rig:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

---------------------------------------------------------------- torso

local function chest(b: Builder, torso: BasePart)
	local s, k = torso.Size, b.k
	local front = -s.Z / 2
	local lean = CFrame.Angles(rad(-6), 0, 0)
	gold(
		b,
		torso,
		"Breastplate",
		Vector3.new(s.X * 1.04, s.Y * 0.62, 0.22 * k),
		CFrame.new(0, s.Y * 0.12, front - 0.06 * k) * lean
	)
	for _, side in { -1, 1 } do
		gold(
			b,
			torso,
			"ChestPlate",
			Vector3.new(s.X * 0.5, s.Y * 0.4, 0.16 * k),
			CFrame.new(side * s.X * 0.25, s.Y * 0.2, front - 0.2 * k)
				* lean
				* CFrame.Angles(0, rad(-14 * side), 0)
		)
	end
	deep(
		b,
		torso,
		"ChestRidge",
		Vector3.new(0.14 * k, s.Y * 0.5, 0.14 * k),
		CFrame.new(0, s.Y * 0.08, front - 0.3 * k) * lean * CFrame.Angles(0, rad(45), 0)
	)
	piece(
		b,
		torso,
		"ChestGem",
		Vector3.new(0.34 * k, 0.34 * k, 0.12 * k),
		torso.CFrame * CFrame.new(0, s.Y * 0.32, front - 0.36 * k) * lean * CFrame.Angles(0, 0, rad(45)),
		C.crimson,
		Enum.Material.Glass
	)
	for i, y in { -0.24, -0.38 } do
		local band = Vector3.new(s.X * (0.9 - 0.06 * i), s.Y * 0.12, 0.16 * k)
		local offset = CFrame.new(0, s.Y * y, front - 0.05 * k)
		if i == 1 then
			deep(b, torso, "Abdomen", band, offset)
		else
			gold(b, torso, "Abdomen", band, offset)
		end
	end
	gold(
		b,
		torso,
		"Backplate",
		Vector3.new(s.X * 1.0, s.Y * 0.82, 0.18 * k),
		CFrame.new(0, s.Y * 0.04, s.Z / 2 + 0.05 * k)
	)
	gold(
		b,
		torso,
		"HighCollar",
		Vector3.new(s.X * 0.72, 0.5 * k, 0.14 * k),
		CFrame.new(0, s.Y / 2 + 0.14 * k, s.Z / 2 - 0.08 * k) * CFrame.Angles(rad(16), 0, 0)
	)
	deep(
		b,
		torso,
		"Gorget",
		Vector3.new(s.X * 0.56, 0.2 * k, s.Z * 0.78),
		CFrame.new(0, s.Y / 2 + 0.02 * k, -0.04 * k)
	)
	-- Cape clasps at the collarbones.
	for _, side in { -1, 1 } do
		deep(
			b,
			torso,
			"CapeClasp",
			Vector3.new(0.12 * k, 0.44 * k, 0.44 * k),
			CFrame.new(side * s.X * 0.4, s.Y * 0.43, front - 0.12 * k) * CFrame.Angles(0, rad(90), 0),
			"cylinder"
		)
	end
end

local function fauld(b: Builder, hips: BasePart)
	local s, k = hips.Size, b.k
	deep(b, hips, "Belt", Vector3.new(s.X * 1.07, math.max(s.Y * 0.9, 0.3 * k), s.Z * 1.08), CFrame.identity)
	piece(
		b,
		hips,
		"Buckle",
		Vector3.new(0.38 * k, 0.38 * k, 0.1 * k),
		hips.CFrame * CFrame.new(0, 0, -s.Z * 0.54 - 0.05 * k) * CFrame.Angles(0, 0, rad(45)),
		C.crimson,
		Enum.Material.Glass
	)
	piece(
		b,
		hips,
		"Tabard",
		Vector3.new(s.X * 0.4, 0.95 * k, 0.06 * k),
		hips.CFrame * CFrame.new(0, -s.Y / 2 - 0.46 * k, -s.Z / 2 - 0.14 * k) * CFrame.Angles(rad(6), 0, 0),
		C.crimson,
		Enum.Material.Fabric
	)
	for _, side in { -1, 1 } do
		gold(
			b,
			hips,
			"FauldPlate",
			Vector3.new(s.X * 0.36, 0.5 * k, 0.1 * k),
			CFrame.new(side * s.X * 0.32, -s.Y / 2 - 0.18 * k, -s.Z / 2 - 0.04 * k)
				* CFrame.Angles(rad(8), 0, 0)
		)
	end
	gold(
		b,
		hips,
		"FauldBack",
		Vector3.new(s.X * 0.82, 0.5 * k, 0.1 * k),
		CFrame.new(0, -s.Y / 2 - 0.18 * k, s.Z / 2 + 0.04 * k) * CFrame.Angles(rad(-8), 0, 0)
	)
end

---------------------------------------------------------------- arms and legs

-- side: +1 for the right limb (its +X points away from the body), -1 for the left.
local function upperArm(b: Builder, arm: BasePart, side: number)
	local s, k = arm.Size, b.k
	for i = 0, 2 do
		local plate = Vector3.new(s.X * (1.5 - 0.14 * i), 0.2 * k, s.Z * (1.38 - 0.1 * i))
		local offset = CFrame.new(side * (0.1 + 0.16 * i) * k, s.Y / 2 + (0.06 - 0.22 * i) * k, 0)
			* CFrame.Angles(0, 0, rad(-side * (16 + 9 * i)))
		if i == 1 then
			deep(b, arm, "Pauldron", plate, offset)
		else
			gold(b, arm, "Pauldron", plate, offset)
		end
	end
	piece(
		b,
		arm,
		"PauldronLining",
		Vector3.new(s.X * 1.3, 0.1 * k, s.Z * 1.28),
		arm.CFrame * CFrame.new(side * 0.5 * k, s.Y / 2 - 0.6 * k, 0) * CFrame.Angles(0, 0, rad(-side * 36)),
		C.crimson,
		Enum.Material.Fabric
	)
	-- A swept-back fin on the top plate: tall at the back, sloping down to the front.
	gold(
		b,
		arm,
		"PauldronFin",
		Vector3.new(0.12 * k, 0.55 * k, 0.75 * k),
		CFrame.new(side * 0.28 * k, s.Y / 2 + 0.4 * k, 0.06 * k) * CFrame.Angles(0, 0, rad(-side * 16)),
		"wedge"
	)
	gold(b, arm, "Rerebrace", Vector3.new(s.X * 1.08, s.Y * 0.42, s.Z * 1.08), CFrame.new(0, -s.Y * 0.14, 0))
end

local function lowerArm(b: Builder, arm: BasePart)
	local s, k = arm.Size, b.k
	gold(b, arm, "Vambrace", Vector3.new(s.X * 1.12, s.Y * 0.7, s.Z * 1.12), CFrame.new(0, -s.Y * 0.1, 0))
	deep(b, arm, "Cuff", Vector3.new(s.X * 1.24, 0.14 * k, s.Z * 1.24), CFrame.new(0, -s.Y * 0.44, 0))
	deep(b, arm, "Couter", Vector3.new(0.6, 0.6, 0.6) * k, CFrame.new(0, s.Y * 0.4, s.Z * 0.3), "ball")
end

local function hand(b: Builder, h: BasePart)
	local s, k = h.Size, b.k
	gold(b, h, "Gauntlet", Vector3.new(s.X * 1.12, s.Y * 1.3, s.Z * 1.12), CFrame.identity)
	deep(b, h, "Knuckles", Vector3.new(s.X * 1.0, 0.12 * k, 0.16 * k), CFrame.new(0, -s.Y * 0.3, -s.Z * 0.56))
end

local function upperLeg(b: Builder, leg: BasePart, side: number)
	local s, k = leg.Size, b.k
	gold(
		b,
		leg,
		"Tasset",
		Vector3.new(s.X * 1.14, s.Y * 0.55, 0.14 * k),
		CFrame.new(side * 0.05 * k, s.Y * 0.2, -s.Z / 2 - 0.07 * k) * CFrame.Angles(rad(6), 0, 0)
	)
	deep(
		b,
		leg,
		"TassetSide",
		Vector3.new(0.14 * k, s.Y * 0.6, s.Z * 1.1),
		CFrame.new(side * (s.X / 2 + 0.07 * k), s.Y * 0.18, 0) * CFrame.Angles(0, 0, rad(side * 8))
	)
end

local function lowerLeg(b: Builder, leg: BasePart)
	local s, k = leg.Size, b.k
	gold(b, leg, "Greave", Vector3.new(s.X * 1.12, s.Y * 0.78, s.Z * 1.12), CFrame.new(0, -s.Y * 0.08, 0))
	deep(
		b,
		leg,
		"Poleyn",
		Vector3.new(s.X * 0.85, 0.5 * k, 0.18 * k),
		CFrame.new(0, s.Y * 0.44, -s.Z / 2 - 0.1 * k) * CFrame.Angles(rad(-15), 0, 0)
	)
	deep(
		b,
		leg,
		"ShinRidge",
		Vector3.new(0.12 * k, s.Y * 0.6, 0.12 * k),
		CFrame.new(0, -s.Y * 0.1, -s.Z * 0.56 - 0.02 * k) * CFrame.Angles(0, rad(45), 0)
	)
end

local function foot(b: Builder, f: BasePart)
	local s, k = f.Size, b.k
	gold(b, f, "Sabaton", Vector3.new(s.X * 1.12, s.Y * 1.2, s.Z * 1.12), CFrame.identity)
	-- Pointed toe cap: the wedge slopes down to the front.
	gold(
		b,
		f,
		"SabatonToe",
		Vector3.new(s.X * 0.96, s.Y * 1.0, 0.5 * k),
		CFrame.new(0, 0, -s.Z / 2 - 0.22 * k),
		"wedge"
	)
end

---------------------------------------------------------------- head

local function head(b: Builder, h: BasePart)
	local s, k = h.Size, b.k
	-- Eyes: thin crimson slits that slant down toward the nose.
	for _, side in { -1, 1 } do
		piece(
			b,
			h,
			N.eye,
			Vector3.new(s.X * 0.22, 0.06 * k, 0.04 * k),
			h.CFrame
				* CFrame.new(side * s.X * 0.19, s.Y * 0.06, -s.Z / 2 - 0.01 * k)
				* CFrame.Angles(0, 0, rad(side * 12)),
			C.eye,
			Enum.Material.Neon
		)
	end
	-- Hair: swept-back spikes. Each wedge is tall at the back and tapers to the front, tipped up.
	local spikes = {
		{ x = 0, y = 0.52, z = -0.05, tilt = -22, yaw = 0, w = 0.3, h = 0.42, d = 1.05 },
		{ x = -0.28, y = 0.47, z = 0.02, tilt = -18, yaw = 10, w = 0.26, h = 0.38, d = 0.95 },
		{ x = 0.28, y = 0.47, z = 0.02, tilt = -18, yaw = -10, w = 0.26, h = 0.38, d = 0.95 },
		{ x = -0.5, y = 0.28, z = 0.12, tilt = -10, yaw = 22, w = 0.22, h = 0.34, d = 0.85 },
		{ x = 0.5, y = 0.28, z = 0.12, tilt = -10, yaw = -22, w = 0.22, h = 0.34, d = 0.85 },
		{ x = -0.2, y = 0.12, z = 0.48, tilt = 8, yaw = 12, w = 0.26, h = 0.4, d = 0.8 },
		{ x = 0.2, y = 0.12, z = 0.48, tilt = 8, yaw = -12, w = 0.26, h = 0.4, d = 0.8 },
	}
	for _, spike in spikes do
		piece(
			b,
			h,
			"Hair",
			Vector3.new(spike.w, spike.h, spike.d) * k,
			h.CFrame
				* CFrame.new(spike.x * s.X, spike.y * s.Y, spike.z * s.Z)
				* CFrame.Angles(0, rad(spike.yaw), 0)
				* CFrame.Angles(rad(spike.tilt), 0, 0),
			C.gold:Lerp(C.edge, 0.15),
			Enum.Material.Metal,
			"wedge"
		)
	end
	-- Circlet: a band at the brow, a diamond crest with a crimson stone, and swept wings.
	local bandY = s.Y * 0.2
	deep(
		b,
		h,
		"Circlet",
		Vector3.new(0.16 * k, s.X * 1.08, s.Z * 1.08),
		CFrame.new(0, bandY, 0) * CFrame.Angles(0, 0, rad(90)),
		"cylinder"
	)
	gold(
		b,
		h,
		"Crest",
		Vector3.new(0.42 * k, 0.42 * k, 0.08 * k),
		CFrame.new(0, bandY + 0.2 * k, -s.Z * 0.55) * CFrame.Angles(0, 0, rad(45))
	)
	piece(
		b,
		h,
		"CrestGem",
		Vector3.new(0.2, 0.2, 0.06) * k,
		h.CFrame * CFrame.new(0, bandY + 0.2 * k, -s.Z * 0.55 - 0.06 * k) * CFrame.Angles(0, 0, rad(45)),
		C.crimson,
		Enum.Material.Glass
	)
	for _, side in { -1, 1 } do
		gold(
			b,
			h,
			"CircletWing",
			Vector3.new(0.1 * k, 0.4 * k, 0.72 * k),
			CFrame.new(side * s.X * 0.55, bandY + 0.14 * k, 0.12 * k) * CFrame.Angles(rad(-26), 0, 0),
			"wedge"
		)
	end
end

-- A ring of 8 gold blades behind the head with a neon octagon edge, on an invisible
-- anchor jointed to UpperTorso by the "HaloSpin" Motor6D (clients spin it).
local function halo(b: Builder, torso: BasePart, h: BasePart)
	local k = b.k
	local headOffset = torso.CFrame:PointToObjectSpace(h.CFrame.Position)
	local c0 = CFrame.new(headOffset + Vector3.new(0, 0.15 * k, h.Size.Z * 0.5 + 0.55 * k))
	local anchor = Instance.new("Part")
	anchor.Name = "HaloAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2) * k
	anchor.Transparency = 1
	anchor.Anchored = false
	anchor.Massless = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.CFrame = torso.CFrame * c0
	anchor.Parent = b.folder
	local motor = Instance.new("Motor6D")
	motor.Name = N.haloSpin
	motor.Part0 = torso
	motor.Part1 = anchor
	motor.C0 = c0
	motor.C1 = CFrame.identity
	motor.Parent = torso

	local radius = 1.05 * k
	local bladeLength, bladeWidth = 0.78 * k, 0.32 * k
	for j = 0, 7 do
		local a = j * math.pi / 4
		local spoke = anchor.CFrame * CFrame.Angles(0, 0, a)
		-- Wedge axes: its X (thickness) along the halo normal, Y along the tangent,
		-- Z pointing inward, so the blade is broad at the ring and sharp at its tip.
		local cf = CFrame.fromMatrix(
			(spoke * CFrame.new(radius + bladeLength / 2, 0, 0)).Position,
			spoke.ZVector,
			spoke.YVector
		)
		piece(
			b,
			anchor,
			"HaloBlade",
			Vector3.new(0.06 * k, bladeWidth, bladeLength),
			cf,
			C.gold,
			Enum.Material.Metal,
			"wedge"
		)
		local mid = anchor.CFrame * CFrame.Angles(0, 0, a + math.pi / 8)
		local chord = 2 * radius * math.sin(math.pi / 8)
		piece(
			b,
			anchor,
			N.haloEdge,
			Vector3.new(0.08 * k, chord * 1.04, 0.08 * k),
			mid * CFrame.new(radius * math.cos(math.pi / 8), 0, 0),
			C.edge,
			Enum.Material.Neon
		)
	end
end

---------------------------------------------------------------- cape

-- Three crimson panels hinged at the back of the shoulders, each with a dark inner layer
-- (facing the body) and a gold trim along the hem.
local function cape(b: Builder, torso: BasePart)
	local s, k = torso.Size, b.k
	local panels = {
		{ x = -0.62, yaw = 9, length = 3.3 },
		{ x = 0, yaw = 0, length = 3.6 },
		{ x = 0.62, yaw = -9, length = 3.3 },
	}
	for i, spec in panels do
		local width, length, thick = 0.7 * k, spec.length * k, 0.07 * k
		-- The hinge tilts the panel a little back so it hangs clear of the legs.
		local c0 = CFrame.new(spec.x * k, s.Y / 2 - 0.06 * k, s.Z / 2 + 0.16 * k)
			* CFrame.Angles(0, rad(spec.yaw), 0)
			* CFrame.Angles(CAPE_TILT, 0, 0)
		local c1 = CFrame.new(0, length / 2, 0)
		local rest = torso.CFrame * c0 * c1:Inverse()
		local panel = Instance.new("Part")
		panel.Name = N.capePanel
		panel.Size = Vector3.new(width, length, thick)
		panel.CFrame = rest
		panel.Color = C.crimson
		panel.Material = Enum.Material.Fabric
		panel.Anchored = false
		panel.Massless = true
		panel.CanCollide = false
		panel.CanTouch = false
		panel.CanQuery = false
		panel.TopSurface = Enum.SurfaceType.Smooth
		panel.BottomSurface = Enum.SurfaceType.Smooth
		panel.Parent = b.folder
		local motor = Instance.new("Motor6D")
		motor.Name = N.capeHinge .. i
		motor.Part0 = torso
		motor.Part1 = panel
		motor.C0 = c0
		motor.C1 = c1
		motor.Parent = torso

		piece(
			b,
			panel,
			"CapeInner",
			Vector3.new(width * 0.96, length * 0.98, thick * 0.6),
			rest * CFrame.new(0, 0.01 * k, -thick * 0.7),
			C.crimsonInner,
			Enum.Material.Fabric
		)
		piece(
			b,
			panel,
			N.capeTrim,
			Vector3.new(width * 1.02, 0.14 * k, thick * 1.6),
			rest * CFrame.new(0, -length / 2 + 0.07 * k, 0),
			C.gold,
			Enum.Material.Metal
		)
	end
end

---------------------------------------------------------------- sword

-- A gold longsword. Model space: Handle (grip) at the origin, blade along +Y. The blade
-- edge and tip edge are Neon ("SwordEdge"); BladeCore carries TrailTop and TrailBottom.
local function sword(b: Builder, rightHand: BasePart)
	local k = b.k
	local model = Instance.new("Model")
	model.Name = N.sword
	model.Parent = b.folder

	local gripAtt = rightHand:FindFirstChild("RightGripAttachment")
	local gripWorld = if gripAtt and gripAtt:IsA("Attachment")
		then rightHand.CFrame * gripAtt.CFrame
		else rightHand.CFrame * CFrame.new(0, -0.25 * k, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

	local swordBuilder: Builder = { folder = model, k = k }

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.28, 1.15, 0.28) * k
	handle.CFrame = gripWorld
	handle.Color = C.obsidian
	handle.Material = Enum.Material.Fabric
	handle.Anchored = false
	handle.Massless = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Parent = model
	weld(rightHand, handle)
	model.PrimaryPart = handle

	local function blade(
		name: string,
		size: Vector3,
		offset: CFrame,
		color: Color3,
		material: Enum.Material,
		kind: Kind?
	)
		local cf = gripWorld * CFrame.new(offset.Position * k) * offset.Rotation
		return piece(swordBuilder, handle, name, size * k, cf, color, material, kind)
	end

	local bottom, length = 0.72, 4.6
	local tipY = bottom + length
	local diamond = CFrame.Angles(0, 0, rad(45))
	blade(
		"Pommel",
		Vector3.new(0.42, 0.42, 0.42),
		CFrame.new(0, -0.72, 0),
		C.gold,
		Enum.Material.Metal,
		"ball"
	)
	blade("Guard", Vector3.new(1.5, 0.18, 0.36), CFrame.new(0, 0.63, 0), C.gold, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		blade(
			"GuardWing",
			Vector3.new(0.18, 0.55, 0.3),
			CFrame.new(side * 0.8, 0.8, 0) * CFrame.Angles(0, 0, rad(-side * 32)),
			C.goldDeep,
			Enum.Material.Metal
		)
	end
	blade(
		"GuardGem",
		Vector3.new(0.24, 0.24, 0.24),
		CFrame.new(0, 0.63, -0.18),
		C.crimson,
		Enum.Material.Glass,
		"ball"
	)
	local core = blade(
		N.swordCore,
		Vector3.new(0.36, length, 0.09),
		CFrame.new(0, bottom + length / 2, 0),
		C.gold,
		Enum.Material.Metal
	)
	blade(
		N.swordEdge,
		Vector3.new(0.5, length - 0.06, 0.04),
		CFrame.new(0, bottom + length / 2, 0),
		C.edge,
		Enum.Material.Neon
	)
	blade(
		"Fuller",
		Vector3.new(0.08, length * 0.68, 0.11),
		CFrame.new(0, bottom + length * 0.38, 0),
		C.crimson,
		Enum.Material.Glass
	)
	local tipCore = 0.36 / math.sqrt(2)
	blade(
		"TipCore",
		Vector3.new(tipCore, tipCore, 0.09),
		CFrame.new(0, tipY, 0) * diamond,
		C.gold,
		Enum.Material.Metal
	)
	local tipEdge = 0.5 / math.sqrt(2)
	blade(
		N.swordEdge,
		Vector3.new(tipEdge, tipEdge, 0.04),
		CFrame.new(0, tipY - 0.03, 0) * diamond,
		C.edge,
		Enum.Material.Neon
	)

	local trailPoints: { [string]: number } = { TrailTop = tipY - 0.15, TrailBottom = bottom + 0.2 }
	for name, y in trailPoints do
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = core.CFrame:ToObjectSpace(gripWorld * CFrame.new(0, y * k, 0))
		a.Parent = core
	end
end

---------------------------------------------------------------- dress

-- Recolors the rig (warm skin, obsidian undersuit) and builds the whole costume on it.
-- Returns the folder that holds the armor. Safe to call twice: the second call is a no-op.
function TyrantArmor.dress(rig: Model): Folder
	local existing = rig:FindFirstChild(TyrantArmor.FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	rig.Name = TyrantArmor.MODEL_NAME
	local torso = bodyPart(rig, "UpperTorso")
	local folder = Instance.new("Folder")
	folder.Name = TyrantArmor.FOLDER_NAME
	local b: Builder = { folder = folder, k = if torso then torso.Size.X / 2 else 1 }

	-- Eyes from the generic rig are replaced by the costume's own.
	for _, child in rig:GetChildren() do
		if child:IsA("BasePart") and child.Name == N.eye then
			child:Destroy()
		end
	end
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			if d.Name == "Head" then
				d.Color = C.skin
				d.Material = Enum.Material.SmoothPlastic
			else
				d.Color = C.obsidian
				d.Material = Enum.Material.Fabric
			end
		end
	end

	if torso then
		chest(b, torso)
		cape(b, torso)
	end
	local hips = bodyPart(rig, "LowerTorso")
	if hips then
		fauld(b, hips)
	end
	for _, side in { -1, 1 } do
		local prefix = if side > 0 then "Right" else "Left"
		local ua = bodyPart(rig, prefix .. "UpperArm")
		if ua then
			upperArm(b, ua, side)
		end
		local la = bodyPart(rig, prefix .. "LowerArm")
		if la then
			lowerArm(b, la)
		end
		local hd = bodyPart(rig, prefix .. "Hand")
		if hd then
			hand(b, hd)
		end
		local ul = bodyPart(rig, prefix .. "UpperLeg")
		if ul then
			upperLeg(b, ul, side)
		end
		local ll = bodyPart(rig, prefix .. "LowerLeg")
		if ll then
			lowerLeg(b, ll)
		end
		local ft = bodyPart(rig, prefix .. "Foot")
		if ft then
			foot(b, ft)
		end
	end
	local h = bodyPart(rig, "Head")
	if h then
		head(b, h)
		if torso then
			halo(b, torso, h)
		end
	end
	local rightHand = bodyPart(rig, "RightHand")
	if rightHand then
		sword(b, rightHand)
	end
	folder.Parent = rig
	return folder
end

return TyrantArmor
