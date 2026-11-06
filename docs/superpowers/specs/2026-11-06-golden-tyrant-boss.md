# Boss rework: Bạo Quân Hoàng Kim (Golden Tyrant)

Date: 2026-11-06. Status: approved in chat. This document replaces the boss parts of spec §4.6 and the `BossFx` contract in §5.2.

The boss is an original "king of treasures" archetype: golden armor, an endless armory, and a devastating finisher. It must not copy any existing character's name, armor design, or signature moves. The enemy id stays `eclipse_warden` so saves and config keys do not change. The display name and model are new.

## 1. Look (`src/shared/Models/TyrantArmor.luau`, built on the server)

- `TyrantArmor.dress(rig: Model)` decorates an R15 rig made by `Enemies.spawnRig`. The server calls it once at spawn, so everything replicates.
- Scale: 1.6× the player. Today the boss is ×3, which reads as a blob. The model is named `GoldenTyrant`, and its Humanoid DisplayName is "Bạo Quân Hoàng Kim".
- Skin: a warm tone. Body base colors: dark obsidian undersuit (`#1A1420`) under gold plates (`#E8B84A`, Metal material, Reflectance 0.2), with crimson accents (`#8E1B24`).
- Armor is built from Parts and WedgeParts, welded with WeldConstraint to each body part. Every armor part is Massless with CanCollide, CanTouch and CanQuery off.
  - Chest: a breastplate (layered plates) and back plate on UpperTorso, plus a fauld (belt with hanging plates) on LowerTorso.
  - Arms: pauldrons with 2–3 stacked plates on the upper arms, vambraces on the lower arms, gauntlets on the hands.
  - Legs: tassets on the upper legs, greaves on the lower legs, sabatons on the feet.
  - Head and face: hair as spiky swept-back gold wedges, eyes as two thin neon crimson slits.
  - Crown: a gold circlet on the head, plus a floating halo ring of 8 small gold blades behind the head, held up by an invisible anchor.
- Cape: 3 crimson panels hinged at the shoulders (HingeConstraint or Weld plus a client-side sway), gold trim, and a darker inner layer.
- Weapon: a part-built gold longsword in the right hand.
- Budget: at most 140 parts in total. Neon is only on the eyes, the halo edge and the sword edge.
- Phase 2: the eyes brighten, the cape trim turns neon, and a gold-crimson aura emitter is added. The client adds these on the `enrage` event.

## 2. Combat (`src/server/Services/Boss.luau`, `src/shared/Config/Enemies.luau` → `eclipse_warden`)

Numbers live in config. HP 4000, XP 2000, 2 gem drops, summon level 8, summon range 20, and altar cooldown 60 s stay as they are.

The boss picks its next action with a pure planner, `src/shared/Logic/BossPlan.luau` (Lune-tested):

```lua
BossPlan.next(state: { phase: 1|2, distance: number, now: number, cooldowns: {[string]: number} }): string
-- returns "melee" | "volley" | "armory" | "chains" | "ultimate"
```

The rules, checked in this order:
1. `ultimate`: phase 2 and off cooldown (cooldown 22 s; the first use comes 4 s after phase 2 starts).
2. `chains`: off cooldown (12 s) and distance ≤ 40.
3. `armory`: off cooldown (14 s; 10 s in phase 2).
4. `melee`: distance ≤ 9.
5. Otherwise `volley`.

Between actions the boss walks toward its target. The action cadence is every 1.6 s in phase 1 and every 1.2 s in phase 2.

| Action | Behaviour | Numbers |
|---|---|---|
| `melee` | A sword cut in front of the boss, with a 0.35 s windup. | Box 10×6 studs, damage 20 |
| `volley` (ranged basic) | The boss snaps its fingers. 3 portals open behind it and 3 weapons fly at the target's position as it was 0.6 s after cast. | 12 damage each, radius 3 |
| `armory` | 10 portals in phase 1, 16 in phase 2, open in a fan behind the boss. Each fires a weapon at a player's position in sequence, 0.12 s apart. Each impact has a 0.5 s line telegraph. | 18 damage each, radius 4 |
| `chains` | A 1.0 s red ring telegraph at the target's feet, radius 6. Players inside are rooted for 1.5 s (WalkSpeed and JumpPower set to 0 on the server, restored after). Then the boss does an instant `melee` lunge toward the rooted player. | Root damage 10 |
| `ultimate` | The boss raises a 3-segment counter-rotating blade. 2.5 s charge, then fires a cone from the boss along the aim at charge start: length 70, half-angle 22°. Players behind a pillar (any blocking raycast against the Arena) take no damage. | Damage 70 |
| `enrage` | Fires once at 50% HP: phase 2, speed ×1.25. | |

Players hit by the boss take damage through `Combat.damagePlayer` as now (hex_aegis absorbs it).

## 3. `BossFx` contract (server → all clients), replaces the old events

Every payload includes `model: Model` (the boss, a replicated Instance) and `event`:

| event | extra fields |
|---|---|
| `spawn` | `position` |
| `pose` | `clip: string` (a PoseClips name; the client plays it on `model`) |
| `melee` | `origin: Vector3, dir: Vector3, delay: number` (windup) |
| `volley` | `portals: {Vector3}, targets: {Vector3}, delay: number, interval: number` |
| `armory` | `portals: {Vector3}, targets: {Vector3}, delay: number, interval: number, telegraph: number` |
| `chains` | `position: Vector3, radius: number, delay: number, duration: number` |
| `ultimate_charge` | `origin: Vector3, dir: Vector3, duration: number, length: number, angle: number` |
| `ultimate_fire` | `origin: Vector3, dir: Vector3, length: number, angle: number` |
| `enrage` | none |
| `defeated` | `position` |

