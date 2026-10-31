class_name LevelBase
extends Node3D
## Base class of every chapter. A chapter supplies an ASCII floor plan (2 m cells) and a theme, then
## places its content with the add_* helpers. The base class turns the plan into merged collision
## geometry with trims, ceilings and lamps, builds the NavGrid, runs the logic channels that link
## switches / plates / doors / hazards, and manages encounters, alarms, objectives and completion.
##
## Map legend
##   #  wall                 (space) void             .  main floor   ,  corridor floor   :  lab floor
##   o  tall crate stack     O  low barrier           p  pillar       r  server rack      n  tank
##   any other character is a marker for the chapter script (floor underneath); see add_* helpers.
##   Lower-case entity letters conventionally mean enemies / props, digits mean doors, capitals devices.

signal channel_changed(id: String, on: bool)
signal completed

const T := 2.0                         # tile size (metres)
const H := 5.0                         # wall height
const PROP_CHARS := "oOprn"
const SOLID_MARKERS := "sTUVW"         # marker cells that are floor but not walkable (sentry, terminals)

var nav: NavGrid
var channels: Dictionary = {}
var player: Player
var exit_gate: ExitTrigger
var entities: Node3D
var objective_text := ""
var th: Dictionary = {}

var rows: PackedStringArray = PackedStringArray()
var grid_w := 0
var grid_h := 0
var marks: Dictionary = {}             # String -> Array[Vector2i]
var doors: Dictionary = {}
var checkpoints: Dictionary = {}
var devices: Dictionary = {}
var cameras: Array = []
var rng := RandomNumberGenerator.new()

var _floor_type: Array = []            # [y][x] -> int (0 none, 1 main, 2 corridor, 3 lab)
var _solid: Array = []                 # [y][x] -> bool (wall / void)
var _prop: Array = []                  # [y][x] -> String prop char or ""
var music_locked := false              # the boss fight owns the music track
var _completed := false
var _encounters: Dictionary = {}
var _wave_alive: Dictionary = {}
var _alarm_spawns: Array = []
var _combat_t := 0.0
var _in_combat := false
var _alarm_cd := 0.0
var _env: Environment

# --- Overridable by chapters ------------------------------------------------------------------------

func chapter() -> int:
	return 1

func map_rows() -> PackedStringArray:
	return PackedStringArray()

func theme() -> Dictionary:
	return {}

func build_content() -> void:
	pass

## Override to false for a chapter that ends some other way (e.g. a boss/ending flow) instead of
## a walk-to-exit gate, so validate() doesn't flag it as missing one.
func needs_exit_gate() -> bool:
	return true

func start_yaw() -> float:
	return 0.0

func after_player_spawned() -> void:
	pass

func level_process(_delta: float) -> void:
	pass

# --- Setup --------------------------------------------------------------------------------------------

func flag_key(key: String) -> String:
	return "c%d_%s" % [chapter(), key]

func _default_theme() -> Dictionary:
	return {
		"wall_style": "plates", "wall_color": Color(0.20, 0.23, 0.28), "wall_accent": Cfg.C_CYAN,
		"floor_style": "tiles", "floor_color": Color(0.17, 0.19, 0.23),
		"floor2_style": "grate", "floor2_color": Color(0.15, 0.17, 0.2),
		"floor3_style": "circuit", "floor3_color": Color(0.14, 0.18, 0.22),
		"accent": Cfg.C_CYAN, "accent2": Cfg.C_BLUE,
		"ambient": Color(0.20, 0.30, 0.45), "ambient_energy": 0.8,
		"fog": Color(0.04, 0.07, 0.12), "fog_density": 0.012,
		"lamp": Color(0.75, 0.88, 1.0), "lamp_energy": 1.1, "lamp_spacing": 5,
		"sky": Color(0.01, 0.015, 0.03), "ceiling": true, "music": "explore",
		"crate": Color(0.24, 0.27, 0.31), "name": "FACILITY",
	}

func _ready() -> void:
	rng.seed = 1189 + chapter() * 31
	th = _default_theme()
	th.merge(theme(), true)
	Fx.reset()
	Fx.root = self
	Projectile.live = 0
	Pickup.live = 0
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)
	if Net.active:
		Net.register_level(self)
	_parse_map()
	_build_nav()
	_build_geometry()
	_setup_environment()
	build_content()
	_auto_lights()
	_spawn_player()
	after_player_spawned()
	Bus.objective_changed.emit(objective_text)
	Sfx.play_music(String(th["music"]))
	Sfx.set_ambient("ambient")
	Bus.level_ready.emit()

func _exit_tree() -> void:
	if Net.active:
		Net.unregister_level(self)
	Fx.reset()
	Bus.interact_prompt.emit("")

func _physics_process(delta: float) -> void:
	_alarm_cd = maxf(_alarm_cd - delta, 0.0)
	_combat_t -= delta
	if _combat_t <= 0.0:
		_combat_t = 0.5
		_update_combat_music()
	level_process(delta)

func _update_combat_music() -> void:
	var fighting := false
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e.state in [Enemy.State.CHASE, Enemy.State.WINDUP, Enemy.State.ATTACK] and e.has_target():
			fighting = true
			break
	if fighting != _in_combat:
		_in_combat = fighting
		if music_locked:
			return
		Sfx.play_music("combat" if fighting else String(th["music"]), 1.2)

