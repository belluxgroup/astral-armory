# Astral Armory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Astral Armory Roblox demo: 6 skills with VFX, passive tree, support gems, enemies, a 2-phase boss, an optimized arena, and HUD/tree/gem UI.

**Architecture:** Rojo project. Pure-Luau `Config/` + `Logic/` are unit-tested with Lune. A server-authoritative `src/server` uses them. A `src/client` renders VFX and UI from remote events. The arena is generated to `assets/Arena.rbxm` by a Lune script.

**Tech Stack:** Luau (`--!strict`), Rojo 7.7.1, Lune 0.11.1, StyLua 2.6.0, Selene 0.32.0, Python 3 + Pillow.

**Spec:** `docs/superpowers/specs/2026-11-06-astral-armory-design.md`. Read it fully before starting. Section 5 (contracts) is binding.

## Global Constraints

- Tools live in `D:\Tools\bin`. In Git Bash, run `export PATH="/d/Tools/bin:$PATH"` first.
- Repo root: `D:\WORKSPACE\Project RBX\demo`. Run every command from there.
- `--!strict` is the first line of every `.luau` file. Tabs for indent (`stylua.toml`).
- `src/shared/Config/**` and `src/shared/Logic/**` must not reference `game`, `workspace`, `Instance`, `Vector3`, `CFrame`, `Color3`, `task`, `Enum` or any Roblox global.
- Cross-module requires inside `Config/` and `Logic/` use this exact dual form, so the same file runs in Roblox and in Lune:
  ```lua
  local Skills = if script then require(script.Parent.Parent.Config.Skills) else require("../Config/Skills")
  ```
  From `Logic` to `Logic`: `if script then require(script.Parent.Stats) else require("./Stats")`.
