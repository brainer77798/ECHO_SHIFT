class_name Player
extends CharacterBody3D
## The operative. Third-person movement relative to the camera, mouse-aimed blaster, dash with
## invulnerability frames, Echo recording/creation and interaction.
##
## Each physics tick the player (1) handles input and moves, then (2) logs the tick into its
## EchoRecorder using the recorder's protocol: begin_tick -> events -> commit_frame. Every player
## owns an independent recorder and Echo list, which is what keeps multiplayer buffers separate.

signal died(player: Player)

var health := 100.0
var max_health := 100.0
var dead := false
var controllable := true       # false while in a cutscene or modal screen
var is_local := true           # false for remote co-op avatars (driven by the network layer)
var peer_id := 1
var tint: Color = Cfg.C_CYAN
var hit_radius := 0.5

var cam: CameraRig
var model: PlayerModel
var recorder := EchoRecorder.new()
var echoes: Array = []         # active Echo nodes, oldest first

var heat := 0.0
var overheated := false
var kills_this_life := 0

var _heat_delay := 0.0
var _fire_cd := 0.0
var _dash_time := 0.0
var _dash_cd := 0.0
var _iframes := 0.0
var _dash_dir := Vector3.ZERO
var _dash_log_dir: Variant = null
var _step_t := 0.0
var _aim_dir := Vector3.FORWARD
var _aim_point := Vector3.ZERO
var _prompt := ""
var _echo_cd := 0.0
var _speed_ratio := 0.0
var _heat_warned := false
var _net_target := Vector3.ZERO
var _net_yaw := 0.0
var _net_has := false
var _net_report_t := 0.0

func aim_direction() -> Vector3:
	return _aim_dir

func _ready() -> void:
	add_to_group("players")
	collision_layer = Cfg.L_PLAYER
	collision_mask = Cfg.L_WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Cfg.PLAYER_RADIUS
	cap.height = Cfg.PLAYER_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, Cfg.PLAYER_HEIGHT * 0.5, 0)
	add_child(cs)
	model = PlayerModel.new()
	add_child(model)
	model.build(false, tint)
	add_child(recorder)
	refresh_stats(true)

## Re-reads upgrade-derived stats. `full_heal` also refills health.
func refresh_stats(full_heal := false) -> void:
	var old_max := max_health
	max_health = GameState.stat("max_health")
	if full_heal:
		health = max_health
	elif max_health > old_max:
		health += max_health - old_max
	health = minf(health, max_health)
	recorder.set_window(GameState.stat("echo_record_time"))
	Bus.player_health_changed.emit(health, max_health)

func attach_camera() -> CameraRig:
	if cam != null and is_instance_valid(cam):
		return cam
	cam = CameraRig.new()
	cam.target = self
	get_parent().add_child(cam)
	cam.yaw = rotation.y
	cam.snap_to_target()
	cam.make_current()
	return cam

func _exit_tree() -> void:
	if cam != null and is_instance_valid(cam):
		cam.queue_free()
	if GameState.local_player == self:
		GameState.local_player = null

