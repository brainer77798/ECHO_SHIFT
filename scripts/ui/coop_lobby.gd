class_name CoopLobby
extends Control
## Host/Join screen for LAN co-op. Host picks a port and waits for friends on the same network to
## join by IP; Join connects to a host's IP. Once connected, shows a live roster and (host only) a
## Start button. Internet matchmaking is explicitly out of scope - this is same-network only.

signal back_pressed
signal game_starting

var _status: Label
var _roster: Label
var _start_btn: Button
var _ip_field: LineEdit
var _port_field: LineEdit
var _mode := ""   # "", "host", "joined"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.035)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UiKit.panel(Cfg.C_CYAN, UiKit.BG_SOLID, 2)
	p.custom_minimum_size = Vector2(520, 0)
	center.add_child(p)
	var col := UiKit.vbox(12)
	p.add_child(col)
	col.add_child(UiKit.title("LAN CO-OP", 26))
	col.add_child(UiKit.label("Same local network only - no internet matchmaking.", 12, Color(0.55, 0.65, 0.72)))
	col.add_child(UiKit.hsep())

	var host_row := UiKit.hbox(10)
	col.add_child(host_row)
	_port_field = LineEdit.new()
	_port_field.text = str(Cfg.NET_PORT)
	_port_field.custom_minimum_size = Vector2(90, 40)
	host_row.add_child(UiKit.label("Port", 14))
	host_row.add_child(_port_field)
	var host_btn := UiKit.button("Host Game", 180, Cfg.C_GREEN)
	host_btn.pressed.connect(_on_host)
	host_row.add_child(host_btn)

	col.add_child(UiKit.hsep())
	var join_row := UiKit.hbox(10)
	col.add_child(join_row)
	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "Host IP, e.g. 192.168.1.5"
	_ip_field.custom_minimum_size = Vector2(220, 40)
	join_row.add_child(_ip_field)
	var join_btn := UiKit.button("Join", 120, Cfg.C_AMBER)
	join_btn.pressed.connect(_on_join)
	join_row.add_child(join_btn)

	col.add_child(UiKit.hsep())
	_status = UiKit.label("Not connected.", 14, Cfg.C_WHITE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(480, 0)
	col.add_child(_status)
	_roster = UiKit.label("", 13, Color(0.6, 0.85, 0.9))
	_roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_roster.custom_minimum_size = Vector2(480, 0)
	col.add_child(_roster)
	_start_btn = UiKit.button("Start Game", 220, Cfg.C_GREEN)
	_start_btn.visible = false
	_start_btn.pressed.connect(_on_start)
	col.add_child(_start_btn)

	var back := UiKit.button("Leave / Back", 220)
	back.pressed.connect(_on_back)
	col.add_child(back)

	Net.session_started.connect(_on_session_started)
	Net.connect_failed.connect(_on_connect_failed)
	Net.roster_changed.connect(_refresh_roster)
	Net.load_chapter_requested.connect(_on_game_starting)

func _on_host() -> void:
	var port := int(_port_field.text) if _port_field.text.is_valid_int() else Cfg.NET_PORT
	var err := Net.host(port)
	if err != "":
		_status.text = err
		Sfx.play("echo_fail")
		return
	_mode = "host"
	_status.text = "Hosting on port %d. Share your LAN IP with your friends." % port
	_start_btn.visible = true
	Sfx.play("ui_click")
	_refresh_roster()

func _on_join() -> void:
	var port := int(_port_field.text) if _port_field.text.is_valid_int() else Cfg.NET_PORT
	var err := Net.join(_ip_field.text, port)
	if err != "":
		_status.text = err
		Sfx.play("echo_fail")
		return
	_mode = "joined"
	_status.text = "Connecting to %s:%d ..." % [_ip_field.text, port]
	Sfx.play("ui_click")

func _on_session_started() -> void:
	if _mode == "joined":
		_status.text = "Connected. Waiting for the host to start the game."
	_refresh_roster()

func _on_connect_failed(reason: String) -> void:
	_status.text = reason
	Sfx.play("echo_fail")

func _refresh_roster() -> void:
	var names := []
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		names.append("%s%s" % [String(Net.players[id].get("name", "Operative")), "  (host)" if id == 1 else ""])
	_roster.text = "Party: " + ", ".join(names) if not names.is_empty() else ""

func _on_start() -> void:
	if not Net.is_host:
		return
	Sfx.play("ui_click")
	Net.start_new_session()

func _on_game_starting(_idx: int) -> void:
	game_starting.emit()

func _on_back() -> void:
	Net.leave()
	Sfx.play("ui_back")
	back_pressed.emit()
