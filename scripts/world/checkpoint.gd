class_name Checkpoint
extends Interactable
## Recovery node. Walking into its radius for the first time records a checkpoint (progress is
## snapshotted and auto-saved); using it restores health and opens the upgrade fabricator.
## Later checkpoints (higher `order`) are never overwritten by walking back into an earlier one.

var cp_id := "cp1"
var order := 1
var area: Area3D

var _ring_mat: ShaderMaterial
var _core: MeshInstance3D
var _light: OmniLight3D
var _lbl: Label3D
var _active := false
var _t := 0.0

func build() -> void:
	prompt = "Recovery node  -  restore & upgrade"
	interact_range = 3.4
	var metal := Mats.plain(Color(0.10, 0.12, 0.16), 0.45, 0.8)
	Shapes.cylinder(self, 1.1, 1.25, 0.18, Vector3(0, 0.09, 0), metal, 24)
	_ring_mat = Mats.energy(Cfg.C_GREEN, 1.0, false, 2.5)
	var ring := Shapes.torus(self, 0.95, 1.05, Vector3(0, 0.22, 0), _ring_mat, 32)
	ring.scale = Vector3(1, 0.18, 1)
	Shapes.cylinder(self, 0.16, 0.22, 1.5, Vector3(0, 0.95, 0), metal, 10)
	_core = Shapes.box(self, Vector3(0.38, 0.38, 0.38), Vector3(0, 1.95, 0), Mats.glow(Cfg.C_GREEN, 2.6))
	_core.rotation = Vector3(0.6, 0.0, 0.6)
	_light = Shapes.add_light(self, Vector3(0, 1.8, 0), Cfg.C_GREEN, 1.1, 7.0)
	_lbl = Shapes.label3d(self, "RECOVERY NODE", Vector3(0, 2.75, 0), Cfg.C_GREEN, 22, 0.006)
	area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = Cfg.L_PLAYER
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.8
	shape.height = 3.0
	cs.shape = shape
	cs.position = Vector3(0, 1.5, 0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body)
	_active = GameState.checkpoint == cp_id
	_refresh()

func _process(delta: float) -> void:
	_t += delta
	if _core != null:
		_core.rotation.y += delta * 1.4
		_core.position.y = 1.95 + sin(_t * 2.0) * 0.08

func _on_body(b: Node) -> void:
	var p := b as Player
	if p == null or not p.is_local or p.dead:
		return
	var cur := int(GameState.get_flag(level.flag_key("cp_order"), 0)) if level != null else 0
	if _active and GameState.checkpoint == cp_id:
		return
	if order < cur:
		return
	_active = true
	if level != null:
		GameState.set_flag(level.flag_key("cp_order"), order)
	p.heal(p.max_health)
	GameState.capture_checkpoint(cp_id, true)
	Sfx.play("checkpoint")
	Bus.checkpoint_reached.emit(cp_id)
	Bus.hud_message.emit("CHECKPOINT SAVED", Cfg.C_GREEN, 2.2)
	Fx.ring(global_position + Vector3(0, 0.2, 0), Cfg.C_GREEN, 3.0, 0.7)
	_refresh()

func interact(who: Node) -> void:
	var p := who as Player
	if p != null:
		p.heal(p.max_health)
		Fx.burst(p.global_position + Vector3(0, 1.0, 0), Cfg.C_GREEN, 10, 3.0, 0.5)
	Sfx.play("health")
	Bus.upgrade_bench_requested.emit()

func _refresh() -> void:
	var c := Cfg.C_GREEN if _active else Cfg.C_AMBER
	_ring_mat.set_shader_parameter("tint", c)
	_light.light_color = c
	_lbl.modulate = Color(c.r, c.g, c.b, 0.9)
	_lbl.text = "RECOVERY NODE" if _active else "RECOVERY NODE - OFFLINE"
