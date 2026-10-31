extends SceneTree
## Loads every .gd file under res:// (except tests) and reports the ones that fail to compile.
## Run:  godot --headless --path . -s tests/check_scripts.gd

func _initialize() -> void:
	var files: Array[String] = []
	for dir in ["res://autoload", "res://scripts"]:
		_collect(dir, files)
	var bad := 0
	for f in files:
		var s: Resource = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if s == null or (s is GDScript and not (s as GDScript).can_instantiate() and not (s as GDScript).is_abstract()):
			print("PARSE FAIL: ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	quit(1 if bad > 0 else 0)

func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
