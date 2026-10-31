class_name Mats
extends RefCounted
## Procedural materials, textures and shaders. Everything is generated in code and cached,
## so the game needs no imported art assets.

static var _cache: Dictionary = {}

const HOLO_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.1, 0.9, 1.0, 1.0);
uniform float strength = 0.7;
uniform float scan_density = 38.0;
uniform float glitch = 0.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float g = step(0.965, fract(TIME * 0.83 + wpos.y * 0.2)) * (0.02 + glitch);
	VERTEX.x += sin(TIME * 40.0 + wpos.y * 12.0) * g;
}
void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float scan = 0.55 + 0.45 * sin(wpos.y * scan_density - TIME * 7.0);
	float a = (0.22 + fres * 0.95) * (0.55 + 0.45 * scan) * strength;
	ALBEDO = tint.rgb * (0.9 + fres * 1.4);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

const ENERGY_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.1, 0.5, 1.0, 1.0);
uniform float strength = 1.0;
uniform float pulse_speed = 2.0;
uniform float stripes = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.6);
	float pulse = 0.65 + 0.35 * sin(TIME * pulse_speed + wpos.x * 0.7 + wpos.z * 0.7);
	float s = 1.0;
	if (stripes > 0.5) {
		s = 0.5 + 0.5 * sin((wpos.y + wpos.x + wpos.z) * 9.0 - TIME * 5.0);
	}
	ALBEDO = tint.rgb * (0.6 + fres);
	ALPHA = clamp((0.18 + fres * 0.8) * pulse * s * strength, 0.0, 1.0);
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float strength = 1.0;
void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = strength * (0.6 + 0.4 * sin(TIME * 40.0));
}
"""

# --- Textures -----------------------------------------------------------------------------

static func _hash2(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177
	h = (h ^ (h >> 16)) & 0x7fffffff
	return float(h % 10000) / 10000.0

## Generates a 256x256 seamless-ish surface texture. Styles: plates, tiles, grate, stripes, circuit, damaged.
static func make_texture(style: String, base: Color, accent: Color, seed_v: int) -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var n := _hash2(x, y, seed_v)
			var n2 := _hash2(x / 4, y / 4, seed_v + 7)
			var c := base * (0.9 + 0.1 * n + 0.08 * n2)
			c.a = 1.0
			match style:
				"plates":
					var gx := x % 128
					var gy := y % 128
					if gx < 3 or gy < 3:
						c = base * 0.45
					elif gx < 5 or gy < 5:
						c = base * 1.25
					if (gx < 14 or gx > 113) and (gy < 14 or gy > 113) and (gx % 100 > 6) and absi(gx - 8) < 4 and absi(gy - 8) < 4:
						c = base * 1.5
					if (x + y * 3) % 61 == 0 and n > 0.5:
						c = base * 0.7
				"tiles":
					var tx := x % 64
					var ty := y % 64
					if tx < 2 or ty < 2:
						c = base * 0.55
					elif tx == 2 or ty == 2:
						c = base * 1.15
					else:
						c = base * (0.94 + 0.08 * _hash2(x / 64, y / 64, seed_v))
				"grate":
					var gx2 := x % 32
					var gy2 := y % 32
					var hole := (gx2 > 6 and gx2 < 26 and gy2 > 6 and gy2 < 26)
					c = base * (0.25 if hole else 1.1)
					if not hole and (gx2 == 5 or gy2 == 5):
						c = base * 1.4
				"stripes":
					var stripe := int(floorf(float(x + y) / 32.0)) % 2 == 0
					c = accent if stripe else base * 0.35
					c = c * (0.85 + 0.15 * n)
					c.a = 1.0
				"circuit":
					var cx := x % 64
					var cy := y % 64
					if cx == 0 or cy == 0:
						c = base * 0.5
					var trace_row := int(_hash2(x / 64, y / 64, seed_v) * 4.0)
					if trace_row == 0 and cy == 32 and cx > 8 and cx < 56:
						c = accent * 0.9
					elif trace_row == 1 and cx == 32 and cy > 8 and cy < 56:
						c = accent * 0.9
					elif trace_row == 2 and ((cx == 20 and cy > 20 and cy < 44) or (cy == 20 and cx > 20 and cx < 44)):
						c = accent * 0.75
				"damaged":
					var stain := _hash2(x / 16, y / 16, seed_v + 3)
					c = base * (0.75 + 0.35 * n2) * (0.7 if stain > 0.78 else 1.0)
					var gx3 := x % 128
					var gy3 := y % 128
					if gx3 < 3 or gy3 < 3:
						c = base * 0.4
					if stain > 0.9 and n > 0.4:
						c = Color(0.1, 0.06, 0.05)
					if _hash2(x, y / 2, seed_v + 11) > 0.995:
						c = accent * 0.8
				_:
					pass
			c.a = 1.0
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Textured, triplanar-mapped surface material (world-space UVs: tiles seamlessly on any box).
static func surface(key: String, style: String, base: Color, accent: Color = Color.WHITE, scale := 0.5, rough := 0.8, metal := 0.25) -> StandardMaterial3D:
	var ck := "surf_" + key
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_texture = make_texture(style, base, accent, key.hash() & 0xffff)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[ck] = m
	return m

static func plain(color: Color, rough := 0.7, metal := 0.3) -> StandardMaterial3D:
	var ck := "plain_%s_%s_%s" % [color.to_html(), rough, metal]
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_cache[ck] = m
	return m

## Glowing emissive material (picked up by the glow post effect).
static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var ck := "glow_%s_%s" % [color.to_html(), energy]
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.35
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	_cache[ck] = m
	return m

static func glass(color: Color, alpha := 0.25) -> StandardMaterial3D:
	var ck := "glass_%s_%s" % [color.to_html(), alpha]
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = 0.1
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = color * 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[ck] = m
	return m

static func unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m

static func _shader(key: String, code: String) -> Shader:
	var ck := "shader_" + key
	if _cache.has(ck):
		return _cache[ck]
	var s := Shader.new()
	s.code = code
	_cache[ck] = s
	return s

## Holographic Echo material (fresnel + scanlines + glitch). Not cached: each Echo tints/fades its own copy.
static func holo(color: Color = Cfg.C_CYAN, strength := 0.7) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("holo", HOLO_SHADER)
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("strength", strength)
	return m

static func energy(color: Color, strength := 1.0, stripes := false, pulse := 2.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("energy", ENERGY_SHADER)
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("stripes", 1.0 if stripes else 0.0)
	m.set_shader_parameter("pulse_speed", pulse)
	return m

static func beam(color: Color, strength := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("beam", BEAM_SHADER)
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("strength", strength)
	return m

## Soft round particle sprite (radial gradient).
static func soft_dot() -> Texture2D:
	if _cache.has("soft_dot"):
		return _cache["soft_dot"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_cache["soft_dot"] = t
	return t

## Additive billboard material for particle quads.
static func particle(color: Color) -> StandardMaterial3D:
	var ck := "part_" + color.to_html()
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.albedo_color = color
	m.disable_receive_shadows = true
	_cache[ck] = m
	return m

static func particle_mesh(color: Color, size := 0.2) -> QuadMesh:
	var ck := "pmesh_%s_%s" % [color.to_html(), size]
	if _cache.has(ck):
		return _cache[ck]
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = particle(color)
	_cache[ck] = q
	return q
