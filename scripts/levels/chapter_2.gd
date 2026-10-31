extends LevelBase
## CHAPTER 2 - RESEARCH DIVISION. Laboratory wing: a switch-sequence vault door, an optional timed
## side-vault, a sentry-guarded echo-only plate (combat-distraction), and a climactic security fight.

const SEQ_ORDER := ["seq_a", "seq_b", "seq_c"]

var _seq_progress := 0

func chapter() -> int:
	return 2

func start_yaw() -> float:
	return 0.0

func theme() -> Dictionary:
	return {
		"name": "RESEARCH DIVISION", "wall_style": "tiles", "wall_color": Color(0.19, 0.23, 0.27),
		"floor_style": "circuit", "floor_color": Color(0.15, 0.18, 0.21),
		"accent": Cfg.C_BLUE, "accent2": Cfg.C_VIOLET, "music": "explore",
	}

func map_rows() -> PackedStringArray:
	var m := MapBuilder.new(62, 52)
	# --- Access ----------------------------------------------------------------------------
	m.room(2, 22, 14, 10)
	m.put(4, 27, "P").put(6, 23, "T").put(12, 27, "C")
	m.put(5, 30, "f").put(13, 23, "f")
	# --- Corridor to the hub -----------------------------------------------------------------
	m.hall(16, 26, 6, 2)
	# --- Lab Wing Hub ------------------------------------------------------------------------
	m.room(22, 8, 26, 26)
	m.mark(24, 10, 2, 2, "A").mark(44, 10, 2, 2, "B").mark(33, 31, 2, 1, "E")
	m.mark(44, 19, 2, 2, "V").put(45, 14, "U")
	for c in [Vector2i(28, 11), Vector2i(28, 30), Vector2i(40, 11), Vector2i(40, 30), Vector2i(32, 20), Vector2i(38, 20)]:
		m.put(c.x, c.y, "p")
	for c in [Vector2i(24, 25), Vector2i(24, 26), Vector2i(46, 25), Vector2i(46, 26)]:
		m.put(c.x, c.y, "o")
	for c in [Vector2i(30, 9), Vector2i(31, 9), Vector2i(42, 29), Vector2i(43, 29)]:
		m.put(c.x, c.y, "r")
	m.put(36, 9, "n").put(36, 30, "h").put(25, 20, "f").put(43, 20, "f").put(23, 27, "Y")
	m.mark(33, 33, 2, 1, "2")
	m.put(32, 8, "D").put(32, 32, "Z")
	# --- Side vault (optional, timed) -----------------------------------------------------------
	m.room(49, 15, 11, 10)
	m.put(58, 17, "W").put(55, 23, "f").put(57, 18, "f")
	m.hall(48, 19, 2, 2).mark(48, 19, 1, 2, "4")
	m.hall(53, 25, 4, 9)
	# --- Lower corridor ----------------------------------------------------------------------------
	m.hall(28, 34, 29, 3)
	# --- Test chamber ------------------------------------------------------------------------------------
	m.room(26, 40, 24, 10)
	m.mark(33, 44, 2, 2, "Q").mark(44, 44, 1, 2, "3").mark(36, 46, 3, 2, "K")
	for c in [Vector2i(30, 41), Vector2i(30, 48), Vector2i(40, 41), Vector2i(40, 48)]:
		m.put(c.x, c.y, "O")
	m.put(28, 44, "s").put(43, 46, "s")
	m.put(29, 41, "h").put(39, 48, "f")
	m.room(45, 42, 6, 6)
	m.put(47, 44, "X").put(48, 44, "N")
	m.hall(30, 37, 4, 3)
	return m.rows()

