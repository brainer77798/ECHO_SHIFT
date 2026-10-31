class_name Sentry
extends Enemy
## Stationary turret that guards corridors and objectives. The head turns at a limited rate, so
## the target can out-rotate it. Before firing it paints a red laser along its aim for a full
## wind-up; the aim freezes shortly before the shot, leaving a clear window to leave the line.
## Echoes in sight are tracked like operatives, which is the intended way past it.

const WINDUP_TIME := 1.15
const LOCK_TIME := 0.8
const TRACK_RATE := 2.0

var base_yaw := 0.0
var _head_yaw := 0.0
var _head_pitch := 0.0
var _yaw_node: Node3D
var _pitch_node: Node3D
var _muzzle: Node3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _eye_mat: StandardMaterial3D
var _eye_light: OmniLight3D
var _atk_cd := 1.0
var _shots_left := 0
var _shot_t := 0.0
var _scan_t := 0.0

func _init() -> void:
	kind_name = "Sentry"
	max_health = 90.0
	move_speed = 0.0
	radius = 0.55
	body_height = 1.7
	eye_height = 1.35
	hit_radius = 0.75
	fragment_drop = 8
	detect_range = 30.0
	close_threat_range = 10.0
	memory_time = 2.5

func _build_visual() -> void:
	var dark := Mats.plain(Color(0.09, 0.10, 0.13), 0.45, 0.8)
	var plate := Mats.surface("sentry_plate", "plates", Color(0.25, 0.15, 0.15), Cfg.C_RED, 1.2, 0.5, 0.6)
	Shapes.cylinder(visual, 0.6, 0.7, 0.18, Vector3(0, 0.09, 0), dark, 16)
	Shapes.cylinder(visual, 0.28, 0.4, 0.9, Vector3(0, 0.6, 0), plate, 12)
	Shapes.torus(visual, 0.38, 0.44, Vector3(0, 0.3, 0), Mats.glow(Cfg.C_RED, 1.6), 20).scale = Vector3(1, 0.2, 1)
	_yaw_node = Node3D.new()
	_yaw_node.position = Vector3(0, 1.3, 0)
	visual.add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_yaw_node.add_child(_pitch_node)
	Shapes.sphere(_yaw_node, 0.32, Vector3.ZERO, plate, 14)
	Shapes.box(_pitch_node, Vector3(0.5, 0.36, 0.6), Vector3(0, 0, -0.1), plate)
	for sx in [-1.0, 1.0]:
		Shapes.cylinder(_pitch_node, 0.05, 0.07, 0.75, Vector3(sx * 0.15, -0.05, -0.62), dark, 8).rotation.x = PI * 0.5
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.emission_enabled = true
	_eye_mat.albedo_color = Color(0.3, 0.02, 0.02)
	_eye_mat.emission = Cfg.C_RED
	_eye_mat.emission_energy_multiplier = 2.0
	Shapes.box(_pitch_node, Vector3(0.26, 0.07, 0.04), Vector3(0, 0.1, -0.41), _eye_mat)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, -0.05, -1.0)
	_pitch_node.add_child(_muzzle)
	_eye_light = Shapes.add_light(_pitch_node, Vector3(0, 0.1, -0.6), Cfg.C_RED, 0.5, 4.0)
	_beam_mat = Mats.beam(Cfg.C_RED, 0.0)
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 1.0)
	_beam.mesh = bm
	_beam.material_override = _beam_mat
	_beam.top_level = true
	_beam.visible = false
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	Props.blob_shadow(visual, 0.85, 0.5)
	_head_yaw = base_yaw

func _forward(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

func _think(delta: float) -> void:
	_atk_cd -= delta
	match state:
		State.IDLE, State.PATROL:
			_scan_t += delta
			var want := base_yaw + sin(_scan_t * 0.55) * 0.9
			_turn_towards(want, 0.0, 0.6, delta)
			_set_eye(1.5, 0.4)
		State.CHASE:
			_track(delta)
		State.WINDUP:
			_windup(delta)
		State.ATTACK:
			_fire(delta)
		State.RECOVER:
			_beam.visible = false
			_set_eye(1.5, 0.4)
			if _state_time > 1.2:
				set_state(State.CHASE if has_target() else State.IDLE)
	_apply_head()

func _aim_angles(point: Vector3) -> Vector2:
	var from := _muzzle.global_position
	var d := point - from
	var flat := Vector2(d.x, d.z).length()
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, maxf(flat, 0.01)))

