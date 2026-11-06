--!strict
-- Soulslike boss health bar (boss spec §5b): a wide bar centred at the bottom of the screen,
-- just above the HUD hotbar, with the boss name over its left end.
--
--   layers   a dark backing, a pale-gold "recent damage" layer that drains to the current
--            health 0.6 s after the last hit (over 0.5 s), and a crimson fill that updates
--            at once; a gold tick at 50% marks phase 2, where the fill turns a deeper,
--            pulsing crimson
--   damage   the damage dealt in the current flurry shows at the right end, then fades
--   data     the boss Humanoid's Health and MaxHealth (they replicate). The model comes
--            from any BossFx event that carries it, or Workspace.Enemies.GoldenTyrant
--   visible  fades in with the boss, out 2 s after `defeated` (or at once when the model
--            goes away); hidden while no boss is alive
-- On touch screens the bar moves to the top centre, clear of the touch buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemiesConfig = require(Shared:WaitForChild("Config"):WaitForChild("Enemies"))
local TyrantArmor = require(Shared:WaitForChild("Models"):WaitForChild("TyrantArmor"))
local Theme = require(script.Parent.Theme)

local make = Theme.make
local colors = Theme.colors

local BossBar = {}

local BOSS = EnemiesConfig.eclipse_warden
local PHASE2_AT = BOSS.phase2At

local BAR_HEIGHT = 11
local NAME_HEIGHT = 24
local GAP = 5
local DESIGN_HEIGHT = NAME_HEIGHT + GAP + BAR_HEIGHT
local MIN_WIDTH, MAX_WIDTH = 420, 900
local WIDTH_SHARE = 0.6
-- The HUD bottom block (Hud.luau): 14 px from the bottom, 158 design px tall, UIScale'd.
local HUD_BOTTOM, HUD_HEIGHT, HUD_GAP = 14, 158, 16
-- Room the top-left HUD corner needs on each side when the bar sits at the top (touch).
local TOP_SIDE_CLEARANCE = 180

local LAG_DELAY = 0.6
local LAG_DRAIN = 0.5
local DAMAGE_HOLD = 2.4
local FADE_IN = 0.45
local FADE_OUT = 0.6
local HIDE_AFTER_DEFEAT = 2

local CRIMSON = Color3.fromHex("B3122E")
local CRIMSON_DEEP = Color3.fromHex("7A0A1E")
local LAG_GOLD = Color3.fromHex("E8D59C")
local NAME_COLOR = Color3.fromHex("F1E6C8")

type State = {
	model: Model?,
	humanoid: Humanoid?,
	connections: { RBXScriptConnection },
	fill: number,
	lag: number,
	lastHitAt: number,
	drainFrom: number?,
	drainStart: number,
	damage: number,
	damageAt: number,
	lastHealth: number,
	shown: boolean,
	enraged: boolean,
	defeated: boolean,
	hideToken: number,
}

-- Combining marks (Vietnamese tone marks when the text is decomposed) stay with their letter.
local function isCombining(code: number): boolean
	return (code >= 0x0300 and code <= 0x036F) or (code >= 0x1DC0 and code <= 0x1DFF)
end

