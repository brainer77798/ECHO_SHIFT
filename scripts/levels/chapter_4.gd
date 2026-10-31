extends LevelBase
## CHAPTER 4 - BROKEN CORE. Damaged experimental chambers: a timed-arc hazard gauntlet, a moving
## crusher barrier, an energy field door, and the advanced dual-echo puzzle (two plates held at
## once, which only becomes possible because the operative can field two Echoes simultaneously).

func chapter() -> int:
	return 4

func start_yaw() -> float:
	return 0.0

func theme() -> Dictionary:
	return {
		"name": "EXPERIMENTAL CHAMBERS", "wall_style": "damaged", "wall_color": Color(0.20, 0.17, 0.14),
		"floor_style": "grate", "floor_color": Color(0.15, 0.14, 0.13),
		"accent": Cfg.C_ORANGE, "accent2": Cfg.C_AMBER, "ambient": Color(0.28, 0.18, 0.12),
		"fog": Color(0.06, 0.04, 0.03), "music": "explore",
	}

func map_rows() -> PackedStringArray:
	var m := MapBuilder.new(60, 70)
	# --- Access -------------------------------------------------------------------------------
	m.room(2, 26, 12, 10)
	m.put(4, 31, "P").put(6, 27, "T").put(11, 31, "C")
	m.put(5, 34, "f")
	# --- Arc hazard gauntlet ----------------------------------------------------------------------
	m.hall(14, 28, 20, 6)
	m.mark(18, 29, 1, 4, "K").mark(24, 29, 1, 4, "L").mark(30, 29, 1, 4, "M")
	for c in [Vector2i(16, 29), Vector2i(16, 32), Vector2i(34, 29), Vector2i(34, 32)]:
		m.put(c.x, c.y, "O")
	m.put(21, 29, "h")
	# --- Crusher hall -----------------------------------------------------------------------------
	m.hall(34, 28, 10, 6)
	m.mark(40, 30, 1, 2, "Q")
	m.put(36, 29, "f")
	# --- Hub before the dual-echo chamber -------------------------------------------------------------
	m.room(44, 20, 14, 20)
	m.put(46, 22, "U").put(50, 38, "D")
	for c in [Vector2i(47, 26), Vector2i(53, 26), Vector2i(47, 34), Vector2i(53, 34)]:
		m.put(c.x, c.y, "p")
	m.put(50, 29, "n").put(46, 36, "h")
	m.mark(49, 39, 2, 1, "2")
	# --- Connector down to the dual-echo chamber ---------------------------------------------------------------
	m.hall(48, 40, 4, 2)
	# --- Dual-echo chamber -----------------------------------------------------------------------------------
	m.room(40, 42, 22, 16)
	m.mark(43, 46, 2, 2, "A").mark(57, 46, 2, 2, "B")
	for c in [Vector2i(47, 44), Vector2i(53, 44), Vector2i(47, 55), Vector2i(53, 55)]:
		m.put(c.x, c.y, "O")
	m.put(49, 51, "n").put(51, 52, "n")
	m.put(50, 43, "W").put(42, 55, "f").put(58, 55, "f")
	m.mark(49, 58, 2, 1, "3")
	# --- Field corridor to the core access ---------------------------------------------------------------------------
	m.hall(44, 59, 12, 6)
	m.mark(49, 61, 2, 1, "F")
	m.put(46, 63, "h").put(52, 63, "f")
	m.mark(49, 65, 2, 1, "E")
	m.room(40, 66, 20, 4)
	m.put(42, 68, "N").put(56, 68, "X")
	return m.rows()

