class_name HitFlash
extends RefCounted
## Brief additive colour flash over every mesh under a root node (damage feedback).

static func apply(root: Node3D, color: Color = Color(1, 1, 1), strength := 0.75, duration := 0.12) -> void:
	if not is_instance_valid(root):
		return
	var mat: StandardMaterial3D
	if root.has_meta("_flash_mat"):
		mat = root.get_meta("_flash_mat")
	else:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(1, 1, 1, 0)
		root.set_meta("_flash_mat", mat)
		for m in _meshes(root):
			m.material_overlay = mat
	mat.albedo_color = Color(color.r, color.g, color.b, strength)
	if root.has_meta("_flash_tween"):
		var old: Tween = root.get_meta("_flash_tween")
		if old and old.is_valid():
			old.kill()
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	root.set_meta("_flash_tween", tw)

static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