func _turn_towards(yaw: float, pitch: float, rate: float, delta: float) -> void:
	var diff := wrapf(yaw - _head_yaw, -PI, PI)
	_head_yaw += clampf(diff, -rate * delta, rate * delta)
	_head_pitch = move_toward(_head_pitch, clampf(pitch, -0.6, 0.6), rate * delta)

func _apply_head() -> void:
	_yaw_node.rotation.y = _head_yaw - rotation.y
	_pitch_node.rotation.x = _head_pitch

func _track(delta: float) -> void:
	if not has_target():
		if memory_left <= 0.0:
			set_state(State.IDLE)
		return
	var a := _aim_angles(target_center())
	_turn_towards(a.x, a.y, TRACK_RATE, delta)
	_set_eye(3.0, 0.7)
	var err := absf(wrapf(a.x - _head_yaw, -PI, PI)) + absf(a.y - _head_pitch)
	if _atk_cd <= 0.0 and err < 0.15 and has_los_to(target_center()):
		set_state(State.WINDUP)
		Sfx.play_at("charge", _muzzle.global_position, -6.0, 1.6)

func _windup(delta: float) -> void:
	var k := clampf(_state_time / WINDUP_TIME, 0.0, 1.0)
	if _state_time < LOCK_TIME and has_target():
		var a := _aim_angles(target_center())
		var rate := lerpf(TRACK_RATE * 0.8, 0.5, k)
		_turn_towards(a.x, a.y, rate, delta)
	_set_eye(3.0 + 8.0 * k, 0.7 + k)
	_draw_beam(0.35 + 0.65 * k if _state_time < LOCK_TIME else 1.0, _state_time >= LOCK_TIME)
	if _state_time >= WINDUP_TIME:
		_shots_left = 2
		_shot_t = 0.0
		set_state(State.ATTACK)

func _fire(delta: float) -> void:
	_shot_t -= delta
	if _shots_left > 0 and _shot_t <= 0.0:
		_shot_t = 0.16
		var dir := _forward(_head_yaw, _head_pitch)
		fire_bolt(_muzzle.global_position, dir, 36.0, 14.0, {"size": 0.12, "from_point": _pitch_node.global_position})
		Sfx.play_at("enemy_shot", _muzzle.global_position, 0.0, 0.8)
		Fx.burst(_muzzle.global_position, Cfg.C_RED, 4, 3.0, 0.15, 0.14, 0.0, dir, 25.0)
		_shots_left -= 1
		_set_eye(14.0, 1.0)
	if _shots_left <= 0 and _shot_t <= 0.0:
		_atk_cd = randf_range(0.9, 1.5)
		_beam.visible = false
		set_state(State.RECOVER)

func _draw_beam(strength: float, locked: bool) -> void:
	var from := _muzzle.global_position
	var dir := _forward(_head_yaw, _head_pitch)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, Cfg.L_WORLD | Cfg.L_PLAYER | Cfg.L_ECHO)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + dir * 60.0
	if not hit.is_empty():
		end = hit["position"]
	var len_v := from.distance_to(end)
	_beam.visible = true
	_beam.global_position = (from + end) * 0.5
	_beam.look_at(end, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	_beam.scale = Vector3(1.0 if not locked else 2.2, 1.0 if not locked else 2.2, len_v)
	_beam_mat.set_shader_parameter("strength", strength)

func _set_eye(energy: float, light: float) -> void:
	_eye_mat.emission_energy_multiplier = energy
	_eye_light.light_energy = light

func _on_spotted() -> void:
	set_state(State.CHASE)
	Sfx.play_at("warn", global_position, -4.0, 0.8)

func _on_death() -> void:
	if _beam != null:
		_beam.visible = false
