extends Node
## Persistent campaign state: chapter, checkpoint snapshot, level flags, upgrades,
## collected evidence and statistics. Scene flow itself lives in Main.

const DEFAULT_CHECKPOINT := "start"

var in_game := false
var chapter := 1
var checkpoint := DEFAULT_CHECKPOINT

## Level flags (doors opened, encounters cleared, pickups taken). Keys are prefixed "c<N>_".
var flags: Dictionary = {}
var fragments := 0
var logs: Array = []
var upgrades: Dictionary = {}

## Snapshot taken at the last checkpoint; restored on death.
var snap: Dictionary = {}
## Snapshot taken when the current chapter began; restored by "restart level".
var chapter_snap: Dictionary = {}

var deaths := 0
var kills := 0
var echoes_made := 0
var play_time := 0.0
var endings_seen: Array = []
var ending := ""

## Debug / test switches (set via command line user args after "--").
var god_mode := false
var local_player: Node = null     # Player node of this machine

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--god":
			god_mode = true

func _process(delta: float) -> void:
	if in_game and not get_tree().paused:
		play_time += delta

# --- Campaign flow ---------------------------------------------------------------------

func new_game() -> void:
	chapter = 1
	checkpoint = DEFAULT_CHECKPOINT
	flags = {}
	fragments = 0
	logs = []
	upgrades = {}
	deaths = 0
	kills = 0
	echoes_made = 0
	play_time = 0.0
	ending = ""
	in_game = true
	begin_chapter(1)

func begin_chapter(index: int) -> void:
	chapter = clampi(index, 1, Cfg.CHAPTERS.size())
	checkpoint = DEFAULT_CHECKPOINT
	snap = _snapshot()
	chapter_snap = snap.duplicate(true)

func capture_checkpoint(id: String, autosave := true) -> void:
	checkpoint = id
	snap = _snapshot()
	if autosave:
		SaveSys.save_game()

func restore_checkpoint() -> void:
	_apply_snapshot(snap)

func restart_chapter() -> void:
	_apply_snapshot(chapter_snap)
	snap = chapter_snap.duplicate(true)

func _snapshot() -> Dictionary:
	return {
		"chapter": chapter,
		"checkpoint": checkpoint,
		"flags": flags.duplicate(true),
		"fragments": fragments,
		"logs": logs.duplicate(),
		"upgrades": upgrades.duplicate(),
	}

func _apply_snapshot(s: Dictionary) -> void:
	chapter = int(s.get("chapter", chapter))
	checkpoint = str(s.get("checkpoint", DEFAULT_CHECKPOINT))
	flags = (s.get("flags", {}) as Dictionary).duplicate(true)
	fragments = int(s.get("fragments", 0))
	logs = (s.get("logs", []) as Array).duplicate()
	upgrades = (s.get("upgrades", {}) as Dictionary).duplicate()
	Bus.fragments_changed.emit(fragments)

# --- Flags -------------------------------------------------------------------------------

func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value

func has_flag(key: String) -> bool:
	return flags.has(key) and bool(flags[key])

func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)

# --- Evidence / fragments -----------------------------------------------------------------

func collect_log(id: String) -> bool:
	if logs.has(id):
		return false
	logs.append(id)
	Bus.log_collected.emit(id)
	return true

func add_fragments(n: int) -> void:
	fragments += n
	Bus.fragments_changed.emit(fragments)

# --- Upgrades ---------------------------------------------------------------------------------

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

func upgrade_cost(id: String) -> int:
	var def: Dictionary = Cfg.UPGRADES[id]
	var lvl := upgrade_level(id)
	if lvl >= int(def["max"]):
		return -1
	return int((def["costs"] as Array)[lvl])

func buy_upgrade(id: String) -> bool:
	if not Cfg.UPGRADES.has(id):
		return false
	var cost := upgrade_cost(id)
	if cost < 0 or fragments < cost:
		return false
	fragments -= cost
	upgrades[id] = upgrade_level(id) + 1
	Bus.fragments_changed.emit(fragments)
	return true

## Derived gameplay statistics (all upgrades are applied here).
func stat(name: String) -> float:
	match name:
		"max_health":
			return Cfg.PLAYER_MAX_HEALTH + 25.0 * upgrade_level("hull")
		"blaster_damage":
			return Cfg.BLASTER_DAMAGE * (1.0 + 0.15 * upgrade_level("blaster"))
		"blaster_cooldown":
			return Cfg.BLASTER_COOLDOWN * (1.0 - 0.05 * upgrade_level("blaster"))
		"dash_cooldown":
			return maxf(0.5, Cfg.DASH_COOLDOWN - 0.18 * upgrade_level("dash"))
		"echo_record_time":
			return minf(Cfg.ECHO_BUFFER_CAPACITY_TIME - 0.5, Cfg.ECHO_RECORD_TIME + 1.0 * upgrade_level("buffer"))
		"echo_damage_mult":
			return Cfg.ECHO_BASE_DAMAGE_MULT + 0.10 * upgrade_level("echo")
		"echo_linger":
			return Cfg.ECHO_BASE_LINGER + 1.2 * upgrade_level("echo")
	push_warning("Unknown stat '%s'" % name)
	return 0.0

# --- Saving ------------------------------------------------------------------------------------

func to_save_dict() -> Dictionary:
	return {
		"snap": snap.duplicate(true),
		"chapter_snap": chapter_snap.duplicate(true),
		"deaths": deaths,
		"kills": kills,
		"echoes_made": echoes_made,
		"play_time": play_time,
		"endings_seen": endings_seen.duplicate(),
	}

## Applies a validated save dictionary (see SaveSys.validate). Returns false if unusable.
func apply_save_dict(d: Dictionary) -> bool:
	if not SaveSys.validate(d):
		return false
	snap = (d["snap"] as Dictionary).duplicate(true)
	chapter_snap = (d["chapter_snap"] as Dictionary).duplicate(true)
	deaths = int(d.get("deaths", 0))
	kills = int(d.get("kills", 0))
	echoes_made = int(d.get("echoes_made", 0))
	play_time = float(d.get("play_time", 0.0))
	endings_seen = (d.get("endings_seen", []) as Array).duplicate()
	_apply_snapshot(snap)
	in_game = true
	return true

func record_ending(kind: String) -> void:
	ending = kind
	if not endings_seen.has(kind):
		endings_seen.append(kind)
	SaveSys.save_meta_only()
