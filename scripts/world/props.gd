class_name Props
extends RefCounted
## Procedural set dressing. Solid props are StaticBody3D on the world layer so collision always
## matches what is visible; purely decorative pieces have no collision.

static func _rng_for(pos: Vector3) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(pos.x * 73.0) * 31 + int(pos.z * 131.0) + 977
	return r

## Soft dark disc under a character; stands in for a real shadow on cheap quality levels.
static func blob_shadow(parent: Node3D, radius: float, alpha := 0.55) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Mats.soft_dot()
	m.albedo_color = Color(0, 0, 0, alpha)
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.03, 0)
	parent.add_child(mi)
	return mi

## Stack of cargo crates filling one grid cell. `tall` gives full cover, otherwise waist-high cover.
static func crate_stack(parent: Node3D, center: Vector3, tall: bool, accent: Color, base: Color) -> StaticBody3D:
	var r := _rng_for(center)
	var h := 2.0 + r.randf() * 0.3 if tall else 1.05
	var size := Vector3(1.8, h, 1.8)
	var body := StaticBody3D.new()
	body.position = Vector3(center.x, 0, center.z)
	body.rotation.y = r.randf_range(-0.09, 0.09)
	body.collision_layer = Cfg.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	parent.add_child(body)
	Shapes.box(body, size, Vector3(0, h * 0.5, 0), Mats.surface("crate_" + base.to_html(), "plates", base, accent, 0.9, 0.7, 0.35))
	# corner posts + glowing band so crates read as industrial cargo
	var post := Mats.plain(base * 0.55, 0.5, 0.6)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Shapes.box(body, Vector3(0.12, h + 0.04, 0.12), Vector3(sx * 0.9, h * 0.5, sz * 0.9), post)
	var band := Mats.glow(accent, 1.6)
	Shapes.box(body, Vector3(size.x + 0.02, 0.07, size.z + 0.02), Vector3(0, h * 0.62, 0), band)
	if tall and r.randf() > 0.5:
		Shapes.box(body, Vector3(1.4, 0.9, 1.4), Vector3(0.1, h + 0.45, -0.05), Mats.surface("crate2_" + base.to_html(), "damaged", base * 0.9, accent, 0.9), "TopCrate")
	return body

