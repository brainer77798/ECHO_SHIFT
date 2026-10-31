class_name WardenBoss
extends Node3D
## The Chrono Core's guardian intelligence. Three phases:
##   1 SECURITY PROTOCOL - shielded by 3 ShieldNodes; the core itself is invulnerable and fires
##     slow spread bursts. Destroy every shield to expose it.
##   2 SYSTEM OVERLOAD - the core takes damage directly. Attacks intensify (faster bursts, a homing
##     seeker bolt that targets a live Echo over the operative when one is near) and the chapter
##     enables its environmental hazards.
##   3 CORE EXPOSURE - once health drops below EXPOSE_HP_RATIO, the core alternates ARMORED
##     (invulnerable, telegraphed AoE pulse that forces movement) and EXPOSED (vulnerable, nearly
##     passive) windows. Burst it down during EXPOSED.
## Defeat plays the closing dialogue and tells the level to reveal the three ending consoles.

signal phase_changed(phase: int)
signal defeated

const EXPOSE_HP_RATIO := 0.45
const ARMORED_TIME := 5.0
const EXPOSED_TIME := 4.5

enum CoreState { ARMORED, EXPOSED }

var max_health := 1400.0
var health := 0.0
var phase := 1
var active := false
var shields: Array = []
var core_state: CoreState = CoreState.ARMORED

var _core_mat: ShaderMaterial
var _shell_mat: StandardMaterial3D
var _ring: Node3D
var _light: OmniLight3D
var _attack_t := 1.5
var _state_t := 0.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()
var _defeated := false

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	_rng.randomize()
	_build_visual()
	health = max_health

func start(p_shields: Array) -> void:
	shields = p_shields
	for s in shields:
		(s as ShieldNode).boss = self
	active = true
	phase = 1
	health = max_health
	if shields.is_empty():
		push_warning("WardenBoss: started with no shield nodes - skipping straight to phase 2")
		phase = 2
	_push_bar()

func _build_visual() -> void:
	var core := Node3D.new()
	core.name = "Core"
	add_child(core)
	_core_mat = Mats.energy(Cfg.C_RED, 1.4, true, 2.0)
	Shapes.sphere(core, 1.3, Vector3(0, 2.6, 0), _core_mat, 28)
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = Color(0.1, 0.09, 0.1)
	_shell_mat.metallic = 0.7
	_shell_mat.roughness = 0.35
	for i in 3:
		var shell := Shapes.sphere(core, 1.55, Vector3(0, 2.6, 0), _shell_mat, 20)
		shell.rotation = Vector3(0.3 * i, 1.1 * i, 0)
		shell.scale = Vector3(1.0, 0.25, 1.0)
	_ring = Node3D.new()
	_ring.position = Vector3(0, 2.6, 0)
	core.add_child(_ring)
	for i in 3:
		var t := Shapes.torus(_ring, 1.8 + i * 0.3, 1.88 + i * 0.3, Vector3.ZERO, Mats.glow(Cfg.C_RED, 1.6), 36)
		t.rotation = Vector3(0.5 + i * 0.6, 0, 0.3 * i)
	Shapes.cylinder(core, 0.9, 1.3, 2.6, Vector3(0, 1.3, 0), _shell_mat, 20)
	_light = Shapes.add_light(core, Vector3(0, 2.6, 0), Cfg.C_RED, 2.0, 14.0)

func _process(delta: float) -> void:
	if not active:
		return
	_ring.rotation.y += delta * 0.6
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.0, 0.0)
	var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.002)
	var col := _phase_color()
	_core_mat.set_shader_parameter("tint", col)
	_core_mat.set_shader_parameter("strength", 1.2 + _flash * 2.0 + k * 0.2)
	_light.light_color = col

func _phase_color() -> Color:
	if phase == 3 and core_state == CoreState.EXPOSED:
		return Cfg.C_GREEN
	if phase >= 2:
		return Cfg.C_ORANGE
	return Cfg.C_RED

func _physics_process(delta: float) -> void:
	if not active or _defeated:
		return
	_attack_t -= delta
	_state_t -= delta
	match phase:
		1:
			if _attack_t <= 0.0:
				_spread_burst(5, 0.5)
				_attack_t = randf_range(2.6, 3.4)
		2:
			if _attack_t <= 0.0:
				if _rng.randf() < 0.5:
					_spread_burst(7, 0.42)
				else:
					_seeker_bolt()
				_attack_t = randf_range(1.8, 2.6)
			if health <= max_health * EXPOSE_HP_RATIO:
				_enter_phase(3)
		3:
			_tick_phase3(delta)
	_push_bar()

func _enter_phase(p: int) -> void:
	if phase == p:
		return
	phase = p
	_attack_t = 1.2
	if p == 3:
		core_state = CoreState.ARMORED
		_state_t = ARMORED_TIME
	Bus.hud_message.emit({1: "", 2: "WARDEN - SYSTEM OVERLOAD", 3: "WARDEN - CORE EXPOSURE CYCLING"}.get(p, ""), Cfg.C_RED, 2.5)
	Sfx.play("boss_phase", 0.0)
	Bus.screen_shake.emit(0.6)
	phase_changed.emit(p)

func _tick_phase3(_delta: float) -> void:
	if _state_t <= 0.0:
		if core_state == CoreState.ARMORED:
			core_state = CoreState.EXPOSED
			_state_t = EXPOSED_TIME
			Bus.hud_message.emit("CORE EXPOSED", Cfg.C_GREEN, 1.5)
			Sfx.play("shield_down", -2.0)
		else:
			core_state = CoreState.ARMORED
			_state_t = ARMORED_TIME
			Bus.hud_message.emit("WARDEN RE-ARMORING", Cfg.C_RED, 1.5)
	if core_state == CoreState.ARMORED and _attack_t <= 0.0:
		_core_pulse()
		_attack_t = randf_range(2.2, 2.8)
	elif core_state == CoreState.EXPOSED and _attack_t <= 0.0:
		_spread_burst(3, 0.6)
		_attack_t = 2.0

