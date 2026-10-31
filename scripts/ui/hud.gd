class_name Hud
extends CanvasLayer
## Always-on gameplay UI: vitals, objective, prompts, boss bar, dialogue subtitles, toasts, and the
## two blocking modals (terminal reader, upgrade bench). Lives for the whole play session (Main
## creates one on New Game / Continue) and listens to Bus the whole time, so it works no matter
## which chapter is currently loaded underneath it.

signal modal_opened
signal modal_closed

var _health_bar: Dictionary
var _heat_bar: Dictionary
var _dash_bar: Dictionary
var _health_label: Label
var _objective_label: Label
var _frag_label: Label
var _prompt_label: Label
var _boss_root: Control
var _boss_bar: Dictionary
var _boss_title: Label
var _boss_phase: Label
var _toast: Label
var _toast_tween: Tween
var _flash: ColorRect
var _echo_pips: Array = []
var _dialogue_label: Label
var _dialogue_speaker: Label
var _dialogue_root: Control
var _dialogue_queue: Array = []
var _dialogue_t := 0.0
var _terminal_modal: Control
var _terminal_body: Label
var _bench_modal: Control
var _bench_frag_label: Label
var _bench_rows: Dictionary = {}
var _modal_count := 0

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_vitals()
	_build_objective()
	_build_crosshair()
	_build_boss_bar()
	_build_toast()
	_build_flash()
	_build_dialogue()
	_build_terminal_modal()
	_build_upgrade_bench()
	Bus.player_health_changed.connect(_on_health)
	Bus.objective_changed.connect(func(t: String) -> void: _objective_label.text = t)
	Bus.fragments_changed.connect(func(n: int) -> void: _frag_label.text = "%04d" % n)
	Bus.interact_prompt.connect(func(t: String) -> void: _prompt_label.text = t; _prompt_label.visible = t != "")
	Bus.hud_message.connect(_on_toast)
	Bus.boss_bar.connect(_on_boss_bar)
	Bus.screen_flash.connect(_on_flash)
	Bus.dialogue_requested.connect(_on_dialogue)
	Bus.terminal_requested.connect(_on_terminal)
	Bus.upgrade_bench_requested.connect(_on_bench)
	Bus.player_died.connect(func(_p: Node) -> void: _prompt_label.visible = false)
	_frag_label.text = "%04d" % GameState.fragments

func any_modal_open() -> bool:
	return _modal_count > 0

func _process(delta: float) -> void:
	var p := GameState.local_player as Player
	if p != null and is_instance_valid(p):
		UiKit.bar_set_ratio(_heat_bar, p.weapon_heat_ratio())
		UiKit.bar_set_color(_heat_bar, Cfg.C_RED if p.overheated else Cfg.C_ORANGE)
		UiKit.bar_set_ratio(_dash_bar, p.dash_ready_ratio())
		var count := p.active_echo_count()
		var can_make := p.recorder.can_snapshot()
		for i in _echo_pips.size():
			var pip: Dictionary = _echo_pips[i]
			var active: bool = i < count
			var sb: StyleBoxFlat = (pip["panel"] as Panel).get_theme_stylebox("panel")
			sb.bg_color = Cfg.C_CYAN * Color(1, 1, 1, 0.85) if active else Color(0.08, 0.1, 0.13, 0.7)
			sb.border_color = Cfg.C_CYAN if (active or can_make) else Color(0.4, 0.42, 0.46, 0.5)
	_tick_dialogue(delta)

# --- Vitals: health / heat / dash / echo pips ----------------------------------------------------------