local function graphemes(text: string): { string }
	local out: { string } = {}
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		if isCombining(code) and #out > 0 then
			out[#out] ..= ch
		else
			table.insert(out, ch)
		end
	end
	return out
end

local function bossName(humanoid: Humanoid?): string
	local name = if humanoid then humanoid.DisplayName else ""
	-- Drop any " · level" suffix; the bar shows the name alone.
	local cut = string.find(name, " · ", 1, true)
	if cut then
		name = string.sub(name, 1, cut - 1)
	end
	return if name ~= "" then name else BOSS.displayName
end

function BossBar.start(playerGui: Instance, bossFx: RemoteEvent)
	local screen = make("ScreenGui", {
		Name = "BossBar",
		DisplayOrder = 2,
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = playerGui,
	})
	local root = make("CanvasGroup", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Size = UDim2.fromOffset(MIN_WIDTH, DESIGN_HEIGHT),
		Parent = screen,
	})
	local scale = make("UIScale", { Parent = root })

	-- Name (letter-spaced: one label per letter) and the damage counter above the bar.
	local nameRow = make("Frame", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(2, 0),
		Size = UDim2.new(0.75, 0, 0, NAME_HEIGHT),
		Parent = root,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 1.5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local shownName = ""
	local function setName(text: string)
		if text == shownName then
			return
		end
		shownName = text
		for _, child in nameRow:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, ch in graphemes(text) do
			if ch == " " then
				make("Frame", {
					LayoutOrder = i,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(6, NAME_HEIGHT),
					Parent = nameRow,
				})
			else
				Theme.label({
					LayoutOrder = i,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, NAME_HEIGHT),
					FontFace = Theme.fonts.bold,
					Text = ch,
					TextSize = 19,
					TextColor3 = NAME_COLOR,
					TextStrokeColor3 = Color3.new(0, 0, 0),
					TextStrokeTransparency = 0.55,
					TextYAlignment = Enum.TextYAlignment.Bottom,
					Parent = nameRow,
				})
			end
		end
	end

	local damageLabel = Theme.label({
		Name = "Damage",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 0),
		Size = UDim2.new(0.25, 0, 0, NAME_HEIGHT),
		FontFace = Theme.fonts.bold,
		Text = "",
		TextSize = 17,
		TextColor3 = LAG_GOLD,
		TextStrokeTransparency = 0.6,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextTransparency = 1,
		Parent = root,
	})

	-- The bar: backing, lag layer, fill, the 50% tick, a thin gold frame with end caps.
	local barY = NAME_HEIGHT + GAP
	local frame = make("Frame", {
		Name = "Bar",
		BackgroundColor3 = colors.panelSunken,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, barY),
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		Parent = root,
	})
	make("UIStroke", {
		Color = colors.gold,
		Thickness = 1,
		Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
	local inner = make("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		Parent = frame,
	})
	local lagBar = make("Frame", {
		Name = "Recent",
		BackgroundColor3 = LAG_GOLD,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = inner,
	})
	local fillBar = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = inner,
	})
	local fillGradient = make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(
			CRIMSON:Lerp(Color3.new(1, 1, 1), 0.22),
			CRIMSON:Lerp(Color3.new(0, 0, 0), 0.25)
		),
		Parent = fillBar,
	})
	-- A faint highlight line along the top of the fill.
	make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 3,
		Parent = fillBar,
	})
	make("Frame", {
		Name = "PhaseTick",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = colors.gold,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Position = UDim2.new(PHASE2_AT, 0, 0, barY + BAR_HEIGHT / 2),
		Size = UDim2.fromOffset(2, BAR_HEIGHT + 6),
		ZIndex = 4,
		Parent = root,
	})
	for _, x in { 0, 1 } do
		make("Frame", {
			Name = "Cap",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = colors.gold,
			BorderSizePixel = 0,
			Position = UDim2.new(x, 0, 0, barY + BAR_HEIGHT / 2),
			Rotation = 45,
			Size = UDim2.fromOffset(8, 8),
			ZIndex = 4,
			Parent = root,
		}, {
			make("UIStroke", { Color = colors.panelSunken, Thickness = 1, Transparency = 0.3 }),
		})
	end

	-- Layout: width from the screen, above the hotbar (or at the top on touch screens).
	local function layout()
		local viewport = workspace.CurrentCamera.ViewportSize
		local s = Theme.screenScale()
		scale.Scale = s
		local touch = UserInputService.TouchEnabled
		local widthPx = math.clamp(viewport.X * WIDTH_SHARE, MIN_WIDTH, MAX_WIDTH)
		widthPx = math.min(widthPx, viewport.X - 32)
		if touch then
			widthPx = math.min(widthPx, viewport.X - 2 * TOP_SIDE_CLEARANCE * s)
			root.AnchorPoint = Vector2.new(0.5, 0)
			root.Position = UDim2.new(0.5, 0, 0, 10)
		else
			root.AnchorPoint = Vector2.new(0.5, 1)
			root.Position = UDim2.new(0.5, 0, 1, -(HUD_BOTTOM + (HUD_HEIGHT + HUD_GAP) * s))
		end
		root.Size = UDim2.fromOffset(math.max(widthPx, 200) / s, DESIGN_HEIGHT)
	end
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)

	local state: State = {
		model = nil,
		humanoid = nil,
		connections = {},
		fill = 1,
		lag = 1,
		lastHitAt = 0,
		drainFrom = nil,
		drainStart = 0,
		damage = 0,
		damageAt = 0,
		lastHealth = 0,
		shown = false,
		enraged = false,
		defeated = false,
		hideToken = 0,
	}

	local function phase2(): boolean
		return state.enraged or state.fill <= PHASE2_AT
	end

	local function show()
		state.hideToken += 1
		if state.shown then
			return
		end
		state.shown = true
		screen.Enabled = true
		root.GroupTransparency = 1
		scale.Scale = Theme.screenScale() * 0.96
		Theme.tween(root, FADE_IN, { GroupTransparency = 0 }, Enum.EasingStyle.Sine)
		Theme.tween(scale, FADE_IN, { Scale = Theme.screenScale() }, Enum.EasingStyle.Quad)
	end

	local function hide(after: number)
		state.hideToken += 1
		local token = state.hideToken
		task.delay(after, function()
			if token ~= state.hideToken or not state.shown then
				return
			end
			state.shown = false
			local tween = Theme.tween(root, FADE_OUT, { GroupTransparency = 1 }, Enum.EasingStyle.Sine)
			tween.Completed:Once(function()
				if token == state.hideToken then
					screen.Enabled = false
				end
			end)
		end)
	end

	local function unbind()
		for _, c in state.connections do
			c:Disconnect()
		end
		table.clear(state.connections)
		state.model = nil
		state.humanoid = nil
	end

	local function readHealth(humanoid: Humanoid, hit: boolean)
		local max = math.max(humanoid.MaxHealth, 1)
		local health = math.clamp(humanoid.Health, 0, max)
		local fraction = health / max
		local now = os.clock()
		if hit and health < state.lastHealth then
			local dealt = state.lastHealth - health
			if now - state.damageAt > DAMAGE_HOLD then
				state.damage = 0
			end
			state.damage += dealt
			state.damageAt = now
			state.lastHitAt = now
			state.drainFrom = nil
			damageLabel.Text = tostring(math.floor(state.damage + 0.5))
			damageLabel.TextTransparency = 0
		end
		if fraction >= state.lag then
			-- Healed or reset: both layers jump.
			state.lag = fraction
			state.drainFrom = nil
		end
		state.fill = fraction
		state.lastHealth = health
		fillBar.Size = UDim2.fromScale(fraction, 1)
	end

	local restGradient = fillGradient.Color

	local function bind(model: Model)
		if state.model == model then
			if not state.defeated then
				show()
			end
			return
		end
		unbind()
		state.model = model
		state.enraged = false
		state.defeated = false
		fillGradient.Color = restGradient
		state.damage = 0
		damageLabel.TextTransparency = 1
		task.spawn(function()
			local humanoid = model:FindFirstChildOfClass("Humanoid")
				or model:WaitForChild("Humanoid", 5) :: Humanoid?
			if state.model ~= model or not humanoid or not humanoid:IsA("Humanoid") then
				return
			end
			state.humanoid = humanoid
			-- The bar replaces the overhead name and health bar on this client.
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			setName(bossName(humanoid))
			state.lastHealth = humanoid.Health
			state.lag = 1
			readHealth(humanoid, false)
			state.lag = state.fill
			lagBar.Size = UDim2.fromScale(state.lag, 1)
			table.insert(
				state.connections,
				humanoid.HealthChanged:Connect(function()
					readHealth(humanoid, true)
				end)
			)
			table.insert(
				state.connections,
				humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
					readHealth(humanoid, false)
				end)
			)
			table.insert(
				state.connections,
				humanoid:GetPropertyChangedSignal("DisplayName"):Connect(function()
					setName(bossName(humanoid))
				end)
			)
			table.insert(
				state.connections,
				humanoid.Died:Connect(function()
					state.defeated = true
					hide(HIDE_AFTER_DEFEAT)
				end)
			)
			if humanoid.Health > 0 then
				show()
			end
		end)
		table.insert(
			state.connections,
			model.AncestryChanged:Connect(function(_, parent)
				if parent == nil and state.model == model then
					unbind()
					hide(0)
				end
			end)
		)
	end

	-- Every frame while shown: drain the lag layer, fade the damage counter, pulse phase 2.
	RunService.RenderStepped:Connect(function()
		if not state.shown then
			return
		end
		local now = os.clock()
		if state.lag > state.fill then
			if now - state.lastHitAt >= LAG_DELAY then
				if not state.drainFrom then
					state.drainFrom = state.lag
					state.drainStart = now
				end
				local t = math.clamp((now - state.drainStart) / LAG_DRAIN, 0, 1)
				local eased = 1 - (1 - t) ^ 2
				local from = state.drainFrom :: number
				state.lag = from + (state.fill - from) * eased
				if t >= 1 then
					state.lag = state.fill
					state.drainFrom = nil
				end
			end
		end
		lagBar.Size = UDim2.fromScale(state.lag, 1)
		if state.damage > 0 then
			local idle = now - state.damageAt
			if idle > DAMAGE_HOLD then
				damageLabel.TextTransparency = math.clamp((idle - DAMAGE_HOLD) / 0.4, 0, 1)
				if idle > DAMAGE_HOLD + 0.4 then
					state.damage = 0
				end
			end
		end
		if phase2() then
			local pulse = 0.5 + 0.5 * math.sin(now * 4.2)
			local top = CRIMSON_DEEP:Lerp(CRIMSON, 0.35 + 0.35 * pulse)
			fillGradient.Color = ColorSequence.new(top, CRIMSON_DEEP:Lerp(Color3.new(0, 0, 0), 0.3))
		end
	end)

	local enemiesConn: RBXScriptConnection? = nil
	local function watchEnemies(folder: Instance)
		if enemiesConn then
			return
		end
		enemiesConn = folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") and child.Name == TyrantArmor.MODEL_NAME then
				bind(child)
			end
		end)
		local existing = folder:FindFirstChild(TyrantArmor.MODEL_NAME)
		if existing and existing:IsA("Model") then
			bind(existing)
		end
	end
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		watchEnemies(enemies)
	else
		local waiting: RBXScriptConnection? = nil
		waiting = workspace.ChildAdded:Connect(function(child)
			if child.Name == "Enemies" then
				if waiting then
					waiting:Disconnect()
				end
				watchEnemies(child)
			end
		end)
	end

	bossFx.OnClientEvent:Connect(function(evt: any)
		if type(evt) ~= "table" then
			return
		end
		local model = evt.model
		if evt.event == "defeated" then
			if state.model == nil or model == state.model then
				state.defeated = true
				hide(HIDE_AFTER_DEFEAT)
			end
			return
		end
		if typeof(model) == "Instance" and model:IsA("Model") and model.Parent then
			bind(model)
		end
		if evt.event == "enrage" then
			state.enraged = true
		end
	end)
end

return BossBar
