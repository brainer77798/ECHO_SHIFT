class_name ExitTrigger
extends Node3D
## Chapter exit gate. Red and inert while `locked`; once unlocked, any operative stepping inside
## completes the chapter.

var level: LevelBase
var locked := true
var locked_reason := "The exit is sealed."
var yaw := 0.0

var _area: Area3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _lbl: Label3D
var _warned := false
var _fired := false

func build() -> void:
	rotation.y = yaw
	var metal := Mats.plain(Color(0.10, 0.12, 0.16), 0.45, 0.8)
	for sx in [-1.0, 1.0]:
		Shapes.box(self, Vector3(0.4, 4.4, 0.6), Vector3(sx * 2.0, 2.2, 0), metal)
		Shapes.box(self, Vector3(0.12, 4.0, 0.14), Vector3(sx * 1.8, 2.2, 0), Mats.glow(Cfg.C_CYAN, 2.0))
	Shapes.box(self, Vector3(4.8, 0.5, 0.7), Vector3(0, 4.55, 0), metal)
	_mat = Mats.energy(Cfg.C_RED, 1.0, true, 2.0)
	var field := Shapes.box(self, Vector3(3.6, 4.0, 0.1), Vector3(0, 2.2, 0), _mat)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = Shapes.add_light(self, Vector3(0, 2.4, 1.2), Cfg.C_RED, 1.0, 8.0)
	_lbl = Shapes.label3d(self, "EXIT SEALED", Vector3(0, 5.3, 0), Cfg.C_RED, 30, 0.007)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = Cfg.L_PLAYER
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 3.6, 2.6)
	cs.shape = shape
	cs.position = Vector3(0, 1.8, 0)
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body)
	set_locked(true)

func set_locked(v: bool, reason := "") -> void:
	locked = v
	if reason != "":
		locked_reason = reason
	var c := Cfg.C_RED if locked else Cfg.C_GREEN
	_mat.set_shader_parameter("tint", c)
	_light.light_color = c
	_lbl.text = "EXIT SEALED" if locked else "EXIT"
	_lbl.modulate = c

func _on_body(b: Node) -> void:
	var p := b as Player
	if p == null or not p.is_local or p.dead:
		return
	if locked:
		Bus.hud_message.emit(locked_reason, Cfg.C_RED, 2.5)
		Sfx.play("echo_fail")
		return
	if _fired:
		return
	_fired = true
	if level != null:
		level.complete()