# --- Map parsing --------------------------------------------------------------------------------------

func _parse_map() -> void:
	rows = map_rows()
	grid_h = rows.size()
	grid_w = 0
	for r in rows:
		grid_w = maxi(grid_w, r.length())
	_floor_type = []
	_solid = []
	_prop = []
	marks = {}
	for y in grid_h:
		var ft: Array = []
		var sd: Array = []
		var pr: Array = []
		for x in grid_w:
			var ch := _char_at(x, y)
			var t := 0
			var solid := false
			var prop := ""
			match ch:
				"#", " ":
					solid = true
				".":
					t = 1
				",":
					t = 2
				":":
					t = 3
				_:
					if PROP_CHARS.contains(ch):
						t = 1
						prop = ch
					else:
						t = 1
						if not marks.has(ch):
							marks[ch] = []
						(marks[ch] as Array).append(Vector2i(x, y))
			ft.append(t)
			sd.append(solid)
			pr.append(prop)
		_floor_type.append(ft)
		_solid.append(sd)
		_prop.append(pr)
	# marker cells inherit the floor style of a neighbouring plain floor cell
	for ch in marks:
		for c in marks[ch]:
			var v := Vector2i(c)
			for off in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var n: Vector2i = v + off
				if _in_grid(n) and _char_at(n.x, n.y) in [".", ",", ":"]:
					_floor_type[v.y][v.x] = {".": 1, ",": 2, ":": 3}[_char_at(n.x, n.y)]
					break

func _char_at(x: int, y: int) -> String:
	if y < 0 or y >= rows.size():
		return " "
	var r := rows[y]
	if x < 0 or x >= r.length():
		return " "
	return r.substr(x, 1)

func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid_w and c.y < grid_h

func is_solid_cell(c: Vector2i) -> bool:
	return not _in_grid(c) or _solid[c.y][c.x]

