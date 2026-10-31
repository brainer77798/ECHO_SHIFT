class_name ArmoredBrute
extends Enemy
## Heavy shock unit. Frontal armour soaks most damage, so it must be flanked or exposed.
##   CHARGE  - long wind-up with a red lane painted on the floor; locks direction late. Dash aside, or
##             let it charge an Echo / empty floor into a wall: it is stunned and its back core opens.
##   SLAM    - short wind-up area strike when someone stays close; dash out of the ring.
##   STUNNED - core exposed, 1.8x damage, no armour. The vulnerability window.
## A charge shatters any Echo it runs through.

const CHARGE_WINDUP := 1.2
const CHARGE_LOCK := 0.8
const CHARGE_SPEED := 15.0
const CHARGE_MAX := 19.0
const SLAM_WINDUP := 0.85
const SLAM_RADIUS := 3.9
const STUN_TIME := 2.9

var _charge_cd := 2.0
var _slam_cd := 0.0
var _attack_kind := ""
var _charge_dir := Vector3.FORWARD
var _charge_travel := 0.0
var _exposed := false
var _core_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _core_light: OmniLight3D
var _lane: MeshInstance3D
var _lane_mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _torso: Node3D
var _head: Node3D
var _anim := 0.0
var _steam_t := 0.0

func _init() -> void:
	kind_name = "Armored Brute"
	max_health = 280.0
	move_speed = 3.3
	radius = 0.8
	body_height = 2.5
	eye_height = 2.0
	hit_radius = 1.05
	fragment_drop = 16
	detect_range = 26.0
	close_threat_range = 9.0
	accel = 7.0

func _build_visual() -> void:
	var armor := Mats.surface("brute_armor", "plates", Color(0.30, 0.22, 0.17), Cfg.C_ORANGE, 0.9, 0.5, 0.7)
	var dark := Mats.plain(Color(0.07, 0.08, 0.10), 0.5, 0.8)
	_core_mat = StandardMaterial3D.new()
	_core_mat.emission_enabled = true
	_core_mat.albedo_color = Color(0.25, 0.08, 0.02)
	_core_mat.emission = Cfg.C_ORANGE
	_core_mat.emission_energy_multiplier = 0.5
	_visor_mat = StandardMaterial3D.new()
	_visor_mat.emission_enabled = true
	_visor_mat.albedo_color = Color(0.3, 0.1, 0.02)
	_visor_mat.emission = Cfg.C_ORANGE
	_visor_mat.emission_energy_multiplier = 2.5
	_leg_l = _limb(Vector3(-0.42, 1.0, 0), Vector3(0.5, 1.0, 0.55), dark)
	_leg_r = _limb(Vector3(0.42, 1.0, 0), Vector3(0.5, 1.0, 0.55), dark)
	Shapes.box(_leg_l, Vector3(0.62, 0.22, 0.75), Vector3(0, -0.95, -0.08), armor)
	Shapes.box(_leg_r, Vector3(0.62, 0.22, 0.75), Vector3(0, -0.95, -0.08), armor)
	_torso = Node3D.new()
	_torso.position = Vector3(0, 1.0, 0)
	visual.add_child(_torso)
	Shapes.box(_torso, Vector3(1.55, 1.1, 1.0), Vector3(0, 0.65, 0), dark)
	Shapes.box(_torso, Vector3(1.45, 1.0, 0.2), Vector3(0, 0.7, -0.55), armor)          # front plate
	Shapes.box(_torso, Vector3(0.9, 0.12, 0.22), Vector3(0, 1.0, -0.6), Mats.glow(Cfg.C_ORANGE, 1.4))
	Shapes.box(_torso, Vector3(0.75, 0.62, 0.12), Vector3(0, 0.7, 0.55), _core_mat)     # back core
	Shapes.box(_torso, Vector3(1.0, 0.9, 0.08), Vector3(0, 0.7, 0.5), dark)
	for sx in [-1.0, 1.0]:
		Shapes.sphere(_torso, 0.46, Vector3(sx * 1.0, 1.1, 0), armor, 12)
	_head = Node3D.new()
	_head.position = Vector3(0, 1.5, -0.1)
	_torso.add_child(_head)
	Shapes.box(_head, Vector3(0.55, 0.42, 0.55), Vector3.ZERO, armor)
	Shapes.box(_head, Vector3(0.45, 0.1, 0.06), Vector3(0, 0.02, -0.29), _visor_mat)
	_arm_l = _arm(Vector3(-1.0, 1.05, 0), dark, armor)
	_arm_r = _arm(Vector3(1.0, 1.05, 0), dark, armor)
	_core_light = Shapes.add_light(_torso, Vector3(0, 0.8, 1.0), Cfg.C_ORANGE, 0.0, 5.0)
	Props.blob_shadow(visual, 1.2, 0.6)
	# floor telegraphs
	_lane_mat = Mats.beam(Cfg.C_RED, 0.0)
	_lane = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.5, 0.04, 1.0)
	_lane.mesh = lm
	_lane.material_override = _lane_mat
	_lane.top_level = true
	_lane.visible = false
	_lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lane)
	_ring_mat = Mats.energy(Cfg.C_RED, 0.0, true, 6.0)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 4
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.top_level = true
	_ring.visible = false
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

