extends Node
## Automated gameplay tests for the Echo system and core combat. Run headless:
##   godot --headless --path . res://tests/test_core.tscn
## Prints PASS/FAIL per check and exits non-zero if anything failed.

class Dummy extends Enemy:
	func _init() -> void:
		kind_name = "Dummy"
		max_health = 100.0
		radius = 0.5
		body_height = 1.8
		lure_enabled = false
	func _think(_d: float) -> void:
		pass

var _pass := 0
var _fail := 0
var level: LevelBase
var player: Player

func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name)
	else:
		_fail += 1
		print("  FAIL  ", name, "   ", detail)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	GameState.in_game = true
	GameState.new_game()
	GameState.god_mode = true
	level = load("res://tests/test_level.gd").new()
	add_child(level)
	await get_tree().physics_frame
	player = level.player
	await test_recorder_buffer()
	await test_playback_timing()
	await test_fire_events()
	await test_dash_event()
	await test_echo_limit_and_expiry()
	await test_plate_and_door()
	await test_echo_only_plate()
	await test_wall_blocks_shots()
	await test_distraction()
	await test_independent_players()
	await test_heat_and_fire_rate()
	print("\nRESULT: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# --- helpers ---------------------------------------------------------------------------------

func _make_rec(duration: float, pos_fn: Callable, fires: Array = [], dashes: Array = [], fire_dir := Vector3(0, 0, -1)) -> EchoRecording:
	var rec := EchoRecording.new()
	var n := int(duration * 60.0) + 1
	for i in n:
		var t := float(i) / 60.0
		rec.times.append(t)
		rec.positions.append(pos_fn.call(t))
		rec.yaws.append(0.0)
		rec.aims.append(Vector3(0, 0, -1))
		rec.states.append(EchoRecording.ST_RUN)
	rec.duration = rec.times[n - 1]
	for f in fires:
		rec.events.append({"t": f, "type": "fire", "muzzle": Vector3(0, 1.3, -0.5), "dir": fire_dir})
	for d in dashes:
		rec.events.append({"t": d, "type": "dash", "dir": Vector3(1, 0, 0)})
	return rec

func _spawn_echo(rec: EchoRecording, linger := 1.0, damage := 6.6) -> Echo:
	var e := Echo.create(rec, player, damage, linger)
	level.add_child(e)
	return e

func _park_player() -> void:
	player.global_position = Vector3(8.0, 0.1, 20.0)
	player.velocity = Vector3.ZERO

func _dummy(pos: Vector3) -> Enemy:
	var d := Dummy.new()
	d.level = level
	level.entities.add_child(d)
	d.global_position = pos
	return d

# --- tests --------------------------------------------------------------------------------------

func test_recorder_buffer() -> void:
	print("[recorder buffer]")
	var rec := EchoRecorder.new()
	add_child(rec)
	var cap0 := rec.capacity
	for i in 1500:    # 25 s at 60 Hz
		rec.begin_tick(1.0 / 60.0)
		if i % 60 == 30:
			rec.log_fire(Vector3(0, 1.3, -0.5), Vector3(0, 0, -1))
		rec.commit_frame(Vector3(float(i) * 0.1, 0, 0), 0.0, Vector3(0, 0, -1), EchoRecording.ST_RUN)
	_check("capacity never grows", rec.capacity == cap0, "%d vs %d" % [rec.capacity, cap0])
	_check("history capped at window", rec.available_time() <= rec.window + 0.001 and rec.available_time() > rec.window - 0.1, "avail=%f" % rec.available_time())
	_check("event list is bounded", rec.events.size() <= int(Cfg.ECHO_BUFFER_CAPACITY_TIME) + 2, "events=%d" % rec.events.size())
	var snap := rec.snapshot(7)
	_check("snapshot valid", snap != null and snap.is_valid())
	_check("snapshot spans ~5 s", absf(snap.duration - 5.0) < 0.05, "dur=%f" % snap.duration)
	_check("snapshot starts at t=0", snap.times[0] == 0.0)
	_check("snapshot keeps owner id", snap.owner_id == 7)
	var fires := snap.fire_event_count()
	_check("snapshot keeps ~5 fire events", fires == 5, "fires=%d" % fires)
	var ordered := true
	var last_t := -1.0
	for e in snap.events:
		if float(e["t"]) < last_t or float(e["t"]) > snap.duration + 0.001:
			ordered = false
		last_t = float(e["t"])
	_check("events ordered and inside the recording", ordered)
	# motion fidelity: positions are the most recent 5 s, in order
	_check("positions end at the latest frame", absf(snap.positions[snap.positions.size() - 1].x - 149.9) < 0.01, "x=%f" % snap.positions[snap.positions.size() - 1].x)
	var short := EchoRecorder.new()
	add_child(short)
	short.record_frame(1.0 / 60.0, Vector3.ZERO, 0.0, Vector3.FORWARD, 0)
	_check("too-short recording refuses to snapshot", short.snapshot() == null)
	rec.queue_free()
	short.queue_free()

func test_playback_timing() -> void:
	print("[playback timing]")
	_park_player()
	var rec := _make_rec(3.0, func(t: float) -> Vector3: return Vector3(10.0 + t * 4.0, 0.0, 20.0))
	var e := _spawn_echo(rec, 0.5)
	await _frames(1)
	var start_x := e.global_position.x
	_check("echo starts at the recorded start", absf(start_x - 10.0) < 0.2, "x=%f" % start_x)
	await _frames(60)     # 1.0 s
	_check("echo clock matches physics time", absf(e.time - 1.0) < 0.04, "time=%f" % e.time)
	_check("position at 1.0 s", absf(e.global_position.x - 14.0) < 0.35, "x=%f" % e.global_position.x)
	await _frames(90)     # 2.5 s
	_check("position at 2.5 s", absf(e.global_position.x - 20.0) < 0.35, "x=%f" % e.global_position.x)
	await _frames(40)     # past the end of the recording
	_check("echo holds final pose while lingering", e.phase == Echo.Phase.LINGER and absf(e.global_position.x - 22.0) < 0.35, "phase=%d x=%f" % [e.phase, e.global_position.x])
	await _frames(40)
	_check("echo frees itself after linger", not is_instance_valid(e) or e.is_queued_for_deletion())

func test_fire_events() -> void:
	print("[echo firing]")
	_park_player()
	var target := _dummy(Vector3(20.0, 0.0, 10.0))
	var hp0 := target.health
	# echo at (20,0,20) shoots -Z three times at t = 0.5, 1.5, 3.0: the dummy sits 10 m ahead
	var rec := _make_rec(3.5, func(_t: float) -> Vector3: return Vector3(20.0, 0.0, 20.0), [0.5, 1.5, 3.0], [], Vector3(0, -0.035, -1).normalized())
	var e := _spawn_echo(rec, 1.0, 6.6)
	await _frames(36)    # 0.6 s
	_check("first shot fired exactly once by 0.6 s", e.shots_fired == 1, "shots=%d" % e.shots_fired)
	await _frames(60)    # 1.6 s
	_check("second shot by 1.6 s (no duplicate)", e.shots_fired == 2, "shots=%d" % e.shots_fired)
	await _frames(100)   # 3.27 s
	_check("third shot by 3.2 s", e.shots_fired == 3, "shots=%d" % e.shots_fired)
	await _frames(60)
	_check("echo never fires more than recorded", e.shots_fired == 3, "shots=%d" % e.shots_fired)
	var dealt := hp0 - target.health
	_check("each shot damaged the enemy once (3 x 6.6)", absf(dealt - 19.8) < 0.05, "dealt=%f" % dealt)
	_check("no projectiles left in flight", Projectile.live == 0, "live=%d" % Projectile.live)
	target.queue_free()
	await _frames(2)

func test_dash_event() -> void:
	print("[dash]")
	_park_player()
	player.global_position = Vector3(10.0, 0.1, 22.0)
	await _frames(3)
	var p0 := player.global_position
	Input.action_press("move_right")
	Input.action_press("dash")
	await _frames(1)
	Input.action_release("dash")
	await _frames(14)
	Input.action_release("move_right")
	var moved := player.global_position.distance_to(p0)
	_check("dash covers a useful distance", moved > 3.2, "moved=%f" % moved)
	var dash_logged := false
	for e in player.recorder.events:
		if e["type"] == "dash":
			dash_logged = true
	_check("dash is recorded as an event", dash_logged)
	_check("dash has a cooldown", player.dash_ready_ratio() < 1.0, "ratio=%f" % player.dash_ready_ratio())
	await _frames(20)    # let dash momentum fully bleed off via friction before checking
	var p1 := player.global_position
	Input.action_press("dash")
	await _frames(1)
	Input.action_release("dash")
	_check("pressing dash during cooldown does not restart it", player._dash_time <= 0.001, "dash_time=%f" % player._dash_time)
	await _frames(10)
	_check("cannot dash again during cooldown", player.global_position.distance_to(p1) < 1.0, "moved=%f" % player.global_position.distance_to(p1))
	await _frames(70)
	player.recorder.clear()

func test_echo_limit_and_expiry() -> void:
	print("[echo limit + expiry]")
	_park_player()
	await _frames(2)
	var replaced := [0]
	var on_replace := func(_p: Node) -> void: replaced[0] += 1
	Bus.echo_replaced.connect(on_replace)
	var made: Array = []
	for i in 3:
		player.recorder.clear()
		await _frames(75)    # record 1.25 s of standing still
		var e := player.try_create_echo()
		_check("echo %d created" % (i + 1), e != null)
		made.append(e)
	await _frames(3)
	_check("never more than two active echoes", player.active_echo_count() == 2, "count=%d" % player.active_echo_count())
	_check("the oldest echo was removed", not is_instance_valid(made[0]) or made[0].is_queued_for_deletion() or made[0].phase == Echo.Phase.DONE)
	_check("the newer echoes survive", is_instance_valid(made[1]) and is_instance_valid(made[2]))
	_check("replacement signal fired once", replaced[0] == 1, "replaced=%d" % replaced[0])
	Bus.echo_replaced.disconnect(on_replace)
	var no_data := Player.new()
	level.add_child(no_data)
	await _frames(2)
	_check("echo refused with nothing recorded", no_data.try_create_echo() == null)
	no_data.queue_free()
	await _frames(300)    # replay (1.25 s) + linger (3 s) + fade
	_check("all echoes expire and clean up", player.active_echo_count() == 0 and get_tree().get_nodes_in_group("echoes").size() == 0, "left=%d" % get_tree().get_nodes_in_group("echoes").size())

func test_plate_and_door() -> void:
	print("[plate + door]")
	_park_player()
	var plate: PressurePlate = level.devices["plate_b"]
	var door: Door = level.doors["d1"]
	await _frames(20)
	_check("door starts closed", not door.is_open and not plate.pressed)
	var pp := plate.global_position
	var rec := _make_rec(1.0, func(_t: float) -> Vector3: return Vector3(pp.x, 0.0, pp.z))
	var e := _spawn_echo(rec, 1.2)
	await _frames(20)
	_check("echo on the plate presses it", plate.pressed and level.get_channel("plate_b"))
	await _frames(45)
	_check("pressing the plate opens the door", door.is_open)
	await _frames(100)    # echo done: 1.0 s replay + 1.2 s linger
	_check("door closes again when the echo is gone", not door.is_open and not plate.pressed, "open=%s pressed=%s" % [door.is_open, plate.pressed])
	# the operative can hold the plate too
	player.global_position = Vector3(pp.x, 0.1, pp.z)
	await _frames(40)
	_check("operative standing on the plate presses it", plate.pressed)
	_park_player()
	await _frames(60)

func test_echo_only_plate() -> void:
	print("[echo-only plate]")
	var plate: PressurePlate = level.devices["plate_echo"]
	var pp := plate.global_position
	player.global_position = Vector3(pp.x, 0.1, pp.z)
	await _frames(30)
	_check("operative cannot press an echo-only plate", not plate.pressed)
	_park_player()
	var rec := _make_rec(0.8, func(_t: float) -> Vector3: return Vector3(pp.x, 0.0, pp.z))
	var e := _spawn_echo(rec, 0.6)
	await _frames(20)
	_check("echo presses the echo-only plate", plate.pressed)
	await _frames(120)

func test_wall_blocks_shots() -> void:
	print("[wall blocks shots]")
	_park_player()
	var behind := _dummy(Vector3(56.0, 0.0, 10.0))
	var hp0 := behind.health
	Projectile.spawn(level, Vector3(30.0, 1.3, 10.0), Vector3(1, 0, 0), Cfg.BLASTER_SPEED, 50.0, Cfg.TEAM_PLAYER, player, {"source_player": player})
	await _frames(90)
	_check("projectile stopped by the wall", behind.health == hp0, "hp=%f" % behind.health)
	_check("projectile was freed", Projectile.live == 0, "live=%d" % Projectile.live)
	var open := _dummy(Vector3(12.0, 0.0, 10.0))
	Projectile.spawn(level, Vector3(30.0, 1.3, 10.0), Vector3(-1, 0, 0), Cfg.BLASTER_SPEED, 20.0, Cfg.TEAM_PLAYER, player, {"source_player": player})
	await _frames(60)
	_check("same shot hits an enemy in the open (damage applied once)", absf(open.health - 80.0) < 0.01, "hp=%f" % open.health)
	behind.queue_free()
	open.queue_free()
	await _frames(2)

func test_distraction() -> void:
	print("[echo distraction]")
	_park_player()
	player.global_position = Vector3(30.0, 0.1, 10.0)
	var drone := HunterDrone.new()
	drone.level = level
	level.entities.add_child(drone)
	drone.global_position = Vector3(8.0, 1.15, 10.0)
	# echo 6 m from the drone, operative 22 m away: the echo is the better target
	var rec := _make_rec(6.0, func(_t: float) -> Vector3: return Vector3(14.0, 0.0, 10.0))
	var e := _spawn_echo(rec, 3.0)
	await _frames(20)
	_check("enemy targets the nearby echo over a distant operative", drone.target == e, "target=%s" % drone.target)
	# the operative walks right up to the drone - positioned relative to wherever it has
	# drifted to while circling the echo, since the drone does not stand still
	player.global_position = drone.global_position + Vector3(1.6, 0.0, 0.0)
	var ok := false
	for i in 40:
		await get_tree().physics_frame
		if drone.target == player:
			ok = true
			break
	_check("an operative at close range outranks the echo", ok, "target=%s" % drone.target)
	drone.queue_free()
	await _frames(300)

func test_independent_players() -> void:
	print("[independent players]")
	_park_player()
	var p2 := Player.new()
	p2.peer_id = 2
	p2.is_local = true
	level.add_child(p2)
	p2.global_position = Vector3(8.0, 0.1, 24.0)
	p2.controllable = false
	await _frames(80)
	_check("each player owns its own recorder", p2.recorder != player.recorder)
	player.controllable = false
	player.recorder.clear()
	await _frames(70)
	var before := p2.recorder.available_time()
	var e1 := player.try_create_echo()
	_check("player one's echo uses player one's buffer", e1 != null and e1.owner_player == player)
	_check("creating an echo leaves the other buffer untouched", absf(p2.recorder.available_time() - before) < 0.5 and p2.recorder.can_snapshot())
	var e2 := p2.try_create_echo()
	_check("player two can still create their own echo", e2 != null and e2.owner_player == p2)
	_check("echo limits are per player", player.active_echo_count() == 1 and p2.active_echo_count() == 1)
	player.controllable = true
	p2.queue_free()
	await _frames(300)

func test_heat_and_fire_rate() -> void:
	print("[blaster heat]")
	_park_player()
	player.heat = 0.0
	player.overheated = false
	player.cam.yaw = 0.0
	player.cam.pitch = 0.0
	await _frames(5)
	var start_live := Projectile.live
	Input.action_press("fire")
	for i in 220:
		await get_tree().physics_frame
		if player.overheated:
			break
	Input.action_release("fire")
	_check("sustained fire eventually overheats the blaster", player.overheated, "heat=%f" % player.heat)
	_check("heat is capped", player.heat <= Cfg.HEAT_MAX + 0.01, "heat=%f" % player.heat)
	Input.action_press("fire")
	await _frames(10)
	Input.action_release("fire")
	var rec_events := 0
	for e in player.recorder.events:
		if e["type"] == "fire":
			rec_events += 1
	_check("every shot was logged for the echo recorder", rec_events > 5, "logged=%d" % rec_events)
	await _frames(200)
	_check("blaster cools down and recovers", not player.overheated, "heat=%f" % player.heat)
