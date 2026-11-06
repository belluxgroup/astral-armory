--!strict
-- Bottom-center HUD: skill hotbar with cooldown sweeps, HP / Energy / Stamina / XP bars.
-- Top-left: points badge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Skills = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Skills"))
local Theme = require(script.Parent.Theme)
local Types = require(script.Parent.Types)

type PlayerState = Types.PlayerState

local make = Theme.make
local colors = Theme.colors

local WIDTH = 460
local SLOT = 64
local SLOT_GAP = 14
local BARS_HEIGHT = 98
local BOSS_SUMMON_LEVEL = 8 -- spec §4.6: the boss can be summoned from level 8
local STAMINA_COLOR = Color3.fromHex("5BD08A") -- dodge spec §1
local FLASH_TIME = 0.12
local FLASH_REPEATS = 2

export type Hud = { update: (state: PlayerState) -> (), flashStamina: () -> () }

type Deps = {
	getCooldown: (skillId: string) -> (number, number),
	openPassives: () -> (),
	summonBoss: () -> (),
}

type Bar = { set: (current: number, max: number, text: string?) -> (), flash: () -> () }

local function makeBar(parent: Instance, y: number, height: number, color: Color3, textSize: number): Bar
	local radius = math.floor(height / 2)
	local track = make("Frame", {
		BackgroundColor3 = colors.panelSunken,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, height),
		Parent = parent,
	}, { Theme.corner(radius) })
	local ghost = make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	}, { Theme.corner(radius) })
	local fill = make("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	}, {
		Theme.corner(radius),
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(
				color:Lerp(Color3.new(1, 1, 1), 0.35),
				color:Lerp(Color3.new(0, 0, 0), 0.15)
			),
		}),
	})
	local flashOverlay = make("Frame", {
		BackgroundColor3 = colors.danger,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = track,
	}, { Theme.corner(radius) })
	local flashTween = TweenService:Create(
		flashOverlay,
		TweenInfo.new(FLASH_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, FLASH_REPEATS, true),
		{ BackgroundTransparency = 0.15 }
	)
	local label = Theme.label({
		Size = UDim2.fromScale(1, 1),
		TextSize = textSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Text = "",
		ZIndex = 3,
		Parent = track,
	})

	local shown = 1
	return {
		set = function(current: number, max: number, text: string?)
			local fraction = if max > 0 then math.clamp(current / max, 0, 1) else 0
			label.Text = text or ""
			if math.abs(fraction - shown) < 1e-4 then
				return
			end
			if fraction < shown then
				-- Losses leave a white trail that catches up, so big hits read at a glance.
				Theme.tween(fill, 0.15, { Size = UDim2.fromScale(fraction, 1) })
				Theme.tween(ghost, 0.4, { Size = UDim2.fromScale(fraction, 1) }, nil, nil, 0.35)
			else
				ghost.Size = UDim2.fromScale(fraction, 1)
				Theme.tween(fill, 0.25, { Size = UDim2.fromScale(fraction, 1) })
			end
			shown = fraction
		end,
		-- A few quick red blinks, for an action refused for lack of this resource.
		flash = function()
			flashTween:Cancel()
			flashOverlay.BackgroundTransparency = 1
			flashTween:Play()
		end,
	}
end

-- Radial sweep from two clipped half discs. Each half holds a full-size disc whose UIGradient is
-- opaque on one side of a line through the center; rotating the gradient sweeps that half.
local function makeSweep(parent: GuiObject, zIndex: number): (fraction: number) -> ()
	local gradients: { [string]: UIGradient } = {}
	local clips: { GuiObject } = {}
	for _, side in { "right", "left" } do
		local clip = make("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromScale(if side == "right" then 0.5 else 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			Visible = false,
			ZIndex = zIndex,
			Parent = parent,
		})
		local disc = make("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(if side == "right" then -1 else 0, 0),
			Size = UDim2.fromScale(2, 1),
			ZIndex = zIndex,
			Parent = clip,
		}, { Theme.corner(0.5) })
		gradients[side] = make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.501, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = disc,
		})
		table.insert(clips, clip)
	end
	-- fraction 1 covers the whole slot; it shrinks counter-clockwise back to 12 o'clock.
	return function(fraction: number)
		local angle = math.clamp(fraction, 0, 1) * 360
		for _, clip in clips do
			clip.Visible = angle > 0
		end
		gradients.right.Rotation = math.clamp(angle, 0, 180)
		gradients.left.Rotation = 180 + math.clamp(angle - 180, 0, 180)
	end
