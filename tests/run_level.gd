extends Node
## Loads a chapter, lets it run for a number of frames and saves screenshots. Windowed (needs a GPU).
##   godot --path . res://tests/run_level.tscn -- --chapter=1 --frames=40 --shot=a.png [--cam=x,y,z,tx,ty,tz] [--god]
##   Extra: --pos=x,z (teleport player)  --yaw=deg  --top (top-down overview of the whole map)

var _args := {}
var _frames := 0
var _level: Node
var _cam: Camera3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var chapter := int(_args.get("chapter", "1"))
	GameState.in_game = true
	GameState.chapter = chapter
	GameState.begin_chapter(chapter)
	var scene: PackedScene = load(Cfg.CHAPTERS[chapter - 1]["scene"])
	_level = scene.instantiate()
	add_child(_level)
	print("LEVEL READY chapter=%d  grid=%dx%d" % [chapter, _level.grid_w, _level.grid_h])
	var problems: Array = _level.validate()
	for p in problems:
		print("VALIDATE: ", p)
	if _args.has("pos"):
		var p: PackedStringArray = String(_args["pos"]).split(",")
		_level.player.global_position = Vector3(float(p[0]), 0.1, float(p[1]))
	if _args.has("yaw"):
		_level.player.rotation.y = deg_to_rad(float(_args["yaw"]))
		_level.player.cam.yaw = _level.player.rotation.y
		_level.player.cam.snap_to_target()
	_cam = Camera3D.new()
	add_child(_cam)
	if _args.has("cam"):
		var c: PackedStringArray = String(_args["cam"]).split(",")
		_cam.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		_cam.look_at(Vector3(float(c[3]), float(c[4]), float(c[5])))
		_cam.make_current()
	if _args.has("top"):
		var w: float = _level.grid_w * 2.0
		var h: float = _level.grid_h * 2.0
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = maxf(w * 0.5625, h) * 1.02
		_cam.global_position = Vector3(w * 0.5, 60.0, h * 0.5)
		_cam.rotation_degrees = Vector3(-90, 0, 0)
		_cam.far = 200.0
		_cam.make_current()
		var ceil_node := _level.get_node_or_null("Geometry/Ceiling")
		if ceil_node:
			ceil_node.visible = false

func _process(_delta: float) -> void:
	_frames += 1
	var target := int(_args.get("frames", "40"))
	if _frames == target:
		var img := get_viewport().get_texture().get_image()
		var path := "user://" + String(_args.get("shot", "level.png"))
		img.save_png(path)
		print("SCREENSHOT ", ProjectSettings.globalize_path(path), " ", img.get_size(), "  fps=", Engine.get_frames_per_second())
	if _frames >= target + 2:
		get_tree().quit(0)