func _limb(pos: Vector3, size: Vector3, mat: Material) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	visual.add_child(p)
	Shapes.box(p, size, Vector3(0, -size.y * 0.5, 0), mat)
	return p

func _arm(pos: Vector3, mat: Material, cap: Material) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	_torso.add_child(p)
	Shapes.box(p, Vector3(0.42, 1.0, 0.42), Vector3(0, -0.5, 0), mat)
	Shapes.box(p, Vector3(0.62, 0.55, 0.62), Vector3(0, -1.15, 0), cap)
	return p

# --- Behaviour -------------------------------------------------------------------------------------

func _think(delta: float) -> void:
	_charge_cd -= delta
	_slam_cd -= delta
	match state:
		State.IDLE:
			stop_moving(delta)
		State.PATROL:
			patrol_step(delta, 2.2)
		State.CHASE:
			_chase(delta)
		State.WINDUP:
			_windup(delta)
		State.ATTACK:
			_attack(delta)
		State.RECOVER:
			stop_moving(delta)
			if _state_time > 0.9:
				set_state(State.CHASE)
		State.STUNNED:
			stop_moving(delta)
			_stunned(delta)
	_animate(delta)

func _chase(delta: float) -> void:
	if not has_target():
		if nav_move(last_known, move_speed, delta, 1.5) and memory_left <= 0.0:
			set_state(State.PATROL if patrol_points.size() > 1 else State.IDLE)
		return
	var tp := target.global_position
	var flat := Vector3(tp.x - global_position.x, 0.0, tp.z - global_position.z)
	var d := flat.length()
	face_towards(tp, delta, 4.0)
	var los := has_los_to(target_center())
	if d < 3.5 and _slam_cd <= 0.0:
		_begin_windup("slam")
	elif los and d > 5.5 and d < 18.0 and _charge_cd <= 0.0:
		_begin_windup("charge")
	else:
		nav_move(tp, move_speed, delta, 2.2)

func _begin_windup(kind: String) -> void:
	_attack_kind = kind
	set_state(State.WINDUP)
	if kind == "charge":
		Sfx.play_at("charge", global_position, 2.0, 0.7)
	else:
		Sfx.play_at("warn", global_position, 2.0, 0.6)

