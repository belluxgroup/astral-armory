--!strict
-- Part-built crimson lance (about 7.3 studs). Built in code, no meshes.
--
-- The model pivot points the lance along its LookVector: the Neon tip is at
-- -Z, the butt at +Z, so `model:PivotTo(CFrame.lookAt(from, to))` aims it.
-- Named parts the VFX reads: "Tip" (Neon spearhead), "Barb", "Band" and
-- "Butt" (Neon accents). Attachments on the Shaft (contract addendum item 5):
--   Shaft.TrailA, Shaft.TrailB  on opposite sides of the shaft, for trails
-- The VFX orbits them around the shaft axis to draw a helix.
-- All parts are unanchored, Massless and non-colliding, welded to Shaft.

local LanceModel = {}

LanceModel.CRIMSON = Color3.fromRGB(230, 28, 58)
LanceModel.LENGTH = 7.3
-- Distance of the trail attachments from the shaft axis.
LanceModel.TRAIL_RADIUS = 0.45

local SHAFT_COLOR = Color3.fromRGB(64, 12, 22)
local DARK_GOLD = Color3.fromRGB(150, 98, 52)

-- Rotates a part so its X axis (cylinder axis) points along model -Z.
local ALONG = CFrame.Angles(0, math.pi / 2, 0)

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
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

function LanceModel.build(): Model
	local model = Instance.new("Model")
	model.Name = "CrimsonLance"

	local shaft = makePart(
		model,
		"Shaft",
		Vector3.new(5.4, 0.2, 0.2),
		CFrame.new(0, 0, 0.3) * ALONG,
		SHAFT_COLOR,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)

	-- Leaf-shaped spearhead: an ellipsoid flattened on Y.
	local tip = makePart(
		model,
		"Tip",
		Vector3.new(0.5, 0.16, 2.0),
		CFrame.new(0, 0, -3.25),
		LanceModel.CRIMSON,
		Enum.Material.Neon
	)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = tip

	makePart(
		model,
		"Collar",
		Vector3.new(0.25, 0.36, 0.36),
		CFrame.new(0, 0, -2.3) * ALONG,
		DARK_GOLD,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	for _, side in { -1, 1 } do
		makePart(
			model,
			"Barb",
			Vector3.new(0.06, 0.12, 0.62),
			CFrame.new(side * 0.26, 0, -1.95) * CFrame.Angles(0, math.rad(side * -24), 0),
			LanceModel.CRIMSON,
			Enum.Material.Neon
		)
	end
	for _, z in { -0.9, 1.3 } do
		makePart(
			model,
			"Band",
			Vector3.new(0.07, 0.27, 0.27),
			CFrame.new(0, 0, z) * ALONG,
			LanceModel.CRIMSON,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
	end
	makePart(
		model,
		"Butt",
		Vector3.new(0.3, 0.3, 0.3),
		CFrame.new(0, 0, 3.05),
		LanceModel.CRIMSON,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)

	-- Shaft local space: X is the lance axis, so the attachments sit at ±Y.
	local a = Instance.new("Attachment")
	a.Name = "TrailA"
	a.Position = Vector3.new(0, LanceModel.TRAIL_RADIUS, 0)
	a.Parent = shaft
	local b = Instance.new("Attachment")
	b.Name = "TrailB"
	b.Position = Vector3.new(0, -LanceModel.TRAIL_RADIUS, 0)
	b.Parent = shaft

	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= shaft then
			local w = Instance.new("WeldConstraint")
			w.Part0 = shaft
			w.Part1 = child
			w.Parent = child
		end
	end
	model.PrimaryPart = shaft
	-- Make the model pivot the identity frame at build time (-Z forward).
	shaft.PivotOffset = shaft.CFrame:Inverse()
	return model
end

return LanceModel
