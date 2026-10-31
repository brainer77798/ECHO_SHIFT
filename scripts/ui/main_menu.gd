class_name MainMenu
extends Control
## The title screen: New Game, Continue, Multiplayer (once implemented), Settings, Credits, Quit.

signal new_game_pressed
signal continue_pressed
signal multiplayer_pressed
signal credits_pressed
signal quit_pressed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.035)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_backdrop()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UiKit.vbox(26)
	center.add_child(col)
	var title := UiKit.title("ECHO // SHIFT", 62, Cfg.C_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var tag := UiKit.label("Your past actions shape your present, but what you do next determines your future.", 14, Color(0.55, 0.7, 0.8))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.custom_minimum_size = Vector2(520, 0)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(tag)
	col.add_child(UiKit.hsep())
	var buttons := UiKit.vbox(10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	var new_btn := UiKit.button("New Game")
	new_btn.pressed.connect(func() -> void: Sfx.play("ui_click"); new_game_pressed.emit())
	buttons.add_child(new_btn)
	var cont_btn := UiKit.button("Continue")
	cont_btn.disabled = not SaveSys.has_save()
	cont_btn.pressed.connect(func() -> void: Sfx.play("ui_click"); continue_pressed.emit())
	buttons.add_child(cont_btn)
	if Net.implemented:
		var mp_btn := UiKit.button("LAN Co-op")
		mp_btn.pressed.connect(func() -> void: Sfx.play("ui_click"); multiplayer_pressed.emit())
		buttons.add_child(mp_btn)
	var settings_btn := UiKit.button("Settings")
	settings_btn.pressed.connect(_open_settings)
	buttons.add_child(settings_btn)
	var credits_btn := UiKit.button("Credits")
	credits_btn.pressed.connect(func() -> void: Sfx.play("ui_click"); credits_pressed.emit())
	buttons.add_child(credits_btn)
	var quit_btn := UiKit.button("Quit", 260, Cfg.C_RED)
	quit_btn.pressed.connect(func() -> void: Sfx.play("ui_click"); quit_pressed.emit())
	buttons.add_child(quit_btn)
	var version := UiKit.label("MERIDIAN STATION INCIDENT - 2189", 11, Color(0.3, 0.38, 0.45))
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.position = Vector2(-260, -30)
	add_child(version)
	Sfx.play_music("menu")

func _build_backdrop() -> void:
	for i in 26:
		var ln := ColorRect.new()
		ln.color = Color(Cfg.C_CYAN.r, Cfg.C_CYAN.g, Cfg.C_CYAN.b, 0.03)
		ln.set_anchors_preset(Control.PRESET_FULL_RECT)
		ln.offset_top = i * 42
		ln.offset_bottom = i * 42 + 1
		add_child(ln)

func _open_settings() -> void:
	Sfx.play("ui_click")
	var s := SettingsPanel.new()
	add_child(s)
