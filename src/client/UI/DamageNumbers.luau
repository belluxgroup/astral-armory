--!strict
-- Floating damage numbers: pop, rise and fade over 0.8 s. Color follows the element; crits are bigger.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxPalette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxPalette"))
local Theme = require(script.Parent.Theme)

local make = Theme.make

local LIFETIME = 0.8
local RISE = 4
local JITTER = 1.2

local rng = Random.new()

local DamageNumbers = {}

function DamageNumbers.spawn(position: Vector3, amount: number, crit: boolean, element: string?)
	local palette = VfxPalette.get(element or "none", false)

	-- An Attachment in Terrain is the cheapest world anchor for a BillboardGui.
	local anchor = make("Attachment", {
		WorldPosition = position
			+ Vector3.new(rng:NextNumber(-JITTER, JITTER), 1.5, rng:NextNumber(-JITTER, JITTER)),
		Parent = workspace.Terrain,
	})
	local billboard = make("BillboardGui", {
		Adornee = anchor,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 200,
		Size = UDim2.fromOffset(180, 64),
		Parent = anchor,
	})
	local rounded = math.floor(amount + 0.5)
	-- 0 means hex_aegis absorbed the whole hit.
	local text = if rounded <= 0
		then Theme.text("blocked")
		else tostring(rounded) .. (if crit then "!" else "")
	local label = Theme.label({
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.fonts.heavy,
		Text = text,
		TextColor3 = palette.glow,
		TextSize = if crit then 40 else 26,
		TextStrokeColor3 = Color3.fromHex("1A0F08"),
		TextStrokeTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = billboard,
	})
	local pop = make("UIScale", { Scale = if crit then 0.3 else 0.5, Parent = label })

	Theme.tween(pop, 0.16, { Scale = if crit then 1.15 else 1 }, Enum.EasingStyle.Back)
	if crit then
		Theme.tween(pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.16)
	end
	Theme.tween(billboard, LIFETIME, { StudsOffsetWorldSpace = Vector3.new(0, RISE, 0) })
	Theme.tween(label, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 }, nil, nil, LIFETIME - 0.35)

	Debris:AddItem(anchor, LIFETIME + 0.1)
end

return DamageNumbers
