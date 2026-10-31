extends Node
## Loads every built chapter headlessly and runs LevelBase.validate() against each, plus basic
## sanity checks (nav grid built, exit present, no duplicate device channels crashing). Prints a
## report and exits non-zero if any chapter has problems.
##   godot --headless --path . res://tests/validate_chapters.tscn -- --chapters=1,2,3,4

var _problems := 0

func _ready() -> void:
	var arg := "1,2,3,4,5"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chapters="):
			arg = a.trim_prefix("--chapters=")
	for s in arg.split(","):
		await _check_chapter(int(s))
	print("\nVALIDATE RESULT: %d problem(s)" % _problems)
	get_tree().quit(1 if _problems > 0 else 0)

func _check_chapter(idx: int) -> void:
	print("--- Chapter %d ---" % idx)
	GameState.in_game = true
	GameState.chapter = idx
	GameState.begin_chapter(idx)
	var scene: PackedScene = load(String(Cfg.CHAPTERS[idx - 1]["scene"]))
	var level: LevelBase = scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	print("  grid: %dx%d" % [level.grid_w, level.grid_h])
	var probs: Array = level.validate()
	for p in probs:
		print("  PROBLEM: ", p)
		_problems += 1
	if level.exit_gate == null and level.needs_exit_gate():
		print("  PROBLEM: exit_gate is null")
		_problems += 1
	if level.player == null:
		print("  PROBLEM: player is null")
		_problems += 1
	print("  doors=%d devices=%d checkpoints=%d enemies=%d" % [
		level.doors.size(), level.devices.size(), level.checkpoints.size(), level.get_tree().get_nodes_in_group("enemies").size()])
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
