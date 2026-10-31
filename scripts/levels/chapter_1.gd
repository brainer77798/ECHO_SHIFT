extends LevelBase
## CHAPTER 1 - THE ARRIVAL. Outer facility: dock, cargo hall, control annex, comms relay.
## Teaches movement, aiming, shooting, dash, interaction, and the Echo (plate + locked door puzzle).

var _obj_t := 0.0

func chapter() -> int:
	return 1

func start_yaw() -> float:
	return -PI * 0.5      # facing east, towards the dock door

func theme() -> Dictionary:
	return {
		"name": "OUTER FACILITY", "wall_style": "plates", "wall_color": Color(0.21, 0.24, 0.29),
		"floor_style": "tiles", "floor_color": Color(0.18, 0.20, 0.24),
		"accent": Cfg.C_CYAN, "accent2": Cfg.C_BLUE, "music": "explore",
	}

func map_rows() -> PackedStringArray:
	var m := MapBuilder.new(64, 40)
	# --- Dock 4 -------------------------------------------------------------------------------
	m.room(2, 24, 12, 12)
	m.put(4, 30, "P").put(6, 24, "T").put(13, 26, "A")
	for c in [Vector2i(3, 34), Vector2i(4, 34), Vector2i(3, 35), Vector2i(10, 35), Vector2i(11, 35), Vector2i(11, 34)]:
		m.put(c.x, c.y, "o")
	for c in [Vector2i(8, 27), Vector2i(8, 28), Vector2i(8, 32), Vector2i(8, 33)]:
		m.put(c.x, c.y, "O")
	m.put(12, 33, "f").put(12, 34, "f").put(5, 26, "f")
	# --- Corridor to the cargo hall --------------------------------------------------------------
	m.hall(14, 29, 11, 2)
	m.mark(14, 29, 1, 2, "1").put(20, 29, "C")
	# --- Cargo hall C ------------------------------------------------------------------------------
	m.room(25, 22, 18, 16)
	m.mark(26, 29, 2, 2, "Z")
	for c in [Vector2i(29, 26), Vector2i(29, 33), Vector2i(38, 26), Vector2i(38, 33)]:
		m.put(c.x, c.y, "o")
	for c in [Vector2i(33, 27), Vector2i(34, 27), Vector2i(33, 32), Vector2i(34, 32)]:
		m.put(c.x, c.y, "O")
	m.put(31, 30, "p").put(36, 30, "p")
	m.put(40, 24, "f").put(40, 35, "f").put(27, 24, "f").put(27, 35, "h")
	m.mark(33, 21, 2, 1, "2")
	# --- Corridor north to the annex --------------------------------------------------------------------
	m.hall(33, 14, 2, 7)
	# --- Control annex ---------------------------------------------------------------------------------------
	m.room(26, 4, 16, 10)
	m.mark(32, 8, 2, 2, "B").put(26, 6, "U").put(29, 12, "D").mark(31, 10, 6, 2, "H")
	for x in [28, 29, 30, 36, 37]:
		m.put(x, 4, "r")
	m.put(40, 12, "o").put(40, 11, "o").put(28, 10, "O").put(28, 9, "O")
	m.put(39, 5, "f").put(38, 5, "f").put(39, 12, "h")
	m.mark(42, 8, 1, 2, "3")
	# --- Corridor east to comms ---------------------------------------------------------------------------------
	m.hall(43, 8, 10, 2)
	m.mark(46, 8, 2, 2, "J")
	# --- Comms relay ---------------------------------------------------------------------------------------------------
	m.room(53, 2, 10, 14)
	m.put(54, 8, "E").put(54, 2, "V").mark(60, 2, 2, 1, "X").put(62, 9, "s")
	for c in [Vector2i(56, 6), Vector2i(56, 11), Vector2i(59, 8), Vector2i(59, 9), Vector2i(60, 13), Vector2i(57, 4), Vector2i(58, 4)]:
		m.put(c.x, c.y, "o" if c.y > 5 else "O")
	m.put(58, 6, "d").put(60, 12, "d").put(55, 14, "f").put(61, 14, "f").put(55, 5, "h")
	return m.rows()

