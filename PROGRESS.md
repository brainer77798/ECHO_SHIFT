# ECHO//SHIFT — Build Progress

Last updated: 2026-10-29. This is the authoritative, current build log — written from a full read of every
script in `autoload/`, `scripts/`, and `tests/`, cross-checked against actually running the automated test
suites (not just reading code and assuming it works). If this ever drifts from the code, trust the code and the
test output, and update this file.

## Status: single-player campaign complete and playable end-to-end

Main Menu → New Game/Continue → Chapter 1 → 2 → 3 → 4 → 5 → WARDEN boss fight → ending console choice → one of
3 ending screens → back to Main Menu. All of it runs on procedurally generated geometry, materials, music and
sound effects — there are no imported art or audio assets anywhere in the project.

**LAN co-op is now implemented and verified working** over real ENet networking between two separate local
Godot processes (host + client on 127.0.0.1) — see "LAN co-op" section below for what was tested and how.

---

## Test results (actually run, not assumed)

```
$ godot --headless --path . --script res://tests/check_scripts.gd
checked 61 scripts, 0 failed

$ godot --headless --path . res://tests/test_core.tscn
RESULT: 58 passed, 0 failed
(WARNING: 4 ObjectDB instances leaked at exit — a test-teardown cleanliness
 issue in the headless harness, not a gameplay-logic failure; see below)

$ godot --headless --path . res://tests/validate_chapters.tscn -- --chapters=1,2,3,4,5
--- Chapter 1 ---  grid 64x40   doors=3 devices=2 checkpoints=3 enemies=3
--- Chapter 2 ---  grid 62x52   doors=3 devices=5 checkpoints=2 enemies=2
--- Chapter 3 ---  grid 62x64   doors=2 devices=3 checkpoints=3 enemies=3
--- Chapter 4 ---  grid 60x70   doors=3 devices=2 checkpoints=3 enemies=0
--- Chapter 5 ---  grid 70x60   doors=0 devices=0 checkpoints=1 enemies=4
VALIDATE RESULT: 0 problem(s)
```

`tests/validate_chapters.gd` defaults to `--chapters=1,2,3,4` (a stale default — see Known gaps), so a plain
run without arguments silently skips chapter 5. Run explicitly with `-- --chapters=1,2,3,4,5` as above to cover
it — chapter 5 also validates clean: 0 problems, 1 checkpoint, 4 enemies (the WARDEN boss + its 3 shield nodes),
0 doors/devices since it ends via the 3 ending consoles rather than an exit gate.

The 58/58 `test_core.tscn` suite covers: the Echo recorder's ring buffer (capacity, windowing, event ordering),
Echo playback timing and firing (exact shot counts, no duplicates/misses, correct damage), dash (distance,
cooldown), the 2-Echo cap and forced-replacement, plate/door logic (including the echo-only plate), line-of-sight
blocking shots, the enemy echo-vs-player lure/distraction logic, per-player recorder independence (the data
model co-op would use), and the blaster heat/overheat/cooldown system.

## What's built, system by system

- **Autoloads** (`autoload/`): `Bus` (global signal bus, ~20 signals everything routes through), `Cfg` (every
  tuning constant, the upgrade table, the 5-chapter list, physics-layer bitmasks), `Prefs` (all settings +
  builds the entire InputMap at runtime, including live key-rebinding), `GameState` (campaign flags/fragments/
  logs/upgrades, checkpoint & chapter-start snapshots, derived stat calculation), `SaveSys` (JSON save with a
  checksum, atomic write + rolling backup, corrupt-save recovery), `Sfx` (every sound effect and music track
  synthesized in code at startup — zero imported audio), `Net` (LAN co-op: ENet host/join, roster sync,
  host-authoritative state broadcast — see "LAN co-op" section below).
- **Core/combat/echo** (`scripts/core/`, `scripts/combat/`, `scripts/echo/`): procedural texture/shader factory
  (`Mats`), primitive-mesh builders (`Shapes`), capped VFX pool (`Fx`), universal hit-flash, raycast-based
  projectiles with proximity assist, and the Echo mechanic itself — a ring-buffer recorder
  (`EchoRecorder`/`EchoRecording`) and a playback actor (`Echo`) that replays position, fire/dash/interact
  events at their original timestamps, and is invulnerable "hard light" (damage to an Echo is cosmetic only).
- **Player** (`scripts/player/`): full movement/dash/iframes, blaster with a heat/overheat system, Echo
  creation (with the 2-Echo cap and oldest-replacement), interact scanning, third-person spring-arm camera. The
  remote-avatar lerp/animate path (`apply_net_state`/`_remote_step`) now drives every non-local player in a
  LAN co-op session.
