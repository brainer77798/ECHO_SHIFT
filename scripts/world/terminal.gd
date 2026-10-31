class_name Terminal
extends Interactable
## Readable computer terminal / audio log station. The log text lives in Story; reading a log for
## the first time records it in GameState (evidence collected) and awards a few fragments.

var log_id := ""
var channel_on_read := ""
var _screen_mat: StandardMaterial3D
var _light: OmniLight3D
var _lbl: Label3D

func build(yaw: float) -> void:
	prompt = "Access terminal"
	interact_range = 3.0
	var desk := Props.console_desk(self, Vector3.ZERO, yaw, Cfg.C_CYAN, false)
	var screen: MeshInstance3D = desk.get_meta("screen")
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.emission_enabled = true
	_screen_mat.albedo_color = Cfg.C_CYAN * 0.2
	_screen_mat.emission = Cfg.C_CYAN
	screen.material_override = _screen_mat
	_light = Shapes.add_light(self, Vector3(0, 1.8, 0.5).rotated(Vector3.UP, yaw), Cfg.C_CYAN, 0.8, 5.0)
	_lbl = Shapes.label3d(self, "TERMINAL", Vector3(0, 2.5, 0), Cfg.C_CYAN, 22, 0.006)
	# a solid collider so the desk blocks movement like the other props
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.L_WORLD
	body.collision_mask = 0
	body.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.0, 0.8)
	cs.shape = shape
	cs.position = Vector3(0, 0.5, 0)
	body.add_child(cs)
	add_child(body)
	_refresh()

func _refresh() -> void:
	var unread := not GameState.logs.has(log_id)
	var c := Cfg.C_CYAN if unread else Color(0.25, 0.45, 0.55)
	if _screen_mat != null:
		_screen_mat.emission = c
		_screen_mat.emission_energy_multiplier = 2.0 if unread else 0.5
	if _light != null:
		_light.light_color = c
		_light.light_energy = 0.9 if unread else 0.25
	if _lbl != null:
		_lbl.text = "NEW LOG" if unread else "LOG ARCHIVED"
		_lbl.modulate = Color(c.r, c.g, c.b, 0.9 if unread else 0.5)

func prompt_text() -> String:
	var key := Prefs.binding_text("interact")
	return "[%s]  %s" % [key, "Access terminal" if not GameState.logs.has(log_id) else "Re-read log"]

func interact(_who: Node) -> void:
	var entry := Story.get_log(log_id)
	if entry.is_empty():
		return
	var shown: Dictionary = entry.duplicate()
	var first := GameState.collect_log(log_id)
	shown["id"] = log_id
	shown["new"] = first
	if first:
		var reward := int(entry.get("reward", 6))
		GameState.add_fragments(reward)
		shown["reward"] = reward
		Sfx.play("pickup")
	else:
		shown["reward"] = 0
	if channel_on_read != "" and level != null:
		level.set_channel(channel_on_read, true)
		GameState.set_flag("ch_" + channel_on_read, true)
	Sfx.play("terminal")
	_refresh()
	Bus.terminal_requested.emit(shown)