static func pillar(parent: Node3D, center: Vector3, height: float, accent: Color, base: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = Vector3(center.x, 0, center.z)
	body.collision_layer = Cfg.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.8
	shape.height = height
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	body.add_child(cs)
	parent.add_child(body)
	var mat := Mats.surface("pillar_" + base.to_html(), "plates", base, accent, 0.7, 0.55, 0.5)
	Shapes.cylinder(body, 0.78, 0.78, height, Vector3(0, height * 0.5, 0), mat, 20)
	Shapes.cylinder(body, 0.92, 0.92, 0.35, Vector3(0, 0.175, 0), Mats.plain(base * 0.6, 0.5, 0.6), 20)
	Shapes.cylinder(body, 0.92, 0.92, 0.35, Vector3(0, height - 0.175, 0), Mats.plain(base * 0.6, 0.5, 0.6), 20)
	for y in [1.2, 2.9]:
		Shapes.torus(body, 0.78, 0.84, Vector3(0, y, 0), Mats.glow(accent, 2.2), 24)
	return body

static func server_rack(parent: Node3D, center: Vector3, yaw: float, accent: Color) -> StaticBody3D:
	var r := _rng_for(center)
	var size := Vector3(1.7, 2.7, 1.2)
	var body := StaticBody3D.new()
	body.position = Vector3(center.x, 0, center.z)
	body.rotation.y = yaw
	body.collision_layer = Cfg.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	parent.add_child(body)
	Shapes.box(body, size, Vector3(0, size.y * 0.5, 0), Mats.plain(Color(0.07, 0.09, 0.12), 0.5, 0.6))
	for i in 9:
		var lit: Color = accent if r.randf() > 0.25 else (Cfg.C_AMBER if r.randf() > 0.5 else Cfg.C_RED)
		var w := r.randf_range(0.6, 1.3)
		Shapes.box(body, Vector3(w, 0.07, 0.03), Vector3(-0.35 + (w - 0.9) * 0.3, 0.35 + i * 0.27, -size.z * 0.5 - 0.005), Mats.glow(lit, 2.0))
	Shapes.box(body, Vector3(1.5, 0.08, 1.0), Vector3(0, size.y + 0.04, 0), Mats.plain(Color(0.04, 0.05, 0.07), 0.8, 0.3))
	return body

static func tank(parent: Node3D, center: Vector3, liquid: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = Vector3(center.x, 0, center.z)
	body.collision_layer = Cfg.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.85
	shape.height = 3.6
	cs.shape = shape
	cs.position = Vector3(0, 1.8, 0)
	body.add_child(cs)
	parent.add_child(body)
	var metal := Mats.plain(Color(0.12, 0.14, 0.18), 0.4, 0.8)
	Shapes.cylinder(body, 0.95, 0.95, 0.4, Vector3(0, 0.2, 0), metal, 24)
	Shapes.cylinder(body, 0.95, 0.95, 0.4, Vector3(0, 3.4, 0), metal, 24)
	Shapes.cylinder(body, 0.7, 0.7, 2.9, Vector3(0, 1.85, 0), Mats.glow(liquid, 1.1), 20)
	Shapes.cylinder(body, 0.85, 0.85, 3.0, Vector3(0, 1.85, 0), Mats.glass(liquid, 0.22), 24)
	Shapes.add_light(body, Vector3(0, 1.8, 0), liquid, 0.9, 5.0)
	return body

## Free-standing control desk (decor + cover). Returns the body; `screen` metadata holds the screen mesh.
static func console_desk(parent: Node3D, pos: Vector3, yaw: float, glow: Color, solid := true) -> Node3D:
	var root: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = Cfg.L_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.5, 1.0, 0.8)
		cs.shape = shape
		cs.position = Vector3(0, 0.5, 0)
		body.add_child(cs)
		root = body
	else:
		root = Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var dark := Mats.plain(Color(0.09, 0.11, 0.14), 0.5, 0.6)
	Shapes.box(root, Vector3(1.5, 0.95, 0.8), Vector3(0, 0.475, 0), dark)
	var top := Shapes.box(root, Vector3(1.55, 0.06, 0.85), Vector3(0, 0.98, 0), Mats.plain(Color(0.2, 0.23, 0.28), 0.4, 0.7))
	top.name = "Top"
	var screen := Shapes.box(root, Vector3(1.2, 0.6, 0.05), Vector3(0, 1.38, 0.12), Mats.glow(glow, 1.8), "Screen")
	screen.rotation.x = -0.35
	Shapes.box(root, Vector3(0.06, 0.4, 0.06), Vector3(0, 1.15, 0.18), dark)
	root.set_meta("screen", screen)
	return root

## Emissive ceiling panel with an optional shadow-less light.
static func ceiling_lamp(parent: Node3D, pos: Vector3, color: Color, energy := 1.0, light_range := 9.0, size := Vector2(1.6, 0.5), with_light := true) -> void:
	Shapes.box(parent, Vector3(size.x, 0.08, size.y), pos, Mats.glow(color, 3.0))
	Shapes.box(parent, Vector3(size.x + 0.15, 0.05, size.y + 0.15), pos + Vector3(0, 0.05, 0), Mats.plain(Color(0.05, 0.06, 0.08), 0.8, 0.3))
	if with_light:
		Shapes.add_light(parent, pos + Vector3(0, -0.6, 0), color, energy, light_range)

static func pipe(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = a.distance_to(b)
	c.radial_segments = 8
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_position = (a + b) * 0.5
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) > 0.999:
		mi.rotation = Vector3.ZERO
	else:
		var axis := Vector3.UP.cross(dir).normalized()
		mi.rotate(axis, Vector3.UP.angle_to(dir))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Flat floor decal (hazard stripes, markings). `size` is X/Z extent.
static func floor_decal(parent: Node3D, pos: Vector3, size: Vector2, mat: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = mat
	mi.position = Vector3(pos.x, 0.015, pos.z)
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func stripes_material(accent: Color) -> StandardMaterial3D:
	return Mats.surface("stripes_" + accent.to_html(), "stripes", Color(0.12, 0.12, 0.12), accent, 1.0, 0.9, 0.0)

## Billboard text hologram.
static func holo_text(parent: Node3D, text: String, pos: Vector3, color: Color, size := 36) -> Label3D:
	var l := Shapes.label3d(parent, text, pos, color, size, 0.006)
	l.modulate.a = 0.9
	return l