# --- Main tick ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_local:
		_remote_step(delta)
		return
	if dead:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		velocity.y -= Cfg.GRAVITY * delta
		move_and_slide()
		return
	_tick_timers(delta)
	var ctrl := controllable and is_instance_valid(cam)

	if ctrl and Input.is_action_just_pressed("echo") and _echo_cd <= 0.0:
		try_create_echo()

	# --- movement ---
	var yaw := cam.yaw if is_instance_valid(cam) else rotation.y
	var yaw_basis := Basis(Vector3.UP, yaw)
	var input := Vector2.ZERO
	if ctrl:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := yaw_basis * Vector3(input.x, 0.0, input.y)

	if ctrl and Input.is_action_just_pressed("dash") and _dash_cd <= 0.0 and _dash_time <= 0.0:
		_start_dash(wish if wish.length() > 0.1 else yaw_basis * Vector3(0, 0, 1))

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if _dash_time > 0.0:
		horiz = _dash_dir * Cfg.DASH_SPEED
	else:
		var target_v := wish.limit_length(1.0) * Cfg.PLAYER_SPEED
		var rate := Cfg.PLAYER_ACCEL if wish.length_squared() > 0.001 else Cfg.PLAYER_FRICTION
		horiz = horiz.move_toward(target_v, rate * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= Cfg.GRAVITY * delta
	move_and_slide()

	# turn the body towards where the camera looks
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-22.0 * delta))

	# --- aim ---
	if is_instance_valid(cam):
		_aim_point = cam.aim_point()
		var chest := global_position + Vector3(0, 1.4, 0)
		var to_aim := _aim_point - chest
		_aim_dir = to_aim.normalized() if to_aim.length() > 0.5 else cam.forward()

	# --- state for the recorder + animation ---
	var speed := Vector2(velocity.x, velocity.z).length()
	var state := EchoRecording.ST_IDLE
	if _dash_time > 0.0:
		state = EchoRecording.ST_DASH
	elif speed > 0.6:
		state = EchoRecording.ST_RUN
	_speed_ratio = clampf(speed / Cfg.PLAYER_SPEED, 0.0, 1.0)

	recorder.begin_tick(delta)
	if _dash_log_dir != null:
		recorder.log_dash(_dash_log_dir)
		_dash_log_dir = null
	if ctrl and Input.is_action_pressed("fire"):
		_try_fire()
	if ctrl and Input.is_action_just_pressed("interact"):
		_try_interact()
	recorder.commit_frame(global_position, rotation.y, _aim_dir, state)

	_update_prompt(ctrl)
	_animate(delta)
	_footsteps(delta, speed)
	_net_report_t -= delta
	if Net.active and not Net.is_host and _net_report_t <= 0.0:
		_net_report_t = 0.08
		Net.report_my_state(global_position, rotation.y, _aim_dir, health, dead)

