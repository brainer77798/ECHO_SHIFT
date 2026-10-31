extends Node
## Real two-process LAN co-op test: host side. Hosts, waits for a client, starts a co-op game,
## and reports what it sees once both players exist in the loaded level.
##   godot --headless --path . res://tests/net_host.tscn

var _t := 0.0
var _started := false
var _reported := false

func _ready() -> void:
	print("HOST: starting...")
	Net.load_chapter_requested.connect(_on_load_chapter)
	var err := Net.host(Cfg.NET_PORT)
	if err != "":
		print("HOST ERROR: ", err)
		get_tree().quit(1)
		return
	print("HOST: listening on port %d, my_id=%d" % [Cfg.NET_PORT, Net.my_id()])

func _on_load_chapter(idx: int) -> void:
	print("HOST: load_chapter_requested(%d) - loading..." % idx)
	GameState.chapter = idx
	var scene: PackedScene = load(String(Cfg.CHAPTERS[idx - 1]["scene"]))
	add_child(scene.instantiate())

func _process(delta: float) -> void:
	_t += delta
	if not _started and Net.players.size() >= 2:
		print("HOST: client connected! roster=", Net.players)
		_started = true
		Net.start_new_session()
	if _started and not _reported and Net._level != null:
		_reported = true
		await get_tree().create_timer(1.5).timeout
		var plist := Net._level.get_tree().get_nodes_in_group("players")
		print("HOST: chapter loaded, players in level = ", plist.size())
		for p in plist:
			print("  HOST sees player peer=%d is_local=%s pos=%s hp=%s" % [p.peer_id, p.is_local, p.global_position, p.health])
		print("HOST: enemies in level = ", Net._level.get_tree().get_nodes_in_group("enemies").size())
		print("HOST RESULT: %s" % ("OK" if plist.size() == 2 else "FAIL - expected 2 players"))
		get_tree().quit(0 if plist.size() == 2 else 1)
	if _t > 25.0:
		print("HOST: timeout waiting for client / level")
		get_tree().quit(1)
