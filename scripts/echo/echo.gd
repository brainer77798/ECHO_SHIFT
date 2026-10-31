class_name Echo
extends CharacterBody3D
## A holographic replay of a player's recorded actions.
##
## Replays movement, facing, aim, shots, dashes and supported interactions from an EchoRecording,
## driven by a deterministic playback clock (advanced by the physics delta), then lingers in place
## for a short time (so it can keep a pressure plate down) before fading out.
## Movement uses move_and_collide against world geometry only: an Echo never gets shoved by
## actors, never tunnels through a closed door and can recover if an obstacle opens.

signal expired(echo: Echo)

enum Phase { REPLAY, LINGER, DONE }

const MAX_CATCHUP_SPEED := 32.0
const FADE_TIME := 1.1

var recording: EchoRecording
var owner_player: Node
var damage := 6.0
var linger_time := 3.0
var tint := Cfg.C_CYAN
var phase := Phase.REPLAY
var time := 0.0
var hit_radius := 0.5
var shots_fired := 0           # exposed for tests and HUD
var events_played := 0
var model: PlayerModel
var current_state := 0

var _event_idx := 0
var _linger_left := 0.0
var _prev_pos := Vector3.ZERO
var _ring: MeshInstance3D
var _light: OmniLight3D
var _blocked_time := 0.0
var _speed_ratio := 0.0

static func create(rec: EchoRecording, p_owner: Node, p_damage: float, p_linger: float, p_tint: Color = Cfg.C_CYAN) -> Echo:
	var e := Echo.new()
	e.recording = rec
	e.owner_player = p_owner
	e.damage = p_damage
	e.linger_time = p_linger
	e.tint = p_tint
	return e

func _ready() -> void:
	add_to_group("echoes")
	collision_layer = Cfg.L_ECHO
	collision_mask = Cfg.L_WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Cfg.PLAYER_RADIUS
	cap.height = Cfg.PLAYER_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, Cfg.PLAYER_HEIGHT * 0.5, 0)
	add_child(cs)
	model = PlayerModel.new()
	add_child(model)
	model.build(true, tint)
	# floor ring + light + sparkles make the Echo readable even in the dark
	_ring = Shapes.torus(self, 0.52, 0.62, Vector3(0, 0.04, 0), Mats.energy(tint, 1.4, false, 4.0), 28)
	_ring.scale = Vector3(1, 0.15, 1)
	_light = Shapes.add_light(self, Vector3(0, 1.1, 0), tint, 1.1, 5.5)
	var tag := Shapes.label3d(self, "ECHO", Vector3(0, 2.25, 0), tint, 30, 0.005)
	tag.modulate.a = 0.8
	var p := CPUParticles3D.new()
	p.mesh = Mats.particle_mesh(tint, 0.1)
	p.amount = 10
	p.lifetime = 1.2
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3.ZERO
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.position = Vector3(0, 0.9, 0)
	add_child(p)
	if recording != null and recording.is_valid():
		recording.sample(0.0)
		global_position = recording.s_pos
		rotation.y = recording.s_yaw
		_prev_pos = global_position
	else:
		push_warning("Echo created with an invalid recording")
		phase = Phase.DONE
	Sfx.play_at("echo_create", global_position, -4.0)
	Fx.ring(global_position + Vector3(0, 0.1, 0), tint, 2.0, 0.5)

func _physics_process(delta: float) -> void:
	match phase:
		Phase.REPLAY:
			_replay(delta)
		Phase.LINGER:
			_linger(delta)
		Phase.DONE:
			pass

func _replay(delta: float) -> void:
	time += delta
	var t := minf(time, recording.duration)
	_run_events(time)
	recording.sample(t)
	_move_towards(recording.s_pos, delta)
	rotation.y = recording.s_yaw
	current_state = recording.s_state
	var vel := (global_position - _prev_pos) / maxf(delta, 0.0001)
	_prev_pos = global_position
	var local := global_transform.basis.inverse() * vel
	_speed_ratio = clampf(Vector2(vel.x, vel.z).length() / Cfg.PLAYER_SPEED, 0.0, 1.6)
	var aim := recording.s_aim
	model.animate(delta, local / maxf(Cfg.PLAYER_SPEED, 0.01), minf(_speed_ratio, 1.0), current_state == EchoRecording.ST_DASH, asin(clampf(aim.y, -1.0, 1.0)))
	_ring.rotation.y += delta * 2.0
	if time >= recording.duration - 0.0001:
		_run_events(INF)    # flush any event stamped on the final frame
		phase = Phase.LINGER
		_linger_left = linger_time
		model.animate(delta, Vector3.ZERO, 0.0, false, asin(clampf(aim.y, -1.0, 1.0)))

