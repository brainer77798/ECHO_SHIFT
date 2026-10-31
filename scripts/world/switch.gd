class_name Switch
extends Interactable
## Wall/pedestal console that drives a logic channel.
##   TOGGLE   - flips on every use
##   TIMED    - turns on, then automatically off after `duration` seconds
##   LATCH    - turns on once and stays on (remembered across checkpoints via `persist_key`)
## `hold_time` > 0 turns it into a relay: the user must stand and hold the interact key.
## Echo-compatible switches glow cyan and also respond to a replayed interact event.

enum Mode { TOGGLE, TIMED, LATCH }

var channel := ""
var mode: Mode = Mode.TOGGLE
var duration := 6.0
var title := "SWITCH"
var persist_key := ""
var on := false

var _time_left := 0.0
var _screen_mat: StandardMaterial3D
var _light: OmniLight3D
var _lbl: Label3D
var _bar: MeshInstance3D
var _color: Color = Cfg.C_CYAN

func build() -> void:
	_color = Cfg.C_CYAN if echo_compatible else Cfg.C_AMBER
	if interact_id == "":
		interact_id = channel
	var base := Mats.plain(Color(0.09, 0.11, 0.15), 0.5, 0.7)
	Shapes.box(self, Vector3(0.9, 0.25, 0.9), Vector3(0, 0.125, 0), base)
	Shapes.box(self, Vector3(0.5, 0.95, 0.5), Vector3(0, 0.7, 0), base)
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.emission_enabled = true
	_screen_mat.albedo_color = _color * 0.2
	_screen_mat.emission = _color
	_screen_mat.emission_energy_multiplier = 1.4
	var screen := Shapes.box(self, Vector3(0.6, 0.5, 0.08), Vector3(0, 1.45, 0.05), _screen_mat)
	screen.rotation.x = -0.25
	Shapes.torus(self, 0.44, 0.5, Vector3(0, 0.27, 0), Mats.glow(_color, 2.0), 20).scale = Vector3(1, 0.2, 1)
	_light = Shapes.add_light(self, Vector3(0, 1.6, 0.4), _color, 0.7, 4.5)
	_lbl = Shapes.label3d(self, title, Vector3(0, 2.15, 0), _color, 24, 0.006)
	_lbl.modulate.a = 0.85
	if echo_compatible:
		var tag := Shapes.label3d(self, "ECHO LINK", Vector3(0, 2.45, 0), Cfg.C_CYAN, 18, 0.006)
		tag.modulate.a = 0.7
	_bar = Shapes.box(self, Vector3(0.5, 0.05, 0.05), Vector3(0, 1.85, 0), Mats.glow(Cfg.C_AMBER, 2.0))
	_bar.visible = false
	if persist_key != "" and GameState.has_flag(persist_key):
		_set_on(true, true)
	_refresh()

func prompt_text() -> String:
	var key := Prefs.binding_text("interact")
	if mode == Mode.LATCH and on:
		return ""
	return "[%s]  %s" % [key, prompt if prompt != "Use" else ("Deactivate" if on and mode == Mode.TOGGLE else "Activate")]

func can_interact(_who: Node) -> bool:
	if not enabled:
		return false
	if mode == Mode.LATCH and on:
		return false
	if mode == Mode.TIMED and on:
		return false
	return true

func interact(who: Node) -> void:
	if not can_interact(who):
		return
	Sfx.play_at("switch", global_position, -2.0)
	match mode:
		Mode.TOGGLE:
			_set_on(not on)
		Mode.TIMED:
			_set_on(true)
			_time_left = duration
		Mode.LATCH:
			_set_on(true)
			if persist_key != "":
				GameState.set_flag(persist_key, true)

## Lets a chapter script force this switch's state from outside (e.g. resetting a failed sequence).
func force_state(v: bool) -> void:
	if mode == Mode.TIMED:
		_time_left = 0.0
		_bar.visible = false
	_set_on(v, true)

func _set_on(v: bool, silent := false) -> void:
	on = v
	if level != null:
		level.set_channel(channel, on)
	_refresh()
	if not silent:
		Fx.burst(global_position + Vector3(0, 1.5, 0), _color, 6, 2.5, 0.3, 0.1)

func _physics_process(delta: float) -> void:
	if mode == Mode.TIMED and on:
		_time_left -= delta
		_bar.visible = true
		_bar.scale.x = clampf(_time_left / duration, 0.0, 1.0)
		_lbl.text = "%s  %.1fs" % [title, maxf(_time_left, 0.0)]
		if _time_left <= 0.0:
			_bar.visible = false
			_lbl.text = title
			_set_on(false, true)
			Sfx.play_at("plate_off", global_position, -4.0)

func _refresh() -> void:
	var c := Cfg.C_GREEN if on else _color
	_screen_mat.emission = c
	_screen_mat.albedo_color = c * 0.2
	_screen_mat.emission_energy_multiplier = 2.4 if on else 1.2
	_light.light_color = c
