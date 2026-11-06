--!strict
-- Touch layout: arranges the ContextActionService buttons in a fan around the jump button.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skills = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Skills"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Mobile = {}

Mobile.PASSIVES_ACTION = "AstralPassives"
Mobile.GEMS_ACTION = "AstralGems"

function Mobile.skillAction(skillId: string): string
	return "AstralCast_" .. skillId
end

type Placement = { action: string, ring: number, angle: number }

-- Angles are screen-space degrees: 180 is left of the jump button, 270 is straight above it.
local function placements(): { Placement }
	local list: { Placement } = { { action = Mobile.skillAction("basic"), ring = 1, angle = 225 } }
	local index = 0
	for _, skillId: string in Skills.order do
		if skillId ~= "basic" then
			table.insert(list, { action = Mobile.skillAction(skillId), ring = 2, angle = 180 + index * 22.5 })
			index += 1
		end
	end
	table.insert(list, { action = Mobile.PASSIVES_ACTION, ring = 3, angle = 205 })
	table.insert(list, { action = Mobile.GEMS_ACTION, ring = 3, angle = 245 })
	return list
end

local RING_SIZE = { 76, 58, 44 }
local GAP = 8

local function layout()
	local viewport = workspace.CurrentCamera.ViewportSize
	local shortSide = math.min(viewport.X, viewport.Y)
	local scale = math.clamp(shortSide / 500, 0.75, 1.3)

	-- Matches the default PlayerModule jump button: 70 px at (1,-95,1,-90) on small screens,
	-- 120 px at (1,-170,1,-210) otherwise.
	local small = shortSide <= 500
	local jumpRadius = if small then 35 else 60
	local jumpOffset = if small then Vector2.new(60, 55) else Vector2.new(110, 150)

	local sizes = { RING_SIZE[1] * scale, RING_SIZE[2] * scale, RING_SIZE[3] * scale }
	local gap = GAP * scale
	local distances = { jumpRadius + sizes[1] / 2 + gap }
	distances[2] = distances[1] + sizes[1] / 2 + sizes[2] / 2 + gap
	distances[3] = distances[2] + sizes[2] / 2 + sizes[3] / 2 + gap

	for _, place in placements() do
		local button = ContextActionService:GetButton(place.action)
		local frame = button and button.Parent
		local screen = button and button:FindFirstAncestorWhichIsA("LayerCollector")
		if button and frame and frame:IsA("GuiObject") and screen and screen:IsA("ScreenGui") then
			local size = sizes[place.ring]
			local corner = screen.AbsolutePosition + screen.AbsoluteSize
			local angle = math.rad(place.angle)
			local center = corner
				- jumpOffset
				+ Vector2.new(math.cos(angle), math.sin(angle)) * distances[place.ring]
			local topLeft = center - Vector2.new(size, size) / 2 - frame.AbsolutePosition
			button.Size = UDim2.fromOffset(size, size)
			button.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
		end
	end
end

function Mobile.start()
	for _, skillId: string in Skills.order do
		local title = if skillId == "basic" then Theme.text("skill_basic") else Skills[skillId].key
		ContextActionService:SetTitle(Mobile.skillAction(skillId), title)
	end
	ContextActionService:SetTitle(Mobile.PASSIVES_ACTION, "P")
	ContextActionService:SetTitle(Mobile.GEMS_ACTION, "G")

	-- Buttons are created asynchronously and rebuilt on respawn, so lay out again whenever that can happen.
	task.defer(layout)
	task.delay(1, layout)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.delay(0.5, layout)
	end)
end

return Mobile
