--!strict
-- Passive tree screen: pan / zoom canvas of Config.Passives, hover tooltips, click to allocate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Passives = require(Shared:WaitForChild("Config"):WaitForChild("Passives"))
local PassiveTree = require(Shared:WaitForChild("Logic"):WaitForChild("PassiveTree"))
local Theme = require(script.Parent.Theme)
local Types = require(script.Parent.Types)

type PlayerState = Types.PlayerState
type Actions = Types.Actions
type Node = Passives.Node

local make = Theme.make
local colors = Theme.colors

local NODE_SIZE: { [string]: number } = { start = 24, small = 18, notable = 30, keystone = 44 }
local ZOOM_MIN, ZOOM_MAX = 0.5, 1.6
local HEADER_WIDTH, HEADER_HEIGHT = 780, 64
local TOOLTIP_WIDTH = 290
local RING_RADII = { 200, 400, 600 }

export type Screen = {
	setOpen: (open: boolean) -> (),
	isOpen: () -> boolean,
	update: (state: PlayerState) -> (),
}

type Status = "allocated" | "available" | "reachable" | "locked"

type NodeView = {
	id: string,
	node: Node,
	button: TextButton,
	stroke: UIStroke,
	ring: UIStroke?,
	status: Status?,
	pulse: Tween?,
}

type LinkView = { a: Node, b: Node, frame: Frame, color: Color3, thickness: number, lit: number? }

local function regionColor(region: string): Color3
	return (colors :: any)[region] or colors.gold
end

