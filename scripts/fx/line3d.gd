class_name Line3D
extends MeshInstance3D
## A 2-point camera-facing line (Unity LineRenderer with 2 positions).
## Positions are world space. Use set_local_points() for lines that live in a parent's space.

static var _quad: ArrayMesh

var p0 := Vector3.ZERO
var p1 := Vector3.ZERO
var width := 0.2:
	set(v):
		width = v
		if _mat:
			_mat.set_shader_parameter("width", v)
var _mat: ShaderMaterial
var _local := false
var _lp0 := Vector3.ZERO
var _lp1 := Vector3.ZERO


static func _get_quad() -> ArrayMesh:
	if _quad == null:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
		_quad = ArrayMesh.new()
		_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _quad


func _init(additive := false, texture: Texture2D = null, w := 0.2) -> void:
	mesh = _get_quad()
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = A.shader("line_add" if additive else "line")
	_mat.render_priority = 2
	material_override = _mat
	set_texture(texture if texture else A.tex("one"))
	width = w
	_mat.set_shader_parameter("width", w)
	set_process(false)


func set_texture(t: Texture2D) -> void:
	_mat.set_shader_parameter("tex", t)


## Linear-space tint (HDR ok). For Unity `_TintColor = new Color(2,2,2)` in linear colour space
## pass U.g2l_color(Color(2,2,2)).
func set_tint(c: Color) -> void:
	_mat.set_shader_parameter("tint", c)


func set_vertex_color(c: Color) -> void:
	_mat.set_shader_parameter("vcolor", c)


func set_uv(scale: Vector2, offset: Vector2) -> void:
	_mat.set_shader_parameter("uv_scale", scale)
	_mat.set_shader_parameter("uv_offset", offset)


func set_points(a: Vector3, b: Vector3) -> void:
	_local = false
	p0 = a
	p1 = b
	_apply()


## Points expressed in the space of `space_node` (Unity useWorldSpace = false).
func set_local_points(a: Vector3, b: Vector3) -> void:
	_local = true
	set_process(true)
	_lp0 = a
	_lp1 = b


func _apply() -> void:
	_mat.set_shader_parameter("p0", p0)
	_mat.set_shader_parameter("p1", p1)
	var aabb := AABB(p0, Vector3.ZERO).expand(p1).grow(width + 0.01)
	custom_aabb = aabb


func collapsed() -> bool:
	return p0.is_equal_approx(p1)


func _process(_d: float) -> void:
	if _local:
		var par := get_parent() as Node3D
		if par:
			p0 = par.global_transform * _lp0
			p1 = par.global_transform * _lp1
			_apply()
