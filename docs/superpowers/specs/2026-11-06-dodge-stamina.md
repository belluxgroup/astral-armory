# Dodge roll and stamina

Date: 2026-11-06. Status: approved in chat (Left Shift, separate stamina bar). Adds to spec §4 and §5.

## 1. Stamina

- A new resource, separate from Energy: `maxStamina = 100`.
- Regen is 35 per second. It starts 0.7 s after the last stamina spend.
- Costs:
  - dodge roll: 22
  - backstep: 12
  - each `basic` hit: 8
  - skills cost no stamina
- An action is allowed while stamina is above 0, even if it costs more than what is left. Stamina floors at 0, then the regen delay starts. With 0 stamina, dodge and `basic` are refused.
- The server is the authority, the same way as Energy. `PlayerState` gains `stamina: number` and `maxStamina: number`, and `Stats` gains `maxStamina` and `staminaRegen` (base values above, so passives can grow into them later).
- HUD: a green stamina bar (`#5BD08A`) under the Energy bar, in the same style. When an action is refused for lack of stamina, the bar flashes.

## 2. Dodge

- Input: **Left Shift** on PC. Set `StarterPlayer.EnableMouseLockOption = false` in default.project.json so it no longer toggles Shift Lock. On touch, add an extra button titled "Lăn", using `Mobile.extraButton`, on the fan next to the jump button.
- Remote: `Dodge` (C→S), payload `dir: Vector3`, the world-space move direction. A zero vector means backstep. The server validates the player is alive, is not rooted by boss chains, has stamina above 0 and is off the dodge cooldown (0.8 s, counted from the dodge start). It also rate-limits like CastSkill.
- **Roll** (when moving): 0.55 s, about 14 studs along `dir` (flattened and normalized). I-frames run from 0.10 to 0.40 s.
- **Backstep** (when not moving): 0.35 s, about 6 studs opposite the facing direction. I-frames run from 0.05 to 0.22 s.
- Movement: the client owns its character's physics, so the client applies the motion. A LinearVelocity on the HumanoidRootPart (or AssignAssemblyLinearVelocity each frame) follows an ease-out speed curve. Humanoid AutoRotate is off for the duration, and the character faces the roll direction. The server does not move the player. It only grants the i-frame window and stamina, and checks after the fact that the displacement is at most 20 studs.
- I-frames: `Combat.damagePlayer` ignores damage while `now` is inside the player's i-frame window. That covers enemies, boss melee, volley, armory, chains and the ultimate. A boss chains root is not applied to a player inside an i-frame window.
- Cancels: a dodge may cancel the recovery of a `basic` hit. Skills cannot be cast during a dodge, and the client and server both refuse them.
- `SkillFx` gains a `dodge` event, sent to all clients: `{ skillId = "dodge", casterUserId, origin, target = origin + dir * distance, spec = { kind = "roll" | "backstep" }, serverTime }`. Other clients use it to play the pose and dust. The local client predicts its own roll immediately and does not wait for the server.

## 3. Animation (`Config/PoseClips` + `Logic/PoseClip`)

- `PoseClip` gains optional position channels: a pose value is `{rx, ry, rz}` or `{rx, ry, rz, px, py, pz}` (position in studs). Missing position counts as 0. Validation accepts 3 or 6 numbers.
- New joints in `PoseClips.JOINTS`: `Root` (on LowerTorso, `add`), `RightHip`, `RightKnee`, `LeftHip`, `LeftKnee` (all `override`). Both Motor6D and AnimationConstraint rigs are supported, the same as now.
- `dodge_roll` (0.55 s):
  - tuck: hips flexed, knees bent, arms tucked, head down;
  - a full forward somersault on `Root` X from 0 to -360°, with Root lowered by about 1.2 studs in the middle so the body rolls low along the ground;
  - then a quick stand-up.
  - Ease-in-out so the middle of the roll is fastest.
- `dodge_backstep` (0.35 s): a small crouch-hop back, with the torso leaning forward and the arms flared slightly.

## 4. VFX (`src/client/Vfx/Dodge.luau`)

- A dust puff (`smoke_soft`, low and wide) at the start and on landing.
- A faint after-image trail from 2 torso attachments during the i-frame window.
- No camera shake.

## 5. Tests and checks

- Lune tests:
  - stamina rules in a pure `Logic/Stamina.luau`: spend, floor at 0, refusal at 0, regen delay and rate;
  - the dodge window and cooldown in pure `src/server/Rules/Dodge.luau`;
  - PoseClip position channels.
- All gates green.
- Studio check:
  - Shift rolls and goes through enemy hits during the i-frames;
  - backstep works;
  - the stamina bar drains and refills;
  - a roll at 0 stamina is refused;
  - the boss ultimate can be dodged by rolling;
  - the touch "Lăn" button works.
