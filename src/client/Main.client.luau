--!strict
-- Client boot: remotes, then VFX, UI and input controllers (contract addendum item 7).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Vfx = require(script.Parent:WaitForChild("Vfx"))
local UI = require(script.Parent:WaitForChild("UI"))
local Input = require(script.Parent:WaitForChild("Input"))

Net.client()
Vfx.start()
local ui = UI.start()
Input.start(ui)