func _build_vitals() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.position = Vector2(26, -126)
	add_child(root)
	var col := UiKit.vbox(6)
	root.add_child(col)
	var hp_row := UiKit.hbox(10)
	col.add_child(hp_row)
	_health_bar = UiKit.make_bar(280, 22, Cfg.C_GREEN)
	hp_row.add_child(_health_bar["root"])
	_health_label = UiKit.label("100 / 100", 15, Cfg.C_WHITE)
	hp_row.add_child(_health_label)
	_heat_bar = UiKit.make_bar(280, 9, Cfg.C_ORANGE)
	col.add_child(_heat_bar["root"])
	var bottom_row := UiKit.hbox(14)
	col.add_child(bottom_row)
	var dash_wrap := UiKit.vbox(2)
	bottom_row.add_child(dash_wrap)
	dash_wrap.add_child(UiKit.label("DASH", 10, Color(0.6, 0.75, 0.85)))
	_dash_bar = UiKit.make_bar(90, 6, Cfg.C_BLUE)
	dash_wrap.add_child(_dash_bar["root"])
	var echo_wrap := UiKit.vbox(2)
	bottom_row.add_child(echo_wrap)
	echo_wrap.add_child(UiKit.label("ECHO", 10, Color(0.6, 0.85, 0.9)))
	var pip_row := UiKit.hbox(5)
	echo_wrap.add_child(pip_row)
	for i in Cfg.ECHO_MAX_ACTIVE:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(22, 22)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.1, 0.13, 0.7)
		sb.set_border_width_all(2)
		sb.border_color = Cfg.C_CYAN
		sb.set_corner_radius_all(3)
		p.add_theme_stylebox_override("panel", sb)
		pip_row.add_child(p)
		_echo_pips.append({"panel": p})
	# fragments, top-right
	var frag_root := Control.new()
	frag_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frag_root.position = Vector2(-170, 22)
	add_child(frag_root)
	var frag_box := UiKit.hbox(8)
	frag_root.add_child(frag_box)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(16, 16)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Cfg.C_CYAN
	csb.set_corner_radius_all(3)
	chip.add_theme_stylebox_override("panel", csb)
	frag_box.add_child(chip)
	_frag_label = UiKit.label("0000", 20, Cfg.C_CYAN)
	frag_box.add_child(_frag_label)

func _on_health(hp: float, max_hp: float) -> void:
	UiKit.bar_set_ratio(_health_bar, hp / maxf(max_hp, 1.0))
	UiKit.bar_set_color(_health_bar, Cfg.C_GREEN if hp > max_hp * 0.3 else Cfg.C_RED)
	_health_label.text = "%d / %d" % [int(ceil(hp)), int(max_hp)]

# --- Objective + interact prompt + crosshair --------------------------------------------------------------

func _build_objective() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(26, 22)
	add_child(root)
	var box := UiKit.vbox(2)
	root.add_child(box)
	box.add_child(UiKit.label("OBJECTIVE", 11, Color(0.5, 0.7, 0.8)))
	_objective_label = UiKit.label("", 17, Cfg.C_WHITE)
	_objective_label.custom_minimum_size = Vector2(460, 0)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_objective_label)
	_prompt_label = UiKit.label("", 19, Cfg.C_AMBER)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-220, -210)
	_prompt_label.custom_minimum_size = Vector2(440, 0)
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.visible = false
	add_child(_prompt_label)

func _build_crosshair() -> void:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	for d in [Vector2(-9, 0), Vector2(5, 0), Vector2(0, -9), Vector2(0, 5)]:
		var r := ColorRect.new()
		r.color = Color(Cfg.C_CYAN.r, Cfg.C_CYAN.g, Cfg.C_CYAN.b, 0.85)
		r.size = Vector2(4, 4) if d.x == 0 else Vector2(4, 4)
		r.position = d
		c.add_child(r)

# --- Boss bar ------------------------------------------------------------------------------------------------

func _build_boss_bar() -> void:
	_boss_root = Control.new()
	_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_root.position = Vector2(-280, 26)
	_boss_root.visible = false
	add_child(_boss_root)
	var col := UiKit.vbox(4)
	_boss_root.add_child(col)
	_boss_title = UiKit.title("WARDEN", 22, Cfg.C_RED)
	_boss_title.custom_minimum_size = Vector2(560, 0)
	_boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_boss_title)
	_boss_bar = UiKit.make_bar(560, 20, Cfg.C_RED)
	col.add_child(_boss_bar["root"])
	_boss_phase = UiKit.label("", 14, Cfg.C_AMBER)
	_boss_phase.custom_minimum_size = Vector2(560, 0)
	_boss_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_boss_phase)

func _on_boss_bar(visible_: bool, title_: String, ratio: float, phase_text: String) -> void:
	_boss_root.visible = visible_
	if visible_:
		_boss_title.text = title_
		UiKit.bar_set_ratio(_boss_bar, ratio)
		_boss_phase.text = phase_text

# --- Toasts + screen flash -----------------------------------------------------------------------------------

func _build_toast() -> void:
	_toast = UiKit.label("", 20, Cfg.C_WHITE)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-300, 90)
	_toast.custom_minimum_size = Vector2(600, 0)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	add_child(_toast)

func _on_toast(text: String, color: Color, duration: float) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_toast.modulate.a = 1.0
	_toast_tween.tween_interval(maxf(duration, 0.4))
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)

func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 0, 0, 0)
	add_child(_flash)

