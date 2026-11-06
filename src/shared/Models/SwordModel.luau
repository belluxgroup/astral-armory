--!strict
-- Part-built sword (about 4.7 studs). Built in code, no meshes.
--
-- Layout, in model space (Handle at the origin, blade along +Y):
--   Pommel  y -0.6   Handle (grip) y 0   Guard y 0.55   Blade y 0.63 .. 3.9
-- Named parts the VFX reads: "Edge" and "TipEdge" (Neon rim), "Fuller" (Neon
-- rune line), "Gem" (Neon), "BladeCore" (metal). Attachments:
--   Handle.Grip          the grip point, aligned with R15 RightGripAttachment
--   BladeCore.TrailTop   near the tip    (contract addendum item 5)
--   BladeCore.TrailBottom near the guard (contract addendum item 5)
-- All parts are unanchored, Massless and non-colliding, welded to the
-- PrimaryPart with WeldConstraints.

local SwordModel = {}

SwordModel.EDGE_COLOR = Color3.fromRGB(255, 232, 170)
SwordModel.GEM_COLOR = Color3.fromRGB(255, 206, 102)

local GOLD = Color3.fromRGB(212, 168, 82)
local STEEL = Color3.fromRGB(214, 222, 236)
local LEATHER = Color3.fromRGB(46, 30, 40)

local BLADE_BOTTOM = 0.63
local BLADE_LENGTH = 3.1
local BLADE_WIDTH = 0.3
local EDGE_WIDTH = 0.4

local function makePart(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = material ~= Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function weldAll(model: Model, root: BasePart)
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = child
			w.Parent = child
		end
	end
end

local function attachment(parent: BasePart, name: string, worldPos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = parent.CFrame:ToObjectSpace(CFrame.new(worldPos))
	a.Parent = parent
	return a
end

-- Builds a new sword Model. With `bladeOnly`, the grip and pommel are left out
-- and the PrimaryPart is "BladeCore" (used for summoned blades in Mưa Kiếm).
function SwordModel.build(bladeOnly: boolean?): Model
	local model = Instance.new("Model")
	model.Name = if bladeOnly then "SummonedBlade" else "AstralSword"

	local bladeMid = BLADE_BOTTOM + BLADE_LENGTH / 2
	local tipY = BLADE_BOTTOM + BLADE_LENGTH
	local diamond = CFrame.Angles(0, 0, math.rad(45))

	local handle: Part? = nil
	if not bladeOnly then
		local h = makePart(
			model,
			"Handle",
			Vector3.new(0.26, 0.95, 0.26),
			CFrame.identity,
			LEATHER,
			Enum.Material.Fabric
		)
		handle = h
		local grip = Instance.new("Attachment")
		grip.Name = "Grip"
		grip.Parent = h
		makePart(
			model,
			"Pommel",
			Vector3.new(0.36, 0.36, 0.36),
			CFrame.new(0, -0.6, 0),
			GOLD,
			Enum.Material.Metal,
			Enum.PartType.Ball
		)
		makePart(
			model,
			"GuardTipL",
			Vector3.new(0.2, 0.3, 0.3),
			CFrame.new(-0.62, 0.64, 0) * CFrame.Angles(0, 0, math.rad(22)),
			GOLD,
			Enum.Material.Metal
		)
		makePart(
			model,
			"GuardTipR",
			Vector3.new(0.2, 0.3, 0.3),
			CFrame.new(0.62, 0.64, 0) * CFrame.Angles(0, 0, math.rad(-22)),
			GOLD,
			Enum.Material.Metal
		)
	end

	makePart(model, "Guard", Vector3.new(1.25, 0.16, 0.34), CFrame.new(0, 0.55, 0), GOLD, Enum.Material.Metal)
	makePart(
		model,
		"Gem",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(0, 0.55, -0.16),
		SwordModel.GEM_COLOR,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	local core = makePart(
		model,
		"BladeCore",
		Vector3.new(BLADE_WIDTH, BLADE_LENGTH, 0.07),
		CFrame.new(0, bladeMid, 0),
		STEEL,
		Enum.Material.Metal
	)
	core.Reflectance = 0.15
	makePart(
		model,
		"Edge",
		Vector3.new(EDGE_WIDTH, BLADE_LENGTH - 0.05, 0.035),
		CFrame.new(0, bladeMid, 0),
		SwordModel.EDGE_COLOR,
		Enum.Material.Neon
	)
	makePart(
		model,
		"Fuller",
		Vector3.new(0.06, BLADE_LENGTH * 0.75, 0.08),
		CFrame.new(0, BLADE_BOTTOM + BLADE_LENGTH * 0.42, 0),
		SwordModel.EDGE_COLOR,
		Enum.Material.Neon
	)
	local tipCore = BLADE_WIDTH / math.sqrt(2)
	makePart(
		model,
		"TipCore",
		Vector3.new(tipCore, tipCore, 0.07),
		CFrame.new(0, tipY, 0) * diamond,
		STEEL,
		Enum.Material.Metal
	)
	local tipEdge = EDGE_WIDTH / math.sqrt(2)
	makePart(
		model,
		"TipEdge",
		Vector3.new(tipEdge, tipEdge, 0.035),
		CFrame.new(0, tipY - 0.02, 0) * diamond,
		SwordModel.EDGE_COLOR,
		Enum.Material.Neon
	)

	attachment(core, "TrailTop", Vector3.new(0, tipY - 0.1, 0))
	attachment(core, "TrailBottom", Vector3.new(0, BLADE_BOTTOM + 0.15, 0))

	local root: BasePart = handle or core
	model.PrimaryPart = root
	weldAll(model, root)
	return model
end

-- Attaches a sword built by `build()` to a character's hand so the blade points
-- forward. Uses the hand's RightGripAttachment when present (R15), otherwise a
-- matching fixed offset. A RigidConstraint, not a Weld: on avatars with the
-- constraint-based joint rig a legacy Weld to the hand does not hold and the
-- sword falls out of the world. Returns the RigidConstraint.
function SwordModel.weld(sword: Model, hand: BasePart): RigidConstraint
	local handle = sword.PrimaryPart
	assert(handle, "SwordModel.weld: sword has no PrimaryPart")
	local grip = handle:FindFirstChild("Grip") :: Attachment
	local gripAtt = hand:FindFirstChild("RightGripAttachment")
	if not (gripAtt and gripAtt:IsA("Attachment")) then
		local att = Instance.new("Attachment")
		att.Name = "SwordGripAttachment"
		att.CFrame = CFrame.new(0, -0.25, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
		att.Parent = hand
		gripAtt = att
	end
	local att0 = gripAtt :: Attachment
	sword:PivotTo(att0.WorldCFrame * grip.CFrame:Inverse())
	local rigid = Instance.new("RigidConstraint")
	rigid.Name = "SwordWeld"
	rigid.Attachment0 = att0
	rigid.Attachment1 = grip
	rigid.Parent = handle
	sword.Parent = hand.Parent
	return rigid
end

return SwordModel
