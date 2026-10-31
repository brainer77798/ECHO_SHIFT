class_name Shapes
extends RefCounted
## Small helpers for building meshes, collision bodies and lights from code.

static func mesh(parent: Node, m: Mesh, pos: Vector3, mat: Material, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	if node_name != "":
		mi.name = node_name
	parent.add_child(mi)
	return mi

static func box(parent: Node, size: Vector3, pos: Vector3, mat: Material, node_name := "") -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(parent, b, pos, mat, node_name)

static func cylinder(parent: Node, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, segments := 16) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segments
	c.rings = 1
	return mesh(parent, c, pos, mat)

static func sphere(parent: Node, r: float, pos: Vector3, mat: Material, segments := 20) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segments
	s.rings = segments / 2
	return mesh(parent, s, pos, mat)

static func capsule(parent: Node, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return mesh(parent, c, pos, mat)

static func torus(parent: Node, inner: float, outer: float, pos: Vector3, mat: Material, segments := 32) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = segments
	t.ring_segments = 12
	return mesh(parent, t, pos, mat)

## Visible + solid box on the given collision layer.
static func solid_box(parent: Node, size: Vector3, pos: Vector3, mat: Material, layer := Cfg.L_WORLD, node_name := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0
	if node_name != "":
		body.name = node_name
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body

## Invisible collision-only box.
static func collider_box(parent: Node, size: Vector3, pos: Vector3, layer := Cfg.L_WORLD) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body

static func add_light(parent: Node, pos: Vector3, color: Color, energy := 1.0, light_range := 8.0, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadow
	parent.add_child(l)
	return l

static func spot(parent: Node, pos: Vector3, color: Color, energy := 2.0, light_range := 12.0, angle := 45.0, shadow := false) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.spot_range = light_range
	l.spot_angle = angle
	l.shadow_enabled = shadow
	parent.add_child(l)
	l.rotation_degrees = Vector3(-90, 0, 0)
	return l

static func label3d(parent: Node, text: String, pos: Vector3, color: Color, font_size := 48, pixel_size := 0.006) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.modulate = color
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.double_sided = true
	parent.add_child(l)
	return l