The server fires the matching `pose` before or with each action: `boss_idle` on spawn, then `boss_melee`, `boss_volley`, `boss_armory`, `boss_chains`, `boss_ultimate_charge`, `boss_ultimate_fire`, `boss_enrage` and `boss_defeated`.

## 4. Animation (`src/shared/Config/PoseClips.luau`, `Logic/PoseClip.luau`, `src/client/Vfx/Poses.luau`)

- `Clip` gets `loop: boolean?`. A looping clip wraps its time and has weight 1 after blend-in. `Poses.play` on a new clip replaces it, and a looping idle resumes after any one-shot clip ends.
- Clips:
  - `boss_idle` (loop): regal stance. Arms crossed or left hand on the hip, chest out, slow breathing sway.
  - `boss_melee`: a big diagonal cut.
  - `boss_volley`: a finger snap with the left hand raised.
  - `boss_armory`: both arms spread wide and back, palms open, while the portals open.
  - `boss_chains`: the right hand thrust forward, then a fist pulled back.
  - `boss_ultimate_charge`: the blade raised overhead, held for 2.5 s with a subtle tremble.
  - `boss_ultimate_fire`: a two-handed thrust forward.
  - `boss_enrage`: head thrown back, arms out.
  - `boss_defeated`: a kneel, using a forward torso lean and lowered arms.
- `Poses.forBossFx(evt)` plays `evt.clip` on `evt.model` when `event == "pose"`.

## 5. VFX (`src/client/Vfx/BossTelegraph.luau` is replaced by `src/client/Vfx/Boss/` modules)

The palette is gold (`#F5C542`), white-gold and crimson (`#B3122E`). Use the uploaded textures: `ring_runes`, `glow_soft`, `glow_star`, `spark`, `beam_core`, `slash_arc`, `smoke_soft`, `explosion_flipbook_4x4`.

- **Portal:** a vertical gold ripple disc (ring_runes plus a soft glow plus 2 expanding rings) that opens in 0.15 s. A part-built weapon (sword, spear or axe, chosen at random) slides out tip-first, then launches with a gold Trail. On impact it sticks in the ground for 1 s, then dissolves into sparks. Use small impact rings (`Impact.play`).
- **Line telegraph** (armory): a thin glowing ground line from the portal's ground projection to the target, which fills over `telegraph`.
- **melee:** a gold crescent arc (reuse the BasicSlash arc helper, scaled ×1.6), plus a ground crack.
- **chains:** a red rune ring filling over `delay`. Then 4–6 gold chains (Beams with a chain-link look, or segment parts) erupt from the ground ring and wrap toward the center. A gold bind ring stays on the rooted player for `duration`.
- **ultimate_charge:**
  - a part-built 3-segment cylindrical blade in the boss's right hand, the segments counter-rotating;
  - a crimson and gold spiral wind (Beams in a helix plus ParticleEmitters with dust and debris pulled inward);
  - a cone telegraph decal on the ground, filling over `duration`;
  - rising camera shake.
- **ultimate_fire:**
  - a huge spiral beam along the cone: layered beam_core Beams twisting, plus a crimson-gold vortex rings train;
  - a screen flash and a strong shake within 60 studs;
  - ground scorch along the path.
  - It cleans up within 2 s.
- **enrage:** the gold-crimson aura on the boss (glow_soft and aura_flame emitters), cape-trim neon, and a short screen tint.
- **defeated:** the boss breaks into gold particles, then a golden pillar of light.

The performance rules from spec §5.8 apply. Every effect cleans itself up.

## 5b. Boss health bar (`src/client/UI/BossBar.luau`, booted from `UI/init.luau`)

A wide boss bar centered at the bottom of the screen, above the HUD hotbar, in the style of soulslike games:

- The boss name sits above the bar's left end ("Bạo Quân Hoàng Kim"), in the HUD font, with a subtle letter spacing.
- The bar is about 60% of the screen width (clamped to 420–900 px), 10–12 px tall, and has a thin gold frame.
- Three layers:
  - a dark backing;
  - a "recent damage" layer in pale gold that drains toward the current health after a 0.6 s delay, over 0.5 s;
  - a crimson current-health fill that updates instantly.
- A small tick marks 50%, where phase 2 starts. In phase 2 the fill turns deeper crimson with a soft pulse.
- Data comes from the boss model's Humanoid Health and MaxHealth, which replicate, so no new remote is needed. Find the model through `BossFx` (`spawn`, or any event carrying `model`), or `Workspace.Enemies.GoldenTyrant`. The UI listens to `Humanoid.HealthChanged`.
- It fades in on `spawn` or the first boss event, fades out 2 s after `defeated` or when the model is removed, and is hidden when no boss is alive.
- It does not overlap the hotbar or the touch buttons on phones. Scale it with UIScale like the rest of the HUD.

## 6. Tests and checks

- Lune tests for `BossPlan` (each rule, with cooldown and phase gating) and for the `PoseClip` loop behaviour.
- Pure cone math in `Logic/BossPlan.inCone(origin, dir, point, length, halfAngleDeg)` using `{x, y, z}` tables, plus its tests.
- All gates green: stylua, selene, lune, rojo build.
- Studio check (done later over the Studio MCP):
  - summon the boss,
  - see the armor and the idle pose,
  - see each of the 5 actions with its VFX,
  - see the phase 2 aura and the ultimate,
  - confirm the pillar safe zone,
  - confirm the boss health bar drains with the damage-lag layer,
  - confirm the console is clean.
