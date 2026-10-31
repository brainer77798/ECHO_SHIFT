class_name UiKit
extends RefCounted
## Shared factory for the sci-fi UI look: dark translucent panels with a neon border, glowing
## buttons, consistent typography. Everything is built from code (StyleBoxFlat / default font),
## so menus need no external art or font files.

const BG := Color(0.03, 0.045, 0.07, 0.86)
const BG_SOLID := Color(0.045, 0.06, 0.09, 1.0)

static func panel(accent: Color = Cfg.C_CYAN, bg := BG, border := 2.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border)
	sb.border_color = accent
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	return p

static func label(text: String, size := 18, color: Color = Cfg.C_WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

static func title(text: String, size := 40, color: Color = Cfg.C_CYAN) -> Label:
	var l := label(text, size, color)
	l.add_theme_constant_override("outline_size", 0)
	return l

static func button(text: String, min_w := 260, accent: Color = Cfg.C_CYAN) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	b.add_theme_font_size_override("font_size", 19)
	b.focus_mode = Control.FOCUS_ALL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.08, 0.12, 0.85)
	normal.set_border_width_all(2)
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent.r, accent.g, accent.b, 0.22)
	hover.border_color = accent
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent.r, accent.g, accent.b, 0.4)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.border_color = Color(0.3, 0.32, 0.36, 0.4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Cfg.C_WHITE)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.52, 0.56))
	b.mouse_entered.connect(func() -> void: if not b.disabled: Sfx.play("ui_hover", -8.0))
	return b

static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func hsep(color := Color(1, 1, 1, 0.12)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 2)
	return r

## A neon-filled status bar with a dark track. set_ratio()/set_fill_color() update it live.
static func make_bar(w: float, h: float, fill: Color = Cfg.C_CYAN) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(w, h)
	var track := ColorRect.new()
	track.color = Color(0.05, 0.06, 0.08, 0.85)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(track)
	var border := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.25)
	border.add_theme_stylebox_override("panel", sb)
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fillrect := ColorRect.new()
	fillrect.color = fill
	fillrect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fillrect.size = Vector2(w, h)
	root.add_child(fillrect)
	root.add_child(border)
	return {"root": root, "fill": fillrect, "w": w, "h": h}

static func bar_set_ratio(bar: Dictionary, r: float) -> void:
	(bar["fill"] as ColorRect).size = Vector2(float(bar["w"]) * clampf(r, 0.0, 1.0), float(bar["h"]))

static func bar_set_color(bar: Dictionary, c: Color) -> void:
	(bar["fill"] as ColorRect).color = c