func _windup(delta: float) -> void:
	stop_moving(delta)
	if _attack_kind == "charge":
		if _state_time < CHARGE_LOCK and has_target():
			face_towards(target.global_position, delta, 7.0)
		var dir := -global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
		_draw_lane(dir, clampf(_state_time / CHARGE_LOCK, 0.0, 1.0), _state_time >= CHARGE_LOCK)
		if _state_time >= CHARGE_WINDUP:
			_charge_dir = dir
			_charge_travel = 0.0
			_lane.visible = false
			set_state(State.ATTACK)
			Sfx.play_at("dash", global_position, 4.0, 0.5)
	else:
		_ring.visible = true
		_ring.global_position = Vector3(global_position.x, 0.06, global_position.z)
		var k := clampf(_state_time / SLAM_WINDUP, 0.0, 1.0)
		_ring.scale = Vector3.ONE * SLAM_RADIUS * (0.35 + 0.65 * k)
		_ring_mat.set_shader_parameter("strength", 0.6 + 1.6 * k)
		if _state_time >= SLAM_WINDUP:
			_do_slam()

func _draw_lane(dir: Vector3, k: float, locked: bool) -> void:
	var from := global_position + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * CHARGE_MAX, Cfg.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var length := CHARGE_MAX
	if not hit.is_empty():
		length = from.distance_to(hit["position"])
	_lane.visible = true
	_lane.global_position = Vector3(global_position.x, 0.06, global_position.z) + dir * length * 0.5
	_lane.look_at(_lane.global_position + dir, Vector3.UP)
	_lane.scale = Vector3(1.0 if not locked else 1.15, 1.0, length)
	_lane_mat.set_shader_parameter("strength", 0.25 + 0.75 * k if not locked else 1.0)

func _do_slam() -> void:
	_ring.visible = false
	Fx.ring(global_position + Vector3(0, 0.1, 0), Cfg.C_ORANGE, SLAM_RADIUS, 0.4)
	Fx.burst(global_position + Vector3(0, 0.2, 0), Cfg.C_ORANGE, 18, 7.0, 0.5, 0.2)
	Sfx.play_at("explosion", global_position, 0.0, 0.7)
	Bus.screen_shake.emit(0.8)
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead:
			continue
		var off: Vector3 = p.global_position - global_position
		off.y = 0.0
		if off.length() <= SLAM_RADIUS:
			var info := DamageInfo.make(24.0, Cfg.TEAM_ENEMY, self, "melee")
			info.direction = off.normalized()
			info.knockback = 10.0
			p.take_damage(info)
	_shatter_echoes(SLAM_RADIUS)
	_slam_cd = 3.5
	set_state(State.RECOVER)

func _attack(delta: float) -> void:
	velocity.x = _charge_dir.x * CHARGE_SPEED
	velocity.z = _charge_dir.z * CHARGE_SPEED
	velocity.y = -0.5 if is_on_floor() else velocity.y - Cfg.GRAVITY * delta
	move_and_slide()
	_charge_travel += CHARGE_SPEED * delta
	_anim += delta * 14.0
	_steam_t -= delta
	if _steam_t <= 0.0:
		_steam_t = 0.07
		Fx.burst(global_position + Vector3(0, 0.2, 0), Cfg.C_ORANGE, 2, 2.0, 0.3, 0.2, 0.0, -_charge_dir, 30.0)
	# trample
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead:
			continue
		var off: Vector3 = p.global_position - global_position
		off.y = 0.0
		if off.length() < 1.7:
			var info := DamageInfo.make(30.0, Cfg.TEAM_ENEMY, self, "melee")
			info.direction = (_charge_dir + off.normalized() * 0.4).normalized()
			info.knockback = 12.0
			p.take_damage(info)
			_end_charge(false)
			return
	_shatter_echoes(1.7)
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().dot(_charge_dir) < -0.5:
			_end_charge(true)
			return
	if _charge_travel >= CHARGE_MAX:
		_end_charge(false)