-- Vietnamese decimals use a comma: 0.5 -> "0,5".
local function number(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return tostring(math.floor(rounded))
	end
	return (string.gsub(string.format("%.1f", rounded), "%.", ","))
end

local PERCENT_ADD_STATS = { critChance = true, critMul = true }

local function modText(mod: Passives.Mod): string
	local sign = if mod.value >= 0 then "+" else "-"
	local magnitude = math.abs(mod.value)
	local name = Theme.text("stat_" .. mod.stat)
	if mod.op == "mul" or PERCENT_ADD_STATS[mod.stat] then
		return `{sign}{number(magnitude * 100)}% {name}`
	end
	return `{sign}{number(magnitude)} {name}`
end

local function nodeBody(node: Node): string
	local lines = {}
	for _, mod in node.mods do
		table.insert(lines, modText(mod))
	end
	if node.keystone then
		table.insert(lines, Theme.text("keystoneDesc_" .. node.keystone))
	end
	return table.concat(lines, "\n")
end

local START_ONLY: { [string]: true } = { [Passives.startId] = true }

-- Tree bounds, for fitting the view and limiting pan.
local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
for _, node in Passives.nodes do
	minX, maxX = math.min(minX, node.x), math.max(maxX, node.x)
	minY, maxY = math.min(minY, node.y), math.max(maxY, node.y)
end

local Screen = {}

function Screen.new(parent: Instance, actions: Actions): Screen
	local state: PlayerState? = nil
	local open = false
	local fitted = false
	local zoom = 1
	local pan = Vector2.zero
	local openToken = 0

	local gui = make("ScreenGui", {
		Name = "AstralPassives",
		DisplayOrder = 10,
		Enabled = false,
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})

	-- The backdrop reaches up under the top bar inset so the whole screen darkens.
	local backdrop = make("Frame", {
		BackgroundColor3 = colors.backdrop,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, -80),
		Size = UDim2.new(1, 0, 1, 80),
		Parent = gui,
	}, {
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromHex("140F22"), Color3.fromHex("06040A")),
		}),
	})

	local canvas = make("TextButton", {
		Name = "Canvas",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Parent = gui,
	})
	local world =
		make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Parent = canvas })
	local function layer(z: number): Frame
		return make(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z, Parent = world }
		)
	end
	local decor = layer(1)
	local linkLayer = layer(2)
	local nodeLayer = layer(3)

	-- Animated factor applied on open, so the tree eases in.
	local openScale = make("NumberValue", { Value = 1 })

	-- Decoration: faint orbit rings and region names past each keystone.
	local rings: { { frame: Frame, radius: number } } = {}
	for _, radius in RING_RADII do
		local frame = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Parent = decor,
		}, { Theme.corner(0.5) :: Instance, Theme.stroke(colors.muted, 1, 0.88) })
		table.insert(rings, { frame = frame, radius = radius })
	end
	local regionLabels: { { label: TextLabel, x: number, y: number } } = {}
	for _, node in Passives.nodes do
		if node.kind == "keystone" then
			local label = Theme.label({
				AnchorPoint = Vector2.new(0.5, 0.5),
				FontFace = Theme.fonts.heavy,
				Size = UDim2.fromOffset(240, 30),
				Text = Theme.text("region_" .. node.region),
				TextColor3 = regionColor(node.region),
				TextTransparency = 0.35,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = decor,
			})
			table.insert(regionLabels, { label = label, x = node.x * 1.16, y = node.y * 1.16 + 6 })
		end
	end

	-- Links, one per undirected pair.
	local links: { LinkView } = {}
	for id, node in Passives.nodes do
		for _, otherId in node.links do
			local other = Passives.nodes[otherId]
			if other and id < otherId then
				local color = regionColor(if node.region == "core" then other.region else node.region)
				local frame = make("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = colors.muted,
					BackgroundTransparency = 0.75,
					BorderSizePixel = 0,
					Parent = linkLayer,
				})
				table.insert(links, { a = node, b = other, frame = frame, color = color, thickness = 2 })
			end
		end
	end

	-- Header -------------------------------------------------------------------------------------------
	local header = Theme.panel({
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(HEADER_WIDTH, HEADER_HEIGHT),
		BackgroundTransparency = 0.15,
		ZIndex = 20,
		Parent = gui,
	})
	Theme.autoScale(header, HEADER_WIDTH + 20)
	local left = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.fromScale(0.6, 1),
		ZIndex = 21,
		Parent = header,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 18),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	Theme.label({
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Theme.fonts.heavy,
		Size = UDim2.fromOffset(0, 30),
		Text = Theme.text("passives"),
		TextColor3 = colors.gold,
		TextSize = 22,
		ZIndex = 22,
		Parent = left,
	})
	local pointsLabel = Theme.label({
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		Text = "",
		TextSize = 17,
		ZIndex = 22,
		Parent = left,
	})

	local right = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromScale(0.4, 1),
		ZIndex = 21,
		Parent = header,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 10),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local function headerButton(text: string, order: number, accent: Color3): TextButton
		local button = Theme.button({
			LayoutOrder = order,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			Text = text,
			TextSize = 15,
			ZIndex = 22,
			Parent = right,
		})
		Theme.corner(8).Parent = button
		Theme.stroke(accent, 1.5, 0.35).Parent = button
		make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = button })
		return button
	end
	local resetButton = headerButton(Theme.text("reset"), 1, colors.hp)
	local closeButton = headerButton(Theme.text("close"), 2, colors.gold)

	local hint = Theme.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(600, 20),
		Text = Theme.text("treeHint"),
		TextColor3 = colors.muted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 20,
		Parent = gui,
	})
	Theme.autoScale(hint, 620)

	-- Tooltip ------------------------------------------------------------------------------------------
	local tooltip = Theme.panel({
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.05,
		Size = UDim2.fromOffset(TOOLTIP_WIDTH, 0),
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	})
	Theme.padding(12).Parent = tooltip
	make(
		"UIListLayout",
		{ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tooltip }
	)
	local tooltipScale = Theme.autoScale(tooltip)
	local function tooltipLine(order: number, size: number, color: Color3, font: Font): TextLabel
		return Theme.label({
			LayoutOrder = order,
			AutomaticSize = Enum.AutomaticSize.Y,
			FontFace = font,
			Size = UDim2.fromScale(1, 0),
			Text = "",
			TextColor3 = color,
			TextSize = size,
			TextWrapped = true,
			ZIndex = 31,
			Parent = tooltip,
		})
	end
	local tipName = tooltipLine(1, 18, colors.text, Theme.fonts.heavy)
	local tipKind = tooltipLine(2, 13, colors.muted, Theme.fonts.regular)
	local tipBody = tooltipLine(3, 15, colors.text, Theme.fonts.bold)
	local tipStatus = tooltipLine(4, 13, colors.gold, Theme.fonts.regular)

	-- Nodes --------------------------------------------------------------------------------------------
	local views: { [string]: NodeView } = {}
	local tooltipId: string? = nil
	local touchSelected: string? = nil

	local function effectiveScale(): number
		return zoom * Theme.screenScale() * openScale.Value
	end

	local function placeTooltip()
		local id = tooltipId
		if not id then
			return
		end
		local button = views[id].button
		local center = button.AbsolutePosition + button.AbsoluteSize / 2
		local screen = gui.AbsoluteSize
		local s = tooltipScale.Scale
		local gap = button.AbsoluteSize.X / 2 + 12
		local height = tooltip.AbsoluteSize.Y
		local y = math.clamp(center.Y, height / 2 + 8, math.max(height / 2 + 8, screen.Y - height / 2 - 8))
		if center.X + gap + TOOLTIP_WIDTH * s > screen.X - 8 then
			tooltip.AnchorPoint = Vector2.new(1, 0.5)
			tooltip.Position = UDim2.fromOffset(center.X - gap, y)
		else
			tooltip.AnchorPoint = Vector2.new(0, 0.5)
			tooltip.Position = UDim2.fromOffset(center.X + gap, y)
		end
	end

	local function statusLine(id: string, status: Status?): (string, Color3)
		if status == "allocated" then
			return Theme.text("learned"), regionColor(views[id].node.region)
		end
		if status == "available" then
			return Theme.text(if touchSelected == id then "tapAgain" else "allocateHint"), colors.gold
		end
		local s = state
		local _, reason =
			PassiveTree.canAllocate(if s then s.allocated else START_ONLY, id, if s then s.points else 0)
		return Theme.text("reason_" .. (reason or "unknown")), colors.danger
	end

	local function showTooltip(id: string)
		local view = views[id]
		tooltipId = id
		tipName.Text = view.node.name
		tipName.TextColor3 = regionColor(view.node.region)
		tipKind.Text = Theme.text("kind_" .. view.node.kind)
		local body = nodeBody(view.node)
		tipBody.Text = body
		tipBody.Visible = body ~= ""
		local text, color = statusLine(id, view.status)
		tipStatus.Text = text
		tipStatus.TextColor3 = color
		tooltip.Visible = true
		placeTooltip()
		-- AutomaticSize resolves next frame; place again once the height is known.
		task.defer(placeTooltip)
	end

	local function hideTooltip()
		tooltipId = nil
		touchSelected = nil
		tooltip.Visible = false
	end

	local function layout()
		local e = effectiveScale()
		local sizeScale = math.clamp(e, 0.75, 1.4)
		world.Position = UDim2.new(0.5, pan.X, 0.5, pan.Y)
		for _, view in views do
			local size = NODE_SIZE[view.node.kind] * sizeScale
			view.button.Position = UDim2.fromOffset(view.node.x * e, view.node.y * e)
			view.button.Size = UDim2.fromOffset(size, size)
		end
		for _, link in links do
			local ax, ay, bx, by = link.a.x * e, link.a.y * e, link.b.x * e, link.b.y * e
			local dx, dy = bx - ax, by - ay
			link.frame.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
			link.frame.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), link.thickness)
			link.frame.Rotation = math.deg(math.atan2(dy, dx))
		end
		for _, ring in rings do
			ring.frame.Size = UDim2.fromOffset(ring.radius * 2 * e, ring.radius * 2 * e)
		end
		for _, region in regionLabels do
			region.label.Position = UDim2.fromOffset(region.x * e, region.y * e)
			region.label.TextSize = 20 * sizeScale
		end
		placeTooltip()
	end
	openScale.Changed:Connect(layout)

	local function clampPan()
		-- Keep the screen center over the tree.
		local e = effectiveScale()
		pan = Vector2.new(math.clamp(pan.X, -maxX * e, -minX * e), math.clamp(pan.Y, -maxY * e, -minY * e))
	end

	local function zoomAt(newZoom: number, point: Vector2)
		local before = effectiveScale()
		local center = canvas.AbsolutePosition + canvas.AbsoluteSize / 2
		local offset = point - center
		local worldPoint = (offset - pan) / before
		zoom = math.clamp(newZoom, ZOOM_MIN, ZOOM_MAX)
		pan = offset - worldPoint * effectiveScale()
		clampPan()
		layout()
	end

	local function fit()
		local s = Theme.screenScale()
		local available = workspace.CurrentCamera.ViewportSize - Vector2.new(48, HEADER_HEIGHT * s + 120)
		local e = math.min(available.X / (maxX - minX), available.Y / (maxY - minY))
		zoom = math.clamp(e / s, ZOOM_MIN, ZOOM_MAX)
		local eff = zoom * s
		pan = Vector2.new(-(minX + maxX) / 2 * eff, -(minY + maxY) / 2 * eff + HEADER_HEIGHT * s / 2)
		clampPan()
	end

	local function setStatus(view: NodeView, status: Status)
		if view.status == status then
			return
		end
		view.status = status
		if view.pulse then
			view.pulse:Cancel()
			view.pulse = nil
		end
		local region = regionColor(view.node.region)
		local fill, fillTransparency, strokeColor, strokeTransparency, thickness
		if status == "allocated" then
			fill, fillTransparency = region, 0
			strokeColor, strokeTransparency, thickness = region:Lerp(Color3.new(1, 1, 1), 0.55), 0, 2
		elseif status == "available" then
			fill, fillTransparency = colors.panelRaised, 0
			strokeColor, strokeTransparency, thickness = colors.gold, 0, 2
		elseif status == "reachable" then
			fill, fillTransparency = colors.panelRaised, 0
			strokeColor, strokeTransparency, thickness = region, 0.2, 1.5
		else
			fill, fillTransparency = colors.panelSunken, 0.1
			strokeColor, strokeTransparency, thickness = region, 0.65, 1.5
		end
		Theme.tween(view.button, 0.2, { BackgroundColor3 = fill, BackgroundTransparency = fillTransparency })
		if view.ring then
			Theme.tween(view.ring, 0.2, { Transparency = if status == "allocated" then 0 else 0.55 })
		end
		if status == "available" then
			-- Set the stroke directly: the looping pulse owns Transparency from here on.
			view.stroke.Color, view.stroke.Thickness, view.stroke.Transparency =
				strokeColor, thickness, strokeTransparency
			local pulse = TweenService:Create(
				view.stroke,
				TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.7 }
			)
			pulse:Play()
			view.pulse = pulse
		else
			Theme.tween(
				view.stroke,
				0.2,
				{ Color = strokeColor, Transparency = strokeTransparency, Thickness = thickness }
			)
		end
	end

	local function render()
		local s = state
		local allocated = if s then s.allocated else START_ONLY
		local points = if s then s.points else 0
		pointsLabel.Text = `{Theme.text("pointsLeft")}: {points}`
		pointsLabel.TextColor3 = if points > 0 then colors.gold else colors.muted

		for id, view in views do
			local status: Status
			if id == Passives.startId or allocated[id] then
				status = "allocated"
			elseif PassiveTree.canAllocate(allocated, id, 1) then
				status = if points > 0 then "available" else "reachable"
			else
				status = "locked"
			end
			setStatus(view, status)
		end

		for _, link in links do
			local aOn = link.a.id == Passives.startId or allocated[link.a.id] == true
			local bOn = link.b.id == Passives.startId or allocated[link.b.id] == true
			local lit = (if aOn then 1 else 0) + (if bOn then 1 else 0)
			if lit ~= link.lit then
				link.lit = lit
				link.thickness = if lit == 2 then 4 else 2
				link.frame.Size = UDim2.fromOffset(link.frame.Size.X.Offset, link.thickness)
				Theme.tween(link.frame, 0.25, {
					BackgroundColor3 = if lit == 2 then link.color else colors.muted,
					BackgroundTransparency = if lit == 2 then 0 elseif lit == 1 then 0.4 else 0.75,
				})
			end
		end

		if tooltipId then
			showTooltip(tooltipId)
		end
	end

	local function tryAllocate(id: string)
		local s = state
		if not s then
			return
		end
		local ok, reason = PassiveTree.canAllocate(s.allocated, id, s.points)
		if ok then
			actions.allocatePassive(id)
			local view = views[id]
			local pop = view.button:FindFirstChildOfClass("UIScale")
			if pop then
				pop.Scale = 1.35
				Theme.tween(pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		else
			Theme.toast(gui, Theme.text("reason_" .. (reason or "unknown")), colors.danger)
		end
	end

	for id, node in Passives.nodes do
		local button = make("TextButton", {
			Name = id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = colors.panelSunken,
			Text = "",
			ZIndex = 3,
			Parent = nodeLayer,
		}, { Theme.corner(0.5), make("UIScale") })
		local stroke = Theme.stroke(regionColor(node.region), 1.5, 0.65)
		stroke.Parent = button
		local ring: UIStroke? = nil
		if node.kind == "keystone" or node.kind == "start" then
			local halo = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1.45, 1.45),
				ZIndex = 3,
				Parent = button,
			}, { Theme.corner(0.5) })
			local haloStroke = Theme.stroke(regionColor(node.region), 2, 0.55)
			haloStroke.Parent = halo
			ring = haloStroke
		end
		views[id] = { id = id, node = node, button = button, stroke = stroke, ring = ring }

		button.MouseEnter:Connect(function()
			if not touchSelected then
				showTooltip(id)
			end
		end)
		button.MouseLeave:Connect(function()
			if tooltipId == id and not touchSelected then
				hideTooltip()
			end
		end)
		button.Activated:Connect(function(input: InputObject)
			-- Touch has no hover: the first tap shows the tooltip, the second allocates.
			if input.UserInputType == Enum.UserInputType.Touch and touchSelected ~= id then
				touchSelected = id
				showTooltip(id)
				return
			end
			tryAllocate(id)
		end)
	end

	-- Pan, zoom and pinch --------------------------------------------------------------------------------
	local dragging = false
	local lastMouse = Vector2.zero
	local touches: { [InputObject]: Vector2 } = {}

	local function touchPair(): (Vector2?, Vector2?)
		local a, b = nil, nil
		for _, position in touches do
			if not a then
				a = position
			elseif not b then
				b = position
			end
		end
		return a, b
	end

	canvas.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			lastMouse = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = Vector2.new(input.Position.X, input.Position.Y)
			hideTooltip()
		end
	end)

	canvas.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			zoomAt(
				zoom * (if input.Position.Z > 0 then 1.12 else 1 / 1.12),
				Vector2.new(input.Position.X, input.Position.Y)
			)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not open then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
			pan += position - lastMouse
			lastMouse = position
			clampPan()
			layout()
		elseif input.UserInputType == Enum.UserInputType.Touch and touches[input] then
			local a0, b0 = touchPair()
			touches[input] = position
			local a1, b1 = touchPair()
			if a0 and b0 and a1 and b1 then
				local before = (a0 - b0).Magnitude
				local after = (a1 - b1).Magnitude
				pan += (a1 + b1) / 2 - (a0 + b0) / 2
				if before > 1 then
					zoomAt(zoom * after / before, (a1 + b1) / 2)
				else
					clampPan()
					layout()
				end
			elseif a0 and a1 then
				pan += a1 - a0
				clampPan()
				layout()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = nil
		end
	end)

	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if open then
			clampPan()
			layout()
		end
	end)

	-- Open / close -------------------------------------------------------------------------------------
	local function setOpen(value: boolean)
		if value == open then
			return
		end
		open = value
		openToken += 1
		local token = openToken
		if value then
			gui.Enabled = true
			if not fitted then
				fitted = true
				fit()
			end
			render()
			openScale.Value = 0.88
			layout()
			Theme.tween(backdrop, 0.25, { BackgroundTransparency = 0.06 })
			Theme.tween(openScale, 0.35, { Value = 1 }, Enum.EasingStyle.Quint)
		else
			hideTooltip()
			dragging = false
			table.clear(touches)
			Theme.tween(backdrop, 0.18, { BackgroundTransparency = 1 })
			Theme.tween(openScale, 0.18, { Value = 0.92 })
			task.delay(0.18, function()
				if token == openToken then
					gui.Enabled = false
				end
			end)
		end
	end

	resetButton.Activated:Connect(function()
		hideTooltip()
		actions.resetPassives()
	end)
	closeButton.Activated:Connect(function()
		setOpen(false)
	end)

	return {
		setOpen = setOpen,
		isOpen = function(): boolean
			return open
		end,
		update = function(s: PlayerState)
			state = s
			if open then
				render()
			end
		end,
	}
end

return Screen