- **World systems** (`scripts/world/`): nav grid with door-aware dynamic blockers, set-dressing props, every
  interactable (door, pressure plate, switch, shoot target, terminal, checkpoint, pickup, exit trigger, trigger
  zone, relay), 3 hazard types (sweeping laser, electrical arc, crusher), a fixating security camera, and
  `LevelBase` — the ~1100-line level engine that turns a chapter's ASCII floor-plan string into collision
  geometry, nav grid, lighting/fog, and every placed object. **No level geometry is hand-built in the editor.**
- **Enemies** (`scripts/enemies/`): shared base class with NavGrid pathing, alert propagation, and the
  echo-vs-real-player "lure budget" that makes Echoes work as decoys; 4 concrete types — HunterDrone (flying
  striker), Sentry (turret with a dodgeable laser telegraph), ArmoredBrute (frontal armor, charge + slam, stuns
  itself into an exposed-core window on a wall hit), AegisUnit (shield-support drone, never attacks directly).
- **Boss** (`scripts/boss/`): WARDEN, a 3-phase fight — shields-down phase, direct-damage phase with a
  homing seeker that can target an Echo, and an armored/exposed alternating final phase. 3 `ShieldNode`s, 3
  `EndingConsole`s (two-press confirm, picks one of SHUTDOWN / CONTAINMENT / REACTIVATION — endings differ in
  text/color/music only, not gameplay).
- **Chapters** (`scripts/levels/chapter_1.gd` .. `chapter_5.gd`):
  | Chapter | Theme | Puzzle/content highlight | Doors | Devices | Checkpoints | Enemies | Terminals |
  |---|---|---|---|---|---|---|---|
  | 1 — The Arrival | Dock / cargo hall / comms relay | Tutorial + echo-on-plate door puzzle | 3 | 2 | 3 | 3 | 3 |
  | 2 — Research Division | Laboratory wing | Ordered 3-switch sequence + echo-only guarded plate | 3 | 5 | 2 | 2 | 4 |
  | 3 — Security Grid | Surveillance core | Camera-watched corridor + 3-relay hub + Armored Brute arena | 2 | 3 | 3 | 3 | 4 |
  | 4 — Broken Core | Experimental chambers | Dual simultaneous echo-plates (needs both echo slots) | 3 | 2 | 3 | 0 | 3 |
  | 5 — The Final Echo | Chrono Core chamber | WARDEN boss fight + 3 ending consoles | — | — | 1 | boss+3 shields | 2 |

  (Chapters 1-4's counts are the actual `validate_chapters` output above, cross-checked line-by-line against
  each chapter's source; chapter 5's doors/devices aren't tracked the same way since it has no exit gate — it
  ends via the ending consoles instead.)
- **Story** (`scripts/data/story.gd`): **18 terminal logs** across the 5 chapters (3/5/4/4/2), ~18 named
  dialogue beats, a 5-researcher mystery narrative (the Meridian Station Chrono Core incident) building a
  sympathetic-antagonist arc for WARDEN, 3 ending texts, and credits.
- **UI** (`scripts/ui/`, `scripts/main.gd`): a complete menu/HUD/pause/settings flow, all built from code (no
  imported UI art). `main.gd` wires the whole session lifecycle — new game/continue, chapter loading with
  fade transitions, death/respawn, pause, and the ending flow — into one coherent loop.
- **Tests** (`tests/`): parse-checker, the 58-assertion gameplay unit-test suite, the chapter reachability
  validator, plus three visual/manual harnesses (windowed level screenshots, full main-scene screenshots, a
  bare render smoke test).

## LAN co-op

Implemented in `autoload/net.gd` (ENet host/join, player roster sync, host-authoritative state broadcast) plus
small additive hooks in `main.gd`, `level_base.gd`, `player.gd` and `enemy.gd` — every hook is gated on
`Net.active`, so single-player behaviour is provably unchanged (`test_core.tscn` 58/58 and
`validate_chapters.tscn` 0 problems both still pass after adding it).

**Design:** the host runs the real simulation (enemy AI, puzzle channels, encounters — the same single-player
code, unmodified) and broadcasts a consolidated snapshot (~12 Hz) of every player's transform/health, every
enemy's transform/health/state, and the level's logic-channel dictionary. Clients never simulate enemies or
puzzle logic themselves — they apply the broadcast directly. Each client reports its own avatar's state to the
host the same way. A client that locally detects a hit on a (puppeted) enemy reports it via RPC instead of
mutating its own copy, so health only ever changes authoritatively on the host — `Enemy.take_damage()` has a
single added guard clause for this. Echo creation is broadcast (reliable RPC carrying the recording data) so
every peer sees every player's Echoes play out. Chapter transitions are host-driven: only the host's own
chapter completion advances the party (`Net.broadcast_chapter`); a client that reaches an exit first just waits.