func _on_flash(color: Color, time: float) -> void:
	var tw := create_tween()
	_flash.color = Color(color.r, color.g, color.b, 0.35)
	tw.tween_property(_flash, "color:a", 0.0, maxf(time, 0.1))

# --- Dialogue subtitles (non-blocking) ------------------------------------------------------------------------

func _build_dialogue() -> void:
	_dialogue_root = Control.new()
	_dialogue_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue_root.position = Vector2(-190, -170)
	_dialogue_root.visible = false
	add_child(_dialogue_root)
	var p := UiKit.panel(Cfg.C_CYAN, UiKit.BG, 2)
	p.custom_minimum_size = Vector2(640, 0)
	_dialogue_root.add_child(p)
	var col := UiKit.vbox(4)
	p.add_child(col)
	_dialogue_speaker = UiKit.label("", 13, Cfg.C_CYAN)
	col.add_child(_dialogue_speaker)
	_dialogue_label = UiKit.label("", 18, Cfg.C_WHITE)
	_dialogue_label.custom_minimum_size = Vector2(610, 0)
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_dialogue_label)

func _on_dialogue(speaker: String, lines: Array, voice: String) -> void:
	for line in lines:
		_dialogue_queue.append({"speaker": speaker, "text": String(line), "voice": voice})

func _tick_dialogue(delta: float) -> void:
	if _dialogue_t > 0.0:
		_dialogue_t -= delta
		if _dialogue_t <= 0.0:
			_dialogue_root.visible = false
	if _dialogue_t <= 0.0 and not _dialogue_queue.is_empty():
		var d: Dictionary = _dialogue_queue.pop_front()
		_dialogue_speaker.text = String(d["speaker"])
		_dialogue_speaker.add_theme_color_override("font_color", Cfg.C_RED if String(d["voice"]) == "warden" else Cfg.C_CYAN)
		_dialogue_label.text = String(d["text"])
		_dialogue_root.visible = true
		_dialogue_t = maxf(2.6, String(d["text"]).length() * 0.045)
		Sfx.play("terminal", -10.0, 1.3 if String(d["voice"]) == "warden" else 1.0)

# --- Terminal modal (blocking) ----------------------------------------------------------------------------------

func _open_modal() -> void:
	_modal_count += 1
	if _modal_count == 1:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		modal_opened.emit()

func _close_modal() -> void:
	_modal_count = maxi(_modal_count - 1, 0)
	if _modal_count == 0:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		modal_closed.emit()

func _build_terminal_modal() -> void:
	_terminal_modal = Control.new()
	_terminal_modal.process_mode = Node.PROCESS_MODE_ALWAYS
	_terminal_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terminal_modal.visible = false
	add_child(_terminal_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terminal_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terminal_modal.add_child(center)
	var p := UiKit.panel(Cfg.C_CYAN, UiKit.BG_SOLID, 2)
	p.custom_minimum_size = Vector2(760, 0)
	center.add_child(p)
	var col := UiKit.vbox(10)
	p.add_child(col)
	var head := UiKit.hbox(14)
	col.add_child(head)
	var title_col := UiKit.vbox(2)
	head.add_child(title_col)
	var t_title := UiKit.title("", 22, Cfg.C_CYAN)
	t_title.name = "Title"
	title_col.add_child(t_title)
	var t_meta := UiKit.label("", 13, Color(0.6, 0.7, 0.78))
	t_meta.name = "Meta"
	title_col.add_child(t_meta)
	col.add_child(UiKit.hsep())
	_terminal_body = UiKit.label("", 16, Cfg.C_WHITE)
	_terminal_body.custom_minimum_size = Vector2(720, 0)
	_terminal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 340)
	scroll.add_child(_terminal_body)
	col.add_child(scroll)
	var reward_label := UiKit.label("", 15, Cfg.C_GREEN)
	reward_label.name = "Reward"
	col.add_child(reward_label)
	var close := UiKit.button("Close  [%s]" % Prefs.binding_text("interact"))
	close.pressed.connect(_close_terminal)
	col.add_child(close)
	_terminal_modal.set_meta("title", t_title)
	_terminal_modal.set_meta("meta", t_meta)
	_terminal_modal.set_meta("reward", reward_label)
	_terminal_modal.set_meta("close_btn", close)

func _on_terminal(entry: Dictionary) -> void:
	(_terminal_modal.get_meta("title") as Label).text = String(entry.get("title", "LOG"))
	(_terminal_modal.get_meta("meta") as Label).text = "%s   -   %s" % [String(entry.get("author", "")), String(entry.get("time", ""))]
	_terminal_body.text = String(entry.get("text", ""))
	var reward := int(entry.get("reward", 0))
	var rl := _terminal_modal.get_meta("reward") as Label
	rl.text = ("+%d data fragments collected" % reward) if reward > 0 else ""
	_terminal_modal.visible = true
	(_terminal_modal.get_meta("close_btn") as Button).grab_focus()
	_open_modal()

