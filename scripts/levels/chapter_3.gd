extends LevelBase
## CHAPTER 3 - SECURITY GRID. Camera-watched corridors, a relay hub to hack under pressure, a
## coordinated squad ambush, and an Armored Brute arena (fight it or just outrun it to the exit).

const RELAYS := ["relay_a", "relay_b", "relay_c"]

func chapter() -> int:
	return 3

func start_yaw() -> float:
	return 0.0

func theme() -> Dictionary:
	return {
		"name": "SECURITY GRID", "wall_style": "plates", "wall_color": Color(0.17, 0.15, 0.17),
		"floor_style": "tiles", "floor_color": Color(0.14, 0.13, 0.15),
		"accent": Cfg.C_RED, "accent2": Cfg.C_AMBER, "ambient": Color(0.22, 0.16, 0.16),
		"music": "explore",
	}

func map_rows() -> PackedStringArray:
	var m := MapBuilder.new(62, 64)
	# --- Access -------------------------------------------------------------------------------
	m.room(2, 20, 12, 10)
	m.put(4, 25, "P").put(6, 21, "T").put(11, 25, "C")
	m.put(5, 28, "f")
	# --- Camera corridor -------------------------------------------------------------------------
	m.hall(14, 22, 18, 6)
	m.mark(18, 22, 2, 1, "K").mark(26, 27, 2, 1, "L")
	for c in [Vector2i(22, 23), Vector2i(23, 23), Vector2i(21, 26), Vector2i(22, 26)]:
		m.put(c.x, c.y, "O")
	m.put(17, 25, "f")
	# --- Security hub -----------------------------------------------------------------------------
	m.room(32, 10, 20, 22)
	m.mark(34, 12, 2, 2, "R").mark(49, 12, 2, 2, "Y").mark(41, 29, 2, 1, "G")
	m.put(32, 20, "U").put(41, 9, "D")
	for c in [Vector2i(37, 13), Vector2i(46, 13), Vector2i(37, 28), Vector2i(46, 28)]:
		m.put(c.x, c.y, "p")
	for c in [Vector2i(40, 16), Vector2i(43, 16), Vector2i(40, 24), Vector2i(43, 24)]:
		m.put(c.x, c.y, "r")
	m.put(41, 11, "n").put(33, 30, "h").put(48, 30, "f").put(44, 20, "d")
	m.mark(41, 31, 2, 1, "2")
	# --- Defended route ---------------------------------------------------------------------------------
	m.hall(30, 32, 24, 8)
	m.mark(32, 35, 2, 2, "Z")
	for c in [Vector2i(34, 35), Vector2i(34, 36), Vector2i(48, 35), Vector2i(48, 36)]:
		m.put(c.x, c.y, "O")
	m.put(50, 34, "f")
	m.mark(41, 39, 2, 1, "3")
	m.put(32, 39, "s")
	# --- Connector down to the arena ---------------------------------------------------------------------------
	m.hall(40, 40, 3, 2)
	# --- Brute arena ---------------------------------------------------------------------------------------------
	m.room(26, 42, 30, 18)
	m.put(28, 46, "N").put(52, 46, "W").put(40, 44, "E").put(40, 50, "B")
	for c in [Vector2i(30, 48), Vector2i(50, 48), Vector2i(34, 55), Vector2i(46, 55)]:
		m.put(c.x, c.y, "p")
	for c in [Vector2i(32, 44), Vector2i(48, 44)]:
		m.put(c.x, c.y, "O")
	m.put(40, 58, "X")
	m.put(29, 57, "h").put(51, 57, "f")
	return m.rows()

