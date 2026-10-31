extends Node
## Player preferences: audio volumes, display, mouse sensitivity, quality and key bindings.
## Persisted to user://settings.cfg. Also owns the InputMap registration so controls
## are defined in one place (keyboard/mouse defaults plus controller support).

signal changed

const PATH := "user://settings.cfg"

## Rebindable actions: label + default input (kind "key" or "mouse").
const ACTIONS := {
	"move_forward": {"label": "Move Forward", "kind": "key", "code": KEY_W},
	"move_back": {"label": "Move Back", "kind": "key", "code": KEY_S},
	"move_left": {"label": "Move Left", "kind": "key", "code": KEY_A},
	"move_right": {"label": "Move Right", "kind": "key", "code": KEY_D},
	"fire": {"label": "Fire Blaster", "kind": "mouse", "code": MOUSE_BUTTON_LEFT},
	"echo": {"label": "Create Echo", "kind": "key", "code": KEY_E},
	"dash": {"label": "Dash / Dodge", "kind": "key", "code": KEY_SPACE},
	"interact": {"label": "Interact", "kind": "key", "code": KEY_F},
	"pause": {"label": "Pause / Menu", "kind": "key", "code": KEY_ESCAPE},
}

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const QUALITY_NAMES := ["Low", "Medium", "High"]

var master := 0.8
var music := 0.6
var sfx := 0.9
var fullscreen := false
var resolution := Vector2i(1280, 720)
var sensitivity := 1.0
var invert_y := false
var quality := 1
var show_fps := false
var bindings: Dictionary = {}   # action -> {"kind": String, "code": int}

func _ready() -> void:
	_ensure_buses()
	load_settings()
	register_actions()
	apply_all()

# --- Persistence ---------------------------------------------------------------------

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master = clampf(float(cf.get_value("audio", "master", master)), 0.0, 1.0)
	music = clampf(float(cf.get_value("audio", "music", music)), 0.0, 1.0)
	sfx = clampf(float(cf.get_value("audio", "sfx", sfx)), 0.0, 1.0)
	fullscreen = bool(cf.get_value("display", "fullscreen", fullscreen))
	var res: Variant = cf.get_value("display", "resolution", resolution)
	if res is Vector2i and res.x >= 640 and res.y >= 360:
		resolution = res
	quality = clampi(int(cf.get_value("display", "quality", quality)), 0, 2)
	show_fps = bool(cf.get_value("display", "show_fps", show_fps))
	sensitivity = clampf(float(cf.get_value("controls", "sensitivity", sensitivity)), 0.2, 3.0)
	invert_y = bool(cf.get_value("controls", "invert_y", invert_y))
	var b: Variant = cf.get_value("controls", "bindings", {})
	if b is Dictionary:
		for action in b:
			if ACTIONS.has(action) and b[action] is Dictionary:
				var kind := str(b[action].get("kind", ""))
				var code := int(b[action].get("code", 0))
				if (kind == "key" or kind == "mouse") and code > 0:
					bindings[action] = {"kind": kind, "code": code}

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "music", music)
	cf.set_value("audio", "sfx", sfx)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "resolution", resolution)
	cf.set_value("display", "quality", quality)
	cf.set_value("display", "show_fps", show_fps)
	cf.set_value("controls", "sensitivity", sensitivity)
	cf.set_value("controls", "invert_y", invert_y)
	cf.set_value("controls", "bindings", bindings)
	cf.save(PATH)

# --- Applying settings -------------------------------------------------------------------

func apply_all() -> void:
	apply_audio()
	apply_display()
	changed.emit()

func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func _set_bus_linear(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))

func apply_audio() -> void:
	_set_bus_linear("Master", master)
	_set_bus_linear("Music", music)
	_set_bus_linear("SFX", sfx)

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)
		var screen := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen - resolution) / 2)
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X][quality]
	get_viewport().scaling_3d_scale = 1.0

func set_value(key: String, v: Variant) -> void:
	set(key, v)
	apply_all()
	save_settings()

# --- Input map -------------------------------------------------------------------------------

func register_actions() -> void:
	for action in ACTIONS:
		_ensure_action(action)
		_apply_binding(action)
	_ensure_action("look_left")
	_ensure_action("look_right")
	_ensure_action("look_up")
	_ensure_action("look_down")
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_button("fire", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("dash", JOY_BUTTON_A)
	_add_joy_button("echo", JOY_BUTTON_X)
	_add_joy_button("interact", JOY_BUTTON_Y)
	_add_joy_button("pause", JOY_BUTTON_START)

func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)

func _add_joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and ev.axis == axis and signf(ev.axis_value) == signf(value):
			return
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)

func _add_joy_button(action: String, button: JoyButton) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)

## Replace keyboard/mouse events of an action with the current binding (joypad events untouched).
func _apply_binding(action: String) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			InputMap.action_erase_event(action, ev)
	var b: Dictionary = bindings.get(action, ACTIONS[action])
	if b["kind"] == "key":
		var k := InputEventKey.new()
		k.physical_keycode = int(b["code"]) as Key
		InputMap.action_add_event(action, k)
	else:
		var m := InputEventMouseButton.new()
		m.button_index = int(b["code"]) as MouseButton
		InputMap.action_add_event(action, m)

func rebind(action: String, event: InputEvent) -> bool:
	if not ACTIONS.has(action):
		return false
	if event is InputEventKey and event.pressed:
		bindings[action] = {"kind": "key", "code": int(event.physical_keycode)}
	elif event is InputEventMouseButton and event.pressed:
		bindings[action] = {"kind": "mouse", "code": int(event.button_index)}
	else:
		return false
	_apply_binding(action)
	save_settings()
	changed.emit()
	return true

func reset_bindings() -> void:
	bindings.clear()
	for action in ACTIONS:
		_apply_binding(action)
	save_settings()
	changed.emit()

func binding_text(action: String) -> String:
	var b: Dictionary = bindings.get(action, ACTIONS[action])
	if b["kind"] == "key":
		var key := int(b["code"]) as Key
		# the headless display server (automated tests) can't resolve a physical->localized
		# keycode; fall back to the raw keycode name rather than spamming engine errors.
		if DisplayServer.get_name() == "headless":
			return OS.get_keycode_string(key)
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(key))
	match int(b["code"]):
		MOUSE_BUTTON_LEFT: return "Mouse Left"
		MOUSE_BUTTON_RIGHT: return "Mouse Right"
		MOUSE_BUTTON_MIDDLE: return "Mouse Middle"
		_: return "Mouse %d" % int(b["code"])
