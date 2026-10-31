class_name ConfirmBox
extends Control
## Tiny Yes/No confirmation overlay, used wherever a destructive menu action needs one extra step.

signal confirmed
signal cancelled

var text := "Are you sure?"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UiKit.panel(Cfg.C_RED, UiKit.BG_SOLID, 2)
	p.custom_minimum_size = Vector2(420, 0)
	center.add_child(p)
	var col := UiKit.vbox(16)
	p.add_child(col)
	var lbl := UiKit.label(text, 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(380, 0)
	col.add_child(lbl)
	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var yes := UiKit.button("Yes", 150, Cfg.C_RED)
	yes.pressed.connect(func() -> void: confirmed.emit(); queue_free())
	row.add_child(yes)
	var no := UiKit.button("Cancel", 150)
	no.pressed.connect(func() -> void: cancelled.emit(); queue_free())
	row.add_child(no)
	no.grab_focus()
