class_name ShieldNode
extends Enemy
## One of WARDEN's shield generators. Stationary, moderately tough, fires a slow defensive bolt at
## whatever it can see. While any shield node is alive, WARDEN itself is immune to damage - killing
## shields is the only way to expose the core. Notifies its owning WardenBoss on death.

var boss: WardenBoss

var _fire_cd := 1.4
var _core_mat: StandardMaterial3D
var _ring: Node3D
var _light: OmniLight3D

func _init() -> void:
	kind_name = "Shield Node"
	max_health = 75.0
	move_speed = 0.0
	radius = 0.6
	body_height = 1.9
	eye_height = 1.1
	hit_radius = 0.8
	fragment_drop = 0
	detect_range = 34.0
	lure_enabled = false

func _build_visual() -> void:
	var dark := Mats.plain(Color(0.10, 0.08, 0.14), 0.4, 0.8)
	Shapes.cylinder(visual, 0.55, 0.7, 0.3, Vector3(0, 0.15, 0), dark, 16)
	Shapes.cylinder(visual, 0.3, 0.42, 1.3, Vector3(0, 1.0, 0), dark, 12)
	_core_mat = StandardMaterial3D.new()
	_core_mat.emission_enabled = true
	_core_mat.albedo_color = Cfg.C_VIOLET * 0.3
	_core_mat.emission = Cfg.C_VIOLET
	_core_mat.emission_energy_multiplier = 2.6
	Shapes.sphere(visual, 0.34, Vector3(0, 1.75, 0), _core_mat, 16)
	_ring = Node3D.new()
	_ring.position = Vector3(0, 1.75, 0)
	visual.add_child(_ring)
	for i in 2:
		Shapes.torus(_ring, 0.44 + i * 0.1, 0.49 + i * 0.1, Vector3.ZERO, Mats.glow(Cfg.C_VIOLET, 1.8), 24).rotation = Vector3(0.6 * i, 0, 0.4 * i)
	_light = Shapes.add_light(visual, Vector3(0, 1.75, 0), Cfg.C_VIOLET, 1.1, 7.0)
	Shapes.label3d(self, "SHIELD NODE", Vector3(0, 2.6, 0), Cfg.C_VIOLET, 20, 0.006)

func _think(delta: float) -> void:
	_ring.rotation.y += delta * 1.6
	_fire_cd -= delta
	if not has_target():
		return
	face_towards(target_center(), delta, 3.0)
	if _fire_cd <= 0.0 and has_los_to(target_center()):
		_fire_cd = randf_range(1.6, 2.4)
		var from := global_position + Vector3(0, 1.75, 0)
		var dir := (target_center() - from).normalized()
		fire_bolt(from, dir, 20.0, 10.0, {"color": Cfg.C_VIOLET, "size": 0.1, "from_point": from})
		Sfx.play_at("enemy_shot", from, -2.0, 0.8)
		Fx.burst(from, Cfg.C_VIOLET, 4, 2.5, 0.2, 0.1, 0.0, dir, 20.0)

func _on_damaged(_info: DamageInfo, _amount: float) -> void:
	_core_mat.emission_energy_multiplier = 4.0
	var tw := create_tween()
	tw.tween_property(_core_mat, "emission_energy_multiplier", 2.6, 0.3)

func _on_death() -> void:
	if is_instance_valid(boss):
		boss.on_shield_down(self)
