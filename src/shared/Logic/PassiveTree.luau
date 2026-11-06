--!strict
-- Pure passive tree rules (spec 4.5). No Roblox globals.
local Passives = if script
	then require(script.Parent.Parent.Config.Passives)
	else require("../Config/Passives")

export type Allocated = { [string]: true }
export type Reason = "unknown" | "allocated" | "no_points" | "not_linked"

local PassiveTree = {}

local EXPECTED_NODES = 40
local REGIONS = { "might", "swift", "insight" }

-- Checks the tree data: link targets exist, links are symmetric, every node is
-- reachable from the start node, exactly 40 nodes, one keystone per region.
function PassiveTree.validateGraph(nodes: { [string]: Passives.Node }): (boolean, { string })
	local errors: { string } = {}
	local startId = Passives.startId

	local count = 0
	local keystones: { [string]: number } = {}
	for id, node in nodes do
		count += 1
		if node.id ~= id then
			table.insert(errors, `node {id} has id {node.id}`)
		end
		if node.kind == "keystone" then
			keystones[node.region] = (keystones[node.region] or 0) + 1
			if node.keystone == nil then
				table.insert(errors, `keystone {id} has no keystone id`)
			end
		end
		for _, target in node.links do
			local other = nodes[target]
			if other == nil then
				table.insert(errors, `{id} links to missing node {target}`)
			elseif not table.find(other.links, id) then
				table.insert(errors, `link {id} -> {target} is not symmetric`)
			end
		end
	end
	if count ~= EXPECTED_NODES then
		table.insert(errors, `expected {EXPECTED_NODES} nodes, found {count}`)
	end
	for _, region in REGIONS do
		local n = keystones[region] or 0
		if n ~= 1 then
			table.insert(errors, `region {region} has {n} keystones, expected 1`)
		end
	end

	local start = nodes[startId]
	if start == nil then
		table.insert(errors, `start node {startId} is missing`)
	else
		if start.kind ~= "start" then
			table.insert(errors, `start node has kind {start.kind}`)
		end
		local seen: { [string]: boolean } = { [startId] = true }
		local queue = { startId }
		local head = 1
		while head <= #queue do
			local node = nodes[queue[head]]
			head += 1
			for _, target in node.links do
				if not seen[target] and nodes[target] ~= nil then
					seen[target] = true
					table.insert(queue, target)
				end
			end
		end
		for id in nodes do
			if not seen[id] then
				table.insert(errors, `{id} is not reachable from {startId}`)
			end
		end
	end

	table.sort(errors)
	return #errors == 0, errors
end

function PassiveTree.canAllocate(allocated: Allocated, nodeId: string, points: number): (boolean, Reason?)
	local node = Passives.nodes[nodeId]
	if node == nil then
		return false, "unknown"
	end
	if nodeId == Passives.startId or allocated[nodeId] then
		return false, "allocated"
	end
	if points < 1 then
		return false, "no_points"
	end
	for _, target in node.links do
		if target == Passives.startId or allocated[target] then
			return true, nil
		end
	end
	return false, "not_linked"
end

-- Returns a new allocation set and the remaining points. Errors if not allowed.
function PassiveTree.allocate(allocated: Allocated, nodeId: string, points: number): (Allocated, number)
	local ok, reason = PassiveTree.canAllocate(allocated, nodeId, points)
	if not ok then
		error(`cannot allocate {nodeId}: {reason}`, 2)
	end
	local nextSet: Allocated = table.clone(allocated)
	nextSet[Passives.startId] = true
	nextSet[nodeId] = true
	return nextSet, points - 1
end

-- Full respec: back to the start node only, refunding every other allocated node.
function PassiveTree.reset(allocated: Allocated): (Allocated, number)
	local refunded = 0
	for id in allocated do
		if id ~= Passives.startId then
			refunded += 1
		end
	end
	return { [Passives.startId] = true }, refunded
end

return PassiveTree
