--!strict
local Strings = require("../src/shared/Config/Strings")
local Skills = require("../src/shared/Config/Skills")
local Gems = require("../src/shared/Config/Gems")
local Passives = require("../src/shared/Config/Passives")
local Enemies = require("../src/shared/Config/Enemies")

local function has(key: string): boolean
	local v = (Strings :: any)[key]
	return type(v) == "string" and #v > 0
end

return function(t)
	t.test("core ui keys exist", function()
		for _, key in
			{
				"hp",
				"energy",
				"level",
				"xp",
				"points",
				"passives",
				"gems",
				"reset",
				"locked",
				"unlockAt",
				"summonBoss",
				"bossName",
				"dodge",
			}
		do
			t.ok(has(key), key)
		end
	end)
	t.test("ui screen keys exist", function()
		for _, key in
			{
				"pointsLeft",
				"close",
				"inventory",
				"selectGemHint",
				"unsocketHint",
				"noGems",
				"treeHint",
				"tapAgain",
				"learned",
				"bossNeedLevel",
			}
		do
			t.ok(has(key), key)
		end
		for _, kind in { "start", "small", "notable", "keystone" } do
			t.ok(has("kind_" .. kind), "kind_" .. kind)
		end
	end)
	t.test("boss text names the Golden Tyrant", function()
		local name = Enemies.eclipse_warden.displayName
		t.eq(Strings.bossName, name)
		t.ok(string.find(Strings.bossDefeated, name, 1, true) ~= nil, "bossDefeated")
	end)
	t.test("every reason has text", function()
		for _, r in { "no_sockets", "bad_slot", "tag", "element", "duplicate" } do
			t.ok(has("reason_" .. r), "reason_" .. r)
		end
		for _, r in { "unknown", "allocated", "no_points", "not_linked" } do
			t.ok(has("reason_" .. r), "reason_" .. r)
		end
	end)
	t.test("every skill and gem has a name entry matching its config", function()
		for _, id in Skills.order do
			t.ok(has("skill_" .. id), "skill_" .. id)
			t.eq((Strings :: any)["skill_" .. id], Skills[id].displayName, id)
		end
		for _, id in Gems.order do
			t.ok(has("gem_" .. id), "gem_" .. id)
			t.ok(has("gemDesc_" .. id), "gemDesc_" .. id)
			t.eq((Strings :: any)["gem_" .. id], Gems[id].displayName, id)
		end
	end)
	t.test("every passive stat, region and keystone has text", function()
		for _, node in Passives.nodes do
			for _, m in node.mods do
				t.ok(has("stat_" .. m.stat), "stat_" .. m.stat)
			end
			if node.region ~= "core" then
				t.ok(has("region_" .. node.region), "region_" .. node.region)
			end
			if node.keystone then
				t.ok(has("keystoneDesc_" .. node.keystone), "keystoneDesc_" .. node.keystone)
			end
		end
	end)
end
