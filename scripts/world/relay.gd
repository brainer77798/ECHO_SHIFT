class_name Relay
extends Interactable
## Security relay: hold the interact key beside it to cut its link. Progress bleeds away if the
## operative lets go or walks off, so the hack has to be done under pressure. Requires a live
## operative (Echoes cannot authenticate).

var channel := ""
var hold_time := 3.2
var title := "SECURITY RELAY"
var persist_key := ""
var done := false

var _progress := 0.0
var _bar: MeshInstance3D
var _ring: Node3D
var _lbl: Label3D
var _light: OmniLight3D
var _core_mat: StandardMaterial3D
var _hum := 0.0

func build() -> void:
	prompt = "Hold to disable relay"
	interact_range = 2.6
	echo_compatible = false
	var metal := Mats.plain(Color(0.10, 0.12, 0.16), 0.45, 0.8)
	Shapes.cylinder(self, 0.55, 0.65, 0.3, Vector3(0, 0.15, 0), metal, 12)
	Shapes.cylinder(self, 0.28, 0.34, 2.0, Vector3(0, 1.2, 0), metal, 10)
	_core_mat = StandardMaterial3D.new()
	_core_mat.emission_enabled = true
	_core_mat.albedo_color = Cfg.C_RED * 0.3
	_core_mat.emission = Cfg.C_RED
	_core_mat.emission_energy_multiplier = 2.4
	Shapes.sphere(self, 0.3, Vector3(0, 2.45, 0), _core_mat, 14)
	_ring = Node3D.new()
	_ring.position = Vector3(0, 2.45, 0)
	add_child(_ring)
	Shapes.torus(_ring, 0.52, 0.58, Vector3.ZERO, Mats.glow(Cfg.C_AMBER, 2.0), 20)
	_bar = Shapes.box(self, Vector3(0.1, 1.6, 0.1), Vector3(0.42, 1.2, 0), Mats.glow(Cfg.C_GREEN, 2.5))
	_bar.scale.y = 0.001
	_light = Shapes.add_light(self, Vector3(0, 2.4, 0.6), Cfg.C_RED, 1.2, 6.0)
	_lbl = Shapes.label3d(self, title, Vector3(0, 3.35, 0), Cfg.C_RED, 22, 0.006)
	if persist_key != "" and GameState.has_flag(persist_key):
		_finish(true)

func can_interact(_who: Node) -> bool:
	return enabled and not done

func prompt_text() -> String:
	return "[%s]  HOLD to disable relay" % Prefs.binding_text("interact")

func interact(_who: Node) -> void:
	if not done:
		Bus.hud_message.emit("HOLD [%s] TO DISABLE THE RELAY" % Prefs.binding_text("interact"), Cfg.C_AMBER, 1.6)

func _physics_process(delta: float) -> void:
	_ring.rotation.y += delta * (1.0 + _progress * 6.0)
	if done:
		return
	var holding := false
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead or not p.is_local or not p.controllable:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d <= interact_range and Input.is_action_pressed("interact"):
			holding = true
	if holding:
		_progress = minf(_progress + delta / hold_time, 1.0)
		_hum -= delta
		if _hum <= 0.0:
			_hum = 0.25
			Sfx.play_at("terminal", global_position, -10.0, 0.8 + _progress)
			Fx.burst(global_position + Vector3(0, 2.4, 0), Cfg.C_AMBER, 3, 3.0, 0.3, 0.1)
	else:
		_progress = maxf(_progress - delta * 1.2, 0.0)
	_bar.scale.y = maxf(_progress, 0.001)
	_bar.position.y = 0.4 + 0.8 * _progress
	_lbl.text = "%s  %d%%" % [title, int(_progress * 100.0)] if _progress > 0.0 else title
	if _progress >= 1.0:
		_finish(false)

func _finish(silent: bool) -> void:
	done = true
	_progress = 1.0
	_bar.scale.y = 1.0
	_bar.position.y = 1.2
	_core_mat.emission = Cfg.C_GREEN
	_core_mat.albedo_color = Cfg.C_GREEN * 0.3
	_light.light_color = Cfg.C_GREEN
	_light.light_energy = 0.6
	_lbl.text = "%s  OFFLINE" % title
	_lbl.modulate = Cfg.C_GREEN
	if persist_key != "":
		GameState.set_flag(persist_key, true)
	if level != null:
		level.set_channel(channel, true)
	if not silent:
		Sfx.play_at("shield_down", global_position, 0.0, 1.2)
		Fx.explosion(global_position + Vector3(0, 2.4, 0), Cfg.C_GREEN, 0.7)
		Bus.hud_message.emit("%s DISABLED" % title, Cfg.C_GREEN, 2.0)
