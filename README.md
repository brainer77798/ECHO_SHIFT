# ECHO//SHIFT

A third-person sci-fi action-adventure built in **Godot 4.7** (GDScript, Forward+ renderer). You play an
Echo-certified operative recovering a research station after a temporal-replay cascade. Your signature ability
is the **Echo**: record your last few seconds of movement, firing and interaction, then project a holographic
replay of yourself to distract enemies, hold pressure plates, and solve puzzles that need two of "you" at once.

Everything in the game — geometry, materials, shaders, music, sound effects, UI — is generated procedurally in
code. There are no imported art or audio assets.

> **Status:** single-player campaign is complete and playable start-to-finish (Main Menu → 5 chapters → boss
> fight → one of 3 endings). LAN co-op (2-4 players) is implemented and verified over real networking between
> two local processes — see `PROGRESS.md` for the full, up-to-date build log, test results, and known gaps.

---

## Requirements

- **Godot 4.7.x**, Forward+ renderer. On this machine: `C:\Users\sumat\tools\godot-4.7.2\` — use the
  `..._console.exe` build when running from a terminal (so stdout/stderr are visible), the plain `.exe` for the
  normal editor/GUI.
- No other dependencies. There is no package manager step — it's a self-contained Godot project.
- `.venv/` and `legacy_pygame_backup/` at the repo root belong to an **earlier, superseded Python/Pygame
  prototype** of the same concept (see `legacy_pygame_backup/README.md`). They are not part of the Godot game and
  are not needed to build or run it.

## Running the game

Open the project in the Godot editor and press Play, or from a terminal:

```powershell
& "C:\Users\sumat\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\sumat\Documents\ECHO_SHIFT"
```

Debug flags: `--god` enables god mode (`GameState.god_mode`).

## Controls

| Input | Action |
|---|---|
| `W A S D` | Move (camera-relative) |
| Mouse | Look / aim |
| Left Mouse | Fire blaster |
| `E` | Interact |
| `Space` / configurable | Dash (brief invulnerability) |
| configurable | Project Echo |
| `Esc` | Pause |

All bindings are rebindable from Settings (keyboard, mouse, and gamepad are all supported); the control scheme
is built at runtime by the `Prefs` autoload — `project.godot` itself has no `[input]` section.

## Running the automated checks

These are the project's real correctness gates — run them from a terminal, headless, no GPU window required
(except where noted):

```powershell
# 1. Every script parses (compiles) cleanly
& $godot --headless --path . --script res://tests/check_scripts.gd

# 2. Gameplay-mechanic unit tests (Echo recording/playback, dash, plates, damage, heat, ...)
& $godot --headless --path . res://tests/test_core.tscn

# 3. Every chapter's level geometry is solvable (reachability flood-fill, exit gate present, no orphaned markers)
& $godot --headless --path . res://tests/validate_chapters.tscn -- --chapters=1,2,3,4,5
```

Two more harnesses need a real window/GPU and are for visual inspection, not automated pass/fail:
`tests/run_level.tscn` (screenshot one chapter from any camera angle/top-down) and `tests/run_main.tscn`
(screenshot the real menu → gameplay → modal flow). `tests/smoke_render.gd` is a bare "can this machine render
anything at all" sanity check, unrelated to game logic.

```powershell
# 4. LAN co-op connectivity + replication (run as two separate processes, host then client)
& $godot --headless --path . res://tests/net_host.tscn
& $godot --headless --path . res://tests/net_client.tscn
```

See `PROGRESS.md` for the actual, current output of each of these.

## Hosting / joining LAN co-op

From the Main Menu, choose **LAN Co-op**. One player picks **Host Game** (default port 42424, configurable) and
shares their LAN IP; everyone else enters that IP under **Join** and connects. Once everyone who's joining has
connected, the host presses **Start Game** and the whole party loads into Chapter 1 together. Same local network
only — there is no internet matchmaking.

## Project layout

```
autoload/        7 global singletons (Bus, Cfg, Prefs, GameState, SaveSys, Sfx, Net)
scripts/core/     procedural materials, shapes, VFX, hit-flash
scripts/combat/   damage info, projectiles
scripts/echo/     the Echo mechanic itself (Echo, EchoRecorder, EchoRecording)
scripts/player/   player controller, procedural player model, camera rig
scripts/world/    every interactable/hazard/level-building system, incl. LevelBase (the level engine)
scripts/enemies/  enemy base class + 4 enemy types
scripts/boss/     the WARDEN boss fight, shield nodes, ending consoles
scripts/levels/   the 5 chapter scripts (chapter_1.gd .. chapter_5.gd)
scripts/data/     story.gd — all narrative, logs, dialogue, endings, credits
scripts/ui/       main menu, HUD, pause, settings, credits, ending screen, shared UI kit
scripts/main.gd   top-level scene-flow controller
scenes/           one bare .tscn per chapter + main.tscn (each just carries its script — no pre-placed nodes;
                  everything is built procedurally at runtime)
tests/            automated + visual test harnesses (see above)
legacy_pygame_backup/   superseded earlier prototype (Python/Pygame) — reference only, not part of this game
```

Levels are **not** hand-built in the editor: each chapter script returns an ASCII floor plan, and `LevelBase`
(the ~1100-line level engine) parses it into collision geometry, a nav grid, lighting, props, and every
door/plate/switch/hazard/enemy the chapter script places at marker locations.

## Documentation

- **`PROGRESS.md`** — the real, current build log: what's implemented system-by-system, chapter-by-chapter
  content, actual test output, and a list of known gaps/stubs. Read this for "what's actually done."
- **`legacy_pygame_backup/README.md`** — documents the earlier Python/Pygame prototype of this same game concept.
  Superseded by this Godot project; kept for historical reference, not maintained.
