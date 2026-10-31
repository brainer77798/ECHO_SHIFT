class_name EndingScreen
extends Control
## Shown after the player chooses the Chrono Core's fate. Each of the three endings gets its own
## title, color, closing dialogue and epilogue text.

signal main_menu_pressed

func show_ending(kind: String) -> void:
	for c in get_children():
		c.queue_free()
	var entry: Dictionary = Story.ENDINGS.get(kind, {})
	var color: Color = entry.get("color", Cfg.C_CYAN)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UiKit.vbox(16)
	center.add_child(col)
	var tag := UiKit.label("ENDING", 14, Color(color.r, color.g, color.b, 0.75))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var title := UiKit.title(String(entry.get("title", "")), 46, color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UiKit.label(String(entry.get("subtitle", "")), 16, Color(0.8, 0.84, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(UiKit.hsep())
	var dlg_panel := UiKit.panel(color, UiKit.BG, 1)
	dlg_panel.custom_minimum_size = Vector2(620, 0)
	col.add_child(dlg_panel)
	var dcol := UiKit.vbox(6)
	dlg_panel.add_child(dcol)
	for beat in entry.get("lines", []):
		var speaker := String(beat[0])
		var line := String(beat[1])
		var row := UiKit.hbox(8)
		dcol.add_child(row)
		var sp := UiKit.label(speaker + ":", 14, Cfg.C_RED if speaker == "WARDEN" else Cfg.C_CYAN)
		sp.custom_minimum_size = Vector2(90, 0)
		row.add_child(sp)
		var tx := UiKit.label(line, 14, Cfg.C_WHITE)
		tx.custom_minimum_size = Vector2(500, 0)
		tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(tx)
	var epi := UiKit.label(String(entry.get("epilogue", "")), 15, Color(0.82, 0.85, 0.9))
	epi.custom_minimum_size = Vector2(620, 0)
	epi.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(epi)
	col.add_child(UiKit.hsep())
	var stats := UiKit.label("Deaths: %d    Kills: %d    Echoes made: %d    Evidence found: %d / %d" % [
		GameState.deaths, GameState.kills, GameState.echoes_made, GameState.logs.size(), Story.LOGS.size()], 13, Color(0.55, 0.6, 0.68))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stats)
	var menu_btn := UiKit.button("Return to Main Menu", 260, color)
	menu_btn.pressed.connect(func() -> void: Sfx.play("ui_click"); main_menu_pressed.emit())
	var brow := UiKit.hbox(10)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_child(menu_btn)
	col.add_child(brow)
	visible = true
	Sfx.stop_music(1.5)
	var sfx_name := "ending_" + kind
	if Sfx.has_sound(sfx_name):
		Sfx.play(sfx_name, -4.0)
