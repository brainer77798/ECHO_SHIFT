class_name NavGrid
extends RefCounted
## Tile navigation for the grid-built levels, backed by Godot's AStarGrid2D.
## Walls are permanent solids; doors add/remove reference-counted blockers at run time, so closed
## doors are routed around and open doors are routed through. Paths are smoothed with a swept
## line-of-sight test so enemies cut corners instead of zig-zagging cell to cell.

var width := 0
var height := 0
var tile := 2.0
var astar := AStarGrid2D.new()
var _wall := PackedByteArray()          # 1 = permanently solid
var _blockers: Dictionary = {}          # Vector2i -> int (door reference counts)

func setup(w: int, h: int, tile_size: float) -> void:
	width = w
	height = h
	tile = tile_size
	_wall.resize(w * h)
	_wall.fill(1)
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

func set_walkable(c: Vector2i, walkable: bool) -> void:
	if not in_bounds(c):
		return
	_wall[c.y * width + c.x] = 0 if walkable else 1

## Call once after every set_walkable() has been issued.
func finalize() -> void:
	astar.update()
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			var solid := _wall[y * width + x] == 1
			astar.set_point_solid(c, solid)
			if solid:
				continue
			# prefer routes through the middle of rooms: cells hugging a wall cost more
			var near_wall := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := Vector2i(x + dx, y + dy)
					if not in_bounds(n) or _wall[n.y * width + n.x] == 1:
						near_wall = true
			astar.set_point_weight_scale(c, 1.7 if near_wall else 1.0)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / tile), floori(pos.z / tile))

func cell_center(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3((c.x + 0.5) * tile, y, (c.y + 0.5) * tile)

func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and _wall[c.y * width + c.x] == 0 and not _blockers.has(c)

func is_floor(c: Vector2i) -> bool:
	return in_bounds(c) and _wall[c.y * width + c.x] == 0

## Doors register the cells they occupy while closed.
func add_blocker(cells: Array) -> void:
	for c in cells:
		_blockers[c] = int(_blockers.get(c, 0)) + 1
		if in_bounds(c):
			astar.set_point_solid(c, true)

func remove_blocker(cells: Array) -> void:
	for c in cells:
		if not _blockers.has(c):
			continue
		_blockers[c] = int(_blockers[c]) - 1
		if int(_blockers[c]) <= 0:
			_blockers.erase(c)
			if in_bounds(c) and _wall[c.y * width + c.x] == 0:
				astar.set_point_solid(c, false)

func nearest_walkable(c: Vector2i, max_ring := 6) -> Vector2i:
	if is_walkable(c):
		return c
	for ring in range(1, max_ring + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var n := Vector2i(c.x + dx, c.y + dy)
				if is_walkable(n):
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = n
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

## World position of the nearest walkable cell centre (keeps the input height).
func nearest_walkable_world(pos: Vector3) -> Vector3:
	var c := nearest_walkable(cell_of(pos))
	if c.x < 0:
		return pos
	return cell_center(c, pos.y)

## True when a body of the given radius can travel the straight segment a->b without touching a solid cell.
func has_line(a: Vector3, b: Vector3, radius := 0.45) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var length := d.length()
	if length < 0.01:
		return is_walkable(cell_of(a))
	var dir := d / length
	var side := Vector2(-dir.y, dir.x) * radius
	var step := tile * 0.25
	var t := 0.0
	while true:
		var p := Vector2(a.x, a.z) + dir * t
		if not is_walkable(Vector2i(floori(p.x / tile), floori(p.y / tile))):
			return false
		if radius > 0.0:
			var l := p + side
			var r := p - side
			if not is_walkable(Vector2i(floori(l.x / tile), floori(l.y / tile))):
				return false
			if not is_walkable(Vector2i(floori(r.x / tile), floori(r.y / tile))):
				return false
		if t >= length:
			break
		t = minf(t + step, length)
	return true

## Smoothed world-space waypoints from `from` to `to` (excluding the start). Empty when unreachable.
func find_path(from: Vector3, to: Vector3, radius := 0.45) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := nearest_walkable(cell_of(from))
	var b := nearest_walkable(cell_of(to))
	if a.x < 0 or b.x < 0:
		return out
	if has_line(from, to, radius):
		out.append(to)
		return out
	var ids: Array[Vector2i] = astar.get_id_path(a, b)
	if ids.size() == 0:
		return out
	var pts: Array[Vector3] = []
	for i in range(1, ids.size()):
		pts.append(cell_center(ids[i], to.y))
	if pts.is_empty():
		out.append(to)
		return out
	pts[pts.size() - 1] = to if is_walkable(cell_of(to)) else pts[pts.size() - 1]
	# string-pull: from each anchor, jump to the farthest point still in a clear line
	var anchor := from
	var i := 0
	while i < pts.size():
		var far := i
		for j in range(pts.size() - 1, i - 1, -1):
			if has_line(anchor, pts[j], radius):
				far = j
				break
		out.append(pts[far])
		anchor = pts[far]
		i = far + 1
	return out

## Random walkable point within `radius` metres of `pos` (for patrols / investigation).
func random_point_near(pos: Vector3, radius: float, rng: RandomNumberGenerator) -> Vector3:
	for _i in 12:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(radius * 0.3, radius)
		var p := pos + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if is_walkable(cell_of(p)) and has_line(pos, p, 0.3):
			return p
	return pos
