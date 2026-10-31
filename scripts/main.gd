extends Node
## Top-level orchestrator: boots to the main menu, starts/continues a campaign, loads chapters,
## reacts to chapter completion, player death and the chosen ending, and owns the pause menu.
## This is the scene registered as run/main_scene in project.godot.

var hud: Hud
var chapter_node: Node
var _menu_layer: CanvasLayer
var _fade: ColorRect
var _pause_menu: PauseMenu
var _ending_screen: EndingScreen
var _busy := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveSys.load_meta()
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	add_child(_menu_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(fade_layer)
	fade_layer.add_child(_fade)
	Bus.request_pause.connect(_toggle_pause)
	Bus.chapter_completed.connect(_on_chapter_completed)
	Bus.player_died.connect(_on_player_died)
	Bus.ending_chosen.connect(_on_ending_chosen)
	Net.load_chapter_requested.connect(_on_net_load_chapter)
	Net.session_ended.connect(_on_net_session_ended)
	_show_main_menu()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or _busy:
		return
	if hud == null or _ending_screen != null:
		return
	if hud.any_modal_open():
		hud.close_top_modal()
		get_viewport().set_input_as_handled()
		return
	if chapter_node == null:
		return
	Bus.request_pause.emit()
	get_viewport().set_input_as_handled()

# --- Fade helper ---------------------------------------------------------------------------------

func _fade_to(alpha: float, time: float) -> void:
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(_fade, "color:a", alpha, time)
	await tw.finished

# --- Main menu --------------------------------------------------------------------------------------

func _show_main_menu() -> void:
	_clear_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var m := MainMenu.new()
	m.new_game_pressed.connect(_on_new_game_pressed)
	m.continue_pressed.connect(_on_continue_pressed)
	m.multiplayer_pressed.connect(_show_coop_lobby)
	m.credits_pressed.connect(_show_credits)
	m.quit_pressed.connect(func() -> void: get_tree().quit())
	_menu_layer.add_child(m)

func _show_coop_lobby() -> void:
	_clear_menu()
	var lobby := CoopLobby.new()
	lobby.back_pressed.connect(_show_main_menu)
	lobby.game_starting.connect(func() -> void:
		_clear_menu()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if hud == null:
			hud = Hud.new()
			add_child(hud))
	_menu_layer.add_child(lobby)

func _clear_menu() -> void:
	for c in _menu_layer.get_children():
		c.queue_free()

func _show_credits() -> void:
	var c := CreditsScreen.new()
	c.closed.connect(_show_main_menu)
	_menu_layer.add_child(c)

func _on_new_game_pressed() -> void:
	if SaveSys.has_save():
		var box := ConfirmBox.new()
		box.text = "Start a new game?\nThis will overwrite your existing save."
		box.confirmed.connect(_start_new_game)
		_menu_layer.add_child(box)
	else:
		_start_new_game()

func _start_new_game() -> void:
	GameState.new_game()
	_begin_session()

func _on_continue_pressed() -> void:
	if not SaveSys.load_game():
		Bus.hud_message.emit("No valid save found", Cfg.C_RED, 2.5)
		return
	_begin_session()

func _begin_session() -> void:
	_clear_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud = Hud.new()
	add_child(hud)
	await _load_chapter(GameState.chapter)

# --- Chapter loading ---------------------------------------------------------------------------------

func _load_chapter(idx: int) -> void:
	_busy = true
	await _fade_to(1.0, 0.4)
	if chapter_node != null and is_instance_valid(chapter_node):
		chapter_node.queue_free()
		chapter_node = null
		await get_tree().process_frame
	GameState.chapter = idx
	var def: Dictionary = Cfg.CHAPTERS[idx - 1]
	var scene: PackedScene = load(String(def["scene"]))
	chapter_node = scene.instantiate()
	add_child(chapter_node)
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Bus.hud_message.emit("CHAPTER %d  -  %s" % [idx, String(def["title"])], Cfg.C_CYAN, 3.0)
	await _fade_to(0.0, 0.6)
	_busy = false

func _on_chapter_completed(idx: int) -> void:
	if _busy or idx >= Cfg.CHAPTERS.size():
		return
	if Net.active:
		# host-authoritative: only the host's own completion advances the party; a client that
		# reaches the exit first just waits here for the host's broadcast.
		if Net.is_host:
			GameState.begin_chapter(idx + 1)
			SaveSys.save_game()
			Net.broadcast_chapter(idx + 1)
		else:
			Bus.hud_message.emit("Waiting for the host to move on...", Cfg.C_CYAN, 2.5)
		return
	GameState.begin_chapter(idx + 1)
	SaveSys.save_game()
	await _load_chapter(idx + 1)

func _on_net_load_chapter(idx: int) -> void:
	if not Net.is_host:
		GameState.begin_chapter(idx)
	await _load_chapter(idx)

func _on_net_session_ended(reason: String) -> void:
	if reason != "":
		Bus.hud_message.emit(reason, Cfg.C_RED, 3.0)
	if chapter_node != null or hud != null:
		_quit_to_menu()

func _on_player_died(_p: Node) -> void:
	if _busy:
		return
	_busy = true
	await get_tree().create_timer(1.7).timeout
	GameState.restore_checkpoint()
	_busy = false
	await _load_chapter(GameState.chapter)

# --- Pause -------------------------------------------------------------------------------------------------

func _toggle_pause() -> void:
	if _pause_menu != null:
		_close_pause()
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_menu = PauseMenu.new()
	_pause_menu.resume_pressed.connect(_close_pause)
	_pause_menu.restart_checkpoint_pressed.connect(_restart_checkpoint)
	_pause_menu.restart_chapter_pressed.connect(_restart_chapter)
	_pause_menu.main_menu_pressed.connect(_quit_to_menu)
	_menu_layer.add_child(_pause_menu)

func _close_pause() -> void:
	if _pause_menu != null:
		_pause_menu.queue_free()
		_pause_menu = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _restart_checkpoint() -> void:
	_close_pause()
	GameState.restore_checkpoint()
	await _load_chapter(GameState.chapter)

func _restart_chapter() -> void:
	_close_pause()
	GameState.restart_chapter()
	await _load_chapter(GameState.chapter)

func _quit_to_menu() -> void:
	_close_pause()
	if chapter_node != null:
		chapter_node.queue_free()
		chapter_node = null
	if hud != null:
		hud.queue_free()
		hud = null
	GameState.in_game = false
	await _fade_to(0.0, 0.01)    # ensure a clean slate before the menu fades back in
	_show_main_menu()

# --- Ending ----------------------------------------------------------------------------------------------

func _on_ending_chosen(kind: String) -> void:
	GameState.record_ending(kind)
	await _fade_to(1.0, 1.2)
	if chapter_node != null:
		chapter_node.queue_free()
		chapter_node = null
	if hud != null:
		hud.queue_free()
		hud = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ending_screen = EndingScreen.new()
	_ending_screen.main_menu_pressed.connect(func() -> void:
		_ending_screen.queue_free()
		_ending_screen = null
		GameState.in_game = false
		_show_main_menu())
	_menu_layer.add_child(_ending_screen)
	_ending_screen.show_ending(kind)
	await _fade_to(0.0, 0.8)
