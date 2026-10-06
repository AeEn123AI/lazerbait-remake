class_name LaserBatch
extends MeshInstance3D
## Draws all ship lasers (Unity LineRenderer, width 0.01, "Particles/Additive" with the
## ship colour as vertex colour and the default _TintColor of 0.5) in one ImmediateMesh.

var _im := ImmediateMesh.new()
var _segs: PackedVector3Array = PackedVector3Array()
var _cols: PackedColorArray = PackedColorArray()
var width := 0.01
# Particles/Additive: 2 * vertexColor * _TintColor(0.5 gamma -> 0.214 linear)
const TINT := 2.0 * 0.21404


func _ready() -> void:
	mesh = _im
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = m
	extra_cull_margin = 16384.0


func begin() -> void:
	_segs.clear()
	_cols.clear()


func add(a: Vector3, b: Vector3, c: Color) -> void:
	_segs.append(a)
	_segs.append(b)
	# colour converted to linear like Unity's linear-space vertex colours
	var lc := c.srgb_to_linear()
	_cols.append(Color(lc.r * TINT, lc.g * TINT, lc.b * TINT, 1.0))


func commit() -> void:
	_im.clear_surfaces()
	if _segs.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var hw := width * 0.5
	var begun := false
	for i in range(0, _segs.size(), 2):
		var a := _segs[i]
		var b := _segs[i + 1]
		var d := b - a
		var side := d.cross(cam_pos - (a + b) * 0.5)
		var l := side.length()
		if l < 1e-9:
			continue
		if not begun:
			_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
		side *= hw / l
		var c := _cols[i / 2]
		_im.surface_set_color(c)
		_im.surface_add_vertex(a - side)
		_im.surface_add_vertex(a + side)
		_im.surface_add_vertex(b - side)
		_im.surface_add_vertex(b - side)
		_im.surface_add_vertex(a + side)
		_im.surface_add_vertex(b + side)
	if begun:
		_im.surface_end()
