class_name PauseMenu
extends Control
## In-mission pause menu: Resume, restart from checkpoint / restart chapter, Settings, Main Menu.

signal resume_pressed
signal restart_checkpoint_pressed
signal restart_chapter_pressed
signal main_menu_pressed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.68)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UiKit.panel(Cfg.C_CYAN, UiKit.BG_SOLID, 2)
	center.add_child(p)
	var col := UiKit.vbox(10)
	p.add_child(col)
	col.add_child(UiKit.title("PAUSED", 28))
	col.add_child(UiKit.hsep())
	var resume := UiKit.button("Resume")
	resume.pressed.connect(func() -> void: Sfx.play("ui_back"); resume_pressed.emit())
	col.add_child(resume)
	var rc := UiKit.button("Restart from Checkpoint", 260, Cfg.C_AMBER)
	rc.pressed.connect(func() -> void: Sfx.play("ui_click"); restart_checkpoint_pressed.emit())
	col.add_child(rc)
	var rch := UiKit.button("Restart Chapter", 260, Cfg.C_AMBER)
	rch.pressed.connect(func() -> void: Sfx.play("ui_click"); restart_chapter_pressed.emit())
	col.add_child(rch)
	var settings := UiKit.button("Settings")
	settings.pressed.connect(_open_settings)
	col.add_child(settings)
	var quit := UiKit.button("Return to Main Menu", 260, Cfg.C_RED)
	quit.pressed.connect(_confirm_quit)
	col.add_child(quit)
	resume.grab_focus()

func _open_settings() -> void:
	Sfx.play("ui_click")
	add_child(SettingsPanel.new())

func _confirm_quit() -> void:
	var box := ConfirmBox.new()
	box.text = "Return to the main menu?\nProgress since your last checkpoint will be lost."
	box.confirmed.connect(func() -> void: main_menu_pressed.emit())
	add_child(box)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Sfx.play("ui_back")
		resume_pressed.emit()
		get_viewport().set_input_as_handled()