func build_content() -> void:
	# sequence-gated vault door (also optionally held open by the field hazard on failure state)
	add_door("2", "vault", ["seq_done"], {"label": "SEQUENCE LOCK"})
	add_switch("A", "seq_a", {"echo": false, "title": "RELAY A"})
	add_switch("B", "seq_b", {"echo": false, "title": "RELAY B"})
	add_switch("E", "seq_c", {"echo": false, "title": "RELAY C"})
	channel_changed.connect(_on_channel)
	if GameState.has_flag(flag_key("seq_done")):
		set_channel("seq_done", true)

	add_switch("V", "vault_open", {"echo": false, "title": "VAULT SEAL", "mode": "timed", "duration": 7.0})
	add_door("4", "vault_door", ["vault_open"], {"label": "TIMED SEAL", "open_time": 0.35})

	add_terminal("T", "c2_history")
	add_terminal("U", "c2_voss_memo")
	add_terminal("W", "c2_nand_anomaly", {"channel": "nand_read"})
	add_terminal("N", "c2_hale_warning")
	add_checkpoint("C", "cp1", 1)
	add_checkpoint("D", "cp2", 2)
	add_exit("X", "Defeat the security response before you can leave.")

	add_plate("Q", "plate_echo2", {"accept": "echo", "latch": 1.5})
	var chamber_door := add_door("3", "chamber", ["plate_echo2"], {"label": "FIELD LOCK"})
	if chamber_door != null:
		chamber_door.state_changed.connect(_on_chamber_door)
		if GameState.has_flag(flag_key("chamber_solved")):
			chamber_door.force_open(true)
	spawn_marked("s", "sentry", {"yaw": PI})

	add_pickups("f", "frag", 4)
	add_pickups("h", "health", 25)

	var hall_clear := func() -> void:
		set_channel("hub_clear", true)
	add_encounter_cell("hub_fight", "Z", [
		[{"kind": "drone", "cell": Vector2i(26, 12)}, {"kind": "drone", "cell": Vector2i(44, 30)}],
	], "lock_hub", hall_clear, "c2_switches")

	var final_clear := func() -> void:
		unlock_exit()
	add_encounter_cell("final_fight", "K", [
		[{"kind": "drone", "cell": Vector2i(29, 45)}, {"kind": "drone", "cell": Vector2i(44, 47)}],
		[{"kind": "sentry", "cell": Vector2i(49, 44), "opts": {"yaw": PI}}],
	], "lock_final", final_clear, "c2_end")
	if GameState.has_flag(flag_key("enc_final_fight_done")):
		unlock_exit()

	dialogue_zone("Y", "c2_intro", "intro_zone")
	hint_zone("D", "SWITCHES: activate the three relays in the correct order - A, then B, then C.", 8.0, "hint_seq")
	var chamber_hint := func(_p: Player) -> void:
		hint("FIELD LOCK: this plate only answers to an Echo. Record yourself crossing it, then let your Echo hold it while you flank the sentries.", 9.0)
		Story.play("c2_sentry")
	add_zone_cell("Q", chamber_hint, "hint_chamber")
	restore_persisted(["nand_read"])
	_dress()

func _on_channel(id: String, on: bool) -> void:
	if id in SEQ_ORDER and on and not get_channel("seq_done"):
		if id == SEQ_ORDER[_seq_progress]:
			_seq_progress += 1
			Sfx.play("plate_on", -2.0, 1.0 + _seq_progress * 0.15)
			if _seq_progress >= SEQ_ORDER.size():
				set_channel("seq_done", true)
				GameState.set_flag(flag_key("seq_done"), true)
				Bus.hud_message.emit("SEQUENCE ACCEPTED - VAULT UNLOCKED", Cfg.C_GREEN, 2.5)
			else:
				Bus.hud_message.emit("RELAY %d OF 3 ACCEPTED" % _seq_progress, Cfg.C_CYAN, 1.6)
		else:
			Bus.hud_message.emit("SEQUENCE FAILED - RESETTING RELAYS", Cfg.C_RED, 2.0)
			Sfx.play("echo_fail")
			_seq_progress = 0
			for sid in SEQ_ORDER:
				var dev: Switch = devices.get(sid)
				if dev != null:
					dev.force_state(false)

func after_player_spawned() -> void:
	if not GameState.has_flag(flag_key("intro")):
		GameState.set_flag(flag_key("intro"), true)
	_refresh_objective()

func level_process(_delta: float) -> void:
	_refresh_objective()

func _on_chamber_door(_d: Door, open: bool) -> void:
	if open and not GameState.has_flag(flag_key("chamber_solved")):
		GameState.set_flag(flag_key("chamber_solved"), true)

func _refresh_objective() -> void:
	if GameState.has_flag(flag_key("enc_final_fight_done")):
		set_objective("Leave the research division through the exit")
	elif GameState.has_flag(flag_key("chamber_solved")):
		set_objective("Clear the security response near the exit")
	elif get_channel("seq_done"):
		set_objective("Push past the test chamber - use an Echo to hold the field lock")
	else:
		set_objective("Activate relays A, B and C in order to unlock the vault door")

func _dress() -> void:
	Props.holo_text(entities, "LABORATORY ACCESS", Vector3(18.0, 3.6, 54.0), Cfg.C_BLUE, 40)
	Props.holo_text(entities, "LAB WING HUB", Vector3(70.0, 4.0, 42.0), Cfg.C_BLUE, 48)
	Props.holo_text(entities, "ARCHIVE VAULT", Vector3(110.0, 4.0, 38.0), Cfg.C_VIOLET, 36)
	Props.holo_text(entities, "TEST CHAMBER 3", Vector3(76.0, 4.0, 90.0), Cfg.C_RED, 44)
	var pipe_mat := Mats.plain(Color(0.14, 0.18, 0.2), 0.5, 0.7)
	for z in [16.0, 60.0]:
		Props.pipe(entities, Vector3(46.0, 4.55, z), Vector3(94.0, 4.55, z), 0.14, pipe_mat)
