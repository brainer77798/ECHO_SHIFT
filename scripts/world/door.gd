class_name Door
extends Node3D
## Sliding blast door. Opens while its `requires` channels are satisfied (all of them, or any when
## `mode_any`; a leading "!" means "must be off"). `hold_time` > 0 makes it a timed door that stays
## open that long after the condition drops. It never closes on top of someone standing in the
## doorway, blocks bullets/movement while closed, and registers itself with the NavGrid so
## enemies path around closed doors and through open ones.

signal state_changed(door: Door, open: bool)

var door_id := ""
var requires: Array = []
var mode_any := false
var width_axis_x := true     # true: the door's wide side runs along X (it blocks travel along Z)
var span := 4.0
var height := 4.6
var cells: Array = []
var open_time := 0.6
var hold_time := 0.0
var label := ""
var field := false           # energy-field variant: translucent, hurts on contact
var level: LevelBase

var is_open := false
var progress := 0.0          # 0 closed .. 1 fully open

var _hold_left := 0.0
var _body: StaticBody3D
var _panel_a: Node3D
var _panel_b: Node3D
var _gap: Area3D
var _hurt: Area3D
var _status: MeshInstance3D
var _status_mat: StandardMaterial3D
var _lbl: Label3D
var _light: OmniLight3D
var _field_mat: ShaderMaterial
var _zap_cd := 0.0
var _closed_registered := false
var _want := false

func build() -> void:
	var depth := 0.7
	var size := Vector3(span, height, depth) if width_axis_x else Vector3(depth, height, span)
	_body = StaticBody3D.new()
	_body.collision_layer = Cfg.L_WORLD
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, WALL_CLEAR, size.z)
	cs.shape = shape
	cs.position = Vector3(0, WALL_CLEAR * 0.5, 0)
	_body.add_child(cs)
	add_child(_body)

	var frame := Mats.plain(Color(0.10, 0.12, 0.16), 0.45, 0.8)
	var panel_mat := Mats.surface("door_panel", "plates", Color(0.2, 0.23, 0.29), Cfg.C_CYAN, 0.8, 0.5, 0.6)
	var hv := Vector3(span, height, depth)    # built along local X, then rotated for Z-oriented doors
	var holder := Node3D.new()
	holder.name = "Visual"
	holder.rotation.y = 0.0 if width_axis_x else PI * 0.5
	add_child(holder)
	if field:
		_field_mat = Mats.energy(Cfg.C_RED, 1.4, true, 3.0)
		var plane := Shapes.box(holder, Vector3(span, height, 0.12), Vector3(0, height * 0.5, 0), _field_mat)
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_panel_a = plane
	else:
		_panel_a = Node3D.new()
		_panel_b = Node3D.new()
		holder.add_child(_panel_a)
		holder.add_child(_panel_b)
		for i in 2:
			var p: Node3D = _panel_a if i == 0 else _panel_b
			var sign_x := -1.0 if i == 0 else 1.0
			Shapes.box(p, Vector3(hv.x * 0.5, hv.y, depth * 0.55), Vector3(sign_x * hv.x * 0.25, hv.y * 0.5, 0), panel_mat)
			Shapes.box(p, Vector3(hv.x * 0.5 - 0.1, 0.12, depth * 0.6), Vector3(sign_x * hv.x * 0.25, hv.y * 0.55, 0), Mats.glow(Cfg.C_RED, 1.2))
			Shapes.box(p, Vector3(0.12, hv.y, depth * 0.62), Vector3(sign_x * 0.06, hv.y * 0.5, 0), frame)
	# frame: header + posts
	Shapes.box(holder, Vector3(hv.x + 0.5, 0.7, depth + 0.2), Vector3(0, hv.y + 0.1, 0), frame)
	for sx in [-1.0, 1.0]:
		Shapes.box(holder, Vector3(0.3, hv.y + 0.4, depth + 0.2), Vector3(sx * (hv.x * 0.5 + 0.1), hv.y * 0.5 + 0.1, 0), frame)
	_status_mat = StandardMaterial3D.new()
	_status_mat.emission_enabled = true
	_status_mat.albedo_color = Color.BLACK
	_status = Shapes.box(holder, Vector3(1.2, 0.18, 0.1), Vector3(0, hv.y + 0.1, -depth * 0.5 - 0.1), _status_mat)
	_light = Shapes.add_light(self, Vector3(0, height * 0.8, 0), Cfg.C_RED, 0.8, 6.0)
	_lbl = Shapes.label3d(self, label, Vector3(0, height + 0.9, 0), Cfg.C_RED, 30, 0.006)
	_lbl.visible = label != ""

	# the doorway sensor: nobody gets crushed
	_gap = Area3D.new()
	_gap.collision_layer = 0
	_gap.collision_mask = Cfg.L_PLAYER | Cfg.L_ECHO | Cfg.L_ENEMY
	var gcs := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(size.x + 0.4, 3.0, size.z + 1.0) if width_axis_x else Vector3(size.x + 1.0, 3.0, size.z + 0.4)
	gcs.shape = gshape
	gcs.position = Vector3(0, 1.5, 0)
	_gap.add_child(gcs)
	add_child(_gap)
	if field:
		_hurt = Area3D.new()
		_hurt.collision_layer = 0
		_hurt.collision_mask = Cfg.L_PLAYER
		var hcs := CollisionShape3D.new()
		var hshape := BoxShape3D.new()
		hshape.size = Vector3(size.x + 0.5, 3.0, size.z + 0.5)
		hcs.shape = hshape
		hcs.position = Vector3(0, 1.5, 0)
		_hurt.add_child(hcs)
		add_child(_hurt)
	_register_closed(true)
	_refresh_visuals()
	if level != null:
		level.channel_changed.connect(_on_channel)