func _linger(delta: float) -> void:
	_linger_left -= delta
	_ring.rotation.y += delta * 1.0
	if _linger_left <= FADE_TIME:
		var k := clampf(_linger_left / FADE_TIME, 0.0, 1.0)
		var flick := 0.55 + 0.45 * sin(time * 38.0)
		model.set_holo_strength(lerpf(0.1, 1.0, k) * lerpf(flick, 1.0, k))
		model.set_holo_glitch(0.06 * (1.0 - k))
		_light.light_energy = 1.1 * k
	if _linger_left <= 0.0:
		expire()
	time += delta

## Seconds of lifetime left (replay remainder + linger); used by the HUD.
func remaining() -> float:
	match phase:
		Phase.REPLAY:
			return maxf(recording.duration - time, 0.0) + linger_time
		Phase.LINGER:
			return maxf(_linger_left, 0.0)
	return 0.0

func _move_towards(target: Vector3, delta: float) -> void:
	var motion := target - global_position
	if motion.length_squared() < 0.0000001:
		_blocked_time = 0.0
		return
	var limited := motion.limit_length(MAX_CATCHUP_SPEED * delta)
	var col := move_and_collide(limited)
	if col != null and (target - global_position).length() > 0.25:
		_blocked_time += delta    # a closed door or similar is in the way; keep trying, never snap through
	else:
		_blocked_time = 0.0

func is_blocked() -> bool:
	return _blocked_time > 0.4

# --- Recorded events ----------------------------------------------------------------------

func _run_events(t: float) -> void:
	var evs := recording.events
	while _event_idx < evs.size() and float(evs[_event_idx]["t"]) <= t + 0.0001:
		_do_event(evs[_event_idx])
		_event_idx += 1

func _do_event(ev: Dictionary) -> void:
	events_played += 1
	match String(ev["type"]):
		"fire":
			var dir: Vector3 = ev["dir"]
			var origin := global_position + (ev["muzzle"] as Vector3)
			shots_fired += 1
			Projectile.spawn(Fx.world(), origin, dir, Cfg.BLASTER_SPEED, damage, Cfg.TEAM_PLAYER, self, {
				"from_echo": true, "source_player": owner_player, "color": tint,
				"from_point": global_position + Vector3(0, 1.1, 0), "size": 0.06,
			})
			Sfx.play_at("echo_shot", origin, -6.0)
			Fx.burst(origin, tint, 4, 2.5, 0.2, 0.1, 0.0, dir, 30.0)
		"dash":
			Sfx.play_at("dash", global_position, -8.0, 1.2)
			Fx.ring(global_position + Vector3(0, 0.1, 0), tint, 1.4, 0.3)
		"interact":
			var id := String(ev["id"])
			for n in get_tree().get_nodes_in_group("interactable"):
				if n.get("interact_id") == id and n.get("echo_compatible") == true:
					if (n as Node3D).global_position.distance_to(global_position) <= 4.5:
						n.interact(self)
					break

# --- Damage / targeting ----------------------------------------------------------------------

## Echoes are hard light: hostile fire is absorbed (it is wasted on the decoy) but does not hurt them.
func take_damage(info: DamageInfo) -> void:
	HitFlash.apply(model, tint, 0.9, 0.15)
	Fx.impact(info.point if info.point != Vector3.ZERO else global_position + Vector3(0, 1, 0), Vector3.UP, tint)
	Sfx.play_at("hit", global_position, -12.0, 1.4)

func hit_center() -> Vector3:
	return global_position + Vector3(0, 0.95, 0)

func is_targetable() -> bool:
	return phase != Phase.DONE

## Enemies treat live Echoes as lures.
func is_lure() -> bool:
	return phase != Phase.DONE

func expire(replaced := false) -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	remove_from_group("echoes")
	collision_layer = 0
	Sfx.play_at("echo_expire", global_position, -4.0)
	Fx.burst(global_position + Vector3(0, 1.0, 0), tint, 16, 4.0, 0.6, 0.14, 0.0)
	Fx.ring(global_position + Vector3(0, 0.1, 0), Cfg.C_AMBER if replaced else tint, 1.8, 0.4)
	expired.emit(self)
	Bus.echo_expired.emit(owner_player, self)
	queue_free()
