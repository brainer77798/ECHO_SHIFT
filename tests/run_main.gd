extends Node
## Boots the real Main scene (menu -> New Game -> chapter 1) and takes screenshots along the way,
## so the actual player-facing flow can be eyeballed, not just the bare level.
##   godot --path . res://tests/run_main.tscn -- --shots=menu,game --frames=60

var _main: Node
var _args := {}
var _step := 0
var _t := 0
var _steps: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_steps = String(_args.get("shots", "menu")).split(",")

func _process(_delta: float) -> void:
	_t += 1
	if _step >= _steps.size():
		return
	var name := String(_steps[_step])
	match name:
		"menu":
			if _t == 20:
				_shot("menu")
				_advance()
		"click_new":
			if _t == 2:
				var btn := _find_button("New Game")
				if btn:
					btn.pressed.emit()
			if _t == 40:
				_shot("game")
				_advance()
		"pause":
			if _t == 2:
				var ev := InputEventAction.new()
				ev.action = "pause"
				ev.pressed = true
				Input.parse_input_event(ev)
			if _t == 15:
				_shot("pause")
				_advance()
		"terminal":
			if _t == 2:
				var entry: Dictionary = Story.get_log("c1_hale_transmission").duplicate()
				entry["reward"] = 10
				Bus.terminal_requested.emit(entry)
			if _t == 10:
				_shot("terminal")
				_advance()
		"bench":
			if _t == 2:
				GameState.add_fragments(80)
				Bus.upgrade_bench_requested.emit()
			if _t == 10:
				_shot("bench")
				_advance()
	if _step >= _steps.size() and _t > 5:
		get_tree().quit(0)

func _advance() -> void:
	_step += 1
	_t = 0

func _find_button(text: String) -> Button:
	return _find_button_in(_main, text)

func _find_button_in(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button_in(c, text)
		if r:
			return r
	return null

func _shot(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://main_%s.png" % label
	img.save_png(path)
	print("SHOT ", label, " -> ", ProjectSettings.globalize_path(path))