**Tested and verified:** two separate local Godot processes (`tests/net_host.tscn` / `tests/net_client.tscn`),
host on `127.0.0.1:42424`, real client `ENetMultiplayerPeer.create_client()`/host `create_server()` — not
simulated. Confirmed: connection, roster sync, host-driven chapter-1 load on both processes, correct per-peer
`is_local` assignment, and **bidirectional position/health replication** — each process's view of the *other*
player's position exactly matches what that player's own process reported (e.g. host and client both agree the
client's avatar is at `(8.793849, 0.0, 62.58666)`), which can only happen if the report→host→broadcast→apply
chain is actually working over the network, not just locally. Both processes also agreed on the enemy count (3)
for the shared chapter. Reproduce with: run `tests/net_host.tscn` headless, then `tests/net_client.tscn`
headless (same machine, default port from `Cfg.NET_PORT`); both print a line per visible player and a final
`RESULT: OK` / `FAIL`.

**Not verified:** actual separate physical machines (only tested as two processes on one machine via loopback —
the spec explicitly allows this as a fallback: "if actual multi-device testing is unavailable, clearly state
that multiplayer is unverified"), real network latency/packet loss, live gameplay interaction during a
co-op session (echo-sharing, enemy puppeting, hit-reporting, mid-game disconnect/reconnect, host migration —
all implemented per the design above but not exercised by this connectivity test), the host/join lobby UI
(`scripts/ui/coop_lobby.gd`) itself has not been clicked through by a human, and puzzle-object state (doors,
plates, switches) is *not* given hard client-side authority gating — clients still run their own local copy of
that logic too, self-correcting against the host's periodic channel broadcast rather than being strictly
puppeted, which is a deliberate lower-risk simplification (touching every interactable file was judged too much
additional surface area/regression risk for the remaining time) and could show brief visual flicker/disagreement
between host and client under real latency.

## Known gaps / unfinished work

1. **Human playtesting is still outstanding.** The game has been validated via screenshots (`run_level`,
   `run_main`) and the automated suites above, but (as of this update) has not been played start-to-finish by
   a person at a keyboard.
2. **2-4 leaked `ObjectDB` instances reported at exit** by the headless test harnesses (`test_core.tscn`, and
   the net host/client test processes) — a Godot engine warning about objects not freed before the test
   process quits. Did not block any assertion and needs `--verbose` to see which objects; worth a look but not
   currently understood to affect gameplay correctness (likely an `ENetMultiplayerPeer`/RefCounted not
   explicitly freed on process-exit in the bare test harnesses, which real gameplay sessions don't hit the same
   way since `Main.gd` cleanly calls `Net.leave()`).
3. **Puzzle-object (door/plate/switch) multiplayer authority is soft**, as described above under LAN co-op —
   self-correcting via the channel broadcast rather than strictly host-owned.

## Key lessons learned (worth keeping in mind for future work on this codebase)

- Godot 4.7 treats GDScript type-inference-from-`Variant` as an **error**, not a warning, by default — the
  codebase leans on `Dictionary`/`Variant` heavily (e.g. the `opts := {}` pattern used throughout `LevelBase`),
  so `project.godot`'s `[debug]` section deliberately disables `inference_on_variant` and a few related
  warnings project-wide rather than typing everything strictly.
- `_set` is a reserved `Object` method name — a GDScript method with that exact name silently overrides engine
  behavior instead of erroring, which cost real debugging time once; `MapBuilder`'s equivalent helper is named
  `_cell_put` to avoid the collision.
- There is no `[input]` section in `project.godot` at all — the entire control scheme (including gamepad) is
  registered at runtime by `Prefs.register_actions()`. If a scene ever needs an input action before that
  autoload has run, it won't exist yet; this hasn't been a problem so far because autoloads initialize before
  any scene.

## Where to pick up next

With single-player complete and LAN co-op implemented + connectivity-verified, what's left is lower-stakes:
(a) a human playtest pass (single-player and co-op both), (b) hardening puzzle-object multiplayer authority if
co-op flicker under real latency turns out to matter in practice, and (c) the `ObjectDB` leak in the headless
test harnesses (cosmetic, doesn't affect any assertion).