func _end_charge(hit_wall: bool) -> void:
	_charge_cd = randf_range(3.5, 5.0)
	if hit_wall:
		_stun()
		Fx.explosion(global_position + Vector3(0, 1.0, 0) + _charge_dir * 0.8, Cfg.C_ORANGE, 1.1)
		Sfx.play_at("explosion", global_position, 2.0, 0.6)
		Bus.screen_shake.emit(0.9)
	else:
		set_state(State.RECOVER)

func _shatter_echoes(r: float) -> void:
	for n in get_tree().get_nodes_in_group("echoes"):
		var e := n as Echo
		if e != null and e.global_position.distance_to(global_position) < r:
			e.expire()

func _stun() -> void:
	set_state(State.STUNNED)
	_exposed = true
	_core_mat.emission_energy_multiplier = 6.0
	_core_light.light_energy = 1.6
	Bus.hud_message.emit("ARMOR BREACHED - ATTACK THE CORE", Cfg.C_ORANGE, 1.6)

func _stunned(delta: float) -> void:
	_steam_t -= delta
	if _steam_t <= 0.0:
		_steam_t = 0.25
		Fx.burst(global_position + Vector3(0, 1.7, 0.6), Color(0.8, 0.9, 1.0), 3, 2.0, 0.6, 0.25, 1.0, Vector3.UP, 40.0)
	if _state_time >= STUN_TIME:
		_exposed = false
		_core_mat.emission_energy_multiplier = 0.5
		_core_light.light_energy = 0.0
		set_state(State.RECOVER)

# --- Damage ---------------------------------------------------------------------------------------------

func _damage_modifier(info: DamageInfo) -> float:
	if _exposed:
		return 1.8
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	var from_attacker := -info.direction
	from_attacker.y = 0.0
	if from_attacker.length() > 0.01 and fwd.length() > 0.01 and fwd.normalized().dot(from_attacker.normalized()) > 0.25:
		return 0.3
	return 1.0

func _on_damaged(info: DamageInfo, amount: float) -> void:
	if amount < info.amount * 0.5:
		Sfx.play_at("armor_hit", global_position, -2.0, randf_range(0.9, 1.2))
		Fx.impact(info.point if info.point != Vector3.ZERO else hit_center(), Vector3.UP, Cfg.C_AMBER)

func _on_spotted() -> void:
	set_state(State.CHASE)
	_charge_cd = maxf(_charge_cd, 1.2)

func _on_death() -> void:
	_lane.visible = false
	_ring.visible = false

# --- Animation --------------------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var walking := state != State.ATTACK and speed > 0.4
	if walking:
		_anim += delta * (2.0 + speed * 1.2)
	var swing := sin(_anim) * clampf(speed / 3.0, 0.0, 1.0) * 0.6
	if state == State.ATTACK:
		swing = sin(_anim) * 0.9
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	_torso.rotation.z = sin(_anim) * 0.04 * clampf(speed / 3.0, 0.0, 1.0)
	var arm_l := -swing * 0.8
	var arm_r := swing * 0.8
	var lean := 0.0
	if state == State.WINDUP:
		if _attack_kind == "slam":
			var k := clampf(_state_time / SLAM_WINDUP, 0.0, 1.0)
			arm_l = lerpf(0.0, -2.6, k)
			arm_r = lerpf(0.0, -2.6, k)
			lean = -0.15 * k
		else:
			lean = -0.2 * clampf(_state_time / CHARGE_WINDUP, 0.0, 1.0)
			arm_l = -0.6
			arm_r = -0.6
	elif state == State.ATTACK:
		lean = 0.45
		arm_l = 0.9
		arm_r = 0.9
	elif state == State.STUNNED:
		lean = 0.3
		arm_l = 0.5
		arm_r = 0.5
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, arm_l, 1.0 - exp(-12.0 * delta))
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, arm_r, 1.0 - exp(-12.0 * delta))
	_torso.rotation.x = lerpf(_torso.rotation.x, lean, 1.0 - exp(-8.0 * delta))
	_head.rotation.x = 0.4 if state == State.STUNNED else 0.0
