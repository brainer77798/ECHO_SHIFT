class_name EndingConsole
extends Interactable
## One of the three Chrono Core resolution consoles (SHUTDOWN / CONTAINMENT / REACTIVATION).
## Inert until the level calls reveal(); confirms once (hold is not required, a stray tap on a
## world-ending decision would be bad UX, so interact() asks for a second press) before firing
## Bus.ending_chosen.

var kind := "shutdown"
var revealed := false
var _armed := false
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _lbl: Label3D
var _color: Color

func build() -> void:
	enabled = false
	interact_range = 3.0
	var entry: Dictionary = Story.ENDINGS.get(kind, {})
	_color = entry.get("color", Cfg.C_CYAN)
	var metal := Mats.plain(Color(0.10, 0.11, 0.14), 0.45, 0.8)
	Shapes.cylinder(self, 0.7, 0.85, 0.3, Vector3(0, 0.15, 0), metal, 20)
	Shapes.cylinder(self, 0.4, 0.5, 1.7, Vector3(0, 1.15, 0), metal, 16)
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.albedo_color = Color(0.1, 0.1, 0.1)
	_mat.emission = Color(0.2, 0.2, 0.22)
	_mat.emission_energy_multiplier = 0.6
	Shapes.sphere(self, 0.42, Vector3(0, 2.15, 0), _mat, 18)
	Shapes.torus(self, 0.55, 0.62, Vector3(0, 1.95, 0), Mats.glow(Color(0.3, 0.3, 0.32), 1.0), 24)
	_light = Shapes.add_light(self, Vector3(0, 2.1, 0), Color(0.3, 0.3, 0.32), 0.3, 5.0)
	_lbl = Shapes.label3d(self, String(entry.get("title", kind.to_upper())), Vector3(0, 3.0, 0), Color(0.5, 0.5, 0.52), 24, 0.006)

func reveal() -> void:
	revealed = true
	enabled = true
	_mat.emission = _color
	_mat.emission_energy_multiplier = 2.6
	_light.light_color = _color
	_light.light_energy = 1.3
	_lbl.modulate = _color
	Fx.ring(global_position + Vector3(0, 0.3, 0), _color, 2.0, 0.6)
	Sfx.play_at("checkpoint", global_position, -2.0)

func can_interact(_who: Node) -> bool:
	return revealed

func prompt_text() -> String:
	if not revealed:
		return ""
	if _armed:
		return "[%s]  CONFIRM: %s" % [Prefs.binding_text("interact"), String(Story.ENDINGS.get(kind, {}).get("title", kind))]
	return "[%s]  %s" % [Prefs.binding_text("interact"), String(Story.ENDINGS.get(kind, {}).get("title", kind))]

func interact(_who: Node) -> void:
	if not revealed:
		return
	if _armed:
		Bus.ending_chosen.emit(kind)
		return
	_armed = true
	Bus.hud_message.emit("Press again to confirm: %s" % String(Story.ENDINGS.get(kind, {}).get("title", kind)), _color, 3.0)
	Sfx.play("ui_click")
