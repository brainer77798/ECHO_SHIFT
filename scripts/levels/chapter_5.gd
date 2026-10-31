extends LevelBase
## CHAPTER 5 - THE FINAL ECHO. A short approach to the Chrono Core chamber, the three-phase WARDEN
## boss fight, and the ending choice. music_locked is set so the boss owns the soundtrack.

var boss: WardenBoss
var consoles: Array = []
var _fight_started := false

func chapter() -> int:
	return 5

func start_yaw() -> float:
	return 0.0

func needs_exit_gate() -> bool:
	return false   # this chapter ends through the ending consoles, not a walk-to-exit gate

func theme() -> Dictionary:
	return {
		"name": "CHRONO CORE CHAMBER", "wall_style": "circuit", "wall_color": Color(0.14, 0.12, 0.17),
		"floor_style": "circuit", "floor_color": Color(0.11, 0.1, 0.14),
		"accent": Cfg.C_RED, "accent2": Cfg.C_VIOLET, "ambient": Color(0.22, 0.14, 0.22),
		"fog": Color(0.03, 0.02, 0.05), "lamp_spacing": 7, "music": "explore",
	}

func map_rows() -> PackedStringArray:
	var m := MapBuilder.new(70, 60)
	# --- Access -------------------------------------------------------------------------------
	m.room(2, 30, 12, 10)
	m.put(4, 35, "P").put(6, 31, "T").put(11, 35, "C")
	m.put(5, 38, "f")
	# --- Corridor to the chamber ---------------------------------------------------------------------
	m.hall(14, 33, 10, 4)
	m.mark(18, 34, 2, 2, "W")
	# --- Chrono Core chamber ---------------------------------------------------------------------------------
	m.room(24, 14, 38, 32)
	m.mark(24, 33, 3, 4, "Z")
	for c in [Vector2i(32, 18), Vector2i(32, 42), Vector2i(50, 18), Vector2i(50, 42), Vector2i(41, 18), Vector2i(41, 42)]:
		m.put(c.x, c.y, "p")
	for c in [Vector2i(30, 29), Vector2i(30, 31), Vector2i(53, 29), Vector2i(53, 31)]:
		m.put(c.x, c.y, "O")
	m.put(44, 30, "B").put(38, 24, "1").put(50, 24, "2").put(44, 36, "3")
	m.put(40, 17, "D").put(44, 17, "F").put(48, 17, "G")
	m.mark(34, 26, 1, 4, "H").mark(52, 26, 1, 4, "I")
	return m.rows()

func build_content() -> void:
	add_terminal("T", "c5_core_spec")
	add_terminal("W", "c5_voss_loop")
	add_checkpoint("C", "cp1", 1)
	set_channel("hazards_off", true)

	boss = WardenBoss.new()
	entities.add_child(boss)
	boss.global_position = cell_pos(first_cell("B"))
	boss.phase_changed.connect(_on_boss_phase)
	boss.defeated.connect(_on_boss_defeated)

	var shields: Array = []
	for ch in ["1", "2", "3"]:
		var cell := first_cell(ch)
		if cell.x < 0:
			continue
		var s := ShieldNode.new()
		s.level = self
		entities.add_child(s)
		s.global_position = cell_pos(cell)
		shields.append(s)

	add_hazard_arc("H", {"period": 4.0, "warn": 1.0, "active": 1.1, "phase": 0.0, "damage": 18.0, "disabled_by": "hazards_off"})
	add_hazard_arc("I", {"period": 4.0, "warn": 1.0, "active": 1.1, "phase": 2.0, "damage": 18.0, "disabled_by": "hazards_off"})

	consoles = []
	var kinds := ["shutdown", "containment", "reactivation"]
	var e_cells := [first_cell("D"), first_cell("F"), first_cell("G")]
	for i in 3:
		if e_cells[i].x < 0:
			continue
		var c := EndingConsole.new()
		c.kind = kinds[i]
		entities.add_child(c)
		c.global_position = cell_pos(e_cells[i])
		c.build()
		consoles.append(c)

	add_zone_cell("Z", func(_p: Player) -> void: _start_fight(shields), "fight_zone")

	if GameState.has_flag(flag_key("warden_defeated")):
		_reveal_consoles()
	_dress()

func _start_fight(shields: Array) -> void:
	if _fight_started or GameState.has_flag(flag_key("warden_defeated")):
		return
	_fight_started = true
	music_locked = true
	Sfx.play_music("boss", 1.0)
	Story.play("c5_intro")
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_callback(func() -> void:
		boss.start(shields)
		Story.play("c5_phase1"))

func _on_boss_phase(phase: int) -> void:
	if phase == 2:
		set_channel("hazards_off", false)
		Story.play("c5_phase2")
	elif phase == 3:
		Story.play("c5_phase3")

func _on_boss_defeated() -> void:
	GameState.set_flag(flag_key("warden_defeated"), true)
	set_channel("hazards_off", true)
	Sfx.play_music("ending", 2.0)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(_reveal_consoles)

func _reveal_consoles() -> void:
	for c in consoles:
		(c as EndingConsole).reveal()
	set_objective("The Chrono Core's fate is yours to decide")

func after_player_spawned() -> void:
	set_objective("Reach the Chrono Core chamber")

func _dress() -> void:
	Props.holo_text(entities, "CHRONO CORE - RESTRICTED", Vector3(28.0, 4.0, 72.0), Cfg.C_RED, 44)
	for x in [50.0, 110.0]:
		Props.pipe(entities, Vector3(x, 4.8, 30.0), Vector3(x, 4.8, 96.0), 0.18, Mats.plain(Color(0.14, 0.12, 0.17), 0.5, 0.7))
