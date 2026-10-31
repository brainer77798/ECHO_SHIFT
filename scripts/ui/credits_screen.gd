class_name CreditsScreen
extends Control
## Scrollable credits text (Story.CREDITS), with a Back button.

signal closed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 560)
	center.add_child(scroll)
	var lbl := UiKit.label(Story.CREDITS, 16, Cfg.C_WHITE)
	lbl.custom_minimum_size = Vector2(500, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(lbl)
	var back := UiKit.button("Back", 200)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(30, -70)
	back.pressed.connect(func() -> void: Sfx.play("ui_back"); closed.emit())
	add_child(back)
