extends Node
## Real two-process LAN co-op test: client side. Joins 127.0.0.1, waits for the host to start the
## game, and reports what it sees once both players exist in the loaded level.
##   godot --headless --path . res://tests/net_client.tscn

var _t := 0.0
var _reported := false
var _connected := false

func _ready() -> void:
	print("CLIENT: connecting to 127.0.0.1:%d ..." % Cfg.NET_PORT)
	Net.load_chapter_requested.connect(_on_load_chapter)
	var err := Net.join("127.0.0.1", Cfg.NET_PORT)
	if err != "":
		print("CLIENT ERROR: ", err)
		get_tree().quit(1)
		return
	Net.session_started.connect(func() -> void:
		_connected = true
		print("CLIENT: connected! my_id=", Net.my_id()))
	Net.connect_failed.connect(func(reason: String) -> void:
		print("CLIENT: connect failed - ", reason)
		get_tree().quit(1))

func _on_load_chapter(idx: int) -> void:
	print("CLIENT: load_chapter_requested(%d) - loading..." % idx)
	GameState.chapter = idx
	var scene: PackedScene = load(String(Cfg.CHAPTERS[idx - 1]["scene"]))
	add_child(scene.instantiate())

func _process(delta: float) -> void:
	_t += delta
	if not _reported and Net._level != null:
		_reported = true
		await get_tree().create_timer(1.5).timeout
		var plist := Net._level.get_tree().get_nodes_in_group("players")
		print("CLIENT: chapter loaded, players in level = ", plist.size())
		for p in plist:
			print("  CLIENT sees player peer=%d is_local=%s pos=%s hp=%s" % [p.peer_id, p.is_local, p.global_position, p.health])
		print("CLIENT RESULT: %s" % ("OK" if plist.size() == 2 else "FAIL - expected 2 players"))
		get_tree().quit(0 if plist.size() == 2 else 1)
	if _t > 25.0:
		print("CLIENT: timeout (connected=%s)" % _connected)
		get_tree().quit(1)
