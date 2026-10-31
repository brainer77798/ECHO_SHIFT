class_name HunterDrone
extends Enemy
## Fast, fragile pursuer. Closes to mid range, circle-strafes, and fires a three-bolt burst after a
## visible wind-up (the eye flares and a rising tone plays). The aim is locked at the end of the
## wind-up, so moving or dashing sideways avoids the burst. Distracted by Echoes.

const WINDUP_TIME := 0.6
const BURST_SHOTS := 3

var _atk_cd := 1.4
var _strafe := 1.0
var _strafe_t := 2.0
var _burst_left := 0
var _burst_t := 0.0
var _lock_dir := Vector3.FORWARD
var _eye_mat: StandardMaterial3D
var _eye_light: OmniLight3D
var _ring: Node3D
var _shadow: MeshInstance3D
var _los_t := 0.0
var _los := false

func _init() -> void:
	kind_name = "Hunter Drone"
	max_health = 34.0
	move_speed = 8.2
	flying = true
	radius = 0.42
	body_height = 0.84
	eye_height = 0.42
	hit_radius = 0.62
	fragment_drop = 4
	detect_range = 26.0
	accel = 9.0
	hover_y = 1.15

func _build_visual() -> void:
	var dark := Mats.plain(Color(0.10, 0.11, 0.14), 0.4, 0.8)
	var plate := Mats.plain(Color(0.22, 0.12, 0.13), 0.45, 0.7)
	var c := Vector3(0, 0.42, 0)
	Shapes.sphere(visual, 0.34, c, plate, 16)
	Shapes.box(visual, Vector3(0.9, 0.06, 0.16), c + Vector3(0, 0.0, 0.0), dark)
	Shapes.box(visual, Vector3(0.16, 0.06, 0.9), c, dark)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.emission_enabled = true
	_eye_mat.albedo_color = Color(0.3, 0.02, 0.02)
	_eye_mat.emission = Cfg.C_RED
	_eye_mat.emission_energy_multiplier = 3.0
	Shapes.sphere(visual, 0.13, c + Vector3(0, 0.02, -0.28), _eye_mat, 12)
	_ring = Node3D.new()
	_ring.position = c
	visual.add_child(_ring)
	Shapes.torus(_ring, 0.42, 0.47, Vector3.ZERO, Mats.glow(Cfg.C_RED, 1.6), 24)
	for s in [-1.0, 1.0]:
		var th := Shapes.cylinder(visual, 0.1, 0.13, 0.28, c + Vector3(s * 0.44, -0.02, 0.1), dark, 10)
		th.rotation.z = PI * 0.5
		Shapes.box(visual, Vector3(0.04, 0.04, 0.2), c + Vector3(s * 0.56, -0.02, 0.1), Mats.glow(Cfg.C_ORANGE, 2.5))
	Shapes.cylinder(visual, 0.015, 0.015, 0.4, c + Vector3(0.14, 0.45, 0.1), dark, 6)
	_eye_light = Shapes.add_light(visual, c + Vector3(0, 0, -0.5), Cfg.C_RED, 0.5, 4.0)
	_shadow = Props.blob_shadow(self, 0.55, 0.5)
	_shadow.top_level = true

func _process(_delta: float) -> void:
	if _shadow != null and state != State.DEAD:
		_shadow.global_position = Vector3(global_position.x, 0.03, global_position.z)
		var h := clampf(global_position.y, 0.0, 3.0)
		_shadow.scale = Vector3.ONE * (1.0 - h * 0.1)

func _think(delta: float) -> void:
	_atk_cd -= delta
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.12
		_los = has_target() and has_los_to(target_center())
	_ring.rotation.y += delta * 4.0
	_ring.rotation.x = 0.35 * sin(Time.get_ticks_msec() * 0.004)
	match state:
		State.IDLE:
			stop_moving(delta)
			_set_eye(1.5, Cfg.C_RED)
		State.PATROL:
			patrol_step(delta, 3.2)
			_set_eye(1.5, Cfg.C_RED)
		State.CHASE:
			_chase(delta)
		State.WINDUP:
			_windup(delta)
		State.ATTACK:
			_attack(delta)
		State.RECOVER:
			stop_moving(delta)
			if _state_time > 0.4:
				set_state(State.CHASE)

