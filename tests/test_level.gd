extends LevelBase
## Tiny two-room level used by the automated tests: a plate in the west room, a door between rooms.

func chapter() -> int:
	return 1

func theme() -> Dictionary:
	return {"ceiling": false, "lamp_spacing": 0}

func map_rows() -> PackedStringArray:
	var m := MapBuilder.new(34, 16)
	m.room(1, 1, 19, 14)
	m.room(21, 1, 12, 14)
	m.put(3, 8, "P")
	m.mark(10, 6, 2, 2, "B")
	m.mark(20, 7, 1, 2, "1")
	m.mark(26, 6, 2, 2, "Q")
	m.put(30, 2, "X")
	return m.rows()

func build_content() -> void:
	add_plate("B", "plate_b", {"accept": "any", "latch": 0.0})
	add_plate("Q", "plate_echo", {"accept": "echo"})
	add_door("1", "d1", ["plate_b"])
