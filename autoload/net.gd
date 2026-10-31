extends Node
## LAN co-op networking: ENet host/join, player roster, and the RPCs that keep chapter loading and
## puzzle/enemy state in sync. Entirely inert outside a session (Net.active == false), so none of
## this touches single-player behaviour - every call site in gameplay code guards on Net.active
## first. The host is authoritative: it runs the real simulation (AI, puzzle channels, encounters)
## and broadcasts the results; clients render replicated state and drive only their own avatar.

signal session_started
signal session_ended(reason: String)
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal connect_failed(reason: String)
signal roster_changed
signal load_chapter_requested(index: int)

const DEFAULT_PORT := Cfg.NET_PORT
const MAX_PLAYERS := Cfg.NET_MAX_PLAYERS
const TINTS := [Cfg.C_CYAN, Cfg.C_GREEN, Cfg.C_AMBER, Cfg.C_VIOLET]

var active := false
var is_host := false
var implemented := true    # LAN co-op is wired up; see MainMenu's "LAN Co-op" button gate
var players: Dictionary = {}     # peer_id -> {"name": String}
var local_name := "Operative"
var last_error := ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func is_online() -> bool:
	return active

func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1

func tint_for(peer_id: int) -> Color:
	var ids := players.keys()
	ids.sort()
	var idx := ids.find(peer_id)
	return TINTS[maxi(idx, 0) % TINTS.size()]

# --- Session lifecycle -----------------------------------------------------------------------------

func host(port := DEFAULT_PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		last_error = "Could not host on port %d (%s)" % [port, error_string(err)]
		return last_error
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	players.clear()
	players[1] = {"name": local_name}
	session_started.emit()
	roster_changed.emit()
	return ""

func join(ip: String, port := DEFAULT_PORT) -> String:
	leave()
	if ip.strip_edges() == "":
		return "Enter a host IP address"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port)
	if err != OK:
		last_error = "Could not connect to %s:%d (%s)" % [ip, port, error_string(err)]
		return last_error
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	return ""

func leave(reason := "") -> void:
	var was_active := active
	active = false
	is_host = false
	players.clear()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if was_active:
		session_ended.emit(reason)

func _on_peer_connected(id: int) -> void:
	if is_host:
		players[id] = {"name": "Operative %d" % id}
		_rpc_sync_roster.rpc(players)
	player_joined.emit(id)
	roster_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_left.emit(id)
	roster_changed.emit()
	if is_host:
		_rpc_sync_roster.rpc(players)

func _on_connected_ok() -> void:
	session_started.emit()

func _on_connect_failed() -> void:
	last_error = "Could not reach the host"
	active = false
	connect_failed.emit(last_error)

func _on_server_disconnected() -> void:
	leave("Host disconnected")

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_roster(roster: Dictionary) -> void:
	players = roster
	roster_changed.emit()

# --- Chapter sync (host decides when the party moves on) -----------------------------------------------

## Host-only: begins a fresh co-op campaign. Every peer (itself included) starts a new local
## GameState in lockstep, then the host sends everyone into chapter 1 together.
func start_new_session() -> void:
	if not active or not is_host:
		return
	_rpc_new_game.rpc()
	broadcast_chapter(1)

@rpc("authority", "call_local", "reliable")
func _rpc_new_game() -> void:
	GameState.new_game()

## Host calls this to make every peer (itself included) load the same chapter together.
func broadcast_chapter(index: int) -> void:
	if not active or not is_host:
		return
	_rpc_load_chapter.rpc(index)

@rpc("authority", "call_local", "reliable")
func _rpc_load_chapter(index: int) -> void:
	load_chapter_requested.emit(index)

# --- Live gameplay state replication -----------------------------------------------------------------------
# The host runs the real simulation (enemy AI, puzzle channels, encounters - unchanged single-player
# code) and broadcasts a snapshot at a modest rate; clients apply it directly and never simulate
# enemies or puzzle logic themselves. Player avatars are the exception: each peer always drives its
# own avatar locally for responsiveness, and that peer's state is folded into the same broadcast.

var _level: LevelBase
var _players_by_peer: Dictionary = {}     # peer_id -> Player
var _broadcast_t := 0.0
const BROADCAST_RATE := 0.08   # ~12 Hz - plenty for a LAN co-op snapshot, not a competitive shooter

func register_level(level: LevelBase) -> void:
	_level = level
	_players_by_peer.clear()
	_broadcast_t = 0.0