# --- Attacks ---------------------------------------------------------------------------------------

func _muzzle() -> Vector3:
	return global_position + Vector3(0, 2.6, 0)

func _best_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead:
			continue
		var d := _muzzle().distance_to(p.hit_center())
		if d < best_d:
			best_d = d
			best = p
	return best

func _best_lure() -> Node3D:
	for n in get_tree().get_nodes_in_group("echoes"):
		var e := n as Echo
		if e != null and e.is_lure():
			return e
	return null

func _spread_burst(count: int, spread_deg: float) -> void:
	var target := _best_target()
	if target == null:
		return
	Sfx.play_at("charge", _muzzle(), 0.0, 0.8)
	_flash = 1.0
	var base_dir: Vector3 = (target.hit_center() - _muzzle()).normalized()
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		if not active or _defeated:
			return
		for i in count:
			var off := (float(i) - float(count - 1) * 0.5) * spread_deg
			var dir: Vector3 = base_dir.rotated(Vector3.UP, deg_to_rad(off))
			Projectile.spawn(Fx.world(), _muzzle(), dir, 20.0, 10.0 + phase * 2.0, Cfg.TEAM_ENEMY, self, {"color": Cfg.C_RED, "size": 0.13})
		Sfx.play_at("enemy_shot", _muzzle(), 2.0, 0.6))

func _seeker_bolt() -> void:
	var lure := _best_lure()
	var target: Node3D = lure if lure != null else _best_target()
	if target == null:
		return
	Sfx.play_at("warn", _muzzle(), 0.0, 0.7)
	_flash = 1.0
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(func() -> void:
		if not active or _defeated:
			return
		var dir := ((target.global_position + Vector3(0, 1, 0)) - _muzzle()).normalized()
		Projectile.spawn(Fx.world(), _muzzle(), dir, 16.0, 16.0, Cfg.TEAM_ENEMY, self, {
			"color": Cfg.C_VIOLET, "size": 0.16, "homing": 2.4, "homing_target": target, "knockback": 6.0,
		})
		Sfx.play_at("enemy_shot", _muzzle(), 2.0, 0.5))

func _core_pulse() -> void:
	Sfx.play_at("charge", global_position, 0.0, 0.5)
	Bus.hud_message.emit("CORE PULSE INCOMING - MOVE", Cfg.C_RED, 1.4)
	Fx.ring(global_position + Vector3(0, 0.1, 0), Cfg.C_RED, 0.3, 1.0)
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(func() -> void:
		if not active or _defeated:
			return
		var radius := 9.0
		Fx.explosion(global_position + Vector3(0, 1.0, 0), Cfg.C_RED, 1.6)
		Bus.screen_shake.emit(0.7)
		for n in get_tree().get_nodes_in_group("players"):
			var p := n as Player
			if p == null or p.dead:
				continue
			var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
			if d <= radius:
				var info := DamageInfo.make(lerpf(32.0, 6.0, clampf(d / radius, 0.0, 1.0)), Cfg.TEAM_ENEMY, self, "boss")
				info.direction = (p.global_position - global_position).normalized()
				info.knockback = 9.0
				p.take_damage(info))

# --- Damage / shields --------------------------------------------------------------------------------

func on_shield_down(_s: ShieldNode) -> void:
	shields.erase(_s)
	Bus.hud_message.emit("SHIELD NODE DOWN - %d REMAINING" % shields.size(), Cfg.C_VIOLET, 1.8)
	if shields.is_empty() and phase == 1:
		_enter_phase(2)

func hit_center() -> Vector3:
	return _muzzle()

func is_targetable() -> bool:
	return active and not _defeated and not _is_invulnerable()

func _is_invulnerable() -> bool:
	if phase == 1 and not shields.is_empty():
		return true
	if phase == 3 and core_state == CoreState.ARMORED:
		return true
	return false

func take_damage(info: DamageInfo) -> void:
	if not active or _defeated or info.team == Cfg.TEAM_ENEMY:
		return
	if _is_invulnerable():
		Sfx.play_at("armor_hit", global_position, -4.0, 1.4)
		Fx.impact(info.point if info.point != Vector3.ZERO else hit_center(), Vector3.UP, Cfg.C_VIOLET)
		return
	health = maxf(health - info.amount, 0.0)
	_flash = 1.0
	Fx.damage_number(hit_center() + Vector3(randf_range(-0.6, 0.6), 0.6, randf_range(-0.6, 0.6)), info.amount, Cfg.C_CYAN if info.from_echo else Color.WHITE)
	Sfx.play_at("boss_hit", global_position, 0.0)
	if health <= 0.0:
		_die()

func _die() -> void:
	_defeated = true
	active = false
	Bus.boss_bar.emit(false, "", 0.0, "")
	Fx.explosion(hit_center(), Cfg.C_RED, 3.0)
	Bus.screen_shake.emit(1.2)
	Sfx.play("explosion", 0.0, 0.6)
	Story.play("c5_defeat")
	defeated.emit()

func _push_bar() -> void:
	if not active:
		return
	var text := {1: "SECURITY PROTOCOL", 2: "SYSTEM OVERLOAD", 3: ("CORE EXPOSED" if core_state == CoreState.EXPOSED else "CORE ARMORED")}.get(phase, "")
	if phase == 1:
		text += "  -  %d SHIELD(S) REMAINING" % shields.size()
	Bus.boss_bar.emit(true, "WARDEN", health / max_health, text)
