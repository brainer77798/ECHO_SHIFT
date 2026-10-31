class_name TriggerZone
extends Area3D
## Invisible box that fires once when an operative walks in (dialogue, tutorial hints, encounters).
## `flag_key` makes it remember that it has fired across checkpoints.

signal fired(zone: TriggerZone, who: Player)

var callback: Callable = Callable()
var once := true
var flag_key := ""
var zone_id := ""
var _done := false

func build(size: Vector3) -> void:
	collision_layer = 0
	collision_mask = Cfg.L_PLAYER
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)
	if flag_key != "" and GameState.has_flag(flag_key):
		_done = true
	body_entered.connect(_on_body)

func reset() -> void:
	_done = false

func _on_body(b: Node) -> void:
	var p := b as Player
	if p == null or not p.is_local or p.dead:
		return
	if once and _done:
		return
	_done = true
	if flag_key != "":
		GameState.set_flag(flag_key, true)
	fired.emit(self, p)
	if callback.is_valid():
		callback.call(p)