func _chase(delta: float) -> void:
	_set_eye(3.0, Cfg.C_RED)
	if not has_target():
		# lost them: go to the last known position, then give up
		if nav_move(last_known, move_speed * 0.7, delta, 1.2) and memory_left <= 0.0:
			set_state(State.PATROL if patrol_points.size() > 1 else State.IDLE)
		else:
			face_towards(last_known, delta)
		return
	var tp := target.global_position
	var flat := Vector3(tp.x - global_position.x, 0.0, tp.z - global_position.z)
	var d := flat.length()
	face_towards(tp, delta, 12.0)
	if _atk_cd <= 0.0 and _los and d < 18.0:
		_begin_windup()
		return
	if d > 10.5 or not _los:
		nav_move(tp, move_speed, delta, 6.0)
		return
	# circle-strafe around the target at a comfortable range
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.4, 2.8)
		_strafe = -_strafe if randf() > 0.4 else _strafe
	var radial := flat / maxf(d, 0.01)
	var tangent := Vector3(-radial.z, 0.0, radial.x) * _strafe
	var range_fix := radial * clampf((d - 7.5) * 0.6, -1.0, 1.0)
	_apply_velocity((tangent * 0.8 + range_fix).limit_length(1.0) * move_speed * 0.7 + _separation(), delta)

func _begin_windup() -> void:
	set_state(State.WINDUP)
	Sfx.play_at("warn", global_position, 0.0, 1.0)

func _windup(delta: float) -> void:
	stop_moving(delta)
	if has_target():
		face_towards(target.global_position, delta, 14.0)
	var k := clampf(_state_time / WINDUP_TIME, 0.0, 1.0)
	_set_eye(3.0 + 9.0 * k, Cfg.C_RED.lerp(Color(1, 0.9, 0.7), k))
	if _state_time >= WINDUP_TIME:
		var from := global_position + Vector3(0, 0.42, 0)
		_lock_dir = (target_center() - from).normalized()
		_burst_left = BURST_SHOTS
		_burst_t = 0.0
		set_state(State.ATTACK)

func _attack(delta: float) -> void:
	stop_moving(delta)
	_burst_t -= delta
	if _burst_left > 0 and _burst_t <= 0.0:
		_burst_t = 0.13
		var idx := BURST_SHOTS - _burst_left
		var yaw_off := deg_to_rad(-4.0 + 4.0 * idx)
		var dir := _lock_dir.rotated(Vector3.UP, yaw_off)
		var from := global_position + Vector3(0, 0.42, 0) - global_transform.basis.z * 0.5
		fire_bolt(from, dir, 24.0, 8.0, {"from_point": global_position + Vector3(0, 0.42, 0)})
		Sfx.play_at("enemy_shot", from, -3.0, randf_range(0.95, 1.1))
		_burst_left -= 1
		_set_eye(12.0, Color(1, 0.9, 0.7))
	if _burst_left <= 0 and _burst_t <= 0.0:
		_atk_cd = randf_range(2.0, 3.0)
		set_state(State.RECOVER)

func _set_eye(energy: float, col: Color) -> void:
	_eye_mat.emission_energy_multiplier = energy
	_eye_mat.emission = col
	_eye_light.light_color = col
	_eye_light.light_energy = clampf(energy * 0.12, 0.3, 1.6)

func _on_spotted() -> void:
	set_state(State.CHASE)
	_atk_cd = maxf(_atk_cd, 0.9)

func _on_damaged(_info: DamageInfo, _amount: float) -> void:
	if state == State.WINDUP and health < max_health * 0.3:
		set_state(State.CHASE)   # a badly hurt drone breaks off its attack
