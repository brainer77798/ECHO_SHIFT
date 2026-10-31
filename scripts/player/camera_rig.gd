class_name CameraRig
extends Node3D
## Over-the-shoulder third-person camera. Mouse (or right stick) controls yaw/pitch, a SpringArm3D
## pulls the camera in when geometry is in the way, and aim_point() ray-casts through the crosshair.

const PITCH_MIN := -1.15
const PITCH_MAX := 0.60

var target: Node3D
var yaw := 0.0
var pitch := -0.18
var arm_length := 4.3
var shoulder := 0.8
var focus_height := 1.55
var base_fov := 72.0
var fov_kick := 0.0
var look_enabled := true

var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var _shake := 0.0
var _smoothed := Vector3.ZERO
var _first := true

func _ready() -> void:
	top_level = true
	pivot = Node3D.new()
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = arm_length
	arm.collision_mask = Cfg.L_WORLD
	arm.margin = 0.2
	var sph := SphereShape3D.new()
	sph.radius = 0.25
	arm.shape = sph
	arm.position = Vector3(shoulder, 0, 0)
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.near = 0.08
	camera.far = 220.0
	arm.add_child(camera)
	Bus.screen_shake.connect(_on_shake)

func make_current() -> void:
	camera.make_current()

func _on_shake(strength: float) -> void:
	_shake = maxf(_shake, strength)

func _unhandled_input(event: InputEvent) -> void:
	if not look_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var s: float = 0.0022 * Prefs.sensitivity
		yaw -= event.relative.x * s
		pitch -= event.relative.y * s * (-1.0 if Prefs.invert_y else 1.0)
		pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)

func _process(delta: float) -> void:
	if look_enabled:
		var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if stick.length_squared() > 0.0:
			yaw -= stick.x * 2.8 * Prefs.sensitivity * delta
			pitch -= stick.y * 1.8 * Prefs.sensitivity * delta * (-1.0 if Prefs.invert_y else 1.0)
			pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	if is_instance_valid(target):
		var want := target.global_position + Vector3(0, focus_height, 0)
		if _first:
			_smoothed = want
			_first = false
		_smoothed = _smoothed.lerp(want, 1.0 - exp(-28.0 * delta))
		global_position = _smoothed
	pivot.rotation = Vector3(pitch, yaw, 0)
	camera.fov = lerpf(camera.fov, base_fov + fov_kick, 1.0 - exp(-12.0 * delta))
	if _shake > 0.001:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-9.0 * delta))
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	# keep the shoulder offset from poking through a wall beside the player
	var side := pivot.global_transform.basis.x
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + side * (shoulder + 0.3), Cfg.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var want_off := shoulder
	if not hit.is_empty():
		want_off = clampf(global_position.distance_to(hit["position"]) - 0.35, 0.0, shoulder)
	arm.position.x = lerpf(arm.position.x, want_off, 1.0 - exp(-14.0 * delta))

func snap_to_target() -> void:
	_first = true
	if is_instance_valid(target):
		_smoothed = target.global_position + Vector3(0, focus_height, 0)
		global_position = _smoothed

func forward() -> Vector3:
	return -camera.global_transform.basis.z

## World point under the crosshair (first solid thing along the camera ray).
func aim_point(mask := Cfg.L_WORLD | Cfg.L_ENEMY, max_dist := 90.0) -> Vector3:
	var from := camera.global_position
	var dir := forward()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return from + dir * max_dist
	return hit["position"]