func _tick_timers(delta: float) -> void:
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_echo_cd = maxf(_echo_cd - delta, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	if _dash_time > 0.0:
		_dash_time -= delta
		if _dash_time <= 0.0:
			_dash_time = 0.0
			if is_instance_valid(cam):
				cam.fov_kick = 0.0
	if _heat_delay > 0.0:
		_heat_delay -= delta
	elif heat > 0.0:
		heat = maxf(heat - Cfg.HEAT_COOL_RATE * delta, 0.0)
	if overheated and heat <= Cfg.HEAT_RECOVER:
		overheated = false
		_heat_warned = false

func _animate(delta: float) -> void:
	var local := global_transform.basis.inverse() * velocity
	model.animate(delta, local / Cfg.PLAYER_SPEED, _speed_ratio, _dash_time > 0.0, asin(clampf(_aim_dir.y, -1.0, 1.0)))

func _footsteps(delta: float, speed: float) -> void:
	if speed < 1.5 or not is_on_floor() or _dash_time > 0.0:
		_step_t = 0.0
		return
	_step_t -= delta * (speed / Cfg.PLAYER_SPEED)
	if _step_t <= 0.0:
		_step_t = 0.36
		Sfx.play("step", -16.0, randf_range(0.85, 1.15))

# --- Dash --------------------------------------------------------------------------------------

func _start_dash(dir: Vector3) -> void:
	dir.y = 0.0
	_dash_dir = dir.normalized()
	_dash_time = Cfg.DASH_TIME
	_dash_cd = GameState.stat("dash_cooldown")
	_iframes = maxf(_iframes, Cfg.DASH_IFRAMES)
	_dash_log_dir = _dash_dir
	if is_instance_valid(cam):
		cam.fov_kick = 9.0
	Sfx.play("dash", -4.0)
	Fx.burst(global_position + Vector3(0, 0.9, 0), tint, 8, 2.5, 0.35, 0.14, 0.0, -_dash_dir, 40.0)

func dash_ready_ratio() -> float:
	var total := GameState.stat("dash_cooldown")
	return 1.0 - clampf(_dash_cd / total, 0.0, 1.0)

# --- Blaster -----------------------------------------------------------------------------------

func muzzle_world() -> Vector3:
	if model != null and model.muzzle != null and model.muzzle.is_inside_tree():
		return model.muzzle.global_position
	return global_position + Vector3(0.3, 1.3, 0) + (-global_transform.basis.z) * 0.6

func _try_fire() -> void:
	if _fire_cd > 0.0:
		return
	if overheated:
		if not _heat_warned:
			_heat_warned = true
			Sfx.play("heat_warn", -4.0)
		return
	var origin := muzzle_world()
	var dir := _aim_point - origin
	if dir.length() < 1.2:
		dir = cam.forward() if is_instance_valid(cam) else -global_transform.basis.z
	dir = dir.normalized()
	var dmg := GameState.stat("blaster_damage")
	Projectile.spawn(Fx.world(), origin, dir, Cfg.BLASTER_SPEED, dmg, Cfg.TEAM_PLAYER, self, {
		"source_player": self, "color": tint, "from_point": global_position + Vector3(0, 1.1, 0),
	})
	recorder.log_fire(origin - global_position, dir)
	_fire_cd = GameState.stat("blaster_cooldown")
	heat += Cfg.HEAT_PER_SHOT
	_heat_delay = Cfg.HEAT_COOL_DELAY
	if heat >= Cfg.HEAT_MAX:
		heat = Cfg.HEAT_MAX
		overheated = true
		Sfx.play("overheat", -3.0)
		Bus.hud_message.emit("BLASTER OVERHEATED", Cfg.C_ORANGE, 1.4)
	Sfx.play("shot", -6.0, randf_range(0.95, 1.08))
	Fx.burst(origin, tint, 3, 2.0, 0.12, 0.12, 0.0, dir, 25.0)
	if is_instance_valid(cam):
		cam.fov_kick = maxf(cam.fov_kick, 1.5)

func weapon_heat_ratio() -> float:
	return clampf(heat / Cfg.HEAT_MAX, 0.0, 1.0)

# --- Echoes ------------------------------------------------------------------------------------

func echo_damage() -> float:
	return GameState.stat("blaster_damage") * GameState.stat("echo_damage_mult")

## Turns the recorded window into a live Echo. Returns the Echo, or null if there is not enough
## recorded motion yet. A third Echo replaces the oldest one.
func try_create_echo() -> Echo:
	if dead:
		return null
	if not recorder.can_snapshot():
		Bus.echo_failed.emit("Not enough recorded motion - keep moving")
		Sfx.play("echo_fail")
		return null
	var rec := recorder.snapshot(peer_id)
	if rec == null or not rec.is_valid():
		Bus.echo_failed.emit("Recording unavailable")
		Sfx.play("echo_fail")
		return null
	_prune_echoes()
	while echoes.size() >= Cfg.ECHO_MAX_ACTIVE:
		var oldest: Echo = echoes[0]
		echoes.remove_at(0)
		if is_instance_valid(oldest):
			oldest.expire(true)
		Bus.echo_replaced.emit(self)
		Sfx.play("echo_replace")
	var e := Echo.create(rec, self, echo_damage(), GameState.stat("echo_linger"), tint)
	e.expired.connect(_on_echo_expired)
	Fx.world().add_child(e)
	echoes.append(e)
	recorder.clear()
	_echo_cd = 0.4
	if Net.active and is_local:
		Net.broadcast_echo(peer_id, rec.to_dict(), echo_damage(), GameState.stat("echo_linger"), tint)
	GameState.echoes_made += 1
	Bus.echo_created.emit(self, e)
	return e

func _prune_echoes() -> void:
	for i in range(echoes.size() - 1, -1, -1):
		if not is_instance_valid(echoes[i]):
			echoes.remove_at(i)

func _on_echo_expired(e: Echo) -> void:
	echoes.erase(e)

func clear_echoes() -> void:
	for e in echoes.duplicate():
		if is_instance_valid(e):
			e.expire()
	echoes.clear()

func active_echo_count() -> int:
	_prune_echoes()
	return echoes.size()

# --- Interaction -------------------------------------------------------------------------------

func find_interactable() -> Interactable:
	var best: Interactable = null
	var best_d := INF
	var fwd := -global_transform.basis.z
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null or not it.can_interact(self):
			continue
		var to := it.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > it.interact_range:
			continue
		if d > 1.4 and to.normalized().dot(fwd) < 0.2:
			continue
		if d < best_d:
			best_d = d
			best = it
	return best

func _try_interact() -> void:
	var it := find_interactable()
	if it == null:
		return
	if it.echo_compatible:
		recorder.log_interact(it.interact_id)
	it.interact(self)

func _update_prompt(ctrl: bool) -> void:
	var text := ""
	if ctrl and not dead:
		var it := find_interactable()
		if it != null:
			text = it.prompt_text()
	if text != _prompt:
		_prompt = text
		Bus.interact_prompt.emit(text)

# --- Damage / life -----------------------------------------------------------------------------

func hit_center() -> Vector3:
	return global_position + Vector3(0, 0.95, 0)

func is_targetable() -> bool:
	return not dead

func is_invulnerable() -> bool:
	return _iframes > 0.0 or GameState.god_mode

func take_damage(info: DamageInfo) -> void:
	if dead or info.team == Cfg.TEAM_PLAYER:
		return
	if is_invulnerable():
		return
	health = maxf(health - info.amount, 0.0)
	_iframes = 0.08
	if info.knockback > 0.0 and info.direction.length() > 0.01:
		var kb := info.direction
		kb.y = 0.0
		kb = kb.normalized() * info.knockback
		velocity.x += kb.x
		velocity.z += kb.z
	HitFlash.apply(model, Cfg.C_RED, 0.8, 0.18)
	Sfx.play("hurt", -2.0)
	Bus.screen_shake.emit(clampf(info.amount / 25.0, 0.25, 1.0))
	Bus.player_damaged.emit(info.amount, info.direction)
	Bus.player_health_changed.emit(health, max_health)
	if health <= 0.0:
		die()

func heal(amount: float) -> void:
	if dead:
		return
	health = minf(health + amount, max_health)
	Bus.player_health_changed.emit(health, max_health)

func die() -> void:
	if dead:
		return
	dead = true
	GameState.deaths += 1
	clear_echoes()
	recorder.clear()
	Sfx.play("death")
	Fx.explosion(global_position + Vector3(0, 1.0, 0), tint, 0.8)
	model.visible = false
	_prompt = ""
	Bus.interact_prompt.emit("")
	Bus.player_died.emit(self)
	died.emit(self)

## Brings the operative back at a position (used when no full level reload is needed, e.g. tests).
func respawn(at: Vector3, yaw := 0.0) -> void:
	dead = false
	global_position = at
	velocity = Vector3.ZERO
	rotation.y = yaw
	model.visible = true
	heat = 0.0
	overheated = false
	_iframes = 1.5
	_dash_time = 0.0
	_dash_cd = 0.0
	recorder.clear()
	clear_echoes()
	refresh_stats(true)
	if is_instance_valid(cam):
		cam.yaw = yaw
		cam.snap_to_target()
	Bus.player_respawned.emit()

func set_controllable(v: bool) -> void:
	controllable = v
	if is_instance_valid(cam):
		cam.look_enabled = v

# --- Remote (co-op) avatars ----------------------------------------------------------------------

## Applies a network snapshot; the avatar eases towards it in _remote_step.
func apply_net_state(pos: Vector3, yaw: float, aim: Vector3, hp: float, p_dead: bool) -> void:
	_net_target = pos
	_net_yaw = yaw
	_aim_dir = aim
	if not _net_has:
		global_position = pos
		_net_has = true
	health = hp
	if p_dead != dead:
		dead = p_dead
		model.visible = not dead

func _remote_step(delta: float) -> void:
	if not _net_has:
		return
	var prev := global_position
	global_position = global_position.lerp(_net_target, 1.0 - exp(-16.0 * delta))
	rotation.y = lerp_angle(rotation.y, _net_yaw, 1.0 - exp(-16.0 * delta))
	var vel := (global_position - prev) / maxf(delta, 0.0001)
	var local := global_transform.basis.inverse() * vel
	model.animate(delta, local / Cfg.PLAYER_SPEED, clampf(vel.length() / Cfg.PLAYER_SPEED, 0.0, 1.0), false, asin(clampf(_aim_dir.y, -1.0, 1.0)))