func cell_pos(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3((c.x + 0.5) * T, y, (c.y + 0.5) * T)

func cells_of(ch: String) -> Array:
	return marks.get(ch, [])

## Connected groups of a marker character as rectangles (cell units), in reading order.
func regions(ch: String) -> Array:
	var cells: Array = cells_of(ch)
	var seen := {}
	var out: Array = []
	for c in cells:
		if seen.has(c):
			continue
		var stack: Array = [c]
		seen[c] = true
		var mn := Vector2i(c)
		var mx := Vector2i(c)
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			mn = Vector2i(mini(mn.x, cur.x), mini(mn.y, cur.y))
			mx = Vector2i(maxi(mx.x, cur.x), maxi(mx.y, cur.y))
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = cur + off
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		out.append(Rect2i(mn, mx - mn + Vector2i.ONE))
	return out

func region_center(r: Rect2i, y := 0.0) -> Vector3:
	return Vector3((r.position.x + r.size.x * 0.5) * T, y, (r.position.y + r.size.y * 0.5) * T)

func first_cell(ch: String) -> Vector2i:
	var cs: Array = cells_of(ch)
	return cs[0] if not cs.is_empty() else Vector2i(-1, -1)

## Yaw that makes a console placed in `c` face away from the nearest wall (local +Z is "front").
func facing_yaw(c: Vector2i) -> float:
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for d in dirs:
		if is_solid_cell(c + d):
			var away: Vector2i = -d
			return atan2(float(away.x), float(away.y))
	return 0.0

# --- Navigation ------------------------------------------------------------------------------------------

func _build_nav() -> void:
	nav = NavGrid.new()
	nav.setup(grid_w, grid_h, T)
	for y in grid_h:
		for x in grid_w:
			var walk: bool = not _solid[y][x] and _prop[y][x] == ""
			if walk:
				var ch := _char_at(x, y)
				if SOLID_MARKERS.contains(ch):
					walk = false
			nav.set_walkable(Vector2i(x, y), walk)
	nav.finalize()

# --- Geometry ---------------------------------------------------------------------------------------------

func _wall_needed(x: int, y: int) -> bool:
	if not _in_grid(Vector2i(x, y)) or not _solid[y][x]:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := Vector2i(x + dx, y + dy)
			if _in_grid(n) and not _solid[n.y][n.x]:
				return true
	return false

func _merge(mask: Array) -> Array:
	var out: Array = []
	var h := mask.size()
	for y in h:
		var w: int = (mask[y] as Array).size()
		for x in w:
			if not mask[y][x]:
				continue
			var x2 := x
			while x2 + 1 < w and mask[y][x2 + 1]:
				x2 += 1
			var y2 := y
			while y2 + 1 < h:
				var full := true
				for xx in range(x, x2 + 1):
					if not mask[y2 + 1][xx]:
						full = false
						break
				if not full:
					break
				y2 += 1
			for yy in range(y, y2 + 1):
				for xx in range(x, x2 + 1):
					mask[yy][xx] = false
			out.append(Rect2i(x, y, x2 - x + 1, y2 - y + 1))
	return out

func _build_geometry() -> void:
	var geo := Node3D.new()
	geo.name = "Geometry"
	add_child(geo)
	var wall_mat := Mats.surface("wall_%d" % chapter(), th["wall_style"], th["wall_color"], th["wall_accent"], 0.5, 0.75, 0.3)
	var skirt_mat := Mats.plain(Color(0.06, 0.07, 0.09), 0.6, 0.6)
	var neon := Mats.glow(th["accent"], 2.4)
	# walls
	var wmask: Array = []
	for y in grid_h:
		var r: Array = []
		for x in grid_w:
			r.append(_wall_needed(x, y))
		wmask.append(r)
	var wall_rects := _merge(wmask)
	var n_seg := 0
	for rc in wall_rects:
		var rect: Rect2i = rc
		var size := Vector3(rect.size.x * T, H, rect.size.y * T)
		var pos := Vector3((rect.position.x + rect.size.x * 0.5) * T, H * 0.5, (rect.position.y + rect.size.y * 0.5) * T)
		Shapes.solid_box(geo, size, pos, wall_mat, Cfg.L_WORLD)
		# trims along every face that touches open floor
		for side in 4:
			for seg in _face_segments(rect, side):
				_trim(geo, rect, side, seg, skirt_mat, neon, n_seg)
				n_seg += 1
	# floors, one merged box per surface type
	var floor_mats := {
		1: Mats.surface("floor1_%d" % chapter(), th["floor_style"], th["floor_color"], th["accent"], 0.5, 0.65, 0.35),
		2: Mats.surface("floor2_%d" % chapter(), th["floor2_style"], th["floor2_color"], th["accent"], 0.5, 0.7, 0.4),
		3: Mats.surface("floor3_%d" % chapter(), th["floor3_style"], th["floor3_color"], th["accent"], 0.5, 0.55, 0.45),
	}
	for t in [1, 2, 3]:
		var m: Array = []
		for y in grid_h:
			var r2: Array = []
			for x in grid_w:
				r2.append(_floor_type[y][x] == t)
			m.append(r2)
		for rc in _merge(m):
			var rect2: Rect2i = rc
			var fsize := Vector3(rect2.size.x * T, 0.6, rect2.size.y * T)
			var fpos := Vector3((rect2.position.x + rect2.size.x * 0.5) * T, -0.3, (rect2.position.y + rect2.size.y * 0.5) * T)
			var body := Shapes.solid_box(geo, fsize, fpos, floor_mats[t], Cfg.L_WORLD)
			body.name = "Floor%d" % t
	# ceiling over the whole footprint
	if th["ceiling"]:
		var ceil_mat := Mats.surface("ceil_%d" % chapter(), "damaged", Color(0.09, 0.10, 0.13), th["accent"], 0.35, 0.8, 0.3)
		var csize := Vector3(grid_w * T + 4.0, 0.6, grid_h * T + 4.0)
		var cpos := Vector3(grid_w * T * 0.5, H + 0.3, grid_h * T * 0.5)
		var cbody := Shapes.solid_box(geo, csize, cpos, ceil_mat, Cfg.L_WORLD, "Ceiling")
		for c in cbody.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# props
	var crate_col: Color = th["crate"]
	for y in grid_h:
		for x in grid_w:
			var pc: String = _prop[y][x]
			if pc == "":
				continue
			var cp := cell_pos(Vector2i(x, y))
			match pc:
				"o":
					Props.crate_stack(geo, cp, true, th["accent"], crate_col)
				"O":
					Props.crate_stack(geo, cp, false, th["accent2"], crate_col)
				"p":
					Props.pillar(geo, cp, H, th["accent"], th["wall_color"])
				"r":
					Props.server_rack(geo, cp, atan2(float(_open_dir(Vector2i(x, y)).x), float(_open_dir(Vector2i(x, y)).y)), th["accent"])
				"n":
					Props.tank(geo, cp, th["accent2"])

func _open_dir(c: Vector2i) -> Vector2i:
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		if not is_solid_cell(c + d) and _prop[c.y + d.y][c.x + d.x] == "":
			return d
	return Vector2i(0, 1)

## Runs of consecutive face cells of a wall rectangle that touch open floor.
## side: 0 north (-z), 1 south (+z), 2 west (-x), 3 east (+x). Returns [start, end) in cell offsets.
func _face_segments(rect: Rect2i, side: int) -> Array:
	var out: Array = []
	var n := rect.size.x if side < 2 else rect.size.y
	var run_start := -1
	for i in range(n + 1):
		var open := false
		if i < n:
			var c: Vector2i
			match side:
				0: c = Vector2i(rect.position.x + i, rect.position.y - 1)
				1: c = Vector2i(rect.position.x + i, rect.position.y + rect.size.y)
				2: c = Vector2i(rect.position.x - 1, rect.position.y + i)
				_: c = Vector2i(rect.position.x + rect.size.x, rect.position.y + i)
			open = not is_solid_cell(c)
		if open and run_start < 0:
			run_start = i
		elif not open and run_start >= 0:
			out.append(Vector2i(run_start, i))
			run_start = -1
	return out

func _trim(parent: Node3D, rect: Rect2i, side: int, seg: Vector2i, skirt: Material, neon: Material, idx: int) -> void:
	var length := (seg.y - seg.x) * T
	var along := (seg.x + seg.y) * 0.5 * T
	var pos := Vector3.ZERO
	var rot := 0.0
	var out := 0.05
	match side:
		0:
			pos = Vector3(rect.position.x * T + along, 0, rect.position.y * T - out)
		1:
			pos = Vector3(rect.position.x * T + along, 0, (rect.position.y + rect.size.y) * T + out)
		2:
			pos = Vector3(rect.position.x * T - out, 0, rect.position.y * T + along)
			rot = PI * 0.5
		_:
			pos = Vector3((rect.position.x + rect.size.x) * T + out, 0, rect.position.y * T + along)
			rot = PI * 0.5
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot
	parent.add_child(holder)
	Shapes.box(holder, Vector3(length, 0.34, 0.12), Vector3(0, 0.17, 0), skirt)
	Shapes.box(holder, Vector3(length, 0.1, 0.1), Vector3(0, H - 0.25, 0), skirt)
	var h := (idx * 7919) % 11
	if h < 8 and length >= 3.9:
		Shapes.box(holder, Vector3(length - 0.5, 0.07, 0.05), Vector3(0, H * 0.58, 0), neon)
	if h == 3 or h == 6:
		Shapes.box(holder, Vector3(length - 0.8, 0.5, 0.06), Vector3(0, H * 0.82, 0), Mats.plain(Color(0.05, 0.06, 0.08), 0.5, 0.5))

# --- Environment and lighting --------------------------------------------------------------------------------

func _setup_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = th["sky"]
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = th["ambient"]
	_env.ambient_light_energy = th["ambient_energy"]
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	_env.glow_enabled = Prefs.quality > 0
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 0.95
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	_env.fog_enabled = true
	_env.fog_light_color = th["fog"]
	_env.fog_density = th["fog_density"]
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.08
	_env.adjustment_saturation = 1.12
	if Prefs.quality >= 2:
		_env.ssao_enabled = true
		_env.ssao_radius = 1.2
		_env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	# a dim key light that gives characters and walls real shadows (the ceiling does not block it)
	if Prefs.quality >= 1:
		var sun := DirectionalLight3D.new()
		sun.light_color = Color(0.62, 0.74, 1.0)
		sun.light_energy = 0.32
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 45.0
		sun.rotation_degrees = Vector3(-62.0, 28.0, 0.0)
		add_child(sun)

func environment() -> Environment:
	return _env

func _auto_lights() -> void:
	var spacing := int(th["lamp_spacing"])
	if spacing <= 0:
		return
	var geo := get_node("Geometry") as Node3D
	var lamp_col: Color = th["lamp"]
	var energy: float = th["lamp_energy"]
	var count := 0
	for y in range(2, grid_h, spacing):
		for x in range(2, grid_w, spacing):
			# nudge to the closest open cell so lamps sit over walkable floor
			var best := Vector2i(-1, -1)
			var best_d := 999
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var c := Vector2i(x + dx, y + dy)
					if _in_grid(c) and not _solid[c.y][c.x] and _prop[c.y][c.x] == "":
						var d := absi(dx) + absi(dy)
						if d < best_d:
							best_d = d
							best = c
			if best.x < 0:
				continue
			var p := cell_pos(best, H - 0.1)
			Props.ceiling_lamp(geo, p, lamp_col, energy, 10.0, Vector2(1.8, 0.5) if (x + y) % 2 == 0 else Vector2(0.5, 1.8))
			count += 1

# --- Player ------------------------------------------------------------------------------------------------------

func _spawn_player() -> void:
	var cell := first_cell("P")
	var yaw := start_yaw()
	if cell.x < 0:
		cell = Vector2i(2, 2)
	var pos := cell_pos(cell)
	if GameState.checkpoint != GameState.DEFAULT_CHECKPOINT and checkpoints.has(GameState.checkpoint):
		var cp: Checkpoint = checkpoints[GameState.checkpoint]
		pos = cp.global_position + Vector3(0, 0, 2.6)
		pos = Vector3(nav.nearest_walkable_world(pos).x, 0.0, nav.nearest_walkable_world(pos).z)
	if Net.active:
		_spawn_networked_players(pos, yaw)
		return
	player = Player.new()
	player.name = "Player"
	player.peer_id = 1
	add_child(player)
	player.global_position = pos
	player.rotation.y = yaw
	player.attach_camera()
	GameState.local_player = player
	player.refresh_stats(true)

## One Player per connected peer, spread a little so they don't spawn stacked. The local one gets
## the camera and becomes GameState.local_player; the rest start as puppets driven by Net's
## broadcast (see Net.gd / Player.apply_net_state).
func _spawn_networked_players(pos: Vector3, yaw: float) -> void:
	var my_id := Net.my_id()
	var ids := Net.players.keys()
	ids.sort()
	for i in ids.size():
		var peer_id: int = ids[i]
		var p := Player.new()
		p.name = "Player_%d" % peer_id
		p.peer_id = peer_id
		p.is_local = (peer_id == my_id)
		p.tint = Net.tint_for(peer_id)
		add_child(p)
		var spread := Vector3(cos(float(i) * 1.7), 0, sin(float(i) * 1.7)) * (1.6 if i > 0 else 0.0)
		p.global_position = pos + spread
		p.rotation.y = yaw
		Net.register_player(peer_id, p)
		if p.is_local:
			player = p
			p.attach_camera()
			GameState.local_player = p
			p.refresh_stats(true)

# --- Logic channels --------------------------------------------------------------------------------------------------

func set_channel(id: String, on: bool) -> void:
	if channels.get(id, false) == on:
		return
	channels[id] = on
	channel_changed.emit(id, on)

func get_channel(id: String) -> bool:
	return channels.get(id, false)

# --- Entity helpers (chapter scripts call these) -----------------------------------------------------------------------

## Re-applies channels that were latched on and remembered in the save (e.g. "a terminal was read").
func restore_persisted(ids: Array) -> void:
	for id in ids:
		if GameState.has_flag("ch_" + String(id)):
			set_channel(String(id), true)

func set_objective(text: String) -> void:
	if text == objective_text:
		return
	objective_text = text
	Bus.objective_changed.emit(text)

func hint(text: String, seconds := 5.0) -> void:
	Bus.hud_message.emit(text, Cfg.C_CYAN, seconds)

func add_door(ch: String, id: String, requires: Array, opts := {}) -> Door:
	var comps := regions(ch)
	var idx := int(opts.get("index", 0))
	if comps.size() <= idx:
		push_warning("%s: no door region '%s' (index %d)" % [name, ch, idx])
		return null
	var r: Rect2i = comps[idx]
	var d := Door.new()
	d.name = "Door_" + id
	d.door_id = id
	d.requires = requires
	d.mode_any = bool(opts.get("any", false))
	d.hold_time = float(opts.get("hold", 0.0))
	d.label = String(opts.get("label", ""))
	d.field = bool(opts.get("field", false))
	d.open_time = float(opts.get("open_time", 0.6))
	d.width_axis_x = r.size.x >= r.size.y if r.size.x != r.size.y else bool(opts.get("axis_x", true))
	d.span = (r.size.x if d.width_axis_x else r.size.y) * T
	d.height = H - 0.4
	for yy in range(r.position.y, r.position.y + r.size.y):
		for xx in range(r.position.x, r.position.x + r.size.x):
			d.cells.append(Vector2i(xx, yy))
	d.level = self
	d.position = region_center(r)
	entities.add_child(d)
	d.build()
	doors[id] = d
	# hazard stripes either side of the threshold
	var stripe := Props.stripes_material(th["accent"])
	var depth := (r.size.y if d.width_axis_x else r.size.x) * T
	if d.width_axis_x:
		Props.floor_decal(entities, d.position + Vector3(0, 0, -depth * 0.5 - 0.3), Vector2(d.span, 0.5), stripe)
		Props.floor_decal(entities, d.position + Vector3(0, 0, depth * 0.5 + 0.3), Vector2(d.span, 0.5), stripe)
	else:
		Props.floor_decal(entities, d.position + Vector3(-depth * 0.5 - 0.3, 0, 0), Vector2(0.5, d.span), stripe)
		Props.floor_decal(entities, d.position + Vector3(depth * 0.5 + 0.3, 0, 0), Vector2(0.5, d.span), stripe)
	return d

func add_plate(ch: String, channel: String, opts := {}) -> PressurePlate:
	var comps := regions(ch)
	var idx := int(opts.get("index", 0))
	if comps.size() <= idx:
		push_warning("%s: no plate region '%s'" % [name, ch])
		return null
	var r: Rect2i = comps[idx]
	var p := PressurePlate.new()
	p.name = "Plate_" + channel
	p.channel = channel
	match String(opts.get("accept", "any")):
		"echo":
			p.accept = PressurePlate.Accept.ECHO_ONLY
		"player":
			p.accept = PressurePlate.Accept.PLAYER_ONLY
		_:
			p.accept = PressurePlate.Accept.ANY
	p.latch_time = float(opts.get("latch", 0.0))
	p.size = Vector2(minf(r.size.x * T, 2.4), minf(r.size.y * T, 2.4)) if opts.get("compact", true) else Vector2(r.size.x * T, r.size.y * T)
	p.level = self
	p.position = region_center(r)
	entities.add_child(p)
	p.build()
	devices[channel] = p
	return p

func add_switch(ch: String, channel: String, opts := {}) -> Switch:
	var comps := regions(ch)
	var idx := int(opts.get("index", 0))
	if comps.size() <= idx:
		push_warning("%s: no switch marker '%s'" % [name, ch])
		return null
	var cell: Vector2i = Vector2i(comps[idx].position)
	var s := Switch.new()
	s.name = "Switch_" + channel
	s.channel = channel
	s.echo_compatible = bool(opts.get("echo", true))
	s.title = String(opts.get("title", "SWITCH"))
	s.duration = float(opts.get("duration", 6.0))
	s.persist_key = String(opts.get("persist", ""))
	if opts.has("interact_id"):
		s.interact_id = String(opts["interact_id"])
	match String(opts.get("mode", "toggle")):
		"timed":
			s.mode = Switch.Mode.TIMED
		"latch":
			s.mode = Switch.Mode.LATCH
		_:
			s.mode = Switch.Mode.TOGGLE
	s.level = self
	s.position = cell_pos(cell)
	s.rotation.y = float(opts.get("yaw", facing_yaw(cell)))
	entities.add_child(s)
	s.build()
	devices[channel] = s
	return s

func add_shoot_target(ch: String, channel: String, opts := {}) -> ShootTarget:
	var comps := regions(ch)
	var idx := int(opts.get("index", 0))
	if comps.size() <= idx:
		push_warning("%s: no target marker '%s'" % [name, ch])
		return null
	var cell: Vector2i = Vector2i(comps[idx].position)
	var t := ShootTarget.new()
	t.name = "Target_" + channel
	t.channel = channel
	t.echo_only = bool(opts.get("echo_only", false))
	t.duration = float(opts.get("duration", 6.0))
	t.yaw = float(opts.get("yaw", facing_yaw(cell)))
	t.level = self
	t.position = cell_pos(cell)
	entities.add_child(t)
	t.build()
	devices[channel] = t
	return t

func add_relay(ch: String, channel: String, opts := {}) -> Relay:
	var comps := regions(ch)
	var idx := int(opts.get("index", 0))
	if comps.size() <= idx:
		push_warning("%s: no relay marker '%s'" % [name, ch])
		return null
	var cell: Vector2i = Vector2i(comps[idx].position)
	var r := Relay.new()
	r.name = "Relay_" + channel
	r.channel = channel
	r.title = String(opts.get("title", "SECURITY RELAY"))
	r.hold_time = float(opts.get("hold", 3.2))
	r.persist_key = flag_key("relay_" + channel)
	r.level = self
	r.position = cell_pos(cell)
	entities.add_child(r)
	r.build()
	devices[channel] = r
	return r

func add_terminal(ch: String, log_id: String, opts := {}) -> Terminal:
	var comps := regions(ch)
	var idx := int(opts.get("index", 0))
	if comps.size() <= idx:
		push_warning("%s: no terminal marker '%s'" % [name, ch])
		return null
	var cell: Vector2i = Vector2i(comps[idx].position)
	var t := Terminal.new()
	t.name = "Terminal_" + log_id
	t.log_id = log_id
	t.channel_on_read = String(opts.get("channel", ""))
	t.level = self
	t.position = cell_pos(cell)
	entities.add_child(t)
	t.build(float(opts.get("yaw", facing_yaw(cell))))
	return t

func add_checkpoint(ch: String, id: String, order: int) -> Checkpoint:
	var cell := first_cell(ch)
	if cell.x < 0:
		push_warning("%s: no checkpoint marker '%s'" % [name, ch])
		return null
	var c := Checkpoint.new()
	c.name = "Checkpoint_" + id
	c.cp_id = id
	c.order = order
	c.level = self
	c.position = cell_pos(cell)
	entities.add_child(c)
	c.build()
	checkpoints[id] = c
	return c

func add_exit(ch: String, reason := "The way forward is sealed.") -> ExitTrigger:
	var comps := regions(ch)
	if comps.is_empty():
		push_warning("%s: no exit marker '%s'" % [name, ch])
		return null
	var r: Rect2i = comps[0]
	exit_gate = ExitTrigger.new()
	exit_gate.level = self
	exit_gate.locked_reason = reason
	exit_gate.position = region_center(r)
	exit_gate.yaw = 0.0 if r.size.x >= r.size.y else PI * 0.5
	entities.add_child(exit_gate)
	exit_gate.build()
	return exit_gate

func add_pickups(ch: String, kind: String, value: int) -> void:
	for c in cells_of(ch):
		var key := flag_key("pk_%s_%d_%d" % [ch, c.x, c.y])
		if GameState.has_flag(key):
			continue
		Pickup.spawn(entities, kind, cell_pos(c, 0.75), value, key)

func add_zone(center: Vector3, size: Vector3, callback: Callable, flag := "") -> TriggerZone:
	var z := TriggerZone.new()
	z.callback = callback
	z.flag_key = flag_key(flag) if flag != "" else ""
	z.position = center
	entities.add_child(z)
	z.build(size)
	return z

func add_zone_cell(ch: String, callback: Callable, flag := "", pad := Vector3(0, 0, 0)) -> TriggerZone:
	var comps := regions(ch)
	if comps.is_empty():
		push_warning("%s: no zone marker '%s'" % [name, ch])
		return null
	var r: Rect2i = comps[0]
	return add_zone(region_center(r), Vector3(r.size.x * T, 4.0, r.size.y * T) + pad, callback, flag)

func dialogue_zone(ch: String, dialogue_id: String, flag := "", on_fire: Callable = Callable()) -> TriggerZone:
	var flag_name := flag if flag != "" else "dlg_" + dialogue_id
	var cb := func(p: Player) -> void:
		Story.play(dialogue_id)
		if on_fire.is_valid():
			on_fire.call(p)
	return add_zone_cell(ch, cb, flag_name)

func hint_zone(ch: String, text: String, seconds := 6.0, flag := "") -> TriggerZone:
	var flag_name := flag if flag != "" else "hint_%s_%d" % [ch, text.hash() & 0xfff]
	var cb := func(_p: Player) -> void:
		hint(text, seconds)
	return add_zone_cell(ch, cb, flag_name)

func add_hazard_arc(ch: String, opts := {}) -> ArcHazard:
	var comps := regions(ch)
	var idx := int(opts.get("index", 0))
	if comps.size() <= idx:
		push_warning("%s: no arc marker '%s'" % [name, ch])
		return null
	var r: Rect2i = comps[idx]
	var a := ArcHazard.new()
	a.level = self
	var along_x := r.size.x >= r.size.y
	a.length = (r.size.x if along_x else r.size.y) * T
	a.rotation.y = 0.0 if along_x else PI * 0.5
	a.period = float(opts.get("period", 4.2))
	a.warn_time = float(opts.get("warn", 1.0))
	a.active_time = float(opts.get("active", 1.2))
	a.phase = float(opts.get("phase", 0.0))
	a.disabled_by = String(opts.get("disabled_by", ""))
	a.damage = float(opts.get("damage", 22.0))
	a.position = region_center(r)
	entities.add_child(a)
	a.build()
	return a

func add_sweep(ch: String, opts := {}) -> SweepBeam:
	var cell := first_cell(ch)
	if cell.x < 0:
		push_warning("%s: no sweep marker '%s'" % [name, ch])
		return null
	var s := SweepBeam.new()
	s.level = self
	s.speed = float(opts.get("speed", 0.85))
	s.beam_length = float(opts.get("length", 8.5))
	s.disabled_by = String(opts.get("disabled_by", ""))
	s.position = cell_pos(cell)
	entities.add_child(s)
	s.build()
	return s

func add_crusher(ch: String, travel: Vector3, size: Vector3, opts := {}) -> Crusher:
	var cell := first_cell(ch)
	if cell.x < 0:
		push_warning("%s: no crusher marker '%s'" % [name, ch])
		return null
	var c := Crusher.new()
	c.level = self
	c.travel = travel
	c.size = size
	c.period = float(opts.get("period", 7.0))
	c.dwell = float(opts.get("dwell", 2.2))
	c.phase = float(opts.get("phase", 0.0))
	c.disabled_by = String(opts.get("disabled_by", ""))
	c.position = cell_pos(cell, float(opts.get("base_y", 0.0)))
	entities.add_child(c)
	c.build()
	return c

func add_camera(ch: String, opts := {}) -> SecurityCamera:
	var cell := first_cell(ch)
	if cell.x < 0:
		push_warning("%s: no camera marker '%s'" % [name, ch])
		return null
	var id := String(opts.get("id", "%d_%d" % [cell.x, cell.y]))
	if GameState.has_flag(flag_key("cam_" + id)):
		return null
	var c := SecurityCamera.new()
	c.level = self
	c.cam_id = id
	c.base_yaw = float(opts.get("yaw", 0.0))
	c.sweep_half = float(opts.get("sweep", 1.0))
	c.range_m = float(opts.get("range", 17.0))
	c.disabled_by = String(opts.get("disabled_by", ""))
	c.position = cell_pos(cell, H - 0.55)
	entities.add_child(c)
	c.build()
	cameras.append(c)
	return c

func add_prop_console(ch: String, color: Color = Cfg.C_CYAN) -> void:
	for c in cells_of(ch):
		Props.console_desk(entities, cell_pos(c), facing_yaw(c), color, true)

# --- Enemies, encounters, alarms -----------------------------------------------------------------------------------------------

func spawn_enemy(kind: String, cell: Vector2i, opts := {}) -> Enemy:
	var uid := String(opts.get("uid", "%s_%d_%d" % [kind, cell.x, cell.y]))
	if GameState.has_flag(flag_key("dead_" + uid)):
		return null
	var e: Enemy
	match kind:
		"drone":
			e = HunterDrone.new()
		"sentry":
			e = Sentry.new()
			(e as Sentry).base_yaw = float(opts.get("yaw", 0.0))
		"brute":
			e = ArmoredBrute.new()
		"aegis":
			e = AegisUnit.new()
		_:
			push_warning("Unknown enemy kind '%s'" % kind)
			return null
	e.uid = uid
	e.level = self
	e.group_id = String(opts.get("group", ""))
	for pc in opts.get("patrol", []):
		e.patrol_points.append(cell_pos(Vector2i(pc)))
	entities.add_child(e)
	e.global_position = cell_pos(cell, 0.0)
	if e.flying:
		e.global_position.y = e.hover_y
	e.rotation.y = float(opts.get("yaw", 0.0)) if kind != "sentry" else 0.0
	if bool(opts.get("aware", false)):
		e.alert(player.global_position if player != null else e.global_position, player)
	return e

## Spawns every marker of a letter as the given enemy kind.
func spawn_marked(ch: String, kind: String, opts := {}) -> Array:
	var out: Array = []
	for c in cells_of(ch):
		var o := opts.duplicate()
		var e := spawn_enemy(kind, c, o)
		if e != null:
			out.append(e)
	return out

func enemies_alive() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func alert_around(pos: Vector3, radius: float, who: Node3D, caller: Enemy) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e == caller:
			continue
		if e.global_position.distance_to(pos) <= radius:
			e.alert(pos, who)

## waves: Array of waves, each an Array of {"kind": String, "cell": Vector2i, "opts": Dictionary}.
## The encounter starts when the zone is entered; `lock` is a channel switched on while it runs
## (doors listing "!lock" in `requires` stay shut), and `on_clear` fires after the last wave dies.
func add_encounter(id: String, zone_center: Vector3, zone_size: Vector3, waves: Array, lock := "", on_clear: Callable = Callable(), start_line := "") -> void:
	var done_key := flag_key("enc_" + id + "_done")
	if GameState.has_flag(done_key):
		return
	_encounters[id] = {"waves": waves, "wave": -1, "lock": lock, "clear": on_clear, "done_key": done_key, "alive": 0, "started": false}
	add_zone(zone_center, zone_size, func(_p: Player) -> void: _start_encounter(id, start_line))

func add_encounter_cell(id: String, ch: String, waves: Array, lock := "", on_clear: Callable = Callable(), start_line := "") -> void:
	var comps := regions(ch)
	if comps.is_empty():
		push_warning("%s: no encounter zone marker '%s'" % [name, ch])
		return
	var r: Rect2i = comps[0]
	add_encounter(id, region_center(r), Vector3(r.size.x * T, 4.0, r.size.y * T), waves, lock, on_clear, start_line)

func start_encounter(id: String) -> void:
	_start_encounter(id, "")

func encounter_active(id: String) -> bool:
	return _encounters.has(id) and _encounters[id]["started"] and not GameState.has_flag(_encounters[id]["done_key"])

func _start_encounter(id: String, start_line: String) -> void:
	if not _encounters.has(id):
		return
	var enc: Dictionary = _encounters[id]
	if enc["started"]:
		return
	enc["started"] = true
	if enc["lock"] != "":
		set_channel(enc["lock"], true)
	Bus.hud_message.emit("HOSTILES DETECTED", Cfg.C_RED, 2.0)
	Sfx.play("alarm", -6.0)
	if start_line != "":
		Story.play(start_line)
	_next_wave(id)

func _next_wave(id: String) -> void:
	var enc: Dictionary = _encounters[id]
	enc["wave"] = int(enc["wave"]) + 1
	var waves: Array = enc["waves"]
	if int(enc["wave"]) >= waves.size():
		_finish_encounter(id)
		return
	var alive := 0
	for spec in waves[int(enc["wave"])]:
		var opts: Dictionary = (spec.get("opts", {}) as Dictionary).duplicate()
		opts["uid"] = "enc_%s_w%d_%s_%d_%d" % [id, int(enc["wave"]), spec["kind"], spec["cell"].x, spec["cell"].y]
		opts["aware"] = true
		opts["group"] = id
		var e := spawn_enemy(String(spec["kind"]), spec["cell"], opts)
		if e != null:
			alive += 1
			e.died.connect(func(_en: Enemy) -> void: _on_encounter_enemy_died(id))
	enc["alive"] = alive
	if alive == 0:
		_next_wave(id)

func _on_encounter_enemy_died(id: String) -> void:
	var enc: Dictionary = _encounters[id]
	enc["alive"] = int(enc["alive"]) - 1
	if int(enc["alive"]) <= 0:
		var tw := create_tween()
		tw.tween_interval(1.4)
		tw.tween_callback(func() -> void:
			if is_inside_tree() and _encounters.has(id):
				_next_wave(id))

func _finish_encounter(id: String) -> void:
	var enc: Dictionary = _encounters[id]
	GameState.set_flag(enc["done_key"], true)
	if enc["lock"] != "":
		set_channel(enc["lock"], false)
	Bus.hud_message.emit("AREA SECURE", Cfg.C_GREEN, 2.0)
	Sfx.play("checkpoint", -6.0)
	var cb: Callable = enc["clear"]
	if cb.is_valid():
		cb.call()

func raise_alarm(source: Node3D) -> void:
	if _alarm_cd > 0.0:
		return
	_alarm_cd = 20.0
	Bus.hud_message.emit("ALARM - YOU HAVE BEEN SEEN", Cfg.C_RED, 3.0)
	Bus.screen_flash.emit(Cfg.C_RED, 0.5)
	Sfx.play("alarm")
	var pos := player.global_position if player != null else source.global_position
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null:
			e.alert(pos, player)
	for spec in _alarm_spawns:
		spawn_enemy(String(spec["kind"]), spec["cell"], {"aware": true, "uid": "alarm_%s_%d" % [spec["kind"], Time.get_ticks_msec()]})

func set_alarm_spawns(specs: Array) -> void:
	_alarm_spawns = specs

# --- Completion ------------------------------------------------------------------------------------------------------------------------

func unlock_exit(reason_done := "") -> void:
	if exit_gate != null:
		exit_gate.set_locked(false, reason_done)

func complete() -> void:
	if _completed:
		return
	_completed = true
	GameState.set_flag(flag_key("complete"), true)
	Bus.chapter_completed.emit(chapter())
	completed.emit()

# --- Validation (used by tests) -----------------------------------------------------------------------------------------------------------

## Cells reachable from the player start assuming every door is open.
func reachable_cells() -> Dictionary:
	var seen := {}
	var start := nav.nearest_walkable(first_cell("P") if first_cell("P").x >= 0 else Vector2i(2, 2))
	var stack: Array = [start]
	seen[start] = true
	var door_cells := {}
	for d in doors.values():
		for c in (d as Door).cells:
			door_cells[c] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + off
			if seen.has(n) or not _in_grid(n):
				continue
			if nav.is_floor(n) or door_cells.has(n):
				seen[n] = true
				stack.append(n)
	return seen

func validate() -> Array:
	var problems: Array = []
	var reach := reachable_cells()
	for ch in marks:
		for c in marks[ch]:
			var v: Vector2i = c
			if SOLID_MARKERS.contains(ch):
				continue
			if not reach.has(v) and not doors.is_empty():
				problems.append("marker '%s' at %s is unreachable" % [ch, v])
	if exit_gate == null and needs_exit_gate():
		problems.append("no exit")
	if first_cell("P").x < 0:
		problems.append("no player start 'P'")
	return problems
