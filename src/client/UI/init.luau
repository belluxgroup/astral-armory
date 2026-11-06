--!strict
-- UI controller: owns the latest PlayerState, feeds every screen and exposes the ui handle to Input.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Ascension = require(script.Parent:WaitForChild("Vfx"):WaitForChild("Ascension"))

local DamageNumbers = require(script.DamageNumbers)
local Hud = require(script.Hud)
local Types = require(script.Types)

type PlayerState = Types.PlayerState
type Actions = Types.Actions

local UI = {}

function UI.start(): Types.UIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local remotes = Net.client()

	local state: PlayerState? = nil

	-- Cooldowns arrive as server os.clock() ready times. Convert them to local clock end times on receipt,
	-- and remember each cast's full length so the sweep can show a fraction.
	local cooldowns: { [string]: { endsAt: number, total: number } } = {}

	local function cooldown(skillId: string): (number, number)
		local entry = cooldowns[skillId]
		if not entry then
			return 0, 0
		end
		return math.max(0, entry.endsAt - os.clock()), entry.total
	end

	local function trackCooldowns(s: PlayerState)
		local now = os.clock()
		for skillId, readyAt in s.cooldowns do
			local endsAt = now + (readyAt - s.serverClock)
			local entry = cooldowns[skillId]
			if endsAt > now and (not entry or endsAt > entry.endsAt + 0.05) then
				cooldowns[skillId] = { endsAt = endsAt, total = endsAt - now }
			elseif entry then
				entry.endsAt = endsAt
			end
		end
	end

	-- Input installs the real remote calls; until then UI clicks do nothing.
	local actions: Actions = {
		allocatePassive = function(_: string) end,
		resetPassives = function() end,
		socketGem = function(_: string, _: number, _: string?) end,
		summonBoss = function() end,
	}

	local handle: Types.UIHandle

	local hud = Hud.new(playerGui, {
		getCooldown = cooldown,
		openPassives = function()
			handle.togglePassives()
		end,
		summonBoss = function()
			actions.summonBoss()
		end,
	})

	-- Ascension aura for the local character follows the server's transformed flag, including after respawn.
	local transformed = false
	local function applyTransform()
		local character = player.Character
		if character then
			Ascension.setActive(character, transformed)
		end
	end
	player.CharacterAdded:Connect(function()
		if transformed then
			task.defer(applyTransform)
		end
	end)

	remotes.StateSync.OnClientEvent:Connect(function(s: PlayerState)
		state = s
		trackCooldowns(s)
		hud.update(s)
		if s.transformed ~= transformed then
			transformed = s.transformed
			applyTransform()
		end
	end)

	remotes.DamagePopup.OnClientEvent:Connect(function(popup)
		DamageNumbers.spawn(popup.position, popup.amount, popup.crit, popup.element)
	end)

	handle = {
		togglePassives = function() end,
		toggleGems = function() end,
		getState = function(): PlayerState?
			return state
		end,
		cooldownLeft = function(skillId: string): number
			return (cooldown(skillId))
		end,
		setActions = function(newActions: Actions)
			for key, fn in newActions :: any do
				(actions :: any)[key] = fn
			end
		end,
	}
	return handle
end

return UI
