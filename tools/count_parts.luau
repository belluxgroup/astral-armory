--!strict
-- Verifies assets/Arena.rbxm: counts BaseParts against the budget and checks the
-- arena instance contract (plan, contract addendum item 4). Run: lune run tools/count_parts

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local PATH = "assets/Arena.rbxm"
local PART_BUDGET = 2000

local errors: { string } = {}
local function check(cond: boolean, msg: string)
	if not cond then
		table.insert(errors, msg)
	end
end

if not fs.isFile(PATH) then
	print(`missing {PATH}; run: lune run tools/build_map`)
	process.exit(1)
end

local roots = roblox.deserializeModel(fs.readFile(PATH))
if #roots ~= 1 then
	print(`expected 1 root instance, got {#roots}`)
	process.exit(1)
end
local arena: any = roots[1]
check(arena.Name == "Arena", `root is named {arena.Name}, expected Arena`)

local parts, decorative, badDecor = 0, 0, 0
for _, inst: any in arena:GetDescendants() do
	if inst:IsA("BasePart") then
		parts += 1
		check(inst.Anchored, `{inst:GetFullName()} is not anchored`)
		-- Every non-collidable part is decoration or a marker: it must skip touch and query too.
		if not inst.CanCollide then
			decorative += 1
			if inst.CanTouch or inst.CanQuery then
				badDecor += 1
			end
		end
	end
end
check(parts < PART_BUDGET, `{parts} BaseParts exceeds the budget of {PART_BUDGET}`)
check(badDecor == 0, `{badDecor} non-collidable parts still have CanTouch or CanQuery on`)

local function child(name: string, className: string): any
	local inst = arena:FindFirstChild(name)
	check(inst ~= nil, `missing Arena.{name}`)
	if inst and not inst:IsA(className) then
		check(false, `Arena.{name} is a {inst.ClassName}, expected {className}`)
		return nil
	end
	return inst
end

local function checkMarker(part: any, label: string)
	check(part:IsA("BasePart"), `{label} is not a BasePart`)
	if part:IsA("BasePart") then
		check(part.Anchored, `{label} is not anchored`)
		check(part.Transparency == 1, `{label} is not invisible`)
	end
end

local spawn = child("PlayerSpawn", "SpawnLocation")
if spawn then
	check(spawn.CanCollide, "PlayerSpawn must be collidable")
end

for _, spec in { { "InnerSpawns", 6 }, { "OuterSpawns", 8 } } do
	local name, minimum = spec[1] :: string, spec[2] :: number
	local folder = child(name, "Folder")
	if folder then
		local pads = folder:GetChildren()
		check(#pads >= minimum, `{name} has {#pads} parts, expected at least {minimum}`)
		for _, pad in pads do
			checkMarker(pad, `{name}.{pad.Name}`)
		end
	end
end

local altarModel = child("BossAltar", "Model")
if altarModel then
	local primary = altarModel.PrimaryPart
	check(primary ~= nil and primary.Name == "Altar", "BossAltar.PrimaryPart must be the part named Altar")
	local prompt = primary and primary:FindFirstChild("SummonPrompt")
	check(prompt ~= nil and prompt:IsA("ProximityPrompt"), "Altar needs a ProximityPrompt named SummonPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		check(prompt.ActionText == "Triệu hồi Boss", `SummonPrompt.ActionText is "{prompt.ActionText}"`)
	end
end

local bossSpawn = child("BossSpawn", "BasePart")
if bossSpawn then
	checkMarker(bossSpawn, "BossSpawn")
end
local center = child("Center", "BasePart")
if center then
	checkMarker(center, "Center")
end

local bounds = child("Bounds", "Folder")
if bounds then
	local walls = bounds:GetChildren()
	check(#walls >= 8, `Bounds has {#walls} walls, expected a ring of walls`)
	for _, wall in walls do
		check(
			wall:IsA("BasePart") and wall.Transparency == 1 and wall.CanCollide,
			`Bounds.{wall.Name} must be an invisible collidable part`
		)
	end
end

print(`{parts} BaseParts ({decorative} decorative), budget {PART_BUDGET}`)
if #errors > 0 then
	for _, msg in errors do
		print("FAIL: " .. msg)
	end
	process.exit(1)
end
print("contract ok")