func _close_terminal() -> void:
	_terminal_modal.visible = false
	Sfx.play("ui_back")
	_close_modal()

func _unhandled_input(event: InputEvent) -> void:
	if _terminal_modal.visible and event.is_action_pressed("interact"):
		_close_terminal()
		get_viewport().set_input_as_handled()

## Closes whichever HUD modal is open. Main calls this for the "pause" key so there is a single
## place deciding whether Escape closes a modal or opens the pause menu (no ordering races).
func close_top_modal() -> void:
	if _terminal_modal.visible:
		_close_terminal()
	elif _bench_modal.visible:
		_close_bench()

# --- Upgrade bench modal (blocking) -----------------------------------------------------------------------------

func _build_upgrade_bench() -> void:
	_bench_modal = Control.new()
	_bench_modal.process_mode = Node.PROCESS_MODE_ALWAYS
	_bench_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bench_modal.visible = false
	add_child(_bench_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bench_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bench_modal.add_child(center)
	var p := UiKit.panel(Cfg.C_GREEN, UiKit.BG_SOLID, 2)
	p.custom_minimum_size = Vector2(720, 0)
	center.add_child(p)
	var col := UiKit.vbox(10)
	p.add_child(col)
	var head := UiKit.hbox(14)
	col.add_child(head)
	head.add_child(UiKit.title("RECOVERY NODE", 24, Cfg.C_GREEN))
	_bench_frag_label = UiKit.label("0000 fragments", 17, Cfg.C_CYAN)
	head.add_child(_bench_frag_label)
	col.add_child(UiKit.hsep())
	for id in Cfg.UPGRADES:
		col.add_child(_build_upgrade_row(id))
	var close := UiKit.button("Done", 200, Cfg.C_GREEN)
	close.pressed.connect(_close_bench)
	col.add_child(close)

func _build_upgrade_row(id: String) -> Control:
	var def: Dictionary = Cfg.UPGRADES[id]
	var row := UiKit.hbox(14)
	var info := UiKit.vbox(2)
	info.custom_minimum_size = Vector2(340, 0)
	info.add_child(UiKit.label(String(def["name"]), 17, Cfg.C_WHITE))
	info.add_child(UiKit.label(String(def["desc"]), 12, Color(0.65, 0.68, 0.74)))
	row.add_child(info)
	var pips := UiKit.hbox(4)
	for i in int(def["max"]):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(16, 16)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(2)
		sb.set_border_width_all(1)
		sb.border_color = Cfg.C_GREEN
		pip.add_theme_stylebox_override("panel", sb)
		pips.add_child(pip)
	row.add_child(pips)
	var buy := UiKit.button("BUY", 120, Cfg.C_GREEN)
	buy.pressed.connect(func() -> void: _buy(id))
	row.add_child(buy)
	_bench_rows[id] = {"pips": pips, "buy": buy}
	return row

func _refresh_bench() -> void:
	_bench_frag_label.text = "%d fragments" % GameState.fragments
	for id in _bench_rows:
		var r: Dictionary = _bench_rows[id]
		var lvl := GameState.upgrade_level(id)
		var pips: HBoxContainer = r["pips"]
		for i in pips.get_child_count():
			var pip := pips.get_child(i) as Panel
			var sb := pip.get_theme_stylebox("panel") as StyleBoxFlat
			sb.bg_color = Cfg.C_GREEN if i < lvl else Color(0.08, 0.1, 0.1, 0.6)
		var cost := GameState.upgrade_cost(id)
		var buy: Button = r["buy"]
		if cost < 0:
			buy.text = "MAX"
			buy.disabled = true
		else:
			buy.text = "BUY (%d)" % cost
			buy.disabled = GameState.fragments < cost

func _buy(id: String) -> void:
	if GameState.buy_upgrade(id):
		Sfx.play("pickup")
		var p := GameState.local_player as Player
		if p != null:
			p.refresh_stats(false)
		_refresh_bench()
	else:
		Sfx.play("echo_fail")

func _on_bench() -> void:
	_refresh_bench()
	_bench_modal.visible = true
	_open_modal()

func _close_bench() -> void:
	_bench_modal.visible = false
	Sfx.play("ui_back")
	_close_modal()
