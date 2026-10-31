class_name SecurityCamera
extends StaticBody3D
## WARDEN's eye. Sweeps a vision cone; if it holds an operative in the cone (with a clear line)
## long enough it raises the alarm. A camera that can see an Echo fixates on it and ignores
## operatives, so a decoy buys a safe passage. It can be shot out, and a channel in `disabled_by`
## (a security relay) turns it off.

var level: LevelBase
var base_yaw := 0.0
var sweep_half := 1.0
var sweep_speed := 0.55
var fov_half := deg_to_rad(26.0)
var range_m := 17.0
var alarm_delay := 1.4
var health := 40.0
var disabled_by := ""
var cam_id := ""
var destroyed := false

var _yaw_node: Node3D
var _pitch_node: Node3D
var _lens_mat: StandardMaterial3D
var _cone: MeshInstance3D
var _cone_mat: ShaderMaterial
var _light: SpotLight3D
var _yaw := 0.0
var _pitch := -0.35
var _t := 0.0
var _alarm := 0.0
var _cooldown := 0.0
var _locked: Node3D
var _off := false

func build() -> void:
	collision_layer = Cfg.L_ENEMY
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	cs.shape = shape
	cs.position = Vector3(0, -0.2, 0)
	add_child(cs)
	var dark := Mats.plain(Color(0.08, 0.09, 0.12), 0.45, 0.8)
	Shapes.box(self, Vector3(0.7, 0.18, 0.7), Vector3(0, 0.1, 0), dark)
	Shapes.cylinder(self, 0.08, 0.1, 0.45, Vector3(0, -0.12, 0), dark, 8)
	_yaw_node = Node3D.new()
	_yaw_node.position = Vector3(0, -0.4, 0)
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_yaw_node.add_child(_pitch_node)
	Shapes.box(_pitch_node, Vector3(0.38, 0.34, 0.7), Vector3(0, 0, -0.1), Mats.surface("cam_plate", "plates", Color(0.22, 0.2, 0.22), Cfg.C_RED, 1.2, 0.5, 0.6))
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.emission_enabled = true
	_lens_mat.albedo_color = Color(0.1, 0.02, 0.02)
	_lens_mat.emission = Cfg.C_GREEN
	_lens_mat.emission_energy_multiplier = 3.0
	var lens := Shapes.cylinder(_pitch_node, 0.13, 0.13, 0.1, Vector3(0, 0, -0.48), _lens_mat, 12)
	lens.rotation.x = PI * 0.5
	_light = SpotLight3D.new()
	_light.light_color = Cfg.C_GREEN
	_light.light_energy = 3.0
	_light.spot_range = range_m
	_light.spot_angle = rad_to_deg(fov_half)
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, -0.5)
	_pitch_node.add_child(_light)
	_cone_mat = Mats.energy(Cfg.C_GREEN, 0.28, false, 1.5)
	_cone = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = tan(fov_half) * range_m
	cm.height = range_m
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_bottom = false
	_cone.mesh = cm
	_cone.material_override = _cone_mat
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# cylinder axis is Y: lay it along -Z with the narrow tip at the lens
	_cone.rotation.x = -PI * 0.5
	_cone.position = Vector3(0, 0, -0.5 - range_m * 0.5)
	_pitch_node.add_child(_cone)
	_yaw = base_yaw
	_apply()

func _forward() -> Vector3:
	return Vector3(-sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch))

func _head_pos() -> Vector3:
	return _yaw_node.global_position

func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	var off := level != null and disabled_by != "" and level.get_channel(disabled_by)
	if off != _off:
		_off = off
		_set_visible_cone(not off)
		if off:
			_lens_mat.emission = Color(0.2, 0.2, 0.25)
			_light.visible = false
	if _off:
		return
	var target := _find_target()
	if target != null:
		var d := target.global_position + Vector3(0, 1.0, 0) - _head_pos()
		var want_yaw := atan2(-d.x, -d.z)
		var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
		_yaw += clampf(wrapf(want_yaw - _yaw, -PI, PI), -2.2 * delta, 2.2 * delta)
		_pitch = move_toward(_pitch, clampf(want_pitch, -0.9, 0.2), 1.5 * delta)
		if target is Echo:
			_alarm = maxf(_alarm - delta, 0.0)
			_set_state(Cfg.C_AMBER)
		else:
			_alarm += delta
			_set_state(Cfg.C_RED.lerp(Cfg.C_AMBER, clampf(1.0 - _alarm / alarm_delay, 0.0, 1.0)))
			if _alarm >= alarm_delay and _cooldown <= 0.0:
				_cooldown = 25.0
				_alarm = 0.0
				if level != null:
					level.raise_alarm(self)
	else:
		_alarm = maxf(_alarm - delta * 1.5, 0.0)
		_yaw = lerp_angle(_yaw, base_yaw + sin(_t * sweep_speed) * sweep_half, 1.0 - exp(-3.0 * delta))
		_pitch = lerp(_pitch, -0.35, 1.0 - exp(-3.0 * delta))
		_set_state(Cfg.C_GREEN)
	_apply()

func _find_target() -> Node3D:
	var head := _head_pos()
	var fwd := _forward()
	var best_echo: Node3D = null
	var best_echo_d := INF
	var best_player: Node3D = null
	var best_player_d := INF
	for n in get_tree().get_nodes_in_group("echoes"):
		var e := n as Echo
		if e == null or not e.is_lure():
			continue
		var d := _visible_dist(e, head, fwd)
		if d >= 0.0 and d < best_echo_d:
			best_echo_d = d
			best_echo = e
	if best_echo != null:
		return best_echo
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead:
			continue
		var d := _visible_dist(p, head, fwd)
		if d >= 0.0 and d < best_player_d:
			best_player_d = d
			best_player = p
	return best_player

## Distance to `who` if it is inside the cone with a clear line of sight, otherwise -1.
func _visible_dist(who: Node3D, head: Vector3, fwd: Vector3) -> float:
	var c := who.global_position + Vector3(0, 1.0, 0)
	var to := c - head
	var d := to.length()
	if d > range_m or d < 0.5:
		return -1.0
	if fwd.angle_to(to) > fov_half:
		return -1.0
	var q := PhysicsRayQueryParameters3D.create(head, c, Cfg.L_WORLD)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return -1.0
	return d

func _apply() -> void:
	_yaw_node.rotation.y = _yaw - rotation.y
	_pitch_node.rotation.x = _pitch

func _set_state(c: Color) -> void:
	_lens_mat.emission = c
	_light.light_color = c
	_cone_mat.set_shader_parameter("tint", c)

func _set_visible_cone(v: bool) -> void:
	_cone.visible = v

func hit_center() -> Vector3:
	return _head_pos()

func take_damage(info: DamageInfo) -> void:
	if destroyed or info.team != Cfg.TEAM_PLAYER:
		return
	health -= info.amount
	Sfx.play_at("armor_hit", global_position, -2.0, 1.3)
	Fx.impact(_head_pos(), Vector3.DOWN, Cfg.C_AMBER)
	if health <= 0.0:
		destroyed = true
		_cone.visible = false
		_light.visible = false
		_lens_mat.emission = Color.BLACK
		Fx.explosion(_head_pos(), Cfg.C_ORANGE, 0.7)
		Sfx.play_at("explosion", _head_pos(), -4.0)
		collision_layer = 0
		if level != null and cam_id != "":
			GameState.set_flag(level.flag_key("cam_" + cam_id), true)