const WALL_CLEAR := 5.0

func _on_channel(_id: String, _on: bool) -> void:
	pass   # state is re-evaluated each physics tick; keeps timed doors and edge cases simple

func condition_met() -> bool:
	if requires.is_empty():
		return false
	var n_ok := 0
	for r in requires:
		var key := String(r)
		var want_on := true
		if key.begins_with("!"):
			key = key.substr(1)
			want_on = false
		var ok := level != null and level.get_channel(key) == want_on
		if ok:
			n_ok += 1
	return n_ok > 0 if mode_any else n_ok == requires.size()

func force_open(v: bool) -> void:
	_want = v

func _physics_process(delta: float) -> void:
	var met := condition_met() or _want
	if met:
		_hold_left = hold_time
	elif _hold_left > 0.0:
		_hold_left -= delta
		met = true
	var want := met
	if want and not is_open:
		_set_open(true)
	elif not want and is_open and _doorway_clear():
		_set_open(false)
	var target := 1.0 if is_open else 0.0
	progress = move_toward(progress, target, delta / open_time)
	_animate()
	if field and _hurt != null and progress < 0.95:
		_zap_cd -= delta
		if _zap_cd <= 0.0:
			for b in _hurt.get_overlapping_bodies():
				if b is Player and not (b as Player).dead:
					var info := DamageInfo.make(18.0, Cfg.TEAM_ENEMY, self, "hazard")
					info.direction = (b.global_position - global_position).normalized()
					info.knockback = 7.0
					(b as Player).take_damage(info)
					Sfx.play_at("zap", b.global_position, -2.0)
					Fx.burst(b.global_position + Vector3(0, 1, 0), Cfg.C_RED, 8, 5.0, 0.3)
					_zap_cd = 0.6
	if hold_time > 0.0 and is_open and not condition_met() and _hold_left > 0.0:
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02 * (1.0 + 3.0 * (1.0 - _hold_left / maxf(hold_time, 0.01))))
		_status_mat.emission = Cfg.C_AMBER * (0.3 + blink)

func _doorway_clear() -> bool:
	for b in _gap.get_overlapping_bodies():
		if b is Player or b is Echo or b is Enemy:
			return false
	return true

func _set_open(v: bool) -> void:
	if is_open == v:
		return
	is_open = v
	Sfx.play_at("door" if v else "door_close", global_position, -3.0)
	_register_closed(not v)
	_refresh_visuals()
	state_changed.emit(self, v)

func _register_closed(closed: bool) -> void:
	if level == null or level.nav == null:
		_body.collision_layer = Cfg.L_WORLD if closed else 0
		return
	if closed and not _closed_registered:
		level.nav.add_blocker(cells)
		_closed_registered = true
	elif not closed and _closed_registered:
		level.nav.remove_blocker(cells)
		_closed_registered = false
	_body.collision_layer = Cfg.L_WORLD if closed else 0

func _animate() -> void:
	var s := smoothstep(0.0, 1.0, progress)
	if field:
		_panel_a.visible = progress < 0.98
		if _field_mat != null:
			_field_mat.set_shader_parameter("strength", 1.4 * (1.0 - s))
		return
	var slide := span * 0.5 - 0.05
	_panel_a.position.x = -slide * s
	_panel_b.position.x = slide * s

func _refresh_visuals() -> void:
	var col := Cfg.C_GREEN if is_open else Cfg.C_RED
	if _status_mat != null:
		_status_mat.emission = col * 1.6
		_status_mat.albedo_color = col * 0.3
	if _light != null:
		_light.light_color = col
		_light.light_energy = 0.55
	if _lbl != null:
		_lbl.visible = label != "" and not is_open
	if field and _field_mat != null:
		_field_mat.set_shader_parameter("tint", Cfg.C_RED)

func set_label(text: String) -> void:
	label = text
	if _lbl != null:
		_lbl.text = text
		_lbl.visible = text != "" and not is_open