func unregister_level(level: LevelBase) -> void:
	if _level == level:
		_level = null
		_players_by_peer.clear()

func register_player(peer_id: int, p: Player) -> void:
	_players_by_peer[peer_id] = p

func _physics_process(delta: float) -> void:
	if not active or _level == null or not is_host:
		return
	_broadcast_t -= delta
	if _broadcast_t <= 0.0:
		_broadcast_t = BROADCAST_RATE
		_host_broadcast_state()

func _host_broadcast_state() -> void:
	var pstate := {}
	for peer_id in _players_by_peer:
		var p: Player = _players_by_peer[peer_id]
		if is_instance_valid(p):
			pstate[peer_id] = [p.global_position, p.rotation.y, p.aim_direction(), p.health, p.dead]
	var estate := []
	for e in _level.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e is Enemy and _level.is_ancestor_of(e):
			var en := e as Enemy
			estate.append([_level.get_path_to(en), en.global_position, en.rotation.y, en.health, en.max_health, int(en.state), en.shield_hp])
	_rpc_state.rpc(pstate, estate, _level.channels.duplicate())

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_state(pstate: Dictionary, estate: Array, chan: Dictionary) -> void:
	if _level == null:
		return
	for peer_id in pstate:
		if _players_by_peer.has(peer_id):
			var p: Player = _players_by_peer[peer_id]
			var d: Array = pstate[peer_id]
			if is_instance_valid(p) and not p.is_local:
				p.apply_net_state(d[0], d[1], d[2], d[3], d[4])
	for row in estate:
		var node := _level.get_node_or_null(row[0])
		if node != null and node is Enemy:
			(node as Enemy).apply_net_puppet(row[1], row[2], row[3], row[4], int(row[5]), row[6])
	for id in chan:
		if _level.channels.get(id, false) != chan[id]:
			_level.channels[id] = chan[id]
			_level.channel_changed.emit(id, chan[id])

## Each client reports its own avatar's state to the host at BROADCAST_RATE; the host folds it
## straight into its copy of that player (and into the next consolidated broadcast). No-op on the
## host itself, which already reads its own local player directly.
func report_my_state(pos: Vector3, yaw: float, aim: Vector3, hp: float, p_dead: bool) -> void:
	if not active or is_host:
		return
	_rpc_report_player_state.rpc_id(1, pos, yaw, aim, hp, p_dead)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_report_player_state(pos: Vector3, yaw: float, aim: Vector3, hp: float, p_dead: bool) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var p: Player = _players_by_peer.get(sender)
	if is_instance_valid(p):
		p.apply_net_state(pos, yaw, aim, hp, p_dead)

## Broadcasts a just-created Echo's recording to every other peer so they see it play out too.
func broadcast_echo(owner_peer: int, rec_dict: Dictionary, damage: float, linger: float, tint: Color) -> void:
	if not active:
		return
	_rpc_spawn_echo.rpc(owner_peer, rec_dict, damage, linger, tint)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_echo(owner_peer: int, rec_dict: Dictionary, damage: float, linger: float, tint: Color) -> void:
	if _level == null:
		return
	var owner: Player = _players_by_peer.get(owner_peer)
	if owner == null or owner.is_local:
		return   # it's our own echo, already created locally
	var rec := EchoRecording.from_dict(rec_dict)
	if not rec.is_valid():
		return
	var e := Echo.create(rec, owner, damage, linger, tint)
	Fx.world().add_child(e)

## A client that locally detects a hit on a (puppeted) enemy reports it instead of applying damage
## itself, since the host owns enemy health. No-op in single-player or on the host.
func report_hit(enemy_path_in_level: NodePath, info: DamageInfo) -> void:
	if not active or is_host:
		return
	_rpc_report_hit.rpc_id(1, enemy_path_in_level, info.amount, info.from_echo, info.point, info.direction, info.knockback)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_hit(enemy_path: NodePath, amount: float, from_echo: bool, point: Vector3, direction: Vector3, knockback: float) -> void:
	if not is_host or _level == null:
		return
	var node := _level.get_node_or_null(enemy_path)
	if node == null or not (node is Enemy):
		return
	var info := DamageInfo.new()
	info.amount = amount
	info.team = Cfg.TEAM_PLAYER
	info.from_echo = from_echo
	info.point = point
	info.direction = direction
	info.knockback = knockback
	(node as Enemy).take_damage(info)
