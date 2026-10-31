class_name Pickup
extends Node3D
## Collectible: "frag" (data fragments, the upgrade currency) or "health" (repair cell).
## Drifts towards a nearby operative and is collected on contact. A placed pickup with a
## `persist_key` is remembered in GameState so it does not respawn after being taken.

const MAX_LIVE := 80
static var live := 0

var kind := "frag"
var value := 5
var persist_key := ""

var _t := 0.0
var _base_y := 0.0
var _vel := Vector3.ZERO
var _age := 0.0
var _mesh: Node3D
var _taken := false

static func spawn(parent: Node, p_kind: String, pos: Vector3, p_value: int, p_persist := "", scatter := false) -> Pickup:
	if live >= MAX_LIVE or not is_instance_valid(parent):
		return null
	var p := Pickup.new()
	p.kind = p_kind
	p.value = p_value
	p.persist_key = p_persist
	parent.add_child(p)
	p.global_position = pos
	p._base_y = pos.y
	if scatter:
		p._vel = Vector3(randf_range(-2.5, 2.5), randf_range(3.0, 5.0), randf_range(-2.5, 2.5))
	return p

func _ready() -> void:
	live += 1
	_t = randf() * TAU
	_mesh = Node3D.new()
	add_child(_mesh)
	if kind == "health":
		var m := Mats.glow(Cfg.C_GREEN, 2.6)
		Shapes.box(_mesh, Vector3(0.5, 0.16, 0.16), Vector3.ZERO, m)
		Shapes.box(_mesh, Vector3(0.16, 0.5, 0.16), Vector3.ZERO, m)
		Shapes.box(_mesh, Vector3(0.16, 0.16, 0.5), Vector3.ZERO, m)
		Shapes.add_light(self, Vector3(0, 0.2, 0), Cfg.C_GREEN, 0.5, 3.0)
	else:
		var m := Mats.glow(Cfg.C_CYAN, 3.0)
		var s := 0.22 + 0.06 * clampf(float(value) / 10.0, 0.0, 2.0)
		var a := Shapes.box(_mesh, Vector3(s, s, s), Vector3.ZERO, m)
		a.rotation = Vector3(0.78, 0.0, 0.78)
		Shapes.add_light(self, Vector3(0, 0.1, 0), Cfg.C_CYAN, 0.3, 2.2)

func _exit_tree() -> void:
	live = maxi(live - 1, 0)

func _physics_process(delta: float) -> void:
	_age += delta
	_t += delta
	_mesh.rotation.y += delta * 2.2
	# toss from a defeated enemy: simple ballistic hop onto the floor
	if _vel != Vector3.ZERO:
		_vel.y -= 14.0 * delta
		global_position += _vel * delta
		if global_position.y <= 0.7:
			global_position.y = 0.7
			_base_y = 0.7
			_vel = Vector3.ZERO
		return
	_mesh.position.y = sin(_t * 3.0) * 0.08
	var best: Player = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("players"):
		var pl := n as Player
		if pl == null or pl.dead or not pl.is_local:
			continue
		var d := global_position.distance_to(pl.global_position + Vector3(0, 0.9, 0))
		if d < best_d:
			best_d = d
			best = pl
	if best == null or _taken:
		return
	if kind == "health" and best.health >= best.max_health - 0.01 and best_d > 1.2:
		return
	if best_d < 3.2 and _age > 0.4:
		var to := (best.global_position + Vector3(0, 0.9, 0)) - global_position
		global_position += to.normalized() * minf(to.length(), (6.0 + (3.2 - best_d) * 5.0) * delta)
	if best_d < 0.85 and _age > 0.4:
		_collect(best)

func _collect(pl: Player) -> void:
	if kind == "health":
		if pl.health >= pl.max_health - 0.01:
			return
		pl.heal(float(value))
		Sfx.play("health", -4.0)
		Bus.hud_message.emit("+%d INTEGRITY" % value, Cfg.C_GREEN, 1.0)
	else:
		GameState.add_fragments(value)
		Sfx.play("frag", -4.0, randf_range(0.95, 1.2))
	_taken = true
	if persist_key != "":
		GameState.set_flag(persist_key, true)
	Fx.burst(global_position, Cfg.C_GREEN if kind == "health" else Cfg.C_CYAN, 6, 3.0, 0.3, 0.1)
	queue_free()