func build_content() -> void:
	add_terminal("T", "c4_run_log")
	add_terminal("U", "c4_nand_theory")
	add_terminal("N", "c4_voss_final")
	add_checkpoint("C", "cp1", 1)
	add_checkpoint("D", "cp2", 2)
	add_checkpoint("E", "cp3", 3)
	add_exit("X", "The field lock ahead needs both Echoes to hold it open.")

	# --- Arc gauntlet: three staggered arcs, readable warning then discharge -----------------------
	add_hazard_arc("K", {"period": 3.6, "warn": 0.9, "active": 1.0, "phase": 0.0, "damage": 20.0})
	add_hazard_arc("L", {"period": 3.6, "warn": 0.9, "active": 1.0, "phase": 1.2, "damage": 20.0})
	add_hazard_arc("M", {"period": 3.6, "warn": 0.9, "active": 1.0, "phase": 2.4, "damage": 20.0})

	# --- Crusher barrier: a wall piston that periodically rises from the floor to block the hall ------
	add_crusher("Q", Vector3(0, 5.0, 0), Vector3(1.8, 5.0, 11.5), {"period": 6.0, "dwell": 2.0, "base_y": -5.0})

	# --- Dual-echo puzzle: two echo-only plates must be held at the same time ------------------------------------
	add_plate("A", "dual_a", {"accept": "echo", "latch": 0.6})
	add_plate("B", "dual_b", {"accept": "echo", "latch": 0.6})
	add_door("3", "dual_gate", ["dual_a", "dual_b"], {"label": "DUAL LOCK"})
	add_terminal("W", "c4_hale_last")
	channel_changed.connect(_on_channel)

	add_door("2", "hub_gate", ["dual_solved"], {"label": "SEALED"})
	var dual_gate := doors.get("dual_gate")
	if GameState.has_flag(flag_key("dual_solved")):
		set_channel("dual_solved", true)
		if dual_gate != null:
			(dual_gate as Door).force_open(true)
		var hub_gate: Door = doors.get("hub_gate")
		if hub_gate != null:
			hub_gate.force_open(true)

	# --- Energy field blocking the final corridor until the dual chamber is solved ----------------------------------
	add_door("F", "field_gate", ["dual_solved"], {"label": "CORE FIELD", "field": true})

	add_pickups("f", "frag", 4)
	add_pickups("h", "health", 25)

	var gauntlet_hint := func(_p: Player) -> void:
		hint("Three arcs discharge on a timer. Watch the warning flicker, then dash through the gap.", 7.0)
		Story.play("c4_hazards")
	add_zone_cell("K", gauntlet_hint, "hint_gauntlet")
	var crusher_hint := func(_p: Player) -> void:
		Story.play("c4_barriers")
	add_zone_cell("Q", crusher_hint, "hint_crusher")
	var dual_hint := func(_p: Player) -> void:
		hint("DUAL LOCK: both plates must be held at once. Record an Echo on A, then record a second Echo on B - two Echoes can work together.", 10.0)
	add_zone_cell("A", dual_hint, "hint_dual")
	_dress()

func _on_channel(id: String, _on: bool) -> void:
	if (id == "dual_a" or id == "dual_b") and get_channel("dual_a") and get_channel("dual_b") and not get_channel("dual_solved"):
		set_channel("dual_solved", true)
		GameState.set_flag(flag_key("dual_solved"), true)
		Bus.hud_message.emit("DUAL LOCK RELEASED", Cfg.C_GREEN, 2.5)
		var hub_gate: Door = doors.get("hub_gate")
		if hub_gate != null:
			hub_gate.force_open(true)

func after_player_spawned() -> void:
	if not GameState.has_flag(flag_key("intro")):
		GameState.set_flag(flag_key("intro"), true)
	_refresh_objective()

func level_process(_delta: float) -> void:
	_refresh_objective()

func _refresh_objective() -> void:
	if get_channel("dual_solved"):
		set_objective("Cross the core field and reach the Chrono Core")
	else:
		set_objective("Reach the dual chamber - two Echoes must hold both plates at once")

func _dress() -> void:
	Props.holo_text(entities, "DAMAGE CONTROL CORRIDOR", Vector3(44.0, 4.0, 62.0), Cfg.C_ORANGE, 40)
	Props.holo_text(entities, "RESONANCE CHAMBER", Vector3(102.0, 4.0, 86.0), Cfg.C_ORANGE, 44)
	Props.holo_text(entities, "CORE ACCESS", Vector3(92.0, 4.0, 134.0), Cfg.C_RED, 44)