end

type Slot = {
	skillId: string,
	setSweep: (number) -> (),
	keyLabel: TextLabel,
	cdLabel: TextLabel,
	lock: Frame,
	stroke: UIStroke,
	pop: UIScale,
	cooling: boolean,
}

local function makeSlot(parent: Instance, skillId: string, order: number): Slot
	local skill = Skills[skillId]
	local frame = make("Frame", {
		Name = skillId,
		LayoutOrder = order,
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Size = UDim2.fromOffset(SLOT, SLOT),
		Parent = parent,
	}, {
		Theme.corner(0.5),
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(colors.panelRaised, colors.panel),
		}),
	})
	local stroke = Theme.stroke(colors.gold, 1.5, 0.45)
	stroke.Parent = frame
	local pop = make("UIScale", { Parent = frame })

	local keyLabel = Theme.label({
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.fonts.heavy,
		Text = skill.key,
		TextColor3 = colors.gold,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 1,
		Parent = frame,
	})
	local setSweep = makeSweep(frame, 2)
	local cdLabel = Theme.label({
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.fonts.heavy,
		Text = "",
		TextSize = 20,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = frame,
	})

	local lock = make("Frame", {
		BackgroundColor3 = colors.panelSunken,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 4,
		Parent = frame,
	}, { Theme.corner(0.5) })
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.7),
		Text = Theme.textWith("unlockAt", skill.unlockLevel or 0),
		TextColor3 = colors.muted,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
		Parent = lock,
	})

	-- Hover name above the slot.
	local tip = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 10,
		Parent = frame,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = tip })
	Theme.label({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Text = Theme.text("skill_" .. skillId),
		TextSize = 14,
		ZIndex = 11,
		Parent = tip,
	})
	frame.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	frame.MouseLeave:Connect(function()
		tip.Visible = false
	end)

	return {
		skillId = skillId,
		setSweep = setSweep,
		keyLabel = keyLabel,
		cdLabel = cdLabel,
		lock = lock,
		stroke = stroke,
		pop = pop,
		cooling = false,
	}
end

local Hud = {}

