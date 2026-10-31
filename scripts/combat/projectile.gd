class_name Projectile
extends Node3D
## Energy bolt. Moves in fixed steps and ray-casts every step (no tunnelling through thin walls),
## so shots never pass through solid geometry. Applies damage exactly once, then frees itself.

const MAX_LIVE := 160
static var live := 0

var velocity := Vector3.ZERO
var damage := 10.0
var team := Cfg.TEAM_PLAYER
var source: Node = null
var source_player: Node = null
var from_echo := false
var max_range := Cfg.BLASTER_RANGE
var color := Cfg.C_CYAN
var kind := "blaster"
var hit_radius := 0.0       # forgiving proximity assist against entities
var knockback := 0.0
var homing := 0.0           # turn rate (rad/s) towards homing_target, 0 = off
var homing_target: Node3D = null
var pierce_world := false

var _traveled := 0.0
var _age := 0.0
var _done := false
var _mask := 0

## Spawns a projectile. `opts` keys: from_echo, color, size, range, kind, source_player,
## hit_radius, knockback, homing, homing_target, from_point (muzzle sanity check origin).
static func spawn(parent: Node, origin: Vector3, dir: Vector3, speed: float, dmg: float, p_team: int, p_source: Node, opts := {}) -> Projectile:
	if live >= MAX_LIVE or not is_instance_valid(parent) or dir.length_squared() < 0.0001:
		return null
	var p := Projectile.new()
	p.damage = dmg
	p.team = p_team
	p.source = p_source
	p.source_player = opts.get("source_player", p_source)
	p.from_echo = opts.get("from_echo", false)
	p.color = opts.get("color", Cfg.C_CYAN if p_team == Cfg.TEAM_PLAYER else Cfg.C_RED)
	p.max_range = opts.get("range", Cfg.BLASTER_RANGE)
	p.kind = opts.get("kind", "blaster")
	p.hit_radius = opts.get("hit_radius", 0.18 if p_team == Cfg.TEAM_PLAYER else 0.3)
	p.knockback = opts.get("knockback", 0.0)
	p.homing = opts.get("homing", 0.0)
	p.homing_target = opts.get("homing_target", null)
	p.velocity = dir.normalized() * speed
	p._mask = Cfg.L_WORLD | ((Cfg.L_ENEMY | Cfg.L_TRIGGER) if p_team == Cfg.TEAM_PLAYER else (Cfg.L_PLAYER | Cfg.L_ECHO))
	var size: float = opts.get("size", 0.07)
	p._build_visual(size)
	live += 1
	parent.add_child(p)
	p.global_position = origin
	p.look_at(origin + dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT)
	# Muzzle sanity check: if a wall sits between the shooter's body and the muzzle, impact immediately.
	var from_pt: Variant = opts.get("from_point", null)
	if from_pt is Vector3:
		var q := PhysicsRayQueryParameters3D.create(from_pt, origin, Cfg.L_WORLD)
		var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			p._impact(hit["position"], hit["normal"], hit["collider"])
	return p

func _build_visual(size: float) -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = size
	cap.height = size * 9.0 if team == Cfg.TEAM_PLAYER else size * 5.0
	cap.radial_segments = 8
	cap.rings = 2
	mi.mesh = cap
	mi.rotation_degrees.x = 90.0
	var mat: Material
	if from_echo:
		mat = Mats.holo(color, 1.1)
	else:
		mat = Mats.glow(color, 5.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _exit_tree() -> void:
	live = maxi(live - 1, 0)

func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if homing > 0.0 and is_instance_valid(homing_target):
		var want := (homing_target.global_position + Vector3(0, 1.0, 0) - global_position).normalized()
		var cur := velocity.normalized()
		var ang := cur.angle_to(want)
		if ang > 0.001:
			var turn := minf(ang, homing * delta)
			var axis := cur.cross(want)
			if axis.length_squared() > 0.000001:
				cur = cur.rotated(axis.normalized(), turn)
				velocity = cur * velocity.length()
				look_at(global_position + cur, Vector3.UP)
	var from := global_position
	var step := velocity * delta
	var to := from + step
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, _mask)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	var best_t := 2.0
	var hit_pos := Vector3.ZERO
	var hit_normal := Vector3.UP
	var hit_body: Object = null
	if not hit.is_empty():
		hit_body = hit["collider"]
		hit_pos = hit["position"]
		hit_normal = hit["normal"]
		best_t = from.distance_to(hit_pos) / maxf(step.length(), 0.0001)
	# Proximity assist: forgiving sphere test against live entities (only if nearer than the wall hit).
	if hit_radius > 0.0:
		var assist: Variant = _assist_target(from, to, best_t)
		if assist != null:
			hit_body = assist["node"]
			hit_pos = assist["pos"]
			hit_normal = -velocity.normalized()
			best_t = assist["t"]
	if hit_body != null:
		_impact(hit_pos, hit_normal, hit_body)
		return
	global_position = to
	_traveled += step.length()
	if _traveled >= max_range or _age > 8.0:
		_done = true
		queue_free()

func _assist_target(from: Vector3, to: Vector3, best_t: float) -> Variant:
	var groups: Array[String] = []
	if team == Cfg.TEAM_PLAYER:
		groups.append("enemies")
	else:
		groups.append("players")
		groups.append("echoes")
	var seg := to - from
	var seg_len2 := maxf(seg.length_squared(), 0.000001)
	var best: Variant = null
	for g in groups:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node3D) or not n.has_method("take_damage") or not n.has_method("hit_center"):
				continue
			if n.has_method("is_targetable") and not n.is_targetable():
				continue
			var c: Vector3 = n.hit_center()
			var r: float = float(n.get("hit_radius")) if n.get("hit_radius") != null else 0.5
			var t := clampf((c - from).dot(seg) / seg_len2, 0.0, 1.0)
			var closest := from + seg * t
			if closest.distance_to(c) <= r + hit_radius and t < best_t:
				best_t = t
				best = {"node": n, "pos": closest, "t": t}
	return best

func _impact(pos: Vector3, normal: Vector3, body: Object) -> void:
	if _done:
		return
	_done = true
	global_position = pos
	var dmg_target: Object = body
	if body != null and body.has_method("take_damage"):
		var info := DamageInfo.new()
		info.amount = damage
		info.team = team
		info.source = source if is_instance_valid(source) else null
		info.source_player = source_player if is_instance_valid(source_player) else null
		info.from_echo = from_echo
		info.direction = velocity.normalized()
		info.point = pos
		info.knockback = knockback
		info.kind = kind
		dmg_target.take_damage(info)
	else:
		Sfx.play_at("hit", pos, -10.0, randf_range(0.9, 1.15))
	Fx.impact(pos, normal, color)
	queue_free()
