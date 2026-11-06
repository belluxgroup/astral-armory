--!strict
-- Gem screen: inventory grid on the left, two sockets per skill on the right.
-- Select a gem, then a socket. Right-click or long-press a filled socket to take its gem out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Skills = require(Config:WaitForChild("Skills"))
local Gems = require(Config:WaitForChild("Gems"))
local GemRules = require(Shared:WaitForChild("Logic"):WaitForChild("GemRules"))
local VfxPalette = require(Shared:WaitForChild("VfxPalette"))
local Theme = require(script.Parent.Theme)
local Types = require(script.Parent.Types)

type PlayerState = Types.PlayerState
type GemInstance = Types.GemInstance
type Actions = Types.Actions

local make = Theme.make
local colors = Theme.colors

local WIDTH, HEIGHT = 880, 540
local LEFT_X, RIGHT_X, TOP_Y = 24, 388, 78
local LEFT_W, RIGHT_W, SECTION_H = 340, 468, 404
local ROW_H, SOCKET = 92, 72
local LONG_PRESS = 0.5
local TOOLTIP_WIDTH = 260

-- Gems without an element get their own fixed hue.
local GEM_COLORS: { [string]: Color3 } = {
	multishot = Color3.fromHex("F2C14E"),
	wide_burst = Color3.fromHex("FF8A3D"),
	swift_cast = Color3.fromHex("4FE0C8"),
}

local function gemColor(gemId: string): Color3
	local gem = Gems[gemId]
	if gem and gem.element then
		return VfxPalette.get(gem.element, false).glow
	end
	return GEM_COLORS[gemId] or colors.gold
end

local function gemOrder(gemId: string): number
	return table.find(Gems.order, gemId) or #Gems.order + 1
end

-- A cut-gem glyph: a rotated square with a highlight gradient.
local function diamond(parent: Instance, color: Color3, size: number, y: number): Frame
	return make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, y),
		Rotation = 45,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 3,
		Parent = parent,
	}, {
		Theme.corner(4) :: Instance,
		make("UIGradient", {
			Rotation = -45,
			Color = ColorSequence.new(
				color:Lerp(Color3.new(1, 1, 1), 0.55),
				color:Lerp(Color3.new(0, 0, 0), 0.25)
			),
		}),
		Theme.stroke(color:Lerp(Color3.new(1, 1, 1), 0.7), 1.5, 0.2),
	})
end

export type Screen = {
	setOpen: (open: boolean) -> (),
	isOpen: () -> boolean,
	update: (state: PlayerState) -> (),
}

type SocketView = {
	skillId: string,
	slot: number,
	button: TextButton,
	stroke: UIStroke,
	content: Frame,
	plus: TextLabel,
	name: TextLabel,
	dim: Frame,
	pop: UIScale,
	reason: string?,
	filledGemId: string?,
	look: string?,
}

local Screen = {}

