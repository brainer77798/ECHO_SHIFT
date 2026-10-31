class_name MapBuilder
extends RefCounted
## Builds the ASCII floor plans consumed by LevelBase by carving rectangles out of solid rock.
## Coordinates are cells; every call clips to the grid so a typo can never write out of bounds.

var w := 0
var h := 0
var _g: Array = []

func _init(width: int, height: int) -> void:
	w = width
	h = height
	for y in h:
		var row: Array = []
		for x in w:
			row.append("#")
		_g.append(row)

## Carves a rectangle of floor (x, y = top-left cell).
func room(x: int, y: int, rw: int, rh: int, ch := ".") -> MapBuilder:
	for yy in range(y, y + rh):
		for xx in range(x, x + rw):
			_cell_put(xx, yy, ch)
	return self

## Carves a corridor floor; same as room() but defaults to the corridor floor type.
func hall(x: int, y: int, rw: int, rh: int) -> MapBuilder:
	return room(x, y, rw, rh, ",")

func put(x: int, y: int, ch: String) -> MapBuilder:
	_cell_put(x, y, ch)
	return self

## Fills a rectangle with a marker character (doors, plates, zones).
func mark(x: int, y: int, rw: int, rh: int, ch: String) -> MapBuilder:
	return room(x, y, rw, rh, ch)

func get_char(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= w or y >= h:
		return "#"
	return _g[y][x]

func _cell_put(x: int, y: int, ch: String) -> void:
	assert(ch.length() == 1, "MapBuilder: marker '%s' is not exactly one character - every cell must be a single char or row strings desync" % ch)
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	_g[y][x] = ch

func rows() -> PackedStringArray:
	var out := PackedStringArray()
	for y in h:
		out.append("".join(PackedStringArray(_g[y])))
	return out
