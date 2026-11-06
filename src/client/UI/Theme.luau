--!strict
-- Shared look and helpers for every screen: colors, fonts, instance builder, tweens, scaling, text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Strings =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Strings"))

local Theme = {}

Theme.colors = {
	panel = Color3.fromHex("120E1A"),
	panelRaised = Color3.fromHex("1F1830"),
	panelSunken = Color3.fromHex("0A0710"),
	backdrop = Color3.fromHex("06040A"),
	gold = Color3.fromHex("F2C14E"),
	goldDim = Color3.fromHex("8A6E2F"),
	hp = Color3.fromHex("D6455D"),
	energy = Color3.fromHex("4FA3FF"),
	xp = Color3.fromHex("9B6BFF"),
	text = Color3.fromHex("F4EEDF"),
	muted = Color3.fromHex("9A90AD"),
	danger = Color3.fromHex("FF6B6B"),
	might = Color3.fromHex("E0524F"),
	swift = Color3.fromHex("5BD08A"),
	insight = Color3.fromHex("5AA7FF"),
	core = Color3.fromHex("F2C14E"),
}

Theme.panelTransparency = 0.25

Theme.fonts = {
	bold = Font.fromName("Montserrat", Enum.FontWeight.Bold),
	heavy = Font.fromName("Montserrat", Enum.FontWeight.ExtraBold),
	regular = Font.fromName("Montserrat", Enum.FontWeight.Medium),
}

-- Instance builder: Parent is assigned last so the instance is fully configured before it replicates/renders.
function Theme.make(className: string, props: { [string]: any }?, children: { any }?): any
	local instance = (Instance.new :: any)(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local make = Theme.make

function Theme.corner(radius: number?): UICorner
	-- radius < 1 is a scale (0.5 makes a circle), otherwise pixels.
	local r = radius or 8
	return make("UICorner", { CornerRadius = if r < 1 then UDim.new(r, 0) else UDim.new(0, r) })
end

function Theme.stroke(color: Color3, thickness: number?, transparency: number?): UIStroke
	return make("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return make("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = u, PaddingBottom = u })
end

function Theme.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		FontFace = Theme.fonts.bold,
		TextColor3 = Theme.colors.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		defaults[key] = value
	end
	return make("TextLabel", defaults)
end

function Theme.button(props: { [string]: any }): TextButton
	local defaults: { [string]: any } = {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.colors.panelRaised,
		FontFace = Theme.fonts.bold,
		TextColor3 = Theme.colors.text,
		TextSize = 16,
		Text = "",
	}
	for key, value in props do
		defaults[key] = value
	end
	local button: TextButton = make("TextButton", defaults)
	-- Shared hover/press feedback.
	local base = button.BackgroundColor3
	local hover = base:Lerp(Color3.new(1, 1, 1), 0.12)
	button.MouseEnter:Connect(function()
		Theme.tween(button, 0.12, { BackgroundColor3 = hover })
	end)
	button.MouseLeave:Connect(function()
		Theme.tween(button, 0.12, { BackgroundColor3 = base })
	end)
	return button
end

-- A panel: dark translucent body with a faint gold edge.
function Theme.panel(props: { [string]: any }): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = Theme.panelTransparency,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	return make("Frame", defaults, { Theme.corner(10) :: Instance, Theme.stroke(Theme.colors.gold, 1, 0.7) })
end

function Theme.tween(
	instance: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delay: number?
): Tween
	local info = TweenInfo.new(
		seconds,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out,
		0,
		false,
		delay or 0
	)
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

-- Screen scaling: UIScale = clamp(viewport.Y / 900, 0.7, 1.2), optionally shrunk further so a panel of
-- the given design size still fits on screen.
type ScaleEntry = { scale: UIScale, width: number?, height: number? }
local scaleEntries: { ScaleEntry } = {}
local scaleListening = false

function Theme.screenScale(): number
	return math.clamp(workspace.CurrentCamera.ViewportSize.Y / 900, 0.7, 1.2)
end

-- The scale for a panel of this design size right now.
function Theme.fitScale(designWidth: number?, designHeight: number?): number
	local viewport = workspace.CurrentCamera.ViewportSize
	local s = Theme.screenScale()
	if designWidth then
		s = math.min(s, (viewport.X - 24) / designWidth)
	end
	if designHeight then
		s = math.min(s, (viewport.Y - 24) / designHeight)
	end
	return s
end

-- Adds a UIScale to a long-lived `object` that follows the screen size.
function Theme.autoScale(object: GuiObject, designWidth: number?, designHeight: number?): UIScale
	local scale: UIScale =
		make("UIScale", { Scale = Theme.fitScale(designWidth, designHeight), Parent = object })
	table.insert(scaleEntries, { scale = scale, width = designWidth, height = designHeight })
	if not scaleListening then
		scaleListening = true
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			for _, entry in scaleEntries do
				entry.scale.Scale = Theme.fitScale(entry.width, entry.height)
			end
		end)
	end
	return scale
end

-- All text comes from Config.Strings; a missing key shows as the key itself, so it is easy to spot.
function Theme.text(key: string): string
	return Strings[key] or key
end

-- Strings labels carry no numbers; the number goes after the label ("Cấp 5").
function Theme.textWith(key: string, value: number | string): string
	return Theme.text(key) .. " " .. tostring(value)
end

-- A short message that fades in near the bottom of `screen`, replacing any message already showing.
function Theme.toast(screen: Instance, message: string, color: Color3?)
	local existing = screen:FindFirstChild("Toast")
	if existing then
		existing:Destroy()
	end
	local toast: Frame = Theme.panel({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.1,
		ZIndex = 50,
		Parent = screen,
	})
	local label = Theme.label({
		Text = message,
		TextColor3 = color or Theme.colors.text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 51,
		Parent = toast,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = toast })
	local target = Theme.screenScale()
	local scale = make("UIScale", { Scale = target * 0.85, Parent = toast })
	Theme.tween(scale, 0.18, { Scale = target }, Enum.EasingStyle.Back)
	task.delay(1.8, function()
		if toast.Parent then
			Theme.tween(toast, 0.3, { BackgroundTransparency = 1 })
			Theme.tween(label, 0.3, { TextTransparency = 1 })
			local stroke = toast:FindFirstChildOfClass("UIStroke")
			if stroke then
				Theme.tween(stroke, 0.3, { Transparency = 1 })
			end
			task.delay(0.32, function()
				toast:Destroy()
			end)
		end
	end)
end

return Theme
