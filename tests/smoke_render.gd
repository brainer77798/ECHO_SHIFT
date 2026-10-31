extends SceneTree
## Rendering smoke test: builds a tiny lit 3D scene, saves a screenshot, quits.
## Run (windowed, needs a GPU):  godot --path . -s tests/smoke_render.gd

var _frames := 0

func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.02, 0.04)
	env.glow_enabled = true
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.15, 0.25)
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.9, 1.0)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	root3d.add_child(mi)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.position = Vector3(2, 2, 4)
	cam.look_at(Vector3.ZERO)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 3, 2)
	root3d.add_child(l)
	print("RENDERER: ", RenderingServer.get_video_adapter_name(), " | ", RenderingServer.get_video_adapter_vendor())
	print("RENDER METHOD: ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		var img := get_root().get_texture().get_image()
		var path := "user://smoke.png"
		img.save_png(path)
		print("SCREENSHOT: ", ProjectSettings.globalize_path(path), " size=", img.get_size())
		quit(0)
	return false