function Screen.new(parent: Instance, actions: Actions): Screen
	local state: PlayerState? = nil
	local open = false
	local openToken = 0
	local selectedId: string? = nil
	local inventoryKey = ""

	local gui = make("ScreenGui", {
		Name = "AstralGems",
		DisplayOrder = 10,
		Enabled = false,
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})
	local backdrop = make("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = colors.backdrop,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, -80),
		Size = UDim2.new(1, 0, 1, 80),
		Text = "",
		Parent = gui,
	})

	local panel = Theme.panel({
		Active = true, -- clicks on the panel must not reach the close-on-click backdrop
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 0.08,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Parent = gui,
	})
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(colors.panelRaised, colors.panel),
		Parent = panel,
	})
	local panelScale = Theme.autoScale(panel, WIDTH, HEIGHT)

	-- Header -------------------------------------------------------------------------------------------
	Theme.label({
		FontFace = Theme.fonts.heavy,
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.fromOffset(500, 28),
		Text = string.upper(Theme.text("gems")),
		TextColor3 = colors.gold,
		TextSize = 22,
		Parent = panel,
	})
	local hintLabel = Theme.label({
		FontFace = Theme.fonts.regular,
		Position = UDim2.fromOffset(24, 44),
		Size = UDim2.fromOffset(600, 18),
		Text = Theme.text("selectGemHint"),
		TextColor3 = colors.muted,
		TextSize = 14,
		Parent = panel,
	})
	local closeButton = Theme.button({
		AnchorPoint = Vector2.new(1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(1, -18, 0, 16),
		Size = UDim2.fromOffset(0, 38),
		Text = Theme.text("close"),
		TextSize = 15,
		Parent = panel,
	})
	Theme.corner(8).Parent = closeButton
	Theme.stroke(colors.gold, 1.5, 0.35).Parent = closeButton
	make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = closeButton })

	Theme.label({
		AnchorPoint = Vector2.new(0, 1),
		FontFace = Theme.fonts.regular,
		Position = UDim2.new(0, RIGHT_X, 1, -16),
		Size = UDim2.fromOffset(RIGHT_W, 18),
		Text = Theme.text("unsocketHint"),
		TextColor3 = colors.muted,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})

	-- Inventory ----------------------------------------------------------------------------------------
	local inventoryTitle = Theme.label({
		Position = UDim2.fromOffset(LEFT_X, TOP_Y),
		Size = UDim2.fromOffset(LEFT_W, 22),
		Text = Theme.text("inventory"),
		TextSize = 16,
		Parent = panel,
	})
	local inventory = make("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.panelSunken,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(LEFT_X, TOP_Y + 30),
		ScrollBarImageColor3 = colors.gold,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromOffset(LEFT_W, SECTION_H),
		Parent = panel,
	}, {
		Theme.corner(10) :: Instance,
		Theme.padding(10),
		make("UIGridLayout", {
			CellPadding = UDim2.fromOffset(8, 8),
			CellSize = UDim2.fromOffset(100, 110),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local emptyLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		FontFace = Theme.fonts.regular,
		Position = UDim2.fromOffset(LEFT_X + LEFT_W / 2, TOP_Y + 30 + SECTION_H / 2),
		Size = UDim2.fromOffset(LEFT_W - 40, 60),
		Text = Theme.text("noGems"),
		TextColor3 = colors.muted,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 4,
		Parent = panel,
	})

	-- Tooltip ------------------------------------------------------------------------------------------
	local tooltip = Theme.panel({
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.05,
		Size = UDim2.fromOffset(TOOLTIP_WIDTH, 0),
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	})
	Theme.padding(10).Parent = tooltip
	make(
		"UIListLayout",
		{ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tooltip }
	)
	local tooltipScale = Theme.autoScale(tooltip)
	local tipTitle = Theme.label({
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		FontFace = Theme.fonts.heavy,
		Size = UDim2.fromScale(1, 0),
		Text = "",
		TextSize = 16,
		TextWrapped = true,
		ZIndex = 31,
		Parent = tooltip,
	})
	local tipBody = Theme.label({
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.Y,
		FontFace = Theme.fonts.regular,
		Size = UDim2.fromScale(1, 0),
		Text = "",
		TextSize = 14,
		TextWrapped = true,
		ZIndex = 31,
		Parent = tooltip,
	})
	local tipOwner: GuiObject? = nil

	local function placeTooltip()
		local owner = tipOwner
		if not owner then
			return
		end
		local screen = gui.AbsoluteSize
		local s = tooltipScale.Scale
		local topLeft = owner.AbsolutePosition
		local x = topLeft.X + owner.AbsoluteSize.X + 10
		if x + TOOLTIP_WIDTH * s > screen.X - 8 then
			x = topLeft.X - 10 - TOOLTIP_WIDTH * s
		end
		local y = math.clamp(topLeft.Y, 8, math.max(8, screen.Y - tooltip.AbsoluteSize.Y - 8))
		tooltip.Position = UDim2.fromOffset(x, y)
	end

	local function showTooltip(
		owner: GuiObject,
		title: string,
		titleColor: Color3,
		body: string,
		bodyColor: Color3
	)
		tipOwner = owner
		tipTitle.Text = title
		tipTitle.TextColor3 = titleColor
		tipBody.Text = body
		tipBody.TextColor3 = bodyColor
		tipBody.Visible = body ~= ""
		tooltip.Visible = true
		placeTooltip()
		task.defer(placeTooltip)
	end

	local function hideTooltip(owner: GuiObject?)
		if owner == nil or tipOwner == owner then
			tipOwner = nil
			tooltip.Visible = false
		end
	end

	local function gemTooltip(owner: GuiObject, gemId: string)
		showTooltip(
			owner,
			Theme.text("gem_" .. gemId),
			gemColor(gemId),
			Theme.text("gemDesc_" .. gemId),
			colors.text
		)
	end

	-- Helpers on the current state -----------------------------------------------------------------------
	local function selectedGem(): GemInstance?
		local s = state
		if not s or not selectedId then
			return nil
		end
		for _, gem in s.gems do
			if gem.id == selectedId then
				return gem
			end
		end
		return nil
	end

	local function socketMap(skillId: string): { [number]: string? }
		local map: { [number]: string? } = {}
		local s = state
		if s then
			for slot = 1, Skills[skillId].sockets do
				local gem = Types.socketAt(s, skillId, slot)
				map[slot] = if gem then gem.gemId else nil
			end
		end
		return map
	end

	-- Sockets ------------------------------------------------------------------------------------------
	local socketViews: { SocketView } = {}
	local rows = make("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(RIGHT_X, TOP_Y),
		ScrollBarImageColor3 = colors.gold,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromOffset(RIGHT_W, SECTION_H + 30),
		Parent = panel,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local render: () -> ()

	local function onSocketActivated(view: SocketView)
		local s = state
		if not s then
			return
		end
		local gem = selectedGem()
		if gem then
			local ok, reason = GemRules.canSocket(view.skillId, view.slot, gem.gemId, socketMap(view.skillId))
			if ok then
				actions.socketGem(view.skillId, view.slot, gem.id)
				selectedId = nil
				view.pop.Scale = 1.18
				Theme.tween(view.pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
				render()
			else
				Theme.toast(gui, Theme.text("reason_" .. (reason or "tag")), colors.danger)
			end
		elseif view.filledGemId then
			Theme.toast(gui, Theme.text("unsocketHint"))
		else
			Theme.toast(gui, Theme.text("selectGemHint"))
		end
	end

	local function unsocket(view: SocketView)
		if view.filledGemId then
			actions.socketGem(view.skillId, view.slot, nil)
			view.pop.Scale = 0.85
			Theme.tween(view.pop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	local function makeSocket(row: Frame, skillId: string, slot: number): SocketView
		local button = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = colors.panelSunken,
			BackgroundTransparency = 0.1,
			Position = UDim2.new(1, -14 - (2 - slot) * (SOCKET + 12), 0.5, 0),
			Size = UDim2.fromOffset(SOCKET, SOCKET),
			Text = "",
			Parent = row,
		}, { Theme.corner(12) })
		local stroke = Theme.stroke(colors.muted, 1.5, 0.5)
		stroke.Parent = button
		local pop = make("UIScale", { Parent = button })
		local content =
			make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = button })
		local plus = Theme.label({
			Size = UDim2.fromScale(1, 1),
			FontFace = Theme.fonts.regular,
			Text = "+",
			TextColor3 = colors.muted,
			TextSize = 30,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = button,
		})
		local name = Theme.label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -6, 0, 16),
			Text = "",
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
			Parent = button,
		})
		local dim = make("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 6,
			Parent = button,
		}, { Theme.corner(12) })

		local view: SocketView = {
			skillId = skillId,
			slot = slot,
			button = button,
			stroke = stroke,
			content = content,
			plus = plus,
			name = name,
			dim = dim,
			pop = pop,
		}

		local suppressActivate = false
		local pressToken = 0
		button.Activated:Connect(function()
			if suppressActivate then
				suppressActivate = false
				return
			end
			onSocketActivated(view)
		end)
		button.MouseButton2Click:Connect(function()
			unsocket(view)
		end)
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			pressToken += 1
			local token = pressToken
			task.delay(LONG_PRESS, function()
				if token == pressToken and view.filledGemId then
					suppressActivate = true
					unsocket(view)
				end
			end)
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				pressToken += 1
			end
		end)
		button.MouseEnter:Connect(function()
			if view.reason then
				showTooltip(
					button,
					Theme.text("skill_" .. skillId),
					colors.danger,
					view.reason,
					colors.danger
				)
			elseif view.filledGemId then
				gemTooltip(button, view.filledGemId)
			end
		end)
		button.MouseLeave:Connect(function()
			hideTooltip(button)
		end)
		return view
	end

	local rowIndex = 0
	for _, skillId: string in Skills.order do
		local skill = Skills[skillId]
		if skill.sockets > 0 then
			rowIndex += 1
			local row = make("Frame", {
				BackgroundColor3 = colors.panelRaised,
				BackgroundTransparency = 0.35,
				LayoutOrder = rowIndex,
				Size = UDim2.new(1, -8, 0, ROW_H),
				Parent = rows,
			}, { Theme.corner(10) :: Instance, Theme.stroke(colors.gold, 1, 0.85) })
			local keyBadge = make("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = colors.panel,
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(44, 44),
				Parent = row,
			}, { Theme.corner(0.5) :: Instance, Theme.stroke(colors.gold, 1.5, 0.3) })
			Theme.label({
				FontFace = Theme.fonts.heavy,
				Size = UDim2.fromScale(1, 1),
				Text = skill.key,
				TextColor3 = colors.gold,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = keyBadge,
			})
			Theme.label({
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 70, 0.5, 0),
				Size = UDim2.new(1, -70 - 2 * (SOCKET + 12) - 14, 0, 44),
				Text = Theme.text("skill_" .. skillId),
				TextSize = 17,
				TextWrapped = true,
				Parent = row,
			})
			for slot = 1, skill.sockets do
				table.insert(socketViews, makeSocket(row, skillId, slot))
			end
		end
	end

	-- Rendering ----------------------------------------------------------------------------------------
	local tiles: { [string]: { button: TextButton, stroke: UIStroke, pop: UIScale } } = {}
	local shownSelection = "?" -- selection the tiles currently show; "?" forces a refresh

	local function renderInventory(s: PlayerState)
		local list = table.clone(s.gems)
		table.sort(list, function(a, b)
			local oa, ob = gemOrder(a.gemId), gemOrder(b.gemId)
			if oa ~= ob then
				return oa < ob
			end
			return a.id < b.id
		end)
		local keyParts = table.create(#list)
		for i, gem in list do
			keyParts[i] = gem.id .. ":" .. gem.gemId
		end
		local key = table.concat(keyParts, ",")
		inventoryTitle.Text = `{Theme.text("inventory")} ({#list})`
		emptyLabel.Visible = #list == 0
		if key == inventoryKey then
			return
		end
		inventoryKey = key
		shownSelection = "?"

		for _, tile in tiles do
			tile.button:Destroy()
		end
		table.clear(tiles)
		hideTooltip()

		for index, gem in list do
			local color = gemColor(gem.gemId)
			local button = make("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = colors.panelRaised,
				BackgroundTransparency = 0.1,
				LayoutOrder = index,
				Text = "",
				Parent = inventory,
			}, { Theme.corner(10) })
			local stroke = Theme.stroke(color, 1.5, 0.6)
			stroke.Parent = button
			local pop = make("UIScale", { Parent = button })
			diamond(button, color, 34, 38)
			Theme.label({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, -8, 0, 32),
				Text = Theme.text("gem_" .. gem.gemId),
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 3,
				Parent = button,
			})
			local gemId, instanceId = gem.gemId, gem.id
			button.Activated:Connect(function()
				selectedId = if selectedId == instanceId then nil else instanceId
				render()
			end)
			button.MouseEnter:Connect(function()
				gemTooltip(button, gemId)
			end)
			button.MouseLeave:Connect(function()
				hideTooltip(button)
			end)
			tiles[instanceId] = { button = button, stroke = stroke, pop = pop }
		end
	end

	local function renderSelection()
		if shownSelection == (selectedId or "") then
			return
		end
		shownSelection = selectedId or ""
		for instanceId, tile in tiles do
			local selected = instanceId == selectedId
			Theme.tween(tile.stroke, 0.15, {
				Thickness = if selected then 3 else 1.5,
				Transparency = if selected then 0 else 0.6,
			})
			Theme.tween(tile.pop, 0.2, { Scale = if selected then 1.06 else 1 }, Enum.EasingStyle.Back)
		end
		local gem = selectedGem()
		hintLabel.Text = if gem
			then `{Theme.text("gem_" .. gem.gemId)}: {Theme.text("gemDesc_" .. gem.gemId)}`
			else Theme.text("selectGemHint")
		hintLabel.TextColor3 = if gem then gemColor(gem.gemId) else colors.muted
	end

	local function renderSockets(s: PlayerState)
		local gem = selectedGem()
		for _, view in socketViews do
			local filled = Types.socketAt(s, view.skillId, view.slot)
			local filledId = if filled then filled.gemId else nil
			if filledId ~= view.filledGemId then
				view.filledGemId = filledId
				view.content:ClearAllChildren()
				if filledId then
					diamond(view.content, gemColor(filledId), 28, 30)
				end
				view.plus.Visible = filledId == nil
				view.name.Text = if filledId then Theme.text("gem_" .. filledId) else ""
			end

			local reason: string? = nil
			if gem then
				local ok, why =
					GemRules.canSocket(view.skillId, view.slot, gem.gemId, socketMap(view.skillId))
				if not ok then
					reason = Theme.text("reason_" .. (why or "tag"))
				end
			end
			view.reason = reason
			view.dim.Visible = reason ~= nil
			local look = `{filledId or ""}|{gem and gem.id or ""}|{reason or ""}`
			if look == view.look then
				continue
			end
			view.look = look
			local strokeColor = if gem and not reason
				then colors.gold
				elseif filledId then gemColor(filledId)
				else colors.muted
			Theme.tween(view.stroke, 0.15, {
				Color = strokeColor,
				Thickness = if gem and not reason then 2.5 else 1.5,
				Transparency = if gem and not reason then 0 elseif filledId then 0.3 else 0.5,
			})
		end
	end

	render = function()
		local s = state
		if not s then
			return
		end
		renderInventory(s)
		if selectedId and not selectedGem() then
			selectedId = nil
		end
		renderSelection()
		renderSockets(s)
	end

	-- Open / close -------------------------------------------------------------------------------------
	local function setOpen(value: boolean)
		if value == open then
			return
		end
		open = value
		openToken += 1
		local token = openToken
		local target = Theme.fitScale(WIDTH, HEIGHT)
		if value then
			gui.Enabled = true
			render()
			panelScale.Scale = target * 0.94
			Theme.tween(backdrop, 0.22, { BackgroundTransparency = 0.35 })
			TweenService:Create(panelScale, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = target })
				:Play()
		else
			selectedId = nil
			hideTooltip()
			Theme.tween(backdrop, 0.16, { BackgroundTransparency = 1 })
			Theme.tween(panelScale, 0.16, { Scale = target * 0.94 })
			task.delay(0.16, function()
				if token == openToken then
					gui.Enabled = false
				end
			end)
		end
	end

	closeButton.Activated:Connect(function()
		setOpen(false)
	end)
	backdrop.Activated:Connect(function()
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
