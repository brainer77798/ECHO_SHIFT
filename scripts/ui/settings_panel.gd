class_name SettingsPanel
extends Control
## Reusable settings screen (audio, display, controls incl. live key rebinding). Used by both the
## main menu and the pause menu; every control edits Prefs directly and takes effect immediately.

signal closed

var _listening_action := ""
var _bind_buttons: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UiKit.panel(Cfg.C_CYAN, UiKit.BG_SOLID, 2)
	p.custom_minimum_size = Vector2(620, 0)
	center.add_child(p)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 560)
	p.add_child(scroll)
	var col := UiKit.vbox(14)
	col.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(col)
	col.add_child(UiKit.title("SETTINGS", 26))
	col.add_child(UiKit.hsep())

	col.add_child(UiKit.label("AUDIO", 13, Color(0.55, 0.75, 0.85)))
	col.add_child(_slider_row("Master volume", Prefs.master, func(v: float) -> void: Prefs.set_value("master", v)))
	col.add_child(_slider_row("Music", Prefs.music, func(v: float) -> void: Prefs.set_value("music", v)))
	col.add_child(_slider_row("Sound effects", Prefs.sfx, func(v: float) -> void: Prefs.set_value("sfx", v)))
	col.add_child(UiKit.hsep())

	col.add_child(UiKit.label("DISPLAY", 13, Color(0.55, 0.75, 0.85)))
	col.add_child(_check_row("Fullscreen", Prefs.fullscreen, func(v: bool) -> void: Prefs.set_value("fullscreen", v)))
	col.add_child(_option_row("Resolution", _res_names(), _res_index(), func(i: int) -> void: Prefs.set_value("resolution", Prefs.RESOLUTIONS[i])))
	col.add_child(_option_row("Quality", Prefs.QUALITY_NAMES, Prefs.quality, func(i: int) -> void: Prefs.set_value("quality", i)))
	col.add_child(_check_row("Show FPS", Prefs.show_fps, func(v: bool) -> void: Prefs.set_value("show_fps", v)))
	col.add_child(UiKit.hsep())

	col.add_child(UiKit.label("CONTROLS", 13, Color(0.55, 0.75, 0.85)))
	col.add_child(_slider_row("Mouse sensitivity", (Prefs.sensitivity - 0.2) / 2.8, func(v: float) -> void: Prefs.set_value("sensitivity", 0.2 + v * 2.8)))
	col.add_child(_check_row("Invert Y", Prefs.invert_y, func(v: bool) -> void: Prefs.set_value("invert_y", v)))
	for action in Prefs.ACTIONS:
		col.add_child(_bind_row(action))
	var reset := UiKit.button("Reset bindings to default", 240, Cfg.C_AMBER)
	reset.pressed.connect(func() -> void: Prefs.reset_bindings(); _refresh_binds())
	col.add_child(reset)
	col.add_child(UiKit.hsep())

	var close := UiKit.button("Back", 200)
	close.pressed.connect(_on_close)
	col.add_child(close)

func _res_names() -> Array:
	var out: Array = []
	for r in Prefs.RESOLUTIONS:
		out.append("%d x %d" % [r.x, r.y])
	return out

func _res_index() -> int:
	var i := Prefs.RESOLUTIONS.find(Prefs.resolution)
	return maxi(i, 0)

func _slider_row(label_text: String, value01: float, on_change: Callable) -> Control:
	var row := UiKit.hbox(12)
	var lbl := UiKit.label(label_text, 15)
	lbl.custom_minimum_size = Vector2(200, 0)
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = clampf(value01, 0.0, 1.0)
	s.custom_minimum_size = Vector2(280, 0)
	s.value_changed.connect(func(v: float) -> void: on_change.call(v))
	row.add_child(s)
	return row

func _check_row(label_text: String, value: bool, on_change: Callable) -> Control:
	var row := UiKit.hbox(12)
	var lbl := UiKit.label(label_text, 15)
	lbl.custom_minimum_size = Vector2(200, 0)
	row.add_child(lbl)
	var c := CheckBox.new()
	c.button_pressed = value
	c.toggled.connect(func(v: bool) -> void: on_change.call(v))
	row.add_child(c)
	return row

func _option_row(label_text: String, options: Array, selected: int, on_change: Callable) -> Control:
	var row := UiKit.hbox(12)
	var lbl := UiKit.label(label_text, 15)
	lbl.custom_minimum_size = Vector2(200, 0)
	row.add_child(lbl)
	var o := OptionButton.new()
	for opt in options:
		o.add_item(String(opt))
	o.selected = selected
	o.custom_minimum_size = Vector2(200, 0)
	o.item_selected.connect(func(i: int) -> void: on_change.call(i))
	row.add_child(o)
	return row

func _bind_row(action: String) -> Control:
	var row := UiKit.hbox(12)
	var def: Dictionary = Prefs.ACTIONS[action]
	var lbl := UiKit.label(String(def["label"]), 15)
	lbl.custom_minimum_size = Vector2(200, 0)
	row.add_child(lbl)
	var b := UiKit.button(Prefs.binding_text(action), 180, Cfg.C_AMBER)
	b.pressed.connect(func() -> void: _start_listen(action, b))
	row.add_child(b)
	_bind_buttons[action] = b
	return row

func _start_listen(action: String, b: Button) -> void:
	_listening_action = action
	b.text = "Press a key..."

func _refresh_binds() -> void:
	for action in _bind_buttons:
		(_bind_buttons[action] as Button).text = Prefs.binding_text(action)

func _unhandled_input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			(_bind_buttons[_listening_action] as Button).text = Prefs.binding_text(_listening_action)
			_listening_action = ""
			get_viewport().set_input_as_handled()
			return
		Prefs.rebind(_listening_action, event)
		(_bind_buttons[_listening_action] as Button).text = Prefs.binding_text(_listening_action)
		_listening_action = ""
		get_viewport().set_input_as_handled()

func _on_close() -> void:
	Sfx.play("ui_back")
	closed.emit()
	queue_free()