- Every other module uses `require(script...)` or `ReplicatedStorage.Shared...` paths.
- Tests: `tests/<Name>.spec.luau` returns `function(t)`. The helpers are `t.test(name, fn)`, `t.eq(a, b, msg?)`, `t.near(a, b, eps?, msg?)` and `t.ok(cond, msg?)`. Run with `lune run tests/run [filter]`. Tests require modules as `require("../src/shared/Logic/X")`.
- Gate before every commit: `stylua src tests tools` (format), `selene src` (0 errors), `lune run tests/run` (all pass), and `rojo build -o AstralArmory.rbxl` (succeeds).
- Player-facing strings are Vietnamese and come from `Config/Strings.luau`.
- Commit messages are conventional (`feat:`, `fix:`, `test:`, `chore:`) and end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_017FNpUjnyfktrADte9rPXsd
  ```
- Only touch files your workstream owns (spec §7). The workstreams commit in parallel in one repo, so `git add` only your own paths, never `git add -A`. If a commit fails because the index is locked, retry after 2 s.
- Element ids: `"none" | "frost" | "flame" | "storm"`. Skill ids: `basic`, `blade_rain`, `dawnbreaker`, `crimson_lance`, `hex_aegis`, `ascension`. Gem ids: `multishot`, `frost`, `flame`, `storm`, `wide_burst`, `swift_cast`. Keystone ids: `blood_oath`, `endless_arsenal`, `radiant_mind`.

### Contract addendum (adds to spec §5; binding for all workstreams)

1. `SkillSpec` gains `drainPerSec: number?`. With `radiant_mind`, `ascension` resolves to `duration = math.huge` and `drainPerSec = 6`.
2. `SkillSpec.damage` already includes `stats.damageMul`, gem multipliers and the transform bonus. `Damage.roll(base, stats, rng)` only applies crit: if `rng() < stats.critChance` it returns `base * stats.critMul, true`, else `base, false`.
3. With `blood_oath`, `SkillSpec.cost` stays the same number but `costResource = "hp"`.
4. The arena instance contract (Builder produces it; Combat consumes it). Under `Workspace.Arena`:
   - `PlayerSpawn` (SpawnLocation)
   - `InnerSpawns` (Folder of anchored invisible Parts, at least 6)
   - `OuterSpawns` (Folder of anchored invisible Parts, at least 8)
   - `BossAltar` (Model with PrimaryPart `Altar`, which has a ProximityPrompt `SummonPrompt` with ActionText "Triệu hồi Boss")
   - `BossSpawn` (anchored invisible Part)
   - `Bounds` (Folder of invisible collidable walls)
   - `Center` (anchored invisible Part at the rune circle)
5. Shared models, built by the VFX workstream, used by Combat:
   - `Shared.Models.SwordModel.build(): Model`: PrimaryPart `Handle`, plus Attachments `TrailTop` and `TrailBottom` on the blade.
   - `Shared.Models.LanceModel.build(): Model`: PrimaryPart `Shaft`, plus Attachments `TrailA` and `TrailB`.
6. `Shared.Config.Anims` (Combat owns, VFX reads): `{ idle = "rbxassetid://507766388", walk = "rbxassetid://507777826", run = "rbxassetid://507767714", slash = "rbxassetid://522635514" }`.
7. Client controllers, each a folder with `init.luau`:
   - `Client.Vfx.start()` connects `SkillFx` and `BossFx`.
   - `Client.UI.start()` connects `StateSync` and `DamagePopup` and builds the screens.
   - `Client.Input.start(ui)` binds keys, mobile buttons and aim, and fires `CastSkill`, `AllocatePassive`, `ResetPassives`, `SocketGem` and `SummonBoss`.
   - The UI exposes `ui.togglePassives()`, `ui.toggleGems()` and `ui.getState(): PlayerState?`.
   - `Client/Main.client.luau` (UI owns) calls `Net.client()`, `Vfx.start()`, `local ui = UI.start()`, then `Input.start(ui)`.
8. Server boot: `Server/Main.server.luau` (Combat owns) calls `Net.server()`, then `start()` on `PlayerData`, `Combat`, `Enemies` and `Boss`, in that order. Services are ModuleScripts under `Server/Services/`.
9. `Net` lives at `Shared/Net.luau`. It exports `Net.names` (a table of the remote names in spec §5.2), `Net.server(): { [string]: RemoteEvent }` (creates the remotes) and `Net.client(): { [string]: RemoteEvent }` (waits for them).

---

## Workstream A: Progression (pure Luau, TDD)

Owns: `src/shared/Config/{Skills,Gems,Passives,Progression,Strings}.luau`, `src/shared/Logic/*`, `tests/*.spec.luau`.

### Task A1: XP curve and level gain

**Files:**
- Create: `src/shared/Config/Progression.luau`, `src/shared/Logic/Progression.luau`
- Test: `tests/Progression.spec.luau`

**Interfaces:**
- Produces:
  - `Progression.xpToNext(level: number): number`
  - `Progression.addXp(level: number, xp: number, amount: number): (number, number, number)`, returning new level, new xp and levels gained
  - `Config.Progression = { maxLevel = 20, pointsPerLevel = 1, xpBase = 100, xpExp = 1.5 }`

- [ ] **Step 1: Write the failing test**

```lua
local P = require("../src/shared/Logic/Progression")
return function(t)
	t.test("xp curve", function()
		t.eq(P.xpToNext(1), 100)
		t.eq(P.xpToNext(2), 282)
		t.eq(P.xpToNext(10), 3162)
		t.eq(P.xpToNext(19), 8281)
	end)
	t.test("single level up keeps remainder", function()
		local l, x, g = P.addXp(1, 0, 105)
		t.eq(l, 2); t.eq(x, 5); t.eq(g, 1)
	end)
	t.test("multi level up", function()
		local l, x, g = P.addXp(1, 0, 100 + 282 + 7)
		t.eq(l, 3); t.eq(x, 7); t.eq(g, 2)
	end)
	t.test("caps at max level and discards overflow", function()
		local l, x, g = P.addXp(19, 0, 1e9)
		t.eq(l, 20); t.eq(x, 0); t.eq(g, 1)
		local l2, x2, g2 = P.addXp(20, 0, 500)
		t.eq(l2, 20); t.eq(x2, 0); t.eq(g2, 0)
	end)
end
```

- [ ] **Step 2: Run `lune run tests/run Progression`.** Expected: FAIL (module missing).
- [ ] **Step 3: Implement.**
  - `xpToNext(L) = math.floor(xpBase * L ^ xpExp)`.
  - `addXp` loops while `level < maxLevel` and `xp >= xpToNext(level)`.
  - At `maxLevel`, xp is forced to 0.
- [ ] **Step 4: Run tests.** Expected: all pass.
- [ ] **Step 5: Run the gate, then commit** `feat: progression xp curve`.

### Task A2: Skills and gems config, gem rules

**Files:**
- Create: `src/shared/Config/Skills.luau`, `src/shared/Config/Gems.luau`, `src/shared/Logic/GemRules.luau`
- Test: `tests/GemRules.spec.luau`

**Interfaces:**
- Produces:
  - `Config.Skills[skillId] = { id, key, displayName, tags: {[string]: true}, cost, cooldown, sockets: number, unlockLevel: number?, damage: number?, count: number?, radius: number?, range: number?, length: number?, width: number?, speed: number?, channel: number?, duration: number?, absorb: number?, pierce: boolean?, comboMul: number?, damageBonus: number?, regenBonus: number? }`. Fill every value from spec §4.2.
    - `basic` has `sockets = 0`, `comboMul = 1.6` and tag `Melee`.
    - `ascension` has `sockets = 0`, `unlockLevel = 10`, `damageBonus = 0.30` and `regenBonus = 0.50`.
    - Add `Config.Skills.order = { "basic", "blade_rain", "dawnbreaker", "crimson_lance", "hex_aegis", "ascension" }`. This is a plain array field. Iterate skills through `order`, not `pairs`.
  - `Config.Gems[gemId] = { id, displayName, fits: "Projectile" | "Attack" | "AoEOrProjectile" | "Any", group: string?, damageMul: number?, extraBlades: number?, extraLances: number?, spreadDeg: number?, element: string?, radiusMul: number?, impactExplosion: boolean?, cooldownMul: number? }`. Values come from spec §4.3. `multishot` has `extraBlades = 4`, `extraLances = 2`, `spreadDeg = 20` and `damageMul = 0.85`.
  - `GemRules.canSocket(skillId: string, slot: number, gemId: string, sockets: { [number]: string? }): (boolean, string?)`. The reason is one of `"no_sockets"`, `"bad_slot"`, `"tag"`, `"element"`, `"duplicate"`. `sockets` maps slot to gemId and ignores the target slot itself.
  - `GemRules.isAttack(skillId): boolean` (true when the skill has `damage`).

- [ ] **Step 1: Write the failing test**

```lua
local G = require("../src/shared/Logic/GemRules")
return function(t)
	t.test("projectile gem fits projectile skill", function()
		t.eq((G.canSocket("blade_rain", 1, "multishot", {})), true)
		t.eq((G.canSocket("crimson_lance", 2, "multishot", {})), true)
	end)
	t.test("tag mismatch", function()
		local ok, why = G.canSocket("hex_aegis", 1, "multishot", {})
		t.eq(ok, false); t.eq(why, "tag")
		local ok2, why2 = G.canSocket("hex_aegis", 1, "frost", {})
		t.eq(ok2, false); t.eq(why2, "tag")
	end)
	t.test("swift_cast fits any socketed skill", function()
		t.eq((G.canSocket("hex_aegis", 1, "swift_cast", {})), true)
	end)
	t.test("no sockets and bad slot", function()
		t.eq(select(2, G.canSocket("basic", 1, "swift_cast", {})), "no_sockets")
		t.eq(select(2, G.canSocket("ascension", 1, "swift_cast", {})), "no_sockets")
		t.eq(select(2, G.canSocket("blade_rain", 3, "swift_cast", {})), "bad_slot")
	end)
	t.test("one element per skill", function()
		local ok, why = G.canSocket("dawnbreaker", 2, "frost", { [1] = "flame" })
		t.eq(ok, false); t.eq(why, "element")
		t.eq((G.canSocket("dawnbreaker", 1, "frost", { [1] = "flame" })), true) -- replacing same slot
	end)
	t.test("no duplicate gem on one skill", function()
		t.eq(select(2, G.canSocket("blade_rain", 2, "multishot", { [1] = "multishot" })), "duplicate")
	end)
	t.test("wide_burst fits aoe or projectile, not line-only", function()
		t.eq((G.canSocket("crimson_lance", 1, "wide_burst", {})), true)
		t.eq((G.canSocket("dawnbreaker", 1, "wide_burst", {})), false)
	end)
end
```

- [ ] **Step 2: Run `lune run tests/run GemRules`.** Expected: FAIL.
- [ ] **Step 3: Implement the configs and `GemRules`.**
  - `fits` rules:
    - `Projectile`: the skill has tag `Projectile`.
    - `Attack`: `isAttack`.
    - `AoEOrProjectile`: the skill has `AoE` or `Projectile`.
    - `Any`: always fits.
  - Check order: `no_sockets`, then `bad_slot`, then `tag`, then `duplicate`, then `element`.
- [ ] **Step 4: Run tests.** Expected: all pass.
- [ ] **Step 5: Run the gate, then commit** `feat: skills and gems config with socket rules`.

### Task A3: Passive tree data and allocation

**Files:**
- Create: `src/shared/Config/Passives.luau`, `src/shared/Logic/PassiveTree.luau`
- Test: `tests/PassiveTree.spec.luau`

**Interfaces:**
- Produces:
  - `Config.Passives = { nodes: { [string]: Node }, startId = "start" }`, where `Node = { id, region: "might" | "swift" | "insight" | "core", kind: "start" | "small" | "notable" | "keystone", name: string, mods: { { stat: string, op: "add" | "mul", value: number } }, keystone: string?, x: number, y: number, links: { string } }`.
    - Valid `stat` names: `damage`, `maxHp`, `maxEnergy`, `energyRegen`, `cooldown`, `moveSpeed`, `critChance`, `critMul`, `aoe`, `shield`.
    - `cooldown` uses `op = "mul"` with a negative value.
    - `damage`, `aoe` and `shield` always use `op = "mul"`. `maxHp`, `maxEnergy`, `energyRegen`, `moveSpeed`, `critChance` and `critMul` always use `op = "add"`.
  - `PassiveTree.validateGraph(nodes): (boolean, { string })`
  - `PassiveTree.canAllocate(allocated: {[string]: true}, nodeId: string, points: number): (boolean, string?)`, where the reason is one of `"unknown"`, `"allocated"`, `"no_points"`, `"not_linked"`.
  - `PassiveTree.allocate(allocated, nodeId, points): ({[string]: true}, number)`. It returns a new set and the remaining points, and errors if it cannot allocate.
  - `PassiveTree.reset(allocated): ({[string]: true}, number)`. It returns `{ start = true }` and the number of points refunded (allocated count minus 1).
- Layout:
  - Start is at (0, 0).
  - Regions sit at 90° (might, up, y negative), 210° (swift) and 330° (insight).
  - Each region is a branching path out to radius about 600, with the keystone at the tip.
  - Node names are original Vietnamese. Keystones use `keystone = "blood_oath" | "endless_arsenal" | "radiant_mind"`, with blood_oath in might, endless_arsenal in swift and radiant_mind in insight.
  - Links are listed on both ends.

- [ ] **Step 1: Write the failing test**

```lua
local Tree = require("../src/shared/Logic/PassiveTree")
local Cfg = require("../src/shared/Config/Passives")
return function(t)
	t.test("graph is valid: 40 nodes, symmetric, connected, 3 keystones", function()
		local ok, errs = Tree.validateGraph(Cfg.nodes)
		t.ok(ok, table.concat(errs, "; "))
		local n, ks, per = 0, 0, { might = 0, swift = 0, insight = 0 }
		for _, node in Cfg.nodes do
			n += 1
			if node.kind == "keystone" then ks += 1 end
			if per[node.region] then per[node.region] += 1 end
		end
		t.eq(n, 40); t.eq(ks, 3)
		t.eq(per.might, 13); t.eq(per.swift, 13); t.eq(per.insight, 13)
	end)
	local function firstNeighbor()
		return Cfg.nodes[Cfg.startId].links[1]
	end
	local function farNode()
		for id, node in Cfg.nodes do
			if node.kind == "keystone" then return id end
		end
		return ""
	end
	t.test("allocate linked node spends a point", function()
		local alloc, left = Tree.allocate({ start = true }, firstNeighbor(), 3)
		t.ok(alloc[firstNeighbor()]); t.eq(left, 2)
	end)
	t.test("cannot allocate unlinked, owned, or without points", function()
		t.eq(select(2, Tree.canAllocate({ start = true }, farNode(), 5)), "not_linked")
		t.eq(select(2, Tree.canAllocate({ start = true }, firstNeighbor(), 0)), "no_points")
		t.eq(select(2, Tree.canAllocate({ start = true }, "start", 5)), "allocated")
		t.eq(select(2, Tree.canAllocate({ start = true }, "nope", 5)), "unknown")
	end)
	t.test("reset refunds everything except start", function()
		local alloc = Tree.allocate({ start = true }, firstNeighbor(), 1)
		local fresh, refunded = Tree.reset(alloc)
		t.eq(refunded, 1); t.ok(fresh.start); t.eq(fresh[firstNeighbor()], nil)
	end)
end
```

- [ ] **Step 2: Run `lune run tests/run PassiveTree`.** Expected: FAIL.
- [ ] **Step 3: Implement the data (40 nodes) and the logic.** `validateGraph` checks:
  - every link target exists
  - every link is symmetric
  - BFS from start reaches all nodes
  - exactly 1 keystone per region
  - the start node has kind `start`
- [ ] **Step 4: Run tests.** Expected: all pass.
- [ ] **Step 5: Run the gate, then commit** `feat: passive tree data and allocation rules`.

### Task A4: Stats and Damage

**Files:**
- Create: `src/shared/Logic/Stats.luau`, `src/shared/Logic/Damage.luau`
- Test: `tests/Stats.spec.luau`

**Interfaces:**
- Consumes: `Config.Passives`, plus the base stats in spec §4.1, which go in `Stats.BASE`.
- Produces:
  - `Stats.compute(level, allocated, buffs: { transformed: boolean }): Stats`. The `Stats` type is in spec §5.5.
  - `Damage.roll(base, stats, rng): (number, boolean)`
- Mapping from mod stat to Stats field:
  - `damage` goes to `damageMul` (base 1)
  - `cooldown` goes to `cooldownMul` (base 1)
  - `aoe` goes to `aoeMul` (base 1)
  - `shield` goes to `shieldMul` (base 1)
  - every other name maps to the same field
- Combining: `(base + sum(add)) * prod(1 + mul)` per field.
- Keystones: `blood_oath` multiplies `damageMul` by 1.4. A transform multiplies `damageMul` by 1.3 and `energyRegen` by 1.5. `keystones` is a set of the keystone ids found on allocated nodes.

- [ ] **Step 1: Write the failing test**

```lua
local Stats = require("../src/shared/Logic/Stats")
local Damage = require("../src/shared/Logic/Damage")
local Cfg = require("../src/shared/Config/Passives")
local function findNode(pred)
	for id, n in Cfg.nodes do if pred(n) then return id, n end end
	error("no node")
end
return function(t)
	t.test("base stats at level 1 and level scaling", function()
		local s = Stats.compute(1, { start = true }, { transformed = false })
		t.eq(s.maxHp, 100); t.eq(s.maxEnergy, 100); t.eq(s.energyRegen, 8); t.eq(s.moveSpeed, 18)
		t.near(s.critChance, 0.05); t.near(s.critMul, 1.5); t.near(s.damageMul, 1); t.near(s.cooldownMul, 1)
		t.eq(Stats.compute(5, { start = true }, { transformed = false }).maxHp, 140)
	end)
	t.test("additive hp node", function()
		local id, node = findNode(function(n)
			return n.kind == "small" and n.mods[1] and n.mods[1].stat == "maxHp" and n.mods[1].op == "add"
		end)
		local s = Stats.compute(1, { start = true, [id] = true }, { transformed = false })
		t.eq(s.maxHp, 100 + node.mods[1].value)
	end)
	t.test("keystone and transform multipliers", function()
		local bo = findNode(function(n) return n.keystone == "blood_oath" end)
		local s = Stats.compute(1, { start = true, [bo] = true }, { transformed = true })
		t.ok(s.keystones.blood_oath)
		local plain = Stats.compute(1, { start = true }, { transformed = false })
		local bonus = 1
		for _, m in Cfg.nodes[bo].mods do if m.stat == "damage" then bonus *= (1 + m.value) end end
		t.near(s.damageMul, plain.damageMul * bonus * 1.4 * 1.3, 1e-9)
		t.near(s.energyRegen, plain.energyRegen * 1.5, 1e-9)
	end)
	t.test("damage roll crit is deterministic", function()
		local s = Stats.compute(1, { start = true }, { transformed = false })
		local a, c = Damage.roll(100, s, function() return 0.01 end)
		t.near(a, 150); t.eq(c, true)
		local b, c2 = Damage.roll(100, s, function() return 0.9 end)
		t.near(b, 100); t.eq(c2, false)
	end)
end
```

- [ ] **Step 2: Run `lune run tests/run Stats`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run tests.** Expected: all pass.
- [ ] **Step 5: Run the gate, then commit** `feat: stats compute and damage roll`.

### Task A5: SkillResolver

**Files:**
- Create: `src/shared/Logic/SkillResolver.luau`
- Test: `tests/SkillResolver.spec.luau`

**Interfaces:**
- Consumes: `Config.Skills`, `Config.Gems`, `Stats`.
- Produces: `SkillResolver.resolve(skillId, gemIds: { string }, stats: Stats, transformed: boolean): SkillSpec`. The `SkillSpec` type is in spec §5.4 plus the contract addendum. Rules:
  - `damage = base * stats.damageMul * prod(gem.damageMul)`.
  - For `blade_rain` with `endless_arsenal`: count +6 and damage ×0.75.
  - `count = (skill.count or 1) + extraBlades` for `blade_rain`, or `+ extraLances` for `crimson_lance`, plus the endless_arsenal bonus.
  - `radius = (skill.radius or 0) * stats.aoeMul * prod(gem.radiusMul)`.
  - `cooldown = skill.cooldown * stats.cooldownMul * prod(gem.cooldownMul)`.
  - `element` is the element gem's element, else `"none"`.
  - `impactExplosion` is true if any gem sets it.
  - `spreadDeg` is set when `extraLances > 0`.
  - `absorb = skill.absorb * stats.shieldMul`.
  - `costResource = "hp"` when `blood_oath`.
  - `radiant = transformed`.
  - `ascension` with `radiant_mind` gets `duration = math.huge` and `drainPerSec = 6`.
  - `pierce = skill.pierce == true`.
  - `range`, `length`, `width`, `speed` and `duration` are copied from the config.

- [ ] **Step 1: Write the failing test**

```lua
local R = require("../src/shared/Logic/SkillResolver")
local Stats = require("../src/shared/Logic/Stats")
local Cfg = require("../src/shared/Config/Passives")
local function ks(name)
	for id, n in Cfg.nodes do if n.keystone == name then return id end end
	error(name)
end
local base = Stats.compute(1, { start = true }, { transformed = false })
return function(t)
	t.test("blade_rain base", function()
		local s = R.resolve("blade_rain", {}, base, false)
		t.eq(s.count, 12); t.near(s.damage, 18); t.near(s.cooldown, 6); t.eq(s.cost, 30)
		t.eq(s.costResource, "energy"); t.near(s.radius, 14); t.eq(s.element, "none"); t.eq(s.radiant, false)
	end)
	t.test("multishot adds blades and lowers damage", function()
		local s = R.resolve("blade_rain", { "multishot" }, base, false)
		t.eq(s.count, 16); t.near(s.damage, 18 * 0.85)
	end)
	t.test("multishot + endless_arsenal", function()
		local st = Stats.compute(1, { start = true, [ks("endless_arsenal")] = true }, { transformed = false })
		local s = R.resolve("blade_rain", { "multishot" }, st, false)
		t.eq(s.count, 22); t.near(s.damage, 18 * st.damageMul * 0.85 * 0.75, 1e-9)
	end)
	t.test("lance multishot spread", function()
		local s = R.resolve("crimson_lance", { "multishot" }, base, false)
		t.eq(s.count, 3); t.eq(s.spreadDeg, 20); t.eq(s.pierce, true)
	end)
	t.test("swift_cast, frost, wide_burst", function()
		t.near(R.resolve("blade_rain", { "swift_cast" }, base, false).cooldown, 4.5)
		t.eq(R.resolve("dawnbreaker", { "frost" }, base, false).element, "frost")
		local w = R.resolve("blade_rain", { "wide_burst" }, base, false)
		t.near(w.radius, 14 * 1.4); t.eq(w.impactExplosion, true)
	end)
	t.test("blood_oath pays with hp", function()
		local st = Stats.compute(1, { start = true, [ks("blood_oath")] = true }, { transformed = false })
		local s = R.resolve("crimson_lance", {}, st, false)
		t.eq(s.costResource, "hp"); t.eq(s.cost, 25)
	end)
	t.test("radiant flag and radiant_mind ascension", function()
		t.eq(R.resolve("blade_rain", {}, base, true).radiant, true)
		local st = Stats.compute(10, { start = true, [ks("radiant_mind")] = true }, { transformed = false })
		local a = R.resolve("ascension", {}, st, false)
		t.eq(a.duration, math.huge); t.eq(a.drainPerSec, 6)
		t.eq(R.resolve("ascension", {}, base, false).duration, 20)
	end)
	t.test("shield absorb scales", function()
		t.near(R.resolve("hex_aegis", {}, base, false).absorb, 80)
	end)
end
```

- [ ] **Step 2: Run `lune run tests/run SkillResolver`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full suite `lune run tests/run`.** Expected: all pass.
- [ ] **Step 5: Run the gate, then commit** `feat: skill resolver`.

### Task A6: Strings

**Files:**
- Create: `src/shared/Config/Strings.luau`
- Test: `tests/Strings.spec.luau`

**Interfaces:**
- Produces: `Strings` as a flat table of Vietnamese UI text. Keys:
  - `hp`, `energy`, `level`, `xp`, `points`
  - `passives`, `gems`, `reset`, `locked`, `unlockAt`
  - `summonBoss`, `bossName`
  - `reason_no_sockets`, `reason_bad_slot`, `reason_tag`, `reason_element`, `reason_duplicate`
  - `reason_unknown`, `reason_allocated`, `reason_no_points`, `reason_not_linked`
  - plus `skill_<id>` and `gem_<id>` for every skill and gem
- [ ] **Step 1:** Write a test that asserts every `reason_*` key exists and every id in `Skills.order` and every gem id has a `skill_`/`gem_` entry.
- [ ] **Step 2:** Run it and see it fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run it and see it pass.
- [ ] **Step 5: Run the gate, then commit** `feat: vietnamese strings`.

---

## Workstream B: Combat (server)

Owns: `src/shared/Net.luau`, `src/shared/Config/Enemies.luau`, `src/shared/Config/Anims.luau`, `src/server/**`.

These modules use the Roblox API, so Lune cannot test them. Their verification is the gate (`selene src`, `rojo build`) plus the Studio playtest in Phase 2. Keep the Roblox glue thin: put any branching rule that can be pure (for example the cooldown check or the cast rate limiter) in a small pure module under `src/server/Rules/`, and test it with Lune the same way. Lune can require server files by relative path when they contain no Roblox globals.

### Task B1: Net and server boot

**Files:**
- Create: `src/shared/Net.luau`, `src/shared/Config/Anims.luau`, `src/server/Main.server.luau`, `src/server/Services/` (empty service stubs exporting `start()`)

**Interfaces:**
- Produces: contract addendum items 6, 8 and 9.
- `Net.server()` creates a `Folder` `ReplicatedStorage.Remotes` with one `RemoteEvent` per name and returns them.
- `Net.client()` uses `WaitForChild` with a 10 s timeout and errors with the missing name.

- [ ] Steps:
  - Write the modules.
  - Run `selene src` and `rojo build -o AstralArmory.rbxl`.
  - Commit `feat: remotes and server boot`.

### Task B2: Pure rules and tests

**Files:**
- Create: `src/server/Rules/Cooldowns.luau`, `src/server/Rules/RateLimit.luau`
- Test: `tests/ServerRules.spec.luau`

**Interfaces:**
- `Cooldowns.ready(cooldowns, skillId, now): boolean`
- `Cooldowns.start(cooldowns, skillId, now, duration)`
- `RateLimit.new(maxPerSecond): limiter`, where `limiter:allow(now): boolean` uses a sliding 1 s window.

- [ ] **Step 1: Write the test.**

```lua
local C = require("../src/server/Rules/Cooldowns")
local RL = require("../src/server/Rules/RateLimit")
return function(t)
	t.test("cooldown gate", function()
		local cd = {}
		t.ok(C.ready(cd, "blade_rain", 10))
		C.start(cd, "blade_rain", 10, 6)
		t.eq(C.ready(cd, "blade_rain", 15.9), false)
		t.ok(C.ready(cd, "blade_rain", 16))
	end)
	t.test("rate limit 20/s", function()
		local l = RL.new(20)
		for i = 1, 20 do t.ok(l:allow(1 + i * 0.001)) end
		t.eq(l:allow(1.05), false)
		t.ok(l:allow(2.2))
	end)
end
```

- [ ] **Step 2:** Run it and see it fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run it and see it pass.
- [ ] **Step 5: Run the gate, then commit** `feat: server cooldown and rate limit rules`.

### Task B3: PlayerDataService

**Files:**
- Create: `src/server/Services/PlayerData.luau`

**Interfaces:**
- `PlayerData.start()`
- `PlayerData.get(player): Profile?`, where `Profile = { level, xp, points, allocated, gems, sockets, nextGemId }`
- `PlayerData.onChanged(player)` sends `StateSync`, merging the live combat fields that `Combat.getLive(player)` provides.
- `PlayerData.grantXp(player, amount)`
- `PlayerData.grantGem(player, gemId)`

Behavior (spec §5.7):
- DataStore `AstralArmory_v1`, key `"u_" .. userId`.
- Every call is in `pcall`. On failure, warn once and keep the session in memory.
- New players get the default profile with 1 free starter gem of each element.
- Autosave every 60 s and on `PlayerRemoving`. Use `game:BindToClose` to save everyone.
- `StateSync` is coalesced: mark the player dirty and flush at most 10 times per second from a Heartbeat accumulator.
- Debug: in Studio only (`RunService:IsStudio()`), chatting `/lvl N` sets the level and adds the matching points.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: player data service`.

### Task B4: CombatService

**Files:**
- Create: `src/server/Services/Combat.luau`

**Interfaces:**
- `Combat.start()`
- `Combat.getLive(player): { hp, maxHp, energy, maxEnergy, cooldowns, transformed, transformEndsAt }`
- `Combat.damageEnemy(enemyModel, amount, crit, element, attacker)`, used by its own skills.
- `Combat.damagePlayer(player, amount)` respects `hex_aegis` absorb. Enemy and boss services call it.
- Enemy and boss hooks: `Combat.registerTarget(model, { onHit = fn })`.

Behavior:
- On spawn: weld `SwordModel.build()` to RightHand. Set `Humanoid.WalkSpeed = stats.moveSpeed` and `MaxHealth = stats.maxHp`.
- Energy regen runs on Heartbeat.
- `CastSkill` validation follows spec §5.2.
- Resolve through `SkillResolver` with the sockets' gemIds.
- Hits:
  - `basic`: an 8-stud box in front of the character. A 3-step combo with a 1 s reset; the third hit is ×1.6.
  - `blade_rain`: after a 0.6 s delay, `GetPartBoundsInRadius(target, radius)`. Each blade deals damage to the targets inside its own 3-stud impact point, so more blades means more total damage. Blade points come from a `Random.new(seed)` layout inside the radius, the same algorithm the client uses (export it from `Shared/Logic/BladeLayout.luau`, see Task C4).
  - `dawnbreaker`: after the `channel` delay, a box of `length × width` along the aim direction.
  - `crimson_lance`: for each lance in the spread, a raycast step simulation at `speed` up to `range`, damaging every enemy it passes once (pierce).
  - `hex_aegis`: sets the absorb pool for `duration`.
  - `ascension`: sets transformed and recomputes stats. With `drainPerSec`, drain Energy until it reaches 0.
- Elements:
  - frost: `WalkSpeed` ×0.7 for 2 s
  - flame: 20% of the hit as 4 ticks over 3 s
  - storm: chain to the 2 nearest other enemies within 15 studs for 50%
  - `impactExplosion`: an extra radius-6 hit for 30% at each impact point
- Fire `SkillFx` with `{ skillId, casterUserId, origin, target, spec, seed, serverTime }` before applying delayed hits.
- Every damage call fires `DamagePopup`.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: combat service`.

### Task B5: EnemyService and enemy config

**Files:**
- Create: `src/shared/Config/Enemies.luau`, `src/server/Services/Enemies.luau`

**Interfaces:**
- `Config.Enemies.hollow_knight` and `.eclipse_warden` hold the numbers and formulas in spec §4.6 as functions of level: `hp(L)`, `damage(L)`, `xp(L)`.
- `Enemies.start()`
- `Enemies.spawnRig(opts: { name, scale, bodyColor, eyeColor }): Model`, which Boss reuses.

Behavior:
- Build a rig with `Players:CreateHumanoidModelFromDescription(HumanoidDescription.new(), Enum.HumanoidRigType.R15)`. Recolor its parts and add 2 neon eye parts welded to the head.
- Load `Config.Anims` walk and slash through an Animator, inside `pcall`.
- Keep 10 alive: 4 at InnerSpawns (levels 1–3) and 6 at OuterSpawns (levels 4–8).
- One 0.2 s loop drives all AI:
  - target the nearest living player within 60 studs
  - `MoveTo` toward the target
  - attack within 5 studs on a 1.2 s cooldown through `Combat.damagePlayer`
- On death: give XP to every player who hit it in the last 10 s, roll a 12% gem drop for the killer, then respawn after 8 s.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: enemy service`.

### Task B6: BossService

**Files:**
- Create: `src/server/Services/Boss.luau`

**Interfaces:**
- `Boss.start()`

Behavior (spec §4.6):
- Triggers: the altar `SummonPrompt` and the `SummonBoss` remote. Require level ≥ 8 and no boss alive, with a 60 s cooldown after a kill.
- Spawn at `BossSpawn` with `Enemies.spawnRig({ scale = 3 })`.
- Phase 1, every 5 s:
  - fire `BossFx { event = "telegraph", position, radius = 16, delay = 1.2 }`
  - wait 1.2 s
  - fire `BossFx { event = "slam", position, radius = 16 }`
  - damage players inside the radius
- Phase 2 at 50% HP, once:
  - fire `BossFx { event = "enrage" }`
  - WalkSpeed ×1.25
  - each cycle, also fire 8 `BossFx { event = "blades", position, radius = 5, delay = 1 }` near players, each dealing 25 after its delay
- On death:
  - fire `BossFx { event = "defeated", position }`
  - give 2000 XP to every contributor and 2 gems

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: boss service`.

---

## Workstream C: VFX (client)

Owns: `src/shared/VfxPalette.luau`, `src/shared/Config/AssetIds.luau`, `src/shared/Models/**`, `src/shared/Logic/BladeLayout.luau` (plus `tests/BladeLayout.spec.luau`), `src/client/Vfx/**`, `tools/gen_textures.py`, `assets/textures/**`.

### Task C1: Procedural textures

**Files:**
- Create: `tools/gen_textures.py`, `assets/textures/*.png`

Generate the 9 textures in spec §5.9, 512×512 RGBA except the flipbook, which is 2048×2048 with 4×4 frames:
- `glow_soft`: radial falloff.
- `glow_star`: 4-point star.
- `spark`: thin streak.
- `smoke_soft`: Perlin-like value noise, blurred, radial mask.
- `ring_runes`: a thin double ring plus 24 original glyph shapes made from line segments.
- `hex_cell`: hexagon outline with soft inner glow.
- `slash_arc`: crescent with tapered ends.
- `beam_core`: horizontal gradient bright center.
- `explosion_flipbook_4x4`: expanding fireball noise over 16 frames.

All textures are white or greyscale with alpha, so Roblox tints them with Color.

- [ ] Steps:
  - Write the script.
  - Run `python tools/gen_textures.py`.
  - Verify with `python -c "from PIL import Image;import glob;[print(f,Image.open(f).size,Image.open(f).mode) for f in glob.glob('assets/textures/*.png')]"`. Expected: 9 files, all RGBA, sizes as above.
  - Commit `feat: procedural vfx textures`.

### Task C2: Palette, asset ids, weapon models, blade layout

**Files:**
- Create: `src/shared/VfxPalette.luau`, `src/shared/Config/AssetIds.luau`, `src/shared/Models/SwordModel.luau`, `src/shared/Models/LanceModel.luau`, `src/shared/Logic/BladeLayout.luau`
- Test: `tests/BladeLayout.spec.luau`

**Interfaces:**
- `VfxPalette.get(element: string, radiant: boolean): { core: Color3, glow: Color3, accent: Color3 }`
  - none: gold-white
  - frost: ice blue
  - flame: orange-red
  - storm: violet
  - radiant: shifts toward white-gold with higher brightness
- `AssetIds[name]` gives the custom id or a fallback.
  - Fallbacks are built-in textures: `rbxasset://textures/particles/sparkles_main.dds`, `rbxasset://textures/particles/smoke_main.dds`, `rbxasset://textures/particles/fire_main.dds`.
  - Custom ids start as `nil` with a comment saying they are filled after upload.
  - Export `AssetIds.tex(name): string`.
- Models: contract addendum item 5. The sword is about 4.5 studs: a blade of 2 thin parts with a Neon edge, a guard and a grip, all Massless, CanCollide false. The lance is a 7-stud spear with a crimson Neon tip.
- `BladeLayout.points(seed: number, count: number, radius: number): { { x: number, z: number, delay: number } }` is pure. It uses its own deterministic LCG (do not use `Random`, so Lune can test it). Points lie inside the radius and delays are 0..0.35 s.

- [ ] **Step 1: Write the test.**

```lua
local BL = require("../src/shared/Logic/BladeLayout")
return function(t)
	t.test("deterministic and inside radius", function()
		local a = BL.points(42, 16, 14)
		local b = BL.points(42, 16, 14)
		t.eq(#a, 16)
		for i, p in a do
			t.eq(p.x, b[i].x); t.eq(p.z, b[i].z)
			t.ok(p.x * p.x + p.z * p.z <= 14 * 14 + 1e-9)
			t.ok(p.delay >= 0 and p.delay <= 0.35)
		end
		t.ok(BL.points(7, 16, 14)[1].x ~= a[1].x)
	end)
end
```

- [ ] **Step 2:** Run it and see it fail.
- [ ] **Step 3:** Implement all files.
- [ ] **Step 4:** Run it and see it pass.
- [ ] **Step 5: Run the gate, then commit** `feat: vfx palette, asset ids, weapon models, blade layout`.

### Task C3: VFX core

**Files:**
- Create: `src/client/Vfx/init.luau`, `src/client/Vfx/Common.luau`, `src/client/Vfx/Impact.luau`

**Interfaces:**
- `Vfx.start()` connects `SkillFx`, which dispatches on `skillId` to `Vfx/<Module>.play(event)`, and `BossFx`, which goes to `BossTelegraph.play(evt)`.
- `Common`:
  - `pool(template)` with `:get()` and `:release(obj)`
  - `cleanup(instance, seconds)` through Debris
  - `shake(intensity, duration)`, which applies only if the local character is within 30 studs or is the caster
  - `flash(color, duration)`, a fullscreen frame tween
  - `emitter(parent, props)`, a ParticleEmitter factory with sane defaults and the budget check
  - `tween(obj, info, goal)`
  - `delayAt(serverTime, offset, fn)`, which schedules relative to `workspace:GetServerTimeNow()` so late clients stay in sync
- `Impact.play(position, palette, scale, explosion: boolean)` covers sparks, a ground ring, a short PointLight and the flipbook burst when `explosion`.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: vfx core`.

### Task C4: Mưa Kiếm Tinh Tú (BladeRain)

**Files:** `src/client/Vfx/BladeRain.luau`

Sequence:
1. At 0 s, a rune ring decal (`ring_runes`) spins open 25 studs above the target, tinted `palette.glow`.
2. At 0–0.35 s, for each `BladeLayout.points(seed, spec.count, spec.radius)`, a pooled blade (cloned from `SwordModel` without the grip) fades in point-down above its point. It has a Trail between its attachments and a faint glint ParticleEmitter (`glow_star`).
3. At 0.6 s + the point's delay, the blade drops to the ground in 0.12 s (Quad In) and calls `Impact.play(scale 0.6)`. Every 4th impact adds a small shake.
4. At 1.4 s, the ring fades out and everything is cleaned up by 2.5 s.

`spec.radiant` adds a second, larger ring and white-gold edge light. `spec.element` tints everything through the palette.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: blade rain vfx`.

### Task C5: Cột Sáng Bình Minh (Dawnbreaker)

**Files:** `src/client/Vfx/Dawnbreaker.luau`

Sequence:
1. Channel (0 → `spec.channel`, 1.2 s): `glow_soft` particles stream from a 6-stud sphere into the caster's sword (the emitter shape is inward), a rising hum light, and the sword edge brightens.
2. Release: a 0.1 s white flash (local caster only) and a vertical slash arc (`slash_arc` Beam).
3. A light wall moves along the aim direction, `length × width × 12` tall. It is built from 3 layered Beams (`beam_core`) between two attachments that sweep from origin to the end over 0.25 s, with ground scorch decals along the path.
4. A strong shake.
5. Fade out over 0.6 s.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: dawnbreaker vfx`.

### Task C6: Giáo Huyết (CrimsonLance)

**Files:** `src/client/Vfx/CrimsonLance.luau`

Sequence:
1. 0.15 s: a crimson glyph spiral materializes the lance in the caster's hand (`LanceModel`).
2. Throw: the lance flies along each spread direction at `spec.speed`. Each lance has a double helix trail (2 attachments orbiting the shaft) and a red smoke wake.
3. On reaching range, a red shockwave ring plus `Impact.play`.
4. When the server confirms hits through `DamagePopup` near the path, spawn small piercing bursts there. This is optional; only do it if the hits are cheap to correlate.

The element tints the helix. Storm adds lightning arcs (zig-zag Beams), frost adds ice shards, and flame adds embers.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: crimson lance vfx`.

### Task C7: Khiên Lục Giác (HexAegis) and BasicSlash

**Files:** `src/client/Vfx/HexAegis.luau`, `src/client/Vfx/BasicSlash.luau`

HexAegis:
- A hemisphere dome of radius 7 around the caster, made of about 30 hexagon `ImageLabel`s on `SurfaceGui`s, or Parts with the `hex_cell` decal, in a geodesic-ish arrangement. Build it at runtime and pool it.
- A rotating rune ring on the ground.
- It pulses when `DamagePopup` shows the caster being hit.
- At `duration`, the hexes shatter outward with spin and fade.

BasicSlash:
- An arc Trail on the sword for the swing window, plus a `slash_arc` Beam flash.
- If the caster is the local player, play `Config.Anims.slash` on their Animator.
- The third combo hit is bigger.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: hex aegis and basic slash vfx`.

### Task C8: Thăng Hoa (Ascension) and BossTelegraph

**Files:** `src/client/Vfx/Ascension.luau`, `src/client/Vfx/BossTelegraph.luau`

Ascension:
- Burst: a ground shockwave ring, a vertical light pillar for 0.8 s, and a flash.
- Sustained for `duration`, or until `StateSync` reports `transformed = false`:
  - flame-like aura from 2 ParticleEmitters per limb attachment, rising, white-gold
  - a Highlight with a gold outline
  - floating sparks
  - the sword Neon turns white
- End: the aura implodes and fades.
- Clients that join late or miss the event still show the aura from `transformed` in `StateSync`. Export `Ascension.setActive(character, active)` for the UI to call.

BossTelegraph:
- `telegraph`: a red ground circle (decal ring) that fills over `delay`.
- `slam`: a dust shockwave and a strong shake within 40 studs.
- `blades`: a dark blade falls with a purple trail and a small impact.
- `enrage`: a persistent dark-violet aura on the boss model plus a short screen tint.
- `defeated`: the boss breaks into light particles plus a golden pillar.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: ascension and boss telegraph vfx`.

---

## Workstream D: Builder (arena)

Owns: `tools/build_map.luau`, `assets/Arena.rbxm`, and the `Lighting` and `Workspace.Arena` entries in `default.project.json`.

### Task D1: Arena generator

**Files:**
- Create: `tools/build_map.luau`, `tools/count_parts.luau`
- Generate: `assets/Arena.rbxm`

**Interfaces:**
- Produces: contract addendum item 4.

Use Lune's `@lune/roblox`: `Instance.new`, the `CFrame`, `Vector3`, `Color3` and `Enum` datatypes, and `roblox.serializeModel({ arena })`, written with `@lune/fs`. Check the API against the Lune 0.11.1 docs and fix mismatches.

Geometry:
- Platform: a 220-stud circular platform from about 24 large wedge or cylinder segments, Slate material, dark grey-blue.
- An inner raised ring and a rune circle (Neon thin parts in a ring, CanCollide false).
- 10 broken pillars at radius 95, each 3–5 stacked Cobblestone parts with random tilt from a fixed seed.
- Floating rock debris below the platform: 30 low-detail parts.
- The boss dais at the north (+Z) edge, raised 4 studs, with the altar.
- A `PlayerSpawn` at the south edge.
- Inner spawn pads at radius 35–50 and outer at radius 75–100.
- `Bounds`: 16 tall invisible walls around the rim.
- Decorative parts are Anchored, with CanCollide, CanTouch and CanQuery false. Floor parts are CanCollide true.

- [ ] Steps:
  - Write the generator.
  - Run `lune run tools/build_map`.
  - Run `lune run tools/count_parts`, which deserializes the rbxm and counts `BasePart` descendants and asserts the required children exist. Expected: prints a count under 2000 and `contract ok`.
  - Commit `feat: arena generator`.

### Task D2: Lighting and project mapping

**Files:**
- Modify: `default.project.json`

Changes:
- Add `"Arena": { "$path": "assets/Arena.rbxm" }` under `Workspace`, and add `"FallenPartsDestroyHeight": -50` to the Workspace `$properties`, so a player who falls off dies and respawns.
- Lighting `$properties`:
  - `Technology` Future
  - `ClockTime` 17.6
  - `Brightness` 2.2
  - `EnvironmentDiffuseScale` 0.6
  - `EnvironmentSpecularScale` 0.8
  - `OutdoorAmbient` [0.35, 0.3, 0.4]
- Lighting children:
  - `Atmosphere` (Density 0.32, Haze 1.6, Color warm, Decay purple)
  - `Bloom` (Intensity 0.6, Size 28, Threshold 1.6)
  - `ColorCorrection` (Contrast 0.12, Saturation 0.08, TintColor warm)
  - `SunRays` (Intensity 0.06)
  - `Sky`, using the default sky with `CelestialBodiesShown` true
- [ ] Steps:
  - Edit the file.
  - Run `rojo build -o AstralArmory.rbxl`.
  - Commit `feat: lighting and arena mapping`.

---

## Workstream E: UI and input (client)

Owns: `src/client/UI/**`, `src/client/Input/**`, `src/client/Main.client.luau`.

### Task E1: Client boot and input

**Files:**
- Create: `src/client/Main.client.luau`, `src/client/Input/init.luau`, `src/client/Input/Mobile.luau`

Behavior (contract addendum item 7):
- PC: M1 goes to `basic`; Q, E, R, F and T go to their skills; P goes to `ui.togglePassives()`; G goes to `ui.toggleGems()`.
- Aim target: `mouse.Hit.Position`. On touch, it is the camera center ray hit or 40 studs ahead.
- Client-side throttle: ignore presses while the skill's cooldown shown in state is active (the server still validates).
- Mobile: `ContextActionService:BindAction` with touch buttons, then reposition them in a fan layout bottom-right. Use `SetTitle` with the key letter.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: client boot and input`.

### Task E2: HUD and damage numbers

**Files:**
- Create: `src/client/UI/init.luau`, `src/client/UI/Hud.luau`, `src/client/UI/DamageNumbers.luau`, `src/client/UI/Theme.luau`

Behavior:
- `UI.start()` returns `ui` (contract addendum item 7), keeps the latest `PlayerState` and calls `Vfx.Ascension.setActive` on transform changes.
- `Theme`: a dark translucent panel (`#120E1A` at 0.25 transparency), gold accent `#F2C14E`, red HP `#D6455D`, blue Energy `#4FA3FF`, purple XP `#9B6BFF`. Font `GothamBold` or `Montserrat` from `Font.fromName`.
- HUD (bottom center):
  - HP and Energy bars that tween
  - an XP bar with "Cấp N"
  - 5 skill slots (Q E R F T) with an icon letter, the Vietnamese name on hover, a cooldown radial sweep from `cooldowns[id] - serverClock`, and a lock overlay plus "Mở ở cấp 10" for `ascension` below level 10
  - top-left: free points badge "Điểm: N"
- DamageNumbers: a BillboardGui at the position that rises and fades over 0.8 s. Color comes from the element through `VfxPalette`. Crits are bigger with "!" appended.
- `UIScale` = `clamp(viewport.Y / 900, 0.7, 1.2)`.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: hud and damage numbers`.

### Task E3: Passive tree screen

**Files:**
- Create: `src/client/UI/PassiveTree.luau`

Behavior:
- A fullscreen dark overlay with a canvas Frame.
- Nodes come from `Config.Passives` at `x, y`:
  - small: 18 px circle
  - notable: 30 px
  - keystone: 44 px with a ring
  - start: 24 px
- Colors by region:
  - might: red `#E0524F`
  - swift: green `#5BD08A`
  - insight: blue `#5AA7FF`
- Links are rotated thin Frames between node centers, bright when both ends are allocated.
- Interaction:
  - drag to pan, wheel or pinch to zoom (0.5–1.6)
  - hover tooltip with name and mods text
  - click calls `PassiveTree.canAllocate` locally; if OK, fire `AllocatePassive`, otherwise show the reason through `Strings`
  - a Reset button fires `ResetPassives`
  - a header shows "Điểm còn lại: N"
- Re-render node states on every `StateSync`.

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: passive tree screen`.

### Task E4: Gem screen

**Files:**
- Create: `src/client/UI/Gems.luau`

Behavior:
- Left: an inventory grid of `state.gems`, with a colored gem tile per gem id and the name.
- Right: one row per skill with `sockets > 0`, showing 2 socket slots with the socketed gem or empty.
- Flow:
  - select a gem, then click a socket
  - check `GemRules.canSocket` locally; if OK, fire `SocketGem(skillId, slot, gem.id)`
  - while a gem is selected, sockets it cannot go in are dimmed, with the reason tooltip from `Strings`
  - right-click or long-press a filled socket fires `SocketGem(skillId, slot, nil)`

- [ ] Steps:
  - Implement.
  - Run the gate.
  - Commit `feat: gem screen`.

---

## Phase 2: Integration (after all workstreams)

### Task F1: Integrate and pass every gate

- [ ] Run `export PATH="/d/Tools/bin:$PATH"; stylua src tests tools && selene src && lune run tests/run && rojo build -o AstralArmory.rbxl`.
- [ ] Fix every error at the seam: contract mismatches, missing requires, type errors flagged by selene. Read both sides against spec §5 and the addendum before changing either.
- [ ] Grep for contract names on both sides, to confirm every remote name used on the client exists in `Net.names` and every `spec.*` field read by the VFX exists in `SkillResolver`'s output.
- [ ] Commit `fix: integration seams`.

### Task F2: Studio playtest (Claude, through the built-in Studio MCP)

- [ ] `rojo serve`, connect the Rojo plugin, or open `AstralArmory.rbxl`.
- [ ] Run the spec §6 checklist. Save a screenshot of each item to `docs/screenshots/NN-name.png`.
- [ ] Fix any runtime errors from `get_console_output`. Each fix gets its own commit.

### Task F3: Review

- [ ] Run one code-review agent over the whole repo against the spec, then fix the blocking findings.

### Task F4: Ship

- [ ] Write `README.md`: what the demo is, a controls table, the architecture diagram (text), how to build (`rojo build`), how to test (`lune run tests/run`), and a screenshots section.
- [ ] Write `docs/reel-script.md`: a 75-second shot list (time, action, camera, what it shows).
- [ ] Create the GitHub repo, push, and tag `v1.0`.