func build_content() -> void:
	add_terminal("T", "c3_security_brief")
	add_terminal("U", "c3_okafor_patch")
	add_terminal("N", "c3_warden_audit")
	add_terminal("W", "c3_calder_last")
	add_checkpoint("C", "cp1", 1)
	add_checkpoint("D", "cp2", 2)
	add_checkpoint("E", "cp3", 3)
	add_exit("X", "Push through the defended route first.")

	add_camera("K", {"id": "k1", "yaw": PI * 0.5, "sweep": 1.1, "range": 16.0})
	add_camera("L", {"id": "k2", "yaw": -PI * 0.5, "sweep": 1.1, "range": 16.0})
	set_alarm_spawns([
		{"kind": "drone", "cell": Vector2i(20, 24)},
		{"kind": "drone", "cell": Vector2i(24, 25)},
	])

	add_relay("R", "relay_a", {"title": "RELAY ALPHA"})
	add_relay("Y", "relay_b", {"title": "RELAY BETA"})
	add_relay("G", "relay_c", {"title": "RELAY GAMMA"})
	channel_changed.connect(_on_channel)
	var gate := add_door("2", "sec_gate", RELAYS, {"label": "GRID LOCK"})
	if gate != null and _all_relays_done():
		gate.force_open(true)
	spawn_marked("d", "drone", {})

	var def_clear := func() -> void:
		set_channel("route_clear", true)
		unlock_exit()
	add_encounter_cell("defended_route", "Z", [
		[{"kind": "drone", "cell": Vector2i(34, 38)}, {"kind": "sentry", "cell": Vector2i(48, 38), "opts": {"yaw": PI}}],
	], "lock_route", def_clear, "c3_cameras")
	var route_door := add_door("3", "route", ["route_clear"], {"label": "SQUAD LOCK"})
	if route_door != null and GameState.has_flag(flag_key("enc_defended_route_done")):
		route_door.force_open(true)
	spawn_marked("s", "sentry", {"yaw": -PI * 0.5})
	spawn_enemy("brute", first_cell("B"), {"uid": "ch3_brute"})

	add_pickups("f", "frag", 4)
	add_pickups("h", "health", 25)

	var relay_hint := func(_p: Player) -> void:
		hint("RELAYS: hold [%s] beside each console to hack it. Three relays open the grid lock." % Prefs.binding_text("interact"), 7.0)
		Story.play("c3_relay")
	add_zone_cell("R", relay_hint, "hint_relay")
	var brute_hint := func(_p: Player) -> void:
		Story.play("c3_brute")
	add_zone_cell("E", brute_hint, "hint_brute")
	if GameState.has_flag(flag_key("enc_defended_route_done")):
		unlock_exit()
	_dress()

func _on_channel(id: String, on: bool) -> void:
	if id in RELAYS and on and _all_relays_done():
		var gate: Door = doors.get("sec_gate")
		if gate != null:
			gate.force_open(true)
		Bus.hud_message.emit("GRID LOCK RELEASED", Cfg.C_GREEN, 2.2)
		Story.play("c3_reveal")

func _all_relays_done() -> bool:
	for r in RELAYS:
		if not GameState.has_flag(flag_key("relay_" + r)):
			return false
	return true

func after_player_spawned() -> void:
	if not GameState.has_flag(flag_key("intro")):
		GameState.set_flag(flag_key("intro"), true)
		Story.play("c3_intro")
	_refresh_objective()

func level_process(_delta: float) -> void:
	_refresh_objective()

func _refresh_objective() -> void:
	if GameState.has_flag(flag_key("enc_defended_route_done")):
		set_objective("Reach the Chrono access corridor and leave - fight the brute or slip past it")
	elif _all_relays_done():
		set_objective("Push through the defended route")
	else:
		set_objective("Disable the three security relays in the hub")

func _dress() -> void:
	Props.holo_text(entities, "SURVEILLANCE CORRIDOR", Vector3(44.0, 4.0, 48.0), Cfg.C_RED, 40)
	Props.holo_text(entities, "SECURITY HUB", Vector3(84.0, 4.0, 42.0), Cfg.C_RED, 48)
	Props.holo_text(entities, "DEFENDED ROUTE", Vector3(82.0, 4.0, 70.0), Cfg.C_AMBER, 40)
	Props.holo_text(entities, "CHRONO ACCESS CORRIDOR", Vector3(80.0, 4.0, 86.0), Cfg.C_RED, 44)