function Hud.new(parent: Instance, deps: Deps): Hud
	local screen = make("ScreenGui", {
		Name = "AstralHud",
		DisplayOrder = 1,
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})

	-- Bottom center ----------------------------------------------------------------------------------
	local root = make("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(WIDTH, SLOT + 12 + BARS_HEIGHT),
		Parent = screen,
	})
	Theme.autoScale(root)

	local hotbar = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, SLOT),
		Parent = root,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, SLOT_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local slots: { Slot } = {}
	for i, skillId: string in Skills.order do
		if skillId ~= "basic" then
			table.insert(slots, makeSlot(hotbar, skillId, i))
		end
	end

	local bars = Theme.panel({
		Position = UDim2.fromOffset(0, SLOT + 12),
		Size = UDim2.new(1, 0, 0, BARS_HEIGHT),
		Parent = root,
	})
	local inner = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = bars,
	}, { Theme.padding(10) })
	local hpBar = makeBar(inner, 0, 20, colors.hp, 13)
	local energyBar = makeBar(inner, 26, 16, colors.energy, 12)
	local staminaBar = makeBar(inner, 46, 12, STAMINA_COLOR, 10)

	local levelLabel = Theme.label({
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.fromOffset(70, 16),
		FontFace = Theme.fonts.heavy,
		Text = Theme.textWith("level", 1),
		TextColor3 = colors.gold,
		TextSize = 15,
		Parent = inner,
	})
	local levelPop = make("UIScale", { Parent = levelLabel })
	local xpHolder = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(76, 66),
		Size = UDim2.new(1, -76, 0, 8),
		Parent = inner,
	})
	local xpBar = makeBar(xpHolder, 0, 8, colors.xp, 1)

	-- Top left -----------------------------------------------------------------------------------------
	local corner = make("Frame", {
		Name = "TopLeft",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(220, 100),
		Parent = screen,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Theme.autoScale(corner)

	local pointsButton = Theme.button({
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Size = UDim2.fromOffset(0, 38),
		FontFace = Theme.fonts.heavy,
		Text = Theme.text("points") .. ": 0",
		TextColor3 = colors.gold,
		TextSize = 16,
		Parent = corner,
	})
	Theme.corner(19).Parent = pointsButton
	local pointsStroke = Theme.stroke(colors.gold, 1.5, 0.5)
	pointsStroke.Parent = pointsButton
	make(
		"UIPadding",
		{ PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = pointsButton }
	)
	pointsButton.Activated:Connect(deps.openPassives)

	local summonButton = Theme.button({
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Size = UDim2.fromOffset(0, 34),
		Text = Theme.text("summonBoss"),
		TextColor3 = colors.text,
		TextSize = 14,
		Visible = false,
		Parent = corner,
	})
	Theme.corner(17).Parent = summonButton
	Theme.stroke(colors.hp, 1.5, 0.3).Parent = summonButton
	make(
		"UIPadding",
		{ PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = summonButton }
	)
	summonButton.Activated:Connect(deps.summonBoss)

	-- Points badge breathes while there are points to spend.
	local pulse: Tween? = nil
	local function setPulse(on: boolean)
		if on and not pulse then
			pointsStroke.Transparency = 0.6
			local tween = TweenService:Create(
				pointsStroke,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0, Thickness = 2.5 }
			)
			tween:Play()
			pulse = tween
		elseif not on and pulse then
			pulse:Cancel()
			pulse = nil
			pointsStroke.Transparency = 0.5
			pointsStroke.Thickness = 1.5
		end
	end

	-- Cooldown sweeps --------------------------------------------------------------------------------
	RunService.RenderStepped:Connect(function()
		for _, slot in slots do
			local left, total = deps.getCooldown(slot.skillId)
			if left > 0 and total > 0 then
				slot.setSweep(left / total)
				slot.cdLabel.Text = if left >= 10
					then tostring(math.ceil(left))
					else string.format("%.1f", left)
				slot.keyLabel.TextTransparency = 0.7
				slot.cooling = true
			elseif slot.cooling then
				slot.cooling = false
				slot.setSweep(0)
				slot.cdLabel.Text = ""
				slot.keyLabel.TextTransparency = 0
				-- Ready ping.
				slot.pop.Scale = 1.15
				Theme.tween(slot.pop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
	end)

	local lastLevel = 0
	local lastTransformed = false

	local function update(state: PlayerState)
		hpBar.set(state.hp, state.maxHp, `{math.ceil(state.hp)} / {math.floor(state.maxHp + 0.5)}`)
		energyBar.set(
			state.energy,
			state.maxEnergy,
			`{math.floor(state.energy)} / {math.floor(state.maxEnergy + 0.5)}`
		)
		staminaBar.set(
			state.stamina,
			state.maxStamina,
			`{math.floor(state.stamina)} / {math.floor(state.maxStamina + 0.5)}`
		)
		xpBar.set(state.xp, state.xpToNext)

		if state.level ~= lastLevel then
			levelLabel.Text = Theme.textWith("level", state.level)
			if lastLevel > 0 and state.level > lastLevel then
				levelPop.Scale = 1.4
				Theme.tween(levelPop, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			lastLevel = state.level
		end

		pointsButton.Text = Theme.text("points") .. ": " .. tostring(state.points)
		setPulse(state.points > 0)
		summonButton.Visible = state.level >= BOSS_SUMMON_LEVEL

		for _, slot in slots do
			local unlockLevel = Skills[slot.skillId].unlockLevel
			slot.lock.Visible = unlockLevel ~= nil and state.level < unlockLevel
		end

		if state.transformed ~= lastTransformed then
			lastTransformed = state.transformed
			for _, slot in slots do
				if slot.skillId == "ascension" then
					Theme.tween(slot.stroke, 0.3, {
						Color = if state.transformed then Color3.fromHex("FFF4D6") else colors.gold,
						Thickness = if state.transformed then 3.5 else 1.5,
						Transparency = if state.transformed then 0 else 0.45,
					})
				end
			end
		end
	end

	return { update = update, flashStamina = staminaBar.flash }
end

return Hud
