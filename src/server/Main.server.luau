--!strict
-- Server boot (contract addendum 8): remotes first, then services in dependency order.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

Net.server()

local Services = script.Parent:WaitForChild("Services")
local order = { "PlayerData", "Combat", "Enemies", "Boss" }

for _, name in order do
	local service = require(Services:WaitForChild(name)) :: any
	local ok, err = pcall(service.start)
	if not ok then
		warn(`[Server] {name}.start failed: {err}`)
	end
end
