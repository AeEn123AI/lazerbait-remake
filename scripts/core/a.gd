class_name A
## Cached access to the assets extracted from the original game.

static var _cache := {}


static func _load_res(path: String) -> Resource:
	if _cache.has(path):
		return _cache[path]
	var r: Resource = load(path)
	_cache[path] = r
	return r


static func mesh(name: String) -> Mesh:
	return _load_res("res://assets/meshes/%s.obj" % name) as Mesh


static func tex(name: String) -> Texture2D:
	return _load_res("res://assets/textures/%s.png" % name) as Texture2D


static func sfx(name: String) -> AudioStream:
	var p := "res://assets/audio/sfx/%s.wav" % name
	if not ResourceLoader.exists(p):
		p = "res://assets/audio/sfx/%s.ogg" % name
	return _load_res(p) as AudioStream


static func music(name: String) -> AudioStream:
	return _load_res("res://assets/audio/music/%s.ogg" % name) as AudioStream


## "pixel" = alterebro-pixel-font, "logo" = Plain Cred 1978, "arial" = Arial (Liberation Sans substitute)
static func font(name: String) -> Font:
	match name:
		"pixel":
			return _load_res("res://assets/fonts/alterebro-pixel-font.ttf") as Font
		"logo":
			return _load_res("res://assets/fonts/plain-cred-1978.ttf") as Font
		_:
			return _load_res("res://assets/fonts/LiberationSans-Regular.ttf") as Font


static func shader(name: String) -> Shader:
	return _load_res("res://shaders/%s.gdshader" % name) as Shader


static func explosion_data() -> Dictionary:
	if _cache.has("__explosions"):
		return _cache["__explosions"]
	var f := FileAccess.open("res://assets/data/explosions.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	_cache["__explosions"] = d
	return d


# ---------------------------------------------------------------- materials

## Unity "Car Paint" (Standard, metallic) with a given _Color.
static func car_paint(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = tex("terrain01_albedo")
	m.normal_enabled = true
	m.normal_texture = tex("terrain01_normal")
	m.normal_scale = 1.0
	m.metallic = 0.721
	m.roughness = 1.0 - 0.576
	m.metallic_specular = 0.5
	return m


## Unity "Car Paint Black" (SimplePhysicalShaderCoatBlack) approximation.
static func car_paint_black() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.003, 0.014, 0.015)
	m.metallic = 1.0
	m.roughness = 0.25
	return m


## Unity "lambert1" (Standard, emission 0.1) used by ships, dots and mini planets.
static func lambert1(color: Color, vertex_color := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0 - 0.359
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = Color(0.1, 0.1, 0.1)
	if vertex_color:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
	return m


## Unity "Default-Material" (Standard white).
static func default_material(color := Color(1, 1, 1)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	return m


## Unity "ToonLit" (premultiplied transparent with green emission): effectively an additive green glow.
static func toon_lit() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.095, 0.676, 0.15)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


static func unshaded(color: Color, transparent := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if transparent or color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
