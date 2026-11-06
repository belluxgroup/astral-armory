--!strict
-- Shared pieces for the Golden Tyrant effects: the palette (gold #F5C542, white-gold,
-- crimson #B3122E), payload readers, lookups on the boss model, and small geometry helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemiesConfig = require(Shared:WaitForChild("Config"):WaitForChild("Enemies"))
local TyrantArmor = require(Shared:WaitForChild("Models"):WaitForChild("TyrantArmor"))
local Common = require(script.Parent.Parent.Common)

type Palette = Common.Palette

local Kit = {}

Kit.Armor = TyrantArmor
Kit.Config = EnemiesConfig.eclipse_warden
Kit.NAMES = TyrantArmor.NAMES

Kit.GOLD = Color3.fromHex("F5C542")
Kit.WHITE_GOLD = Color3.fromHex("FFF3C8")
Kit.DEEP_GOLD = Color3.fromHex("C98A1E")
Kit.CRIMSON = Color3.fromHex("B3122E")
Kit.CRIMSON_DEEP = Color3.fromHex("5C0614")
Kit.CRIMSON_HOT = Color3.fromHex("FF4A5E")
Kit.SCORCH = Color3.fromHex("1C1210")

-- Impact palettes (Impact.play caches emitter rigs per palette table, so these stay fixed).
Kit.GOLD_PALETTE = {
	core = Kit.WHITE_GOLD,
	glow = Kit.GOLD,
	accent = Kit.DEEP_GOLD,
	brightness = 1.2,
} :: Palette
Kit.CRIMSON_PALETTE = {
	core = Color3.fromHex("FFD0D6"),
	glow = Kit.CRIMSON_HOT,
	accent = Kit.CRIMSON,
	brightness = 1.2,
} :: Palette
Kit.ROYAL_PALETTE = {
	core = Kit.WHITE_GOLD,
	glow = Kit.GOLD,
	accent = Kit.CRIMSON,
	brightness = 1.6,
} :: Palette

-- Camera shake and flash gate for the big boss moments.
Kit.SHAKE_RADIUS = 30
Kit.BIG_RADIUS = 60

export type Payload = { [string]: any }

---------------------------------------------------------------- payload readers

function Kit.model(evt: Payload): Model?
	local m = evt.model
	if typeof(m) == "Instance" and m:IsA("Model") then
		return m
	end
	return nil
end

function Kit.vec(evt: Payload, key: string): Vector3?
	local v = evt[key]
	return if typeof(v) == "Vector3" then v else nil
end

function Kit.num(evt: Payload, key: string, default: number): number
	local v = evt[key]
	return if type(v) == "number" and v == v then v else default
end

function Kit.vecs(evt: Payload, key: string): { Vector3 }
	local out: { Vector3 } = {}
	local list = evt[key]
	if type(list) == "table" then
		for _, v in list do
			if typeof(v) == "Vector3" then
				table.insert(out, v)
			end
		end
	end
	return out
end

-- A flat unit direction from the payload, or -Z.
function Kit.flatDir(v: Vector3?): Vector3
	if v then
		local f = Vector3.new(v.X, 0, v.Z)
		if f.Magnitude > 1e-3 then
			return f.Unit
		end
	end
	return Vector3.new(0, 0, -1)
end

---------------------------------------------------------------- boss model lookups

function Kit.part(model: Model?, name: string): BasePart?
	if not model then
		return nil
	end
	local p = model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

function Kit.armor(model: Model?): Instance?
	return model and model:FindFirstChild(TyrantArmor.FOLDER_NAME)
end

function Kit.sword(model: Model?): Model?
	local armor = Kit.armor(model)
	local sword = armor and armor:FindFirstChild(TyrantArmor.NAMES.sword)
	return if sword and sword:IsA("Model") then sword else nil
end

-- All armor parts with a given name.
function Kit.named(model: Model?, name: string): { BasePart }
	local out: { BasePart } = {}
	local armor = Kit.armor(model)
	if armor then
		for _, d in armor:GetDescendants() do
			if d:IsA("BasePart") and d.Name == name then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- The boss's scale relative to a default R15 rig (1.6 for the Golden Tyrant).
function Kit.scale(model: Model?): number
	local torso = Kit.part(model, "UpperTorso")
	return if torso then torso.Size.X / 2 else 1.6
end

-- The right-hand grip frame (blade along +Y), as the armor builds the sword.
function Kit.grip(model: Model?): CFrame?
	local hand = Kit.part(model, "RightHand")
	if not hand then
		return nil
	end
	local att = hand:FindFirstChild("RightGripAttachment")
	if att and att:IsA("Attachment") then
		return att.WorldCFrame
	end
	return hand.CFrame * CFrame.new(0, -0.25 * Kit.scale(model), 0) * CFrame.Angles(-math.pi / 2, 0, 0)
end

-- Hides (or shows) the boss's longsword on this client only.
function Kit.hideSword(model: Model?, hidden: boolean)
	local sword = Kit.sword(model)
	if sword then
		for _, d in sword:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

-- The live boss model, if one is in the workspace.
function Kit.findBoss(): Model?
	local enemies = workspace:FindFirstChild("Enemies")
	local boss = enemies and enemies:FindFirstChild(TyrantArmor.MODEL_NAME)
	return if boss and boss:IsA("Model") then boss else nil
end

---------------------------------------------------------------- geometry

-- A frame on the ground whose X axis is `dir` and Y axis is left, so Common.arc
-- draws in the ground plane (angle 0 = along `dir`).
function Kit.groundFrame(position: Vector3, dir: Vector3): CFrame
	local left = Vector3.new(0, 1, 0):Cross(dir).Unit
	return CFrame.fromMatrix(position, dir, left)
end

-- A thin glowing strip lying on the ground from `a` to `b` (Y lifted by `lift`).
function Kit.strip(part: BasePart, a: Vector3, b: Vector3, width: number, lift: number)
	local d = b - a
	local len = math.max(d.Magnitude, 0.05)
	local mid = (a + b) / 2 + Vector3.new(0, lift, 0)
	local look = if d.Magnitude > 1e-3 then mid + d else mid + Vector3.new(0, 0, -1)
	part.Size = Vector3.new(width, 0.06, len)
	part.CFrame = CFrame.lookAt(mid, look)
end

-- Two wedges that fill the triangle a, b, c: split at the foot of the height on the
-- longest edge into two right triangles, one wedge each (the wedge's right angle is
-- its bottom-back edge). Returns false when the triangle is degenerate.
function Kit.triangle(
	w1: WedgePart,
	w2: WedgePart,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number
): boolean
	-- Make ab the longest edge.
	local ab, ac, bc = (b - a).Magnitude, (c - a).Magnitude, (c - b).Magnitude
	if ac > ab and ac >= bc then
		a, b, c = a, c, b
	elseif bc > ab and bc > ac then
		a, b, c = b, c, a
	end
	local edge = b - a
	local len = edge.Magnitude
	if len < 1e-3 then
		return false
	end
	local dir = edge / len
	local t = (c - a):Dot(dir)
	local foot = a + dir * t
	local heightVec = c - foot
	local height = heightVec.Magnitude
	if height < 1e-3 then
		return false
	end
	local up = heightVec / height
	-- Wedge 1 covers a .. foot, wedge 2 covers foot .. b. A wedge's slope runs from its
	-- top-back edge down to its bottom-front edge: back = +Z, top = +Y.
	local function place(w: WedgePart, from: Vector3, to: Vector3, backAtFrom: boolean)
		local width = (to - from).Magnitude
		if width < 1e-3 then
			w.Transparency = 1
			return
		end
		local mid = (from + to) / 2 + up * (height / 2)
		local back = if backAtFrom then (from - to).Unit else (to - from).Unit
		w.Size = Vector3.new(thickness, height, width)
		w.CFrame = CFrame.fromMatrix(mid, up:Cross(back), up)
	end
	place(w1, a, foot, false)
	place(w2, foot, b, true)
	return true
end

return Kit