func build_content() -> void:
	# --- devices --------------------------------------------------------------------------------------
	var power := add_switch("A", "dock_power", {"echo": false, "title": "DOCK POWER", "mode": "latch", "persist": flag_key("dock_power")})
	if power != null:
		power.prompt = "Restore dock power"
	add_terminal("T", "c1_dock")
	add_terminal("U", "c1_primer")
	add_terminal("V", "c1_hale_transmission", {"channel": "comms_read"})
	add_checkpoint("C", "cp1", 1)
	add_checkpoint("D", "cp2", 2)
	add_checkpoint("E", "cp3", 3)
	add_exit("X", "Read the transmission in the comms room first.")
	add_pickups("f", "frag", 4)
	add_pickups("h", "health", 25)
	restore_persisted(["comms_read"])
	if GameState.has_flag(flag_key("enc_hall_done")):
		set_channel("hall_clear", true)
	# --- doors --------------------------------------------------------------------------------------------
	add_door("1", "dock", ["dock_power", "!lock_hall"], {"label": "NO POWER"})
	add_door("2", "hall", ["hall_clear"], {"label": "LOCKED"})
	var d3 := add_door("3", "plate", ["plate_b"], {"label": "PRESSURE LOCK"})
	if d3 != null:
		if GameState.has_flag(flag_key("door3_solved")):
			d3.force_open(true)
		d3.state_changed.connect(_on_door3)
	add_plate("B", "plate_b", {"accept": "any", "latch": 1.8})
	# --- enemies and encounters -------------------------------------------------------------------------------
	spawn_marked("d", "drone")
	spawn_marked("s", "sentry", {"yaw": PI * 0.5})
	var hall_clear := func() -> void:
		set_channel("hall_clear", true)
	add_encounter_cell("hall", "Z", [
		[{"kind": "drone", "cell": Vector2i(40, 25)}],
		[{"kind": "drone", "cell": Vector2i(40, 34)}, {"kind": "drone", "cell": Vector2i(30, 24)}],
	], "lock_hall", hall_clear, "c1_first_enemy")
	# --- hints and story -------------------------------------------------------------------------------------------
	var plate_hint := func(_p: Player) -> void:
		hint("ECHO: stand on the plate, press [%s] to project your last 5 seconds, then run for the door." % Prefs.binding_text("echo"), 9.0)
		Story.play("c1_plate")
	add_zone_cell("H", plate_hint, "hint_plate")
	hint_zone("J", "SENTRY AHEAD: its red laser shows where it will fire. Break the line - or give it an Echo to watch.", 7.0, "hint_sentry")
	channel_changed.connect(_on_channel)
	# --- dressing ---------------------------------------------------------------------------------------------------------
	_dress()

func _on_door3(_d: Door, open: bool) -> void:
	if open and not GameState.has_flag(flag_key("door3_solved")):
		GameState.set_flag(flag_key("door3_solved"), true)
		Story.play("c1_door_open")

func _on_channel(id: String, on: bool) -> void:
	if id == "comms_read" and on:
		unlock_exit()
		Story.play("c1_exit")
		Bus.hud_message.emit("EXIT UNLOCKED", Cfg.C_GREEN, 3.0)
	if id == "dock_power" and on:
		Bus.hud_message.emit("DOCK DOOR POWERED", Cfg.C_GREEN, 2.5)

func after_player_spawned() -> void:
	if not GameState.has_flag(flag_key("intro")):
		GameState.set_flag(flag_key("intro"), true)
		Story.play("c1_intro")
		hint("[%s/%s/%s/%s] MOVE   |   MOUSE aims   |   [LMB] FIRE   |   [%s] DASH   |   [%s] INTERACT" % [
			Prefs.binding_text("move_forward"), Prefs.binding_text("move_left"), Prefs.binding_text("move_back"), Prefs.binding_text("move_right"),
			Prefs.binding_text("dash"), Prefs.binding_text("interact")], 10.0)
	if get_channel("comms_read") and exit_gate != null:
		unlock_exit()
	_refresh_objective()

func level_process(delta: float) -> void:
	_obj_t -= delta
	if _obj_t <= 0.0:
		_obj_t = 0.4
		_refresh_objective()

func _refresh_objective() -> void:
	if get_channel("comms_read"):
		set_objective("Leave the outer facility through the exit gate")
	elif GameState.has_flag(flag_key("door3_solved")):
		set_objective("Reach the communications room and read the terminal")
	elif GameState.has_flag(flag_key("enc_hall_done")):
		set_objective("Cross the control annex. Open the sealed door with an Echo")
	elif get_channel("dock_power"):
		set_objective("Clear the cargo hall")
	else:
		set_objective("Restore power to the dock door (use the console)")

func _dress() -> void:
	Props.holo_text(entities, "DOCK 4  //  ARRIVALS", Vector3(16.0, 3.6, 49.0), Cfg.C_CYAN, 44)
	Props.holo_text(entities, "CARGO HALL C", Vector3(68.0, 4.0, 60.0), Cfg.C_CYAN, 52)
	Props.holo_text(entities, "CONTROL ANNEX", Vector3(66.0, 4.0, 22.0), Cfg.C_CYAN, 48)
	Props.holo_text(entities, "COMMS RELAY", Vector3(116.0, 4.0, 22.0), Cfg.C_CYAN, 48)
	var pipe_mat := Mats.plain(Color(0.14, 0.16, 0.2), 0.5, 0.7)
	for z in [47.0, 53.0, 61.0, 73.0]:
		Props.pipe(entities, Vector3(52.0, 4.55, z), Vector3(84.0, 4.55, z), 0.16, pipe_mat)
	for x in [56.0, 64.0, 74.0]:
		Props.pipe(entities, Vector3(x, 4.7, 46.0), Vector3(x, 4.7, 72.0), 0.12, pipe_mat)
	Props.floor_decal(entities, Vector3(62.0, 0, 46.0), Vector2(6.0, 2.0), Props.stripes_material(Cfg.C_AMBER))
	Shapes.add_light(entities, Vector3(68.0, 3.5, 60.0), Cfg.C_RED, 0.8, 10.0)
