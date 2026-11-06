--!strict
-- Keyboard, mouse and touch input. Turns presses into server intents; the server validates everything.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Enemies = require(Shared:WaitForChild("Config"):WaitForChild("Enemies"))
local Skills = require(Shared:WaitForChild("Config"):WaitForChild("Skills"))

local Types = require(script.Parent:WaitForChild("UI"):WaitForChild("Types"))
local Mobile = require(script.Mobile)

type UIHandle = Types.UIHandle

local MIN_PRESS_GAP = 0.12 -- local spam guard between presses of the same skill
local AIM_RAY_LENGTH = 400
local TOUCH_FALLBACK_DISTANCE = 40

local player = Players.LocalPlayer

local Input = {}

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- PC aims at the mouse hit. Touch aims through the camera center, or 40 studs ahead when that hits nothing.
local function aimTarget(fromTouch: boolean): Vector3
	local camera = workspace.CurrentCamera
	local character = player.Character
	if not fromTouch then
		local mouse = player:GetMouse()
		mouse.TargetFilter = character
		return mouse.Hit.Position
	end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	aimParams.FilterDescendantsInstances = if character then { character } else {}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * AIM_RAY_LENGTH, aimParams)
	if hit then
		return hit.Position
	end

	local root = rootPart()
	local origin = if root then root.Position else camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = if root then root.CFrame.LookVector else Vector3.zAxis
	end
	return origin + flat.Unit * TOUCH_FALLBACK_DISTANCE
end

function Input.start(ui: UIHandle)
	local remotes = Net.client()

	local warden = Enemies.eclipse_warden
	local altarReadyAt = 0
	remotes.BossFx.OnClientEvent:Connect(function(evt)
		if evt.event == "defeated" then
			altarReadyAt = os.clock() + warden.altarCooldown
		end
	end)

	-- The server checks the same rules and ignores a bad summon; these checks only explain why.
	local function summonBoss()
		local state = ui.getState()
		if state and state.level < warden.summonLevel then
			ui.toast("bossNeedLevel")
			return
		end
		if os.clock() < altarReadyAt then
			ui.toast("bossCooldown")
			return
		end
		local arena = workspace:FindFirstChild("Arena")
		local altar = arena and arena:FindFirstChild("BossAltar")
		local altarPart = altar and altar:FindFirstChild("Altar")
		local root = rootPart()
		if
			root
			and altarPart
			and altarPart:IsA("BasePart")
			and (root.Position - altarPart.Position).Magnitude > warden.summonRange
		then
			ui.toast("bossTooFar")
			return
		end
		remotes.SummonBoss:FireServer()
	end

	ui.setActions({
		allocatePassive = function(nodeId: string)
			remotes.AllocatePassive:FireServer(nodeId)
		end,
		resetPassives = function()
			remotes.ResetPassives:FireServer()
		end,
		socketGem = function(skillId: string, slot: number, gemInstanceId: string?)
			remotes.SocketGem:FireServer(skillId, slot, gemInstanceId)
		end,
		summonBoss = summonBoss,
	})

	local lastPress: { [string]: number } = {}

	local function tryCast(skillId: string, fromTouch: boolean)
		local skill = Skills[skillId]
		local state = ui.getState()
		if state then
			if state.hp <= 0 then
				return
			end
			if skill.unlockLevel and state.level < skill.unlockLevel then
				return
			end
			-- basic costs stamina and is refused at 0, the same rule the server applies.
			if skillId == "basic" and state.stamina <= 0 then
				ui.flashStamina()
				return
			end
		end
		-- Client-side throttle only; the server is the authority on cooldowns.
		if ui.cooldownLeft(skillId) > 0 then
			return
		end
		local now = os.clock()
		if now - (lastPress[skillId] or -math.huge) < MIN_PRESS_GAP then
			return
		end
		if not rootPart() then
			return
		end
		lastPress[skillId] = now
		remotes.CastSkill:FireServer(skillId, aimTarget(fromTouch))
	end

	-- Skills: one action each. createTouchButton gives touch devices a button with no extra code.
	-- basic is bound to the gamepad trigger so it gets a touch button; mouse clicks are handled below.
	local actionToSkill: { [string]: string } = {}
	for _, skillId: string in Skills.order do
		local skill = Skills[skillId]
		local actionName = Mobile.skillAction(skillId)
		actionToSkill[actionName] = skillId
		local inputKey = if skill.key == "M1" then Enum.KeyCode.ButtonR2 else (Enum.KeyCode :: any)[skill.key]
		ContextActionService:BindAction(
			actionName,
			function(name: string, inputState: Enum.UserInputState, inputObject: InputObject)
				if inputState ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				tryCast(actionToSkill[name], inputObject.UserInputType == Enum.UserInputType.Touch)
				return Enum.ContextActionResult.Sink
			end,
			true,
			inputKey
		)
	end

	local function bindMenu(actionName: string, key: Enum.KeyCode, touchButton: boolean, fn: () -> ())
		ContextActionService:BindAction(actionName, function(_, inputState: Enum.UserInputState)
			if inputState == Enum.UserInputState.Begin then
				fn()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, touchButton, key)
	end
	bindMenu(Mobile.PASSIVES_ACTION, Enum.KeyCode.P, false, ui.togglePassives)
	Mobile.extraButton(Mobile.PASSIVES_ACTION, "P", ui.togglePassives)
	bindMenu(Mobile.GEMS_ACTION, Enum.KeyCode.G, true, ui.toggleGems)
	-- The altar prompt also summons; B is the keyboard shortcut, touch uses the HUD button.
	bindMenu("AstralSummonBoss", Enum.KeyCode.B, false, summonBoss)

	-- M1: clicks that a GUI already consumed (tree nodes, gem tiles, buttons) never cast.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryCast("basic", false)
		end
	end)

	if UserInputService.TouchEnabled then
		Mobile.start()
	end
end

return Input
