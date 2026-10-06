class_name Wire
## Builds a non-indexed copy of a mesh with barycentric coordinates in COLOR, for wire.gdshader.

static var _cache := {}


static func make_wire_mesh(src_name: String) -> ArrayMesh:
	if _cache.has(src_name):
		return _cache[src_name]
	var src := A.mesh(src_name)
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out_v := PackedVector3Array()
	var out_c := PackedColorArray()
	var bary := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]
	if idx.is_empty():
		for i in verts.size():
			out_v.append(verts[i])
			out_c.append(bary[i % 3])
	else:
		for i in idx.size():
			out_v.append(verts[idx[i]])
			out_c.append(bary[i % 3])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = out_v
	a[Mesh.ARRAY_COLOR] = out_c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	_cache[src_name] = m
	return m
